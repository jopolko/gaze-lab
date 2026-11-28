// PICKUPMESH (Babylon port of downhill-three/pickupmesh.js, 2026-11-28): the look of Godot's pickups, boost pads, rails, glints/orbs, gates, bumpers and slingshot
// springs, built from the same recipes as godot/scripts/RunRig.gd. Pure builders: every shape is one vertex-coloured B.VertexData (merged per shape), every material
// a Babylon material. Same numbers as the three.js original, line for line; three's Matrix4 / Vector3 / Quaternion maths is done with Babylon's (the same memory layout;
// three's A.multiply(B) is Babylon's B.multiply(A)), three's geometry generators come from geo3.js.
//
// SOURCE MAP (RunRig.gd):  _kit_mesh 9445-9560 (ball and stick shapes)   _mol_material 9711 (the glossy lit material, rim .55 tint .35)   _fx_mat 3620 (solid / add / halo / ground)   _glow_texture 3604 (radial 1.0 / 0.4 at .3 / 0.0)
//   _make_item 3806 (buff: root > spin > body x1.3 > kit shape; halo quad 6.2 a.8; pool quad 7.0 at y-1.6; beacon cylinder 9 m at y 5.4)   _spawn_buff 4108 (root at ground+2.4+lift)   _animate_buffs 4815 (bob, spin, halo pulse, orb pulse)
//   _make_pad 8100 + _pad_mesh_get 8118 (chevron bars, pool quad 8, hovering crystal gem x1.25 with halo 3.6)   _build_rail 838 + _seg_box 822 (long boxes every ~8 m, posts, atoms at the joints, glint spiral, tall light)
//   _spawn_orb 4094 + _glint_line 3934 (gold atoms)   _make_gates 10081 + _tm 9569 (lollipops)   _make_bumpers 9981 (three cupcake atoms)   _make_spring 10006 (the slingshot: core, cage, halo, three turning bands, pool 26)   _beacon 9419
// USE:   const PM = createPickupMesh(B, scene);  PM.buff('boost') -> { parts, anim }  (parts are static pieces relative to the holder; anim(age, ph) returns the live offsets).
import { createGeo3 } from './geo3.js';

export const BUFF_COL = { boost: [1, .55, .1], shield: [.3, .85, 1], mult: [.95, .4, 1], donut: [1, .45, .7], saw: [1, .7, .3], orb: [1, .9, .45] };
export const BUFF_KIT = { boost: 'crystal', shield: 'cage', mult: 'rings', donut: 'tetra' };          // _make_item: {"boost": "crystal", "shield": "cage", "mult": "rings", "donut": "tetra"}
export const GATE_COLS = [[.2, .95, 1], [1, .3, .9], [1, .85, .2]];                                   // RunRig.gd GATE_COLS
export const RAIL_H = .9;

export function createPickupMesh(B, scene) {
  const G3 = createGeo3(B);
  const lerp3 = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  const V3 = (a) => new B.Vector3(a[0], a[1], a[2]);
  // three Matrix4.compose(position, quaternion, scale) and makeBasis(x, y, z).setPosition(p): Babylon matrices with the same memory layout
  const compose = (p, q, s) => B.Matrix.Compose(s, q, p);
  const basis = (x, y, z, p) => B.Matrix.FromValues(x.x, x.y, x.z, 0, y.x, y.y, y.z, 0, z.x, z.y, z.z, 0, p ? p.x : 0, p ? p.y : 0, p ? p.z : 0, 1);
  // Godot's own tessellation: the ball is a SphereMesh r=1 radial_segments 10, rings 5 (6 bands); the rod is a 6-sided open cylinder (no caps)
  const BALL = G3.sphere(1, 10, 6), ROD = G3.cylinder(1, 1, 1, 6, 1, true), BOX = G3.box(1, 1, 1);

  function merge(parts) {
    const P = [], N = [], C = [], I = []; let nv = 0;
    for (const p of parts) {
      const g = G3.transform(G3.clone(p.g), p.m), n = g.positions.length / 3;
      for (let i = 0; i < n; i++) { P.push(g.positions[i * 3], g.positions[i * 3 + 1], g.positions[i * 3 + 2]); N.push(g.normals[i * 3], g.normals[i * 3 + 1], g.normals[i * 3 + 2]); C.push(p.c[0], p.c[1], p.c[2], 1); }
      for (const i of g.indices) I.push(i + nv);
      nv += n;
    }
    const g = new B.VertexData(); g.positions = P; g.normals = N; g.colors = C; g.indices = I; return g;
  }
  const ball = (p, r, c) => ({ g: BALL, m: compose(V3(p), B.Quaternion.Identity(), new B.Vector3(r, r, r)), c });
  // _kit_mesh's rod: Basis(x, y, z) with y along the bond, x = y x (UP, or RIGHT when the bond is nearly vertical), z = x x y; scaled (stick, length, stick), placed at the midpoint
  function rod(a, b, stick, c) {
    const A = V3(a), Bv = V3(b), d = Bv.subtract(A), ln = d.length(); if (ln < .001) return null;
    const y = d.scale(1 / ln), ref = Math.abs(y.y) < .95 ? new B.Vector3(0, 1, 0) : new B.Vector3(1, 0, 0), x = B.Vector3.Cross(y, ref).normalize(), z = B.Vector3.Cross(x, y);          // (three's cross is right-handed: Babylon's Vector3.Cross computes the same components)
    const m = basis(x.scale(stick), y.scale(ln), z.scale(stick), A.add(Bv).scale(.5)); return { g: ROD, m, c: [.86, .88, .95] };
  }

  // ---- _kit_mesh(kind, col): crystal, cage, rings, ball, tetra, atom and the default hexagon ("hex")
  const kitCache = {};
  function kitGeo(kind, col) {
    const key = kind + col.join(','); if (kitCache[key]) return kitCache[key];
    const pts = [], bonds = []; const pale = lerp3(col, [1, 1, 1], .72), deep = col.map((x) => x * .75); let stick = .07;
    switch (kind) {
      case 'crystal': pts.push([[0, 0, 0], .36, col]); for (const v of [[0, 1.15, 0], [0, -1.15, 0], [.8, 0, 0], [-.8, 0, 0], [0, 0, .8], [0, 0, -.8]]) pts.push([v, .17, pale]); for (let i = 3; i < 7; i++) { bonds.push([1, i]); bonds.push([2, i]); } for (const pr of [[3, 5], [5, 4], [4, 6], [6, 3]]) bonds.push(pr); break;
      case 'cage': { pts.push([[0, 0, 0], .42, col]); const ph = (1 + Math.sqrt(5)) / 2; for (const a of [-1, 1]) for (const b of [-ph, ph]) for (const v of [[0, a, b], [a, b, 0], [b, 0, a]]) { const l = Math.hypot(...v); pts.push([v.map((x) => x / l * 1.15), .14, pale]); } for (let i = 1; i < 13; i++) for (let j = i + 1; j < 13; j++) if (Math.hypot(pts[i][0][0] - pts[j][0][0], pts[i][0][1] - pts[j][0][1], pts[i][0][2] - pts[j][0][2]) < 1.3) bonds.push([i, j]); stick = .055; break; }
      case 'rings': for (let r = 0; r < 2; r++) { for (let i = 0; i < 6; i++) { const a = i * Math.PI * 2 / 6; let v = [Math.cos(a) * .85, Math.sin(a) * .85, 0]; if (r === 1) v = [v[0] + .85, 0, v[1]]; pts.push([[v[0] - .42, v[1], v[2]], .19, r === 0 ? col : pale]); } for (let i = 0; i < 6; i++) bonds.push([r * 6 + i, r * 6 + (i + 1) % 6]); } break;
      case 'ball': pts.push([[0, 0, 0], 1, col]); break;
      case 'tetra': pts.push([[0, 0, 0], .24, pale]); for (const v of [[1, 1, 1], [1, -1, -1], [-1, 1, -1], [-1, -1, 1]]) { const l = Math.hypot(...v); pts.push([v.map((x) => x / l * .85), .4, col]); } for (let i = 1; i < 5; i++) bonds.push([0, i]); stick = .1; break;
      case 'atom': pts.push([[0, 0, 0], .72, col]); for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) { const v = [sx, sy, sz], l = Math.hypot(...v); pts.push([v.map((x) => x / l * 1.2), .2, pale]); bonds.push([0, pts.length - 1]); } stick = .08; break;
      default: pts.push([[0, 0, 0], .3, pale]); for (let i = 0; i < 6; i++) { const a = i * Math.PI * 2 / 6; pts.push([[Math.cos(a) * 1.2, Math.sin(a) * 1.2, 0], .22, i % 2 === 0 ? col : deep]); } for (let i = 0; i < 6; i++) bonds.push([1 + i, 1 + (i + 1) % 6]); stick = .09;
    }
    const parts = pts.map((p) => ball(p[0], p[1], p[2])); for (const b of bonds) { const r = rod(pts[b[0]][0], pts[b[1]][0], stick, null); if (r) parts.push(r); }
    return (kitCache[key] = merge(parts));
  }

  // ---- _mol_material: vertex colours as the albedo, roughness .45, a dim cool emission (.22,.22,.26), double sided, and a RIM: rim .55, rim_tint .35, exponent (1 - roughness) * 16 = 8.8.
  //  (The three version lit it with the scene's lights; the Babylon world has none, so the albedo is lit by a fixed soft key from above, the same light every material in this game uses.)
  let molMat = null;
  function molMaterial() {
    if (molMat) return molMat;
    B.Effect.ShadersStore.pmMolVertexShader = 'precision highp float; attribute vec3 position; attribute vec3 normal; attribute vec4 color; uniform mat4 viewProjection; varying vec3 vN; varying vec3 vW; varying vec4 vC;\n#include<instancesDeclaration>\nvoid main(void) {\n#include<instancesVertex>\nvec4 w = finalWorld * vec4(position, 1.0); vW = w.xyz; vN = normalize(mat3(finalWorld) * normal); vC = color; gl_Position = viewProjection * w; }';
    B.Effect.ShadersStore.pmMolFragmentShader = 'precision highp float; varying vec3 vN; varying vec3 vW; varying vec4 vC; uniform vec3 uCam; void main(void) { vec3 N = normalize(vN), V = normalize(uCam - vW); if (dot(N, V) < 0.) N = -N; float key = max(dot(N, normalize(vec3(.35, .85, .4))), 0.) * .75 + .25; vec3 c = vC.rgb * key + vec3(.22, .22, .26); float rim = pow(max(1. - clamp(dot(N, V), 0., 1.), 0.), 8.8); c += mix(vec3(1.), vC.rgb, .35) * rim * .55 * 1.6; gl_FragColor = vec4(c, 1.); }';
    const m = new B.ShaderMaterial('pmMol', scene, { vertex: 'pmMol', fragment: 'pmMol' }, { attributes: ['position', 'normal', 'color'], uniforms: ['world', 'viewProjection', 'uCam'] }); m.backFaceCulling = false;
    m.onBindObservable.add(() => { const c = scene.activeCamera; if (c) m.getEffect().setVector3('uCam', c.globalPosition); });
    return (molMat = m);
  }
  // ---- _fx_mat kinds. all fx materials are unshaded and ignore fog (disable_fog = true)
  //  'solid'  unshaded + emission: colour + colour * energy  (HDR; the picture pass blooms it)     'add'  additive translucent, no texture     'halo'  additive, the radial glow, always faces the camera     'ground'  additive, the radial glow, lying flat
  const glowCache = {};
  function fxMaterial(kind, rgba, energy = 1.8) {
    const key = kind + rgba.join(',') + energy; if (glowCache[key]) return glowCache[key];
    let m;
    if (kind === 'solid') { m = new B.StandardMaterial('pmSolid', scene); m.disableLighting = true; m.emissiveColor = new B.Color3(rgba[0] * (1 + energy), rgba[1] * (1 + energy), rgba[2] * (1 + energy)); m.diffuseColor = new B.Color3(0, 0, 0); m.specularColor = new B.Color3(0, 0, 0); m.backFaceCulling = false; m.fogEnabled = false; }
    else if (kind === 'add') { m = new B.StandardMaterial('pmAdd', scene); m.disableLighting = true; m.emissiveColor = new B.Color3(rgba[0], rgba[1], rgba[2]); m.diffuseColor = new B.Color3(0, 0, 0); m.specularColor = new B.Color3(0, 0, 0); m.alpha = rgba[3]; m.alphaMode = B.Engine.ALPHA_ADD; m.disableDepthWrite = true; m.backFaceCulling = false; m.fogEnabled = false; }
    else {
      const bb = kind === 'halo';
      B.Effect.ShadersStore.pmGlowVertexShader = 'precision highp float; attribute vec3 position; attribute vec2 uv; uniform mat4 view; uniform mat4 projection; uniform float bb; varying vec2 vUv;\n#include<instancesDeclaration>\nvoid main(void) {\n#include<instancesVertex>\nvUv = uv; mat4 M = finalWorld; if (bb > .5) { vec3 o = M[3].xyz; vec2 sc = vec2(length(M[0].xyz), length(M[1].xyz)); vec4 mv = view * vec4(o, 1.) + vec4(position.xy * sc, 0., 0.); gl_Position = projection * mv; } else gl_Position = projection * view * M * vec4(position, 1.); }';
      B.Effect.ShadersStore.pmGlowFragmentShader = 'precision highp float; varying vec2 vUv; uniform vec4 col; void main(void) { float r = clamp(length(vUv - .5) * 2., 0., 1.); float k = r < .3 ? mix(1., .4, r / .3) : mix(.4, 0., (r - .3) / .7); gl_FragColor = vec4(col.rgb, col.a * k); }';          // _glow_texture: white a=1 at the centre, .4 at .3, 0 at the edge of the quad's inscribed circle
      m = new B.ShaderMaterial('pmGlow', scene, { vertex: 'pmGlow', fragment: 'pmGlow' }, { attributes: ['position', 'uv'], uniforms: ['world', 'view', 'projection', 'col', 'bb'], needAlphaBlending: true });
      m.setVector4('col', new B.Vector4(rgba[0], rgba[1], rgba[2], rgba[3])); m.setFloat('bb', bb ? 1 : 0); m.alphaMode = B.Engine.ALPHA_ADD; m.disableDepthWrite = true; m.backFaceCulling = false;
    }
    return (glowCache[key] = m);
  }
  const quadGeo = G3.plane(1, 1);          // a unit quad: scale the instance by the Godot size (_quad(sz))
  let beaconG = null; const beaconGeo = () => beaconG || (beaconG = G3.cylinder(.1, .16, 9, 6));          // _buff_assets: top .1, bottom .16, height 9, 6 sides

  // part: { id, geo, mat, pos, rot:[x,y,z], scale, billboard?, size? }  (positions relative to the holder; billboard parts take their size from `size`)
  const part = (id, geo, mat, pos, scale = 1, rot = [0, 0, 0], extra = {}) => Object.assign({ id, geo, mat, pos, rot, scale }, extra);

  // ---- BUFF (_make_item + _spawn_buff). Holder at ground + 2.4 + lift. parts: body (the kit shape, x1.3, spins), halo (quad 6.2, billboard, a .8), pool (quad 7 flat at y -1.6, a .55), beacon (9 m cylinder at y 5.4, additive a .3)
  function buff(type) {
    const col = BUFF_COL[type] || BUFF_COL.donut;
    return {
      type, y0: 2.4, col,
      parts: [
        part('body', kitGeo(BUFF_KIT[type] || 'tetra', col), molMaterial(), [0, 0, 0], 1.3, [0, 0, 0], { spin: true }),
        part('halo', quadGeo, fxMaterial('halo', [col[0], col[1], col[2], .8]), [0, 0, 0], 6.2, [0, 0, 0], { billboard: true, pulse: true }),
        part('pool', quadGeo, fxMaterial('ground', [col[0], col[1], col[2], .55]), [0, -1.6, 0], 7, [-Math.PI / 2, 0, 0]),
        part('beacon', beaconGeo(), fxMaterial('add', [col[0], col[1], col[2], .3]), [0, 5.4, 0], 1),
      ],
      // _animate_buffs: root bobs sin(age*2.4+ph)*.35, the spin node turns age*(2.8 boost, else 1.7)+ph, the halo scales 1+.12*sin(age*3.4+ph)
      anim: (age, ph) => ({ bobY: Math.sin(age * 2.4 + ph) * .35, spinY: age * (type === 'boost' ? 2.8 : 1.7) + ph, haloScale: 1 + .12 * Math.sin(age * 3.4 + ph) }),
    };
  }
  // the little gold atoms along a trail: kit "ball" (1,.82,.3) x .42, glossy and lit, 1.3 above the snow; the pulse runs along the trail toward the pickup
  const orbScale = (age, i) => .85 + .35 * Math.max(Math.sin(age * 7 - i * .9), 0);
  function orb() { return { geo: kitGeo('ball', [1, .82, .3]), mat: molMaterial(), scale: .42, y: 1.3, pulse: orbScale }; }
  // rail glints: kit ball (1,.85,.35) x .24 (a MultiMesh in Godot)
  function glint() { return { geo: kitGeo('ball', [1, .85, .35]), mat: molMaterial(), scale: .24 }; }

  // ---- PAD (_make_pad + _pad_mesh_get). Holder at (x, ground(z-2.2), z-2.2). bars: three chevron pairs of 3.4 x .16 x .7 boxes turned -+.55 rad about Y, at (+-1.4, .22, -i*2.4), solid emissive energy 2.6, tilted to the slope.
  //  pool: quad 8 flat, y +.15, a .5 additive glow.  gem: kit crystal x1.25 hovering at +1.35 (turns and bobs: toys: a += 1.8*dt, bob .22*sin(age*2.6+ph)), with a halo quad 3.6, a .55.
  function pad(epic) {
    const col = epic ? [1, .25, .55] : [1, .55, .1], gcol = epic ? [1, .3, .6] : [1, .62, .15], bars = [];
    for (let i = 0; i < 3; i++) for (const sx of [-1, 1]) bars.push({ g: BOX, m: compose(new B.Vector3(sx * 1.4, .22, -i * 2.4), B.Quaternion.RotationAxis(new B.Vector3(0, 1, 0), -sx * .55), new B.Vector3(3.4, .16, .7)), c: [1, 1, 1] });          // (three setFromAxisAngle and Babylon RotationAxis give the same quaternion)
    return {
      epic, col,
      parts: [
        part('bars', merge(bars), fxMaterial('solid', [col[0], col[1], col[2], 1], 2.6), [0, 0, 0], 1, [0, 0, 0], { slope: true }),
        part('pool', quadGeo, fxMaterial('ground', [col[0], col[1], col[2], .5]), [0, .15, 0], 8, [-Math.PI / 2, 0, 0], { slope: true }),
        part('gem', kitGeo('crystal', gcol), molMaterial(), [0, 1.35, 0], 1.25, [0, 0, 0], { spin: true }),
        part('gemHalo', quadGeo, fxMaterial('halo', [col[0], col[1], col[2], .55]), [0, 1.35, 0], 3.6, [0, 0, 0], { billboard: true }),
      ],
      anim: (age, ph, a) => ({ gemY: .22 * Math.sin(age * 2.6 + ph), gemSpin: a }),
    };
  }

  // ---- RAIL (_build_rail). f: { za, zb }.  xAt(z), yAt(z): the rail's line (RunRig._feat_x, _rail_y).  Godot: n = ceil((za - zb) / 8) segments, each a box .36 x .2 x length (solid, energy 1.8, cyan (.35,.95,1));
  //  a post (r .09 top .12 bottom, 5 sides, RAIL_H high, solid (.86,.88,.95) energy .5) and a glossy atom (kit ball, scale .34, ends .55) at every second joint and the last; a spiral of glints round it; a tall thin light at the way on.
  let vcMat = null; const vertexColourMat = () => { if (vcMat) return vcMat; const m = new B.StandardMaterial('pmVC', scene); m.disableLighting = true; m.diffuseColor = new B.Color3(1, 1, 1); m.emissiveColor = new B.Color3(0, 0, 0); m.specularColor = new B.Color3(0, 0, 0); m.backFaceCulling = false; m.fogEnabled = false; return (vcMat = m); };          // three MeshBasicMaterial({ vertexColors: true }): unlit, the vertex colours as they are
  function rail(f, xAt, yAt, groundAt) {
    const col = f.col || [.35, .95, 1], n = Math.max(1, Math.ceil((f.za - f.zb) / 8)), P = [], boxes = [], posts = [], balls = [];
    for (let i = 0; i <= n; i++) { const z = f.za + (f.zb - f.za) * (i / n); P.push(new B.Vector3(xAt(z), yAt(z), z)); }
    const up = new B.Vector3(0, 1, 0), pc = [.86 * 1.5, .88 * 1.5, .95 * 1.5], bc = col.map((x) => x * 2.8);
    for (let i = 1; i <= n; i++) {
      const a = P[i - 1], b = P[i], d = b.subtract(a), ln = Math.round((d.length() + .06) * 10) / 10, z = d.normalizeToNew(), x = B.Vector3.Cross(up, z).normalize(), y = B.Vector3.Cross(z, x);
      boxes.push({ g: BOX, m: basis(x.scale(.36), y.scale(.2), z.scale(ln), a.add(b).scale(.5)), c: bc });
    }
    const postG = G3.cylinder(.09, .12, RAIL_H, 5);
    for (let i = 0; i <= n; i++) {
      if (i > 0 && (i % 2 === 0 || i === n)) posts.push({ g: postG, m: B.Matrix.Translation(P[i].x, P[i].y - RAIL_H * .5, P[i].z), c: pc });
      if (i % 2 === 0 || i === n) { const s = (i === 0 || i === n) ? .55 : .34; balls.push({ g: BALL, m: compose(P[i], B.Quaternion.Identity(), new B.Vector3(s, s, s)), c: col }); }
    }
    // the glint spiral (every 2.2 m, round the rail)
    const glints = []; for (let gz = f.za - 3; gz > f.zb + 2; gz -= 2.2) { const gt = (f.za - gz) * .8; glints.push([xAt(gz) + Math.sin(gt) * 1.1, yAt(gz) + 1 + Math.cos(gt) * .7, gz]); }
    const ex = xAt(f.za);
    return {
      boxes: { geo: merge(boxes), mat: vertexColourMat() },          // boxes and posts: unshaded emissive, colours baked HDR
      posts: { geo: merge(posts), mat: vertexColourMat() },
      balls: { geo: merge(balls), mat: molMaterial() },
      glints, glint: glint(),
      beacon: { geo: beaconGeo(), mat: fxMaterial('add', [col[0], col[1], col[2], .3]), pos: [ex, groundAt(ex, f.za) + 4.6, f.za + .5] },
    };
  }
  // a stand-alone tall thin light (_beacon): a thing can be picked out from far up the slope. cylinder 9 m, additive a .32, at ground + 4.6
  const beacon = (col) => ({ geo: beaconGeo(), mat: fxMaterial('add', [col[0], col[1], col[2], .32]), y: 4.6 });

  // ---- GATES (_make_gates): a white stick (r .09, 2.3 m, 5 sides, solid (.95,.95,.95) e.8) at y 1.15, a kit hexagon in the gate colour at y 2.9 (glossy), a halo quad 5.5 a .7 at y 2.9
  function gate(ci) {
    const c = GATE_COLS[ci % 3], stickG = G3.cylinder(.09, .09, 2.3, 5);
    return { parts: [part('stick', stickG, fxMaterial('solid', [.95, .95, .95, 1], .8), [0, 1.15, 0]), part('hex', kitGeo('hex', c), molMaterial(), [0, 2.9, 0]), part('halo', quadGeo, fxMaterial('halo', [c[0], c[1], c[2], .7]), [0, 2.9, 0], 5.5, [0, 0, 0], { billboard: true })] };
  }
  // ---- BUMPERS (_make_bumpers): three cupcake atoms (kit atom (1,.4,.75) x1.25 at y 1.7, tilted (.4, x, .2)) each with a halo quad 4.5 a .55 at y 1.4; tall light at the first
  function bumper(px) {
    return { parts: [part('atom', kitGeo('atom', [1, .4, .75]), molMaterial(), [0, 1.7, 0], 1.25, [.4, px, .2]), part('halo', quadGeo, fxMaterial('halo', [1, .45, .75, .55]), [0, 1.4, 0], 4.5, [0, 0, 0], { billboard: true })] };
  }
  // ---- SLINGSHOT SPRING (_make_spring): an additive core sphere (r 1 x .6, (.75,.95,1) a .95) at y 3, a cage atom (cyan) x1.25, a halo 7 a .5, three turning torus bands (inner/outer 2.0/2.3, 3.1/3.35, 4.3/4.5; tilt .5/1.2/2.1; turn rates .9/-.7/.5 rad/s), and a pool quad 26 a .22 on the snow
  function spring() {
    const specs = [[2.0, 2.3, [.55, .9, 1, .8], .5, .9], [3.1, 3.35, [1, .85, .45, .75], 1.2, -.7], [4.3, 4.5, [.6, .8, 1, .6], 2.1, .5]];
    const core = G3.sphere(1, 14, 8);
    const parts = [part('core', core, fxMaterial('add', [.75, .95, 1, .95]), [0, 3, 0], .6), part('cage', kitGeo('cage', [.45, .85, 1]), molMaterial(), [0, 3, 0], 1.25), part('halo', quadGeo, fxMaterial('halo', [.45, .85, 1, .5]), [0, 3, 0], 7, [0, 0, 0], { billboard: true }), part('pool', quadGeo, fxMaterial('ground', [.45, .85, 1, .22]), [0, .15, 0], 26, [-Math.PI / 2, 0, 0], { slope: true })];
    for (const s of specs) { const tg = G3.transform(G3.torus((s[0] + s[1]) / 2, (s[1] - s[0]) / 2, 6, 36), B.Matrix.RotationX(Math.PI / 2)); parts.push(part('ring' + parts.length, tg, fxMaterial('add', s[2]), [0, 3, 0], 1, [s[3], 0, s[3] * .6], { turn: s[4] })); }          // (Godot's TorusMesh lies in the XZ plane, three's in XY: rotated to match)
    return { parts, anim: (age) => ({ turn: age }) };
  }

  return { kitGeo, molMaterial, fxMaterial, quadGeo, beaconGeo, merge, buff, pad, rail, orb, glint, gate, bumper, spring, beacon, orbScale, BUFF_COL, BUFF_KIT, GATE_COLS, RAIL_H };
}

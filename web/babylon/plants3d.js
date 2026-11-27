/* THE PLANTS IN 3D (owner 2026-11-27: "3d models like the bots and raiders"). Same silhouettes and colours as plants.js, so they read from a distance:
   cacao heart, teacup + leaf, bolt bean, running gingerbread man, daisy, wrapped swirl candy, golden pyramid, flaming chilli.
   AGPLANT3D.build(B, scene, name, { lit }) -> a TransformNode about 2 units tall, facing +z, centred on the origin.
   lit: true = lit materials (for the turntable renders); false = self-lit with a soft rim (for scenes with no lights, like the game). */
(function () {
  function build(B, scene, name, o) { o = o || {}; const R = new B.TransformNode('plant_' + name, scene), MAT = {}, V = (x, y, z) => new B.Vector3(x, y, z);
    const mat = (col, k) => { const key = col.join(',') + (k || ''); if (MAT[key]) return MAT[key]; const m = new B.StandardMaterial('pl_' + key, scene), c = new B.Color3(col[0], col[1], col[2]);
      if (o.lit) { m.diffuseColor = c; m.specularColor = new B.Color3(.35, .35, .35); m.specularPower = 24; m.emissiveColor = c.scale(k === 'glow' ? 1 : .28); }
      else { m.disableLighting = true; m.emissiveColor = c.scale(k === 'glow' ? 1 : .82); const f = new B.FresnelParameters(); f.leftColor = c.scale(1.5).add(new B.Color3(.2, .2, .2)); f.rightColor = c.scale(.7); f.power = 2; m.emissiveFresnelParameters = f; }
      if (k === 'glass') m.alpha = .82; return MAT[key] = m; };
    const INK = [.07, .04, .06], WHITE = [1, 1, 1];
    const add = (m, p, mt, s, r) => { m.parent = R; if (p) m.position.copyFrom(p); if (s) m.scaling.copyFrom(s); if (r) m.rotation.copyFrom(r); m.material = mt; m.isPickable = false; return m; };
    const sph = (d, p, col, s, r, k) => add(B.MeshBuilder.CreateSphere('s', { diameter: d, segments: 20 }, scene), p, mat(col, k), s, r);
    const cyl = (h, dt, db, p, col, r, s, tess, k) => add(B.MeshBuilder.CreateCylinder('c', { height: h, diameterTop: dt, diameterBottom: db, tessellation: tess || 32 }, scene), p, mat(col, k), s, r);
    const tube = (pts, rad, col, k) => add(B.MeshBuilder.CreateTube('t', { path: pts.map((q) => V(q[0], q[1], q[2])), radius: rad, tessellation: 12, cap: B.Mesh.CAP_ALL }, scene), null, mat(col, k));
    const box = (w, h, d, p, col, r, k) => add(B.MeshBuilder.CreateBox('b', { width: w, height: h, depth: d }, scene), p, mat(col, k), null, r);
    /* googly-ish eyes: a dark ball with a white glint, sitting on the surface facing +z */
    const eye = (x, y, z, r) => { sph(r * 2, V(x, y, z), INK); sph(r * .7, V(x - r * .3, y + r * .35, z + r * .75), WHITE, null, null, 'glow'); };
    const smile = (cx, cy, z, w, col) => { const pts = []; for (let i = 0; i <= 10; i++) { const a = Math.PI * (1.15 + i * .07); pts.push([cx + Math.cos(a) * w, cy + Math.sin(a) * w * .8, z]); } tube(pts, .035, col || INK); };
    switch (name) {
      case 'cacao': { const C = [.38, .18, .07], s = V(1, 1, .62);          /* a chocolate heart */
        sph(1.15, V(-.33, .28, 0), C, s); sph(1.15, V(.33, .28, 0), C, s); cyl(1.25, 0, 1.7, V(0, -.42, 0), C, V(Math.PI, 0, 0), V(1, 1, .5)); sph(1.05, V(0, -.05, 0), C, V(1.15, .9, .55));
        sph(.28, V(-.46, .55, .3), [1, .92, .85], V(1, .55, .3), null, 'glow');
        eye(-.24, .12, .36, .1); eye(.24, .12, .36, .1); smile(0, -.02, .37, .2); sph(.18, V(-.44, -.06, .33), [1, .45, .6], V(1, .6, .2)); sph(.18, V(.44, -.06, .33), [1, .45, .6], V(1, .6, .2)); break; }
      case 'green tea': { const CUP = [.96, .94, .88], TEA = [.45, .88, .4], LEAF = [.25, .78, .3];          /* a teacup with a leaf standing up out of it */
        cyl(.9, 1.25, .85, V(0, -.35, 0), CUP); cyl(.03, 1.18, 1.18, V(0, .1, 0), TEA, null, null, 32, 'glow');
        add(B.MeshBuilder.CreateTorus('h', { diameter: .55, thickness: .12, tessellation: 24 }, scene), V(.68, -.3, 0), mat(CUP), null, V(Math.PI / 2, 0, 0));
        sph(1, V(.2, .5, 0), LEAF, V(.36, .86, .1), V(0, 0, -.35)); tube([[.04, .12, .05], [.2, .5, .06], [.34, .86, .05]], .025, [.12, .45, .15]);
        eye(-.2, -.3, .53, .09); eye(.2, -.3, .53, .09); smile(0, -.42, .52, .14); break; }
      case 'coffee': { const BEAN = [.28, .16, .08], BOLT = [1, .82, .15];          /* a coffee bean split by a lightning bolt */
        const bean = sph(1.4, V(0, 0, 0), BEAN, V(.72, 1, .5)); bean.rotation.z = -.32;
        const zig = [[.12, .62], [-.12, .12], [.1, .08], [-.14, -.62]]; for (let i = 0; i < 3; i++) { const a = zig[i], b = zig[i + 1], L = Math.hypot(b[0] - a[0], b[1] - a[1]);
          box(.14, L + .06, .12, V((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, .32), BOLT, V(0, 0, Math.atan2(a[0] - b[0], b[1] - a[1])), 'glow'); }
        for (const [x, y] of [[-.3, .18], [.32, -.14]]) { sph(.26, V(x, y, .3), WHITE, V(1, 1, .5)); sph(.12, V(x + .02, y, .38), INK); } break; }
      case 'ginger root': { const G = [.88, .5, .2], s = V(1, 1, .5);          /* a gingerbread man, mid-sprint */
        sph(.62, V(.05, .78, 0), G, V(1, 1, .55)); add(B.MeshBuilder.CreateCapsule('t', { height: .95, radius: .27 }, scene), V(0, .12, 0), mat(G), s, V(0, 0, -.12));
        const limb = (a, b) => tube([a, b], .13, G); limb([.15, .38, 0], [.62, .55, 0]); limb([-.15, .35, 0], [-.55, .12, 0]); limb([.1, -.25, 0], [.42, -.55, 0]); limb([.42, -.55, 0], [.38, -.9, 0]); limb([-.1, -.25, 0], [-.48, -.62, 0]);
        for (const y of [.3, .05]) sph(.09, V(0, y, .15), WHITE, null, null, 'glow'); eye(-.07, .83, .17, .055); eye(.17, .83, .17, .055); smile(.05, .7, .18, .12, WHITE);
        for (const y of [.3, 0, -.3]) box(.26, .03, .03, V(-.85, y, 0), [1, .85, .65], null, 'glow'); break; }
      case 'chamomile': { const PET = [.99, .98, .93], MID = [1, .78, .15];          /* a white daisy, dozing */
        for (let i = 0; i < 10; i++) { const a = i / 10 * Math.PI * 2; sph(1, V(Math.cos(a) * .55, .2 + Math.sin(a) * .55, 0), PET, V(.24, .5, .07), V(0, 0, a - Math.PI / 2)); }
        sph(.7, V(0, .2, .02), MID, V(1, 1, .45)); tube([[0, -.15, 0], [.05, -.6, 0], [-.02, -1, 0]], .05, [.3, .75, .3]);
        tube([[-.24, .24, .17], [-.16, .2, .18], [-.08, .24, .17]], .025, INK); tube([[.08, .24, .17], [.16, .2, .18], [.24, .24, .17]], .025, INK); smile(0, .14, .17, .08); break; }
      case 'peppermint': { const WRAP = [.55, .82, 1];          /* a wrapped red-and-white swirl candy: a bow tie from far away */
        const disc = add(B.MeshBuilder.CreateCylinder('d', { height: .34, diameter: 1.25, tessellation: 48 }, scene), V(0, 0, 0), null, null, V(Math.PI / 2, 0, 0));
        const dt = new B.DynamicTexture('mint', { width: 256, height: 256 }, scene, true), g = dt.getContext(); g.fillStyle = '#fff'; g.fillRect(0, 0, 256, 256); g.fillStyle = '#e3202a';
        for (let i = 0; i < 6; i++) { g.beginPath(); g.moveTo(128, 128); for (let k = 0; k <= 12; k++) { const a = (i / 6 + k / 12 * .085) * Math.PI * 2 + k * .07, r = 128 * k / 12; g.lineTo(128 + Math.cos(a) * r, 128 + Math.sin(a) * r); } for (let k = 12; k >= 0; k--) { const a = (i / 6 + .085) * Math.PI * 2 + k * .07, r = 128 * k / 12; g.lineTo(128 + Math.cos(a) * r, 128 + Math.sin(a) * r); } g.fill(); }
        dt.update(); const m = new B.StandardMaterial('pl_mint', scene); if (o.lit) { m.diffuseTexture = dt; m.emissiveTexture = dt; m.emissiveColor = new B.Color3(.3, .3, .3); m.specularColor = new B.Color3(.5, .5, .5); } else { m.disableLighting = true; m.emissiveTexture = dt; } disc.material = m;
        cyl(.55, .05, .6, V(-.85, 0, 0), WRAP, V(0, 0, -Math.PI / 2), null, 24); cyl(.55, .05, .6, V(.85, 0, 0), WRAP, V(0, 0, Math.PI / 2), null, 24);
        eye(-.1, .02, .2, .055); eye(.1, .02, .2, .055); break; }
      case 'turmeric': { const T = [1, .7, .1];          /* a golden pyramid of powder (it is from the Tomb) */
        cyl(1.45, 0, 1.9, V(0, -.15, 0), T, V(0, Math.PI / 4, 0), null, 4);
        eye(-.16, -.25, .5, .08); eye(.16, -.25, .5, .08); smile(0, -.42, .58, .12); break; }
      case 'chilli': { const RED = [.86, .1, .08];          /* a red chilli, furious, with a flame out of the tip */
        const pts = []; for (let i = 0; i <= 24; i++) { const u = i / 24, a = -.4 + u * 2.1; pts.push(V(Math.sin(a) * .7 - .1, .75 - u * 1.4 + Math.cos(a) * .1, 0)); }
        add(B.MeshBuilder.CreateTube('ch', { path: pts, radiusFunction: (i) => .36 * Math.sin(Math.min(1, (i + 2) / 26) * Math.PI * .5 + .2) * (1 - i / 32), tessellation: 20, cap: B.Mesh.CAP_ALL }, scene), null, mat(RED));
        cyl(.18, .3, .44, V(-.36, .9, 0), [.25, .8, .35], V(0, 0, .25)); tube([[-.36, .98, 0], [-.4, 1.12, 0], [-.3, 1.2, 0]], .05, [.25, .8, .35]);
        const tip = pts[pts.length - 1]; cyl(.6, 0, .34, V(tip.x - .16, tip.y - .24, 0), [1, .5, .05], V(0, 0, -.6), null, 16, 'glow'); cyl(.38, 0, .18, V(tip.x - .12, tip.y - .18, .06), [1, .9, .2], V(0, 0, -.6), null, 16, 'glow');
        eye(.0, .42, .24, .065); eye(.2, .34, .22, .065); box(.16, .03, .03, V(.0, .55, .26), INK, V(0, 0, -.35)); box(.16, .03, .03, V(.22, .47, .25), INK, V(0, 0, .35)); break; }
      default: R.dispose(); return null; }
    R.scaling.z = 1.5;          /* (owner 2026-11-27: a little thicker, so they hold up side-on) */
    return R; }
  window.AGPLANT3D = { build, list: ['cacao', 'green tea', 'coffee', 'ginger root', 'chamomile', 'peppermint', 'turmeric', 'chilli'] };
})();

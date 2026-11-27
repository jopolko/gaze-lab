// SMASH DERBY: a demolition derby in a neon bowl, steered with your head (or touch and keys). Six cars, last one running wins.
// Everything is one file: the arena, the cars, the crashes, the sound, the screens. Flags: &auto (the computer drives your car: a demo and for testing), &calm (gentler effects), &nomusic, &bots=1..7.
import * as THREE from 'three';
THREE.ColorManagement.enabled = false;          // colours are authored as they should look on screen

const Q = new URLSearchParams(location.search);
const AUTO = Q.has('auto');
let CALM = Q.has('calm'), SOUND = !Q.has('nomusic');
const NBOTS = Math.max(1, Math.min(7, +Q.get('bots') || 5));
const clamp = (v, a, b) => Math.min(b, Math.max(a, v)), lerp = (a, b, t) => a + (b - a) * t, rnd = (a, b) => a + Math.random() * (b - a);
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
const R = 92, G = 20;          // arena radius (m), gravity in the air

// ------------------------------------------------------------------ THE ARENA: a bowl with six launch ramps and some mounds
const MOUNDS = [[0, 0, 11, 3.4], [-30, 24, 8, 2.4], [32, -27, 9, 2.6], [-36, -32, 7, 2.2], [34, 32, 7, 2]];
const KICKS = []; for (let i = 0; i < 6; i++) { const a = i / 6 * Math.PI * 2 + .35, rr = 50; KICKS.push({ x: Math.cos(a) * rr, z: Math.sin(a) * rr, dx: -Math.cos(a), dz: -Math.sin(a), L: 14, W: 8.5, h: 5.2 }); }
function kick(k, x, z) { const rx = x - k.x, rz = z - k.z, t = rx * k.dx + rz * k.dz, s = -rx * k.dz + rz * k.dx; if (t < 0 || t > k.L) return 0; const w = Math.max(0, 1 - Math.abs(s) / k.W); return Math.pow(t / k.L, 1.1) * k.h * (w * w * (3 - 2 * w)); }
function H(x, z) {
  const r = Math.hypot(x, z); let h = .00085 * r * r; if (r > R - 14) { const w = r - (R - 14); h += w * w * .09; }
  for (const m of MOUNDS) { const d = Math.hypot(x - m[0], z - m[1]) / m[2]; if (d < 1) { const t = 1 - d * d; h += m[3] * t * t; } }
  for (const k of KICKS) h += kick(k, x, z);
  return h;
}

// ------------------------------------------------------------------ RENDERER, SCENE, POST PASS
const canvas = document.getElementById('c'), UI = document.getElementById('ui');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance' });
renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
let PR = Math.min(devicePixelRatio || 1, 1.5); if (innerWidth * innerHeight * PR * PR > 2.2e6) PR = Math.sqrt(2.2e6 / (innerWidth * innerHeight));
const rt = new THREE.WebGLRenderTarget(4, 4, { samples: 4 });
const scene = new THREE.Scene(); scene.fog = new THREE.FogExp2(0x2a0840, .0038);
const camera = new THREE.PerspectiveCamera(74, 1, .3, 1400); camera.rotation.order = 'YXZ'; scene.add(camera);
function resize() { const w = innerWidth, h = innerHeight; renderer.setPixelRatio(PR); renderer.setSize(w, h, false); rt.setSize(Math.floor(w * PR), Math.floor(h * PR)); camera.aspect = w / h; camera.updateProjectionMatrix(); }
addEventListener('resize', resize); resize();
scene.add(new THREE.HemisphereLight(0xb08cff, 0x40104a, 1.05));
const sun = new THREE.DirectionalLight(0xffb070, 1.5); sun.position.set(-60, 90, 40); scene.add(sun);
const hood = new THREE.Group(); { const g = new THREE.BoxGeometry(2.3, .35, 2.4); hood.add(new THREE.Mesh(g, new THREE.MeshBasicMaterial({ color: 0x16284a })), new THREE.LineSegments(new THREE.EdgesGeometry(g), new THREE.LineBasicMaterial({ color: 0x19e6ff })), (() => { const m = new THREE.Mesh(new THREE.BoxGeometry(.5, .02, 2.42), new THREE.MeshBasicMaterial({ color: 0xffffff })); m.position.set(0, .185, 0); return m; })(), (() => { const m = new THREE.Mesh(new THREE.BoxGeometry(2.0, .02, .25), new THREE.MeshBasicMaterial({ color: 0xff2fa0 })); m.position.set(0, .185, -.9); return m; })()); hood.position.set(0, -1.0, -1.9); hood.rotation.x = -.14; hood.visible = false; camera.add(hood); }
const flashLight = new THREE.PointLight(0xffa040, 0, 90, 1.6); scene.add(flashLight);

const GLSL_HSV = `vec3 hsv(float h,float s,float v){ vec3 k=vec3(1.,2./3.,1./3.); vec3 p=abs(fract(vec3(h)+k)*6.-3.); return v*mix(vec3(1.),clamp(p-1.,0.,1.),s); }`;
const U = { uTime: { value: 0 }, uTrip: { value: 0 }, fogColor: { value: scene.fog.color }, fogDensity: { value: scene.fog.density } };

// the sky: a big gradient with a striped sun and stars
const sky = new THREE.Mesh(new THREE.SphereGeometry(900, 32, 16), new THREE.ShaderMaterial({ side: THREE.BackSide, depthWrite: false, fog: false, uniforms: { uTime: U.uTime },
  vertexShader: 'varying vec3 vD; void main(){ vD = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
  fragmentShader: `uniform float uTime; varying vec3 vD; ${GLSL_HSV}
    float h21(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
    void main(){ vec3 d = normalize(vD); float y = d.y; vec3 top = vec3(.06, 0., .2), hor = vec3(1., .28, .5); vec3 col = mix(hor, top, smoothstep(0., .6, y));
      col += hsv(fract(.78 + y * .25 + uTime * .01), .7, .25) * smoothstep(.0, .5, y);
      vec3 sd = normalize(vec3(-.35, .22, -.9)); float sdist = acos(clamp(dot(d, sd), -1., 1.)); float disk = 1. - smoothstep(.2, .21, sdist);
      float stripe = step(.42, fract((d.y - sd.y) * 38. + uTime * .05)) * step(d.y, sd.y + .05); col = mix(col, vec3(1., .86, .3) * (.8 + .5 * stripe), disk * (.45 + .55 * (1. - stripe * step(d.y, sd.y))));
      col += vec3(1., .5, .2) * exp(-sdist * 5.) * .45;
      vec2 sp = floor(vec2(atan(d.x, d.z) * 90., y * 90.)); float st = step(.9965, h21(sp)) * smoothstep(.12, .4, y); col += vec3(st) * .9;
      gl_FragColor = vec4(col, 1.); }` }));
scene.add(sky);

// the ground: dark, with hue bands that crawl outward, a neon grid, pulsing rings and chevrons on the ramps
const GN = 220, GS = 2 * (R + 16), gg = new THREE.PlaneGeometry(GS, GS, GN, GN); gg.rotateX(-Math.PI / 2);
{ const p = gg.attributes.position, n = p.count, aK = new Float32Array(n), aT = new Float32Array(n);
  for (let i = 0; i < n; i++) { const x = p.getX(i), z = p.getZ(i); p.setY(i, H(x, z)); let km = 0, kt = 0; for (const k of KICKS) { const rx = x - k.x, rz = z - k.z, t = rx * k.dx + rz * k.dz, s = -rx * k.dz + rz * k.dx; if (t >= 0 && t <= k.L && Math.abs(s) < k.W) { const m = 1 - Math.abs(s) / k.W; if (m > km) { km = m; kt = t / k.L; } } } aK[i] = km; aT[i] = kt; }
  gg.setAttribute('aKick', new THREE.BufferAttribute(aK, 1)); gg.setAttribute('aKt', new THREE.BufferAttribute(aT, 1)); }
const ground = new THREE.Mesh(gg, new THREE.ShaderMaterial({ uniforms: U,
  vertexShader: 'attribute float aKick; attribute float aKt; varying vec3 wp; varying float vK; varying float vT; void main(){ wp = (modelMatrix * vec4(position, 1.)).xyz; vK = aKick; vT = aKt; gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.); }',
  fragmentShader: `uniform float uTime, uTrip, fogDensity; uniform vec3 fogColor; varying vec3 wp; varying float vK; varying float vT; ${GLSL_HSV}
    void main(){ float r = length(wp.xz); vec3 n = normalize(cross(dFdx(wp), dFdy(wp))); if (n.y < 0.) n = -n; float slope = 1. - n.y;
      float hb = fract(r * .0085 - uTime * .04 + wp.y * .012 + uTrip * .25);
      vec3 col = hsv(hb, .8, .2 + .22 * slope);
      vec2 gp = wp.xz / 7.; vec2 gd = abs(fract(gp - .5) - .5) / fwidth(gp); float gl = 1. - min(min(gd.x, gd.y), 1.); col += hsv(hb + .5, .9, 1.) * gl * .55;
      float ring = pow(.5 + .5 * sin(r * .42 - uTime * 2.2), 14.); col += hsv(hb + .33, 1., 1.) * ring * .22 * (1. - smoothstep(${R - 8}., ${R}., r));
      float cl = abs(fract(wp.y * .5) - .5) / (fwidth(wp.y * .5) + 1e-4); col += vec3(.9, .5, 1.) * (1. - min(cl, 1.)) * .25 * smoothstep(.05, .3, slope + .1);
      if (vK > .02) { float ch = step(.5, fract(vT * 5. - uTime * 1.4 + abs(vK - .5) * .4)); col = mix(col, mix(vec3(1., .75, .1), vec3(1., .2, .5), ch), smoothstep(.0, .25, vK) * .85); }
      float wall = smoothstep(${R - 7}., ${R - 1}., r); float hz = step(.5, fract((wp.x + wp.z) * .1 + uTime * .3)); col = mix(col, mix(vec3(.9, .05, .15), vec3(1., .85, .1), hz), wall * .6); col *= 1. - .45 * smoothstep(${R - 22}., ${R - 7}., r);
      float fd = distance(wp, cameraPosition); col = mix(col, fogColor, 1. - exp(-fogDensity * fd)); gl_FragColor = vec4(col, 1.); }` }));
scene.add(ground);

// the wall around the bowl: scrolling neon chevrons, and searchlights sweeping over the arena
const wallMat = new THREE.ShaderMaterial({ transparent: true, side: THREE.DoubleSide, depthWrite: false, blending: THREE.AdditiveBlending, uniforms: U,
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.); }',
  fragmentShader: `uniform float uTime; varying vec2 vUv; ${GLSL_HSV} void main(){ float c = step(.5, fract(vUv.x * 60. + vUv.y * 4. - uTime * .8)); float edge = smoothstep(.0, .08, vUv.y) * (1. - smoothstep(.35, 1., vUv.y)); vec3 col = hsv(fract(vUv.x * 2. + uTime * .05), 1., 1.) * (.25 + .75 * c) * edge; gl_FragColor = vec4(col, edge * .85); }` });
const wallMesh = new THREE.Mesh(new THREE.CylinderGeometry(R + 1, R + 1, 16, 128, 1, true), wallMat); wallMesh.position.y = H(R, 0) + 2; scene.add(wallMesh);
const beams = []; for (let i = 0; i < 6; i++) { const m = new THREE.Mesh(new THREE.ConeGeometry(9, 150, 20, 1, true), new THREE.MeshBasicMaterial({ color: new THREE.Color().setHSL(i / 6, 1, .6), transparent: true, opacity: .16, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide, fog: false })); m.userData.a = i / 6 * Math.PI * 2; scene.add(m); beams.push(m); }

// ------------------------------------------------------------------ PARTICLES (sparks and fire add light, smoke is dark) and flying debris
function makePool(n, additive) {
  const pos = new Float32Array(n * 3), col = new Float32Array(n * 3), siz = new Float32Array(n), alp = new Float32Array(n), vel = new Float32Array(n * 3), life = new Float32Array(n), max = new Float32Array(n), g = new Float32Array(n);
  const geo = new THREE.BufferGeometry(); geo.setAttribute('position', new THREE.BufferAttribute(pos, 3)); geo.setAttribute('color', new THREE.BufferAttribute(col, 3)); geo.setAttribute('size', new THREE.BufferAttribute(siz, 1)); geo.setAttribute('alpha', new THREE.BufferAttribute(alp, 1));
  const mat = new THREE.ShaderMaterial({ transparent: true, depthWrite: false, blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending, uniforms: { uScale: { value: 1 } },
    vertexShader: 'attribute float size; attribute float alpha; attribute vec3 color; varying float vA; varying vec3 vC; uniform float uScale; void main(){ vA = alpha; vC = color; vec4 mv = modelViewMatrix * vec4(position, 1.); gl_PointSize = size * uScale / max(1., -mv.z); gl_Position = projectionMatrix * mv; }',
    fragmentShader: 'varying float vA; varying vec3 vC; void main(){ float d = length(gl_PointCoord - .5); float a = smoothstep(.5, .05, d) * vA; if (a < .01) discard; gl_FragColor = vec4(vC, a); }' });
  const pts = new THREE.Points(geo, mat); pts.frustumCulled = false; scene.add(pts); let head = 0;
  return { pts, mat, spawn(x, y, z, vx, vy, vz, r, gC, b, s, life0, gr) { const i = head++ % n; pos[i * 3] = x; pos[i * 3 + 1] = y; pos[i * 3 + 2] = z; vel[i * 3] = vx; vel[i * 3 + 1] = vy; vel[i * 3 + 2] = vz; col[i * 3] = r; col[i * 3 + 1] = gC; col[i * 3 + 2] = b; siz[i] = s; life[i] = life0; max[i] = life0; g[i] = gr; },
    step(dt) { for (let i = 0; i < n; i++) { if (life[i] <= 0) { alp[i] = 0; continue; } life[i] -= dt; const k = life[i] / max[i]; vel[i * 3 + 1] -= g[i] * dt; pos[i * 3] += vel[i * 3] * dt; pos[i * 3 + 1] += vel[i * 3 + 1] * dt; pos[i * 3 + 2] += vel[i * 3 + 2] * dt; if (g[i] > 0 && pos[i * 3 + 1] < H(pos[i * 3], pos[i * 3 + 2]) + .1) { pos[i * 3 + 1] = H(pos[i * 3], pos[i * 3 + 2]) + .1; vel[i * 3 + 1] *= -.35; vel[i * 3] *= .7; vel[i * 3 + 2] *= .7; } alp[i] = clamp(k * 1.6, 0, 1); }
      geo.attributes.position.needsUpdate = geo.attributes.alpha.needsUpdate = true; geo.attributes.color.needsUpdate = geo.attributes.size.needsUpdate = true; } };
}
const FX = makePool(1100, true), SMK = makePool(420, false);
function sparks(x, y, z, n, power, hue) { for (let i = 0; i < n; i++) { const a = rnd(0, 6.283), up = rnd(.2, 1), sp = rnd(4, 14) * power; const c = new THREE.Color().setHSL(hue === undefined ? rnd(.04, .14) : hue + rnd(-.05, .05), 1, .6); FX.spawn(x, y, z, Math.cos(a) * sp, up * sp * .9, Math.sin(a) * sp, c.r, c.g, c.b, rnd(.35, 1.0), rnd(.3, .9), 22); } }
function smoke(x, y, z, n, size, dark) { for (let i = 0; i < n; i++) { const v = dark ? rnd(.04, .14) : rnd(.3, .6); SMK.spawn(x + rnd(-.5, .5), y, z + rnd(-.5, .5), rnd(-1, 1), rnd(2, 5), rnd(-1, 1), v, v * .9, v * 1.1, size * rnd(.7, 1.3), rnd(.9, 1.8), -.5); } }
function fire(x, y, z, n, size) { for (let i = 0; i < n; i++) { const c = new THREE.Color().setHSL(rnd(.0, .12), 1, .55); FX.spawn(x + rnd(-.6, .6), y, z + rnd(-.6, .6), rnd(-2, 2), rnd(3, 8), rnd(-2, 2), c.r, c.g, c.b, size * rnd(.7, 1.3), rnd(.4, .9), -2); } }
const debris = []; for (let i = 0; i < 48; i++) { const m = new THREE.Mesh(new THREE.BoxGeometry(.7, .4, 1.1), new THREE.MeshLambertMaterial({ color: 0x333344 })); m.visible = false; m.userData = { v: new THREE.Vector3(), w: new THREE.Vector3(), t: 0 }; scene.add(m); debris.push(m); }
let dHead = 0; function debrisBurst(c, n) { for (let i = 0; i < n; i++) { const m = debris[dHead++ % debris.length]; m.visible = true; m.position.set(c.x, c.y + 1, c.z); m.material.color.setHex(Math.random() < .5 ? c.col : 0x2a2a38); const a = rnd(0, 6.283), s = rnd(6, 16); m.userData.v.set(Math.cos(a) * s + c.vx * .4, rnd(8, 18), Math.sin(a) * s + c.vz * .4); m.userData.w.set(rnd(-9, 9), rnd(-9, 9), rnd(-9, 9)); m.userData.t = rnd(3, 5); m.scale.setScalar(rnd(.7, 1.5)); } }
function stepDebris(dt) { for (const m of debris) { if (!m.visible) continue; const u = m.userData; u.t -= dt; if (u.t <= 0) { m.visible = false; continue; } u.v.y -= G * dt; m.position.addScaledVector(u.v, dt); m.rotation.x += u.w.x * dt; m.rotation.y += u.w.y * dt; m.rotation.z += u.w.z * dt; const g = H(m.position.x, m.position.z) + .3; if (m.position.y < g) { m.position.y = g; u.v.y *= -.4; u.v.x *= .7; u.v.z *= .7; u.w.multiplyScalar(.6); } if (u.t < .6) m.scale.multiplyScalar(.96); } }

// ------------------------------------------------------------------ THE CARS
const ROSTER = [
  { name: 'DOZER', col: 0xff7a18, mass: 1.55, hp: 150, aggr: .7, skill: .5, spd: .92, caution: .1, taunt: 'Move it or lose it.' },
  { name: 'BLAZE', col: 0xff2d55, mass: 1, hp: 105, aggr: 1, skill: .72, spd: 1.06, caution: .1, taunt: 'Nice paint. Shame.' },
  { name: 'TWITCH', col: 0x2dffb4, mass: .8, hp: 85, aggr: .8, skill: .92, spd: 1.16, caution: .5, taunt: 'Too slow, too slow.' },
  { name: 'MAMA BOLT', col: 0xffe14a, mass: 1.1, hp: 115, aggr: .6, skill: .6, spd: 1, caution: .3, taunt: 'Come to mama.' },
  { name: 'CHROME', col: 0xc8d6ff, mass: 1.25, hp: 125, aggr: .9, skill: .95, spd: 1, caution: .2, taunt: 'Resistance is shiny.' },
  { name: 'SPUD', col: 0xb46bff, mass: .95, hp: 100, aggr: .5, skill: .4, spd: .98, caution: .6, taunt: 'Is this thing on?' },
  { name: 'ROOK', col: 0x6bb6ff, mass: 1.05, hp: 110, aggr: .75, skill: .7, spd: 1.02, caution: .3, taunt: 'Checkmate.' }];
const PLAYER = { name: 'YOU', col: 0x19e6ff, mass: 1.1, hp: 125, spd: 1.04 };
const dark = new THREE.MeshLambertMaterial({ color: 0x14121c }), glass = new THREE.MeshLambertMaterial({ color: 0x0c1f3a, emissive: 0x06304a }), metal = new THREE.MeshLambertMaterial({ color: 0x9aa0b8 }), headlight = new THREE.MeshBasicMaterial({ color: 0xfff6c8 }), tail = new THREE.MeshBasicMaterial({ color: 0xff2030 });
const bx = new THREE.BoxGeometry(1, 1, 1), wheelGeo = new THREE.CylinderGeometry(.5, .5, .45, 14); wheelGeo.rotateZ(Math.PI / 2);
function tagTexture(name, col) { const c = document.createElement('canvas'); c.width = 256; c.height = 64; return { c, tex: new THREE.CanvasTexture(c), name, col }; }
function drawTag(t, hp) { const x = t.c.getContext('2d'); x.clearRect(0, 0, 256, 64); x.font = '900 26px system-ui,sans-serif'; x.textAlign = 'center'; x.fillStyle = '#' + new THREE.Color(t.col).getHexString(); x.strokeStyle = '#000'; x.lineWidth = 5; x.strokeText(t.name, 128, 26); x.fillText(t.name, 128, 26); x.fillStyle = '#000b'; x.fillRect(48, 40, 160, 12); x.fillStyle = hp > .5 ? '#3dff8a' : hp > .25 ? '#ffd23a' : '#ff3a3a'; x.fillRect(50, 42, 156 * Math.max(0, hp), 8); t.tex.needsUpdate = true; }
function makeCarMesh(col, isPlayer) {
  const g = new THREE.Group(), body = new THREE.MeshLambertMaterial({ color: col }), add = (geo, mat, x, y, z, sx, sy, sz) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.scale.set(sx, sy, sz); g.add(m); return m; };
  add(bx, body, 0, .72, 0, 2.05, .62, 4.3); add(bx, body, 0, .5, -1.15, 2.1, .5, 1.6);          // body and hood
  add(bx, glass, 0, 1.28, .35, 1.7, .56, 1.9); add(bx, body, 0, 1.6, .35, 1.75, .1, 1.95);          // cabin and roof
  add(bx, metal, 0, .5, -2.2, 2.3, .38, .42); add(bx, metal, 0, .55, 2.25, 2.2, .36, .36);          // bumpers
  add(bx, dark, 0, 1.75, 1.95, 2.1, .12, .6); add(bx, dark, -.95, 1.5, 1.95, .1, .5, .12); add(bx, dark, .95, 1.5, 1.95, .1, .5, .12);          // spoiler
  add(bx, headlight, -.7, .78, -2.12, .45, .24, .08); add(bx, headlight, .7, .78, -2.12, .45, .24, .08); add(bx, tail, -.7, .85, 2.14, .5, .2, .08); add(bx, tail, .7, .85, 2.14, .5, .2, .08);
  add(bx, new THREE.MeshBasicMaterial({ color: 0xffffff }), 0, 1.04, 0, 2.08, .08, 4.32);          // racing stripe
  for (const [x, z] of [[-1.05, -1.4], [1.05, -1.4], [-1.05, 1.45], [1.05, 1.45]]) add(wheelGeo, dark, x, .5, z, 1, 1, 1);
  const glow = new THREE.Mesh(new THREE.PlaneGeometry(2.6, 5), new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: .5, blending: THREE.AdditiveBlending, depthWrite: false })); glow.rotation.x = -Math.PI / 2; glow.position.y = .12; g.add(glow);
  g.rotation.order = 'YXZ'; scene.add(g); return { g, glow, body };
}
const cars = []; let player = null;
function newCar(def, isPlayer) {
  const c = { name: def.name, col: def.col, mass: def.mass, hpMax: def.hp, hp: def.hp, speedK: def.spd, isPlayer, alive: true, x: 0, z: 0, y: 0, vx: 0, vz: 0, vy: 0, psi: 0, steer: 0, grounded: true, boost: 1, boosting: false, od: 0, wrecks: 0, hurtT: 0, smokeT: 0,
    ai: { t: 0, target: null, aggr: def.aggr || .9, skill: def.skill || .9, caution: def.caution || .2, wob: rnd(0, 6), flee: false }, taunt: def.taunt };
  const m = makeCarMesh(def.col, isPlayer); c.mesh = m.g; c.glow = m.glow; c.bodyMat = m.body;
  if (!isPlayer) { c.tag = tagTexture(def.name, def.col); drawTag(c.tag, 1); const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: c.tag.tex, transparent: true, depthTest: false, fog: false, sizeAttenuation: false })); sp.scale.set(.3, .075, 1); sp.position.y = 4; sp.renderOrder = 10; c.mesh.add(sp); c.sprite = sp; c.tagHp = 1; }
  cars.push(c); return c;
}
function placeCars() {
  const n = cars.length; cars.forEach((c, i) => { const a = i / n * Math.PI * 2 + rnd(-.1, .1), rr = 62; c.x = Math.cos(a) * rr; c.z = Math.sin(a) * rr; c.psi = Math.atan2(-c.x, c.z) + 0 + rnd(-.15, .15); c.psi = Math.atan2(-c.x, c.z); c.y = H(c.x, c.z); c.vx = c.vz = c.vy = 0; c.hp = c.hpMax; c.alive = true; c.grounded = true; c.boost = 1; c.od = 0; c.steer = 0; c.wrecks = 0; c.ai.target = null; c.ai.t = 0; c.mesh.visible = true; c.bodyMat.color.setHex(c.col); c.glow.visible = true; if (c.sprite) { c.sprite.visible = true; c.tagHp = 1; drawTag(c.tag, 1); } });
}
function buildCars() { player = newCar(PLAYER, true); player.hpMax = player.hp = PLAYER.hp; const pick = ROSTER.slice(0, NBOTS); pick.forEach((d) => newCar(d, false)); placeCars(); }
buildCars();

// ------------------------------------------------------------------ PICKUPS: wrench (health), cell (boost), molecule (overdrive)
const PICK = []; const PK = { hp: { col: 0x3dff8a }, boost: { col: 0x19e6ff }, trip: { col: 0xff2fe0 } };
function pickMesh(type) { const g = new THREE.Group(), m = new THREE.MeshBasicMaterial({ color: PK[type].col }); if (type === 'hp') { const a = new THREE.Mesh(bx, m); a.scale.set(1.8, .5, .5); const b = new THREE.Mesh(bx, m); b.scale.set(.5, .5, 1.8); g.add(a, b); } else if (type === 'boost') { const c = new THREE.Mesh(new THREE.ConeGeometry(.9, 1.8, 4), m); c.rotation.x = Math.PI / 2; g.add(c); } else { for (let i = 0; i < 5; i++) { const s = new THREE.Mesh(new THREE.SphereGeometry(.4 + (i % 2) * .15, 10, 8), m); const a = i / 5 * 6.283; s.position.set(Math.cos(a) * .9, Math.sin(a * 2) * .5, Math.sin(a) * .9); g.add(s); } g.add(new THREE.Mesh(new THREE.SphereGeometry(.55, 10, 8), m)); }
  const h = new THREE.Mesh(new THREE.SphereGeometry(1.8, 12, 8), new THREE.MeshBasicMaterial({ color: PK[type].col, transparent: true, opacity: .22, blending: THREE.AdditiveBlending, depthWrite: false })); g.add(h); scene.add(g); return g; }
function spawnPickup(type) { const a = rnd(0, 6.283), rr = rnd(12, 62), x = Math.cos(a) * rr, z = Math.sin(a) * rr; const p = { type, x, z, mesh: pickMesh(type), t: 0, on: true }; p.mesh.position.set(x, H(x, z) + 1.6, z); PICK.push(p); return p; }
['hp', 'hp', 'boost', 'boost', 'trip'].forEach(spawnPickup);

// ------------------------------------------------------------------ SOUND: engine, crashes, a driving synth loop, and an announcer
let AC = null, MG = null, engOsc = null, engGain = null, engFilt = null, NB = null, musicTimer = 0, nextBeat = 0, beatIdx = 0, intensity = 0;
function audioStart() {
  if (AC) { if (AC.state === 'suspended') AC.resume(); return; } try { AC = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { return; }
  MG = AC.createGain(); MG.gain.value = SOUND ? .6 : 0; MG.connect(AC.destination);
  NB = AC.createBuffer(1, AC.sampleRate, AC.sampleRate); const d = NB.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  engOsc = AC.createOscillator(); engOsc.type = 'sawtooth'; engFilt = AC.createBiquadFilter(); engFilt.type = 'lowpass'; engFilt.frequency.value = 500; engGain = AC.createGain(); engGain.gain.value = 0; engOsc.connect(engFilt); engFilt.connect(engGain); engGain.connect(MG); engOsc.start();
  nextBeat = AC.currentTime + .1; musicTimer = setInterval(schedule, 30);
}
function setSound(on) { SOUND = on; if (MG) MG.gain.value = on ? .6 : 0; if (!on && 'speechSynthesis' in window) try { speechSynthesis.cancel(); } catch (e) { } }
function tone(type, f0, f1, dur, vol, when, filt) { if (!AC) return; const t = when || AC.currentTime, o = AC.createOscillator(), g = AC.createGain(); o.type = type; o.frequency.setValueAtTime(f0, t); if (f1) o.frequency.exponentialRampToValueAtTime(f1, t + dur); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(.001, t + dur); let n = o; if (filt) { const f = AC.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = filt; o.connect(f); n = f; } n.connect(g); g.connect(MG); o.start(t); o.stop(t + dur + .02); }
function noise(dur, vol, f0, f1, type, when) { if (!AC) return; const t = when || AC.currentTime, s = AC.createBufferSource(); s.buffer = NB; const f = AC.createBiquadFilter(); f.type = type || 'bandpass'; f.frequency.setValueAtTime(f0, t); if (f1) f.frequency.exponentialRampToValueAtTime(f1, t + dur); const g = AC.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(.001, t + dur); s.connect(f); f.connect(g); g.connect(MG); s.start(t); s.stop(t + dur + .02); }
function sfxCrash(p) { p = clamp(p, .15, 1.4); noise(.32, .9 * p, 1400 + rnd(-300, 300), 300, 'bandpass'); tone('sine', 120, 38, .3, .9 * p); if (p > .5) tone('square', 220, 60, .18, .25 * p, 0, 900); }
function sfxWreck() { noise(.9, 1, 900, 80, 'lowpass'); tone('sine', 90, 28, .9, 1); noise(.25, .6, 4000, 800, 'highpass'); }
function sfxBoost() { noise(.7, .5, 500, 5000, 'bandpass'); tone('sawtooth', 120, 480, .5, .12, 0, 1500); }
function sfxPick(t) { tone('sine', t === 'hp' ? 660 : t === 'boost' ? 880 : 440, t === 'trip' ? 1760 : 1320, .25, .35); }
function sfxLand(p) { noise(.2, .5 * p, 700, 150, 'lowpass'); tone('sine', 80, 40, .2, .5 * p); }
function say(t) { if (!SOUND || !('speechSynthesis' in window)) return; try { speechSynthesis.cancel(); const u = new SpeechSynthesisUtterance(t); u.pitch = .35; u.rate = 1.08; u.volume = 1; speechSynthesis.speak(u); } catch (e) { } }
const SCALE = [0, 3, 5, 7, 10, 12, 15, 17], CHORDS = [[57, 60, 64], [53, 57, 60], [55, 59, 62], [52, 56, 59]];          // A minor, F, G, E
function schedule() {
  if (!AC || !SOUND) return; const bpm = 132 + intensity * 10, step = 60 / bpm / 4;
  while (nextBeat < AC.currentTime + .14) {
    const i = beatIdx % 16, bar = Math.floor(beatIdx / 16), t = nextBeat, I = intensity;
    if (I > .1 && i % 4 === 0) { tone('sine', 150, 42, .22, .85, t); }
    if (I > .35 && (i === 4 || i === 12)) noise(.14, .35, 2200, 1800, 'bandpass', t);
    if (I > .2 && i % 2 === 1) noise(.04, .12, 9000, 9000, 'highpass', t);
    const root = CHORDS[Math.floor(bar / 2) % 4][0] - 24, note = root + SCALE[[0, 2, 4, 2, 0, 3, 5, 3, 0, 4, 6, 4, 0, 2, 5, 7][i] % 8] * (i % 3 === 0 ? 1 : 0) + (i % 3 === 0 ? 0 : 12 * (i % 2));
    if (I > .25) tone('sawtooth', 440 * Math.pow(2, (note - 69) / 12), 0, step * 1.6, .12, t, 600 + 1800 * I);
    if (i === 0 && bar % 2 === 0) { for (const n of CHORDS[Math.floor(bar / 2) % 4]) tone('triangle', 440 * Math.pow(2, (n - 69) / 12), 0, step * 30, .06 + .04 * (1 - I), t, 1400); }
    nextBeat += step; beatIdx++;
  }
}

// ------------------------------------------------------------------ INPUT: head (camera), touch drag, keys
const IN = { steer: 0, boost: false, keyL: 0, keyR: 0, drag: null, head: false };
addEventListener('keydown', (e) => { if (e.repeat) return; const k = e.key; if (k === 'ArrowLeft' || k === 'a' || k === 'A') IN.keyL = 1; if (k === 'ArrowRight' || k === 'd' || k === 'D') IN.keyR = 1; if (k === ' ' || k === 'Shift') IN.boost = true; if (k === 'r' || k === 'R') headCentre(); if (k === ',' || k === '.') { HEAD.gain = clamp(HEAD.gain * (k === '.' ? 1.15 : 1 / 1.15), .4, 3); if (typeof callout === 'function') callout('SENSITIVITY ' + Math.round(HEAD.gain * 100) + '%', '#6df'); } });
addEventListener('keyup', (e) => { const k = e.key; if (k === 'ArrowLeft' || k === 'a' || k === 'A') IN.keyL = 0; if (k === 'ArrowRight' || k === 'd' || k === 'D') IN.keyR = 0; if (k === ' ' || k === 'Shift') IN.boost = false; });
canvas.addEventListener('pointerdown', (e) => { if (e.pointerType === 'mouse' && e.button !== 0) return; IN.drag = { x0: e.clientX, id: e.pointerId }; try { canvas.setPointerCapture(e.pointerId); } catch (er) { } });
canvas.addEventListener('pointermove', (e) => { if (IN.drag && IN.drag.id === e.pointerId) IN.drag.x = e.clientX; });
const endDrag = (e) => { if (IN.drag && IN.drag.id === e.pointerId) IN.drag = null; }; canvas.addEventListener('pointerup', endDrag); canvas.addEventListener('pointercancel', endDrag);
const HEAD = { on: false, ready: false, fb: [], neu: 0, k: 1.2, gain: 1, cur: null, s: 0, t: 0, fitT: 0, ax: [.577, -.577, .577] };
const hproj = (v) => (v[0] * HEAD.ax[0] + v[1] * HEAD.ax[1] + v[2] * HEAD.ax[2]) / (Math.abs(HEAD.ax[0]) + Math.abs(HEAD.ax[1]) + Math.abs(HEAD.ax[2]));
function headFit() { const fb = HEAD.fb, n = fb.length; if (n < 25) return; const pr = fb.slice(-600).map(hproj).sort((a, b) => a - b), med = pr[pr.length >> 1], dev = pr.map((x) => Math.abs(x - med)).sort((a, b) => a - b), q90 = dev[Math.floor(dev.length * .9)]; HEAD.neu = n < 45 ? med : HEAD.neu + (med - HEAD.neu) * .06; HEAD.k = HEAD.k + (.9 / clamp(q90, .3, 2.5) - HEAD.k) * (n < 60 ? 1 : .12); HEAD.ready = n >= 40; }
function headCentre() { if (HEAD.cur) HEAD.neu = hproj([HEAD.cur[0] / 8, HEAD.cur[1] / 5, HEAD.cur[2] / 3.5]); }
async function headStart(onStage) {
  const video = document.createElement('video'); video.playsInline = true; video.muted = true; video.autoplay = true; video.style.cssText = 'position:fixed;right:0;bottom:0;width:2px;height:2px;opacity:.01;pointer-events:none'; document.body.appendChild(video);
  const m = await import('../stargaze/tracker.js'), tr = new m.Tracker(video); tr.noBlend = true; tr.camW = 640; tr.camH = 480; tr.fullRes = false; tr.useWorker = true; tr.inW = 256;
  tr.onSteady = () => { const f = [tr.head ? tr.head.yaw * 57.2958 : 0, tr.head ? tr.head.roll * 57.2958 : 0, (tr.feat ? tr.feat[5] : 0) * 100]; HEAD.t = performance.now(); HEAD.cur = HEAD.cur ? HEAD.cur.map((c, i) => c + (f[i] - c) * .7) : f; HEAD.fb.push([f[0] / 8, f[1] / 5, f[2] / 3.5]); if (HEAD.fb.length > 900) HEAD.fb.shift(); };
  await tr.start(onStage); HEAD.on = true; HEAD.tr = tr;
}
function readSteer(dt) {
  let s = 0;
  if (HEAD.on) { if (performance.now() - HEAD.fitT > 400) { HEAD.fitT = performance.now(); headFit(); } const lost = performance.now() - HEAD.t > 400; if (HEAD.ready && HEAD.cur && !lost) { const pr = hproj([HEAD.cur[0] / 8, HEAD.cur[1] / 5, HEAD.cur[2] / 3.5]); let v = -(pr - HEAD.neu) * HEAD.k * HEAD.gain; const a = Math.abs(v); v = a < .05 ? 0 : Math.sign(v) * (a - .05) / .95; s = clamp(v * 1.05, -1, 1); } HEAD.s += (s - HEAD.s) * (1 - Math.exp(-dt / .07)); s = HEAD.s; }
  const k = IN.keyR - IN.keyL; if (k) s = k; else if (IN.drag && IN.drag.x !== undefined) s = clamp((IN.drag.x - IN.drag.x0) / (innerWidth * .2), -1, 1);
  return s;
}

// ------------------------------------------------------------------ PHYSICS
function stepCar(c, dt, steerIn, boostIn) {
  const fx = Math.sin(c.psi), fz = -Math.cos(c.psi), rx = Math.cos(c.psi), rz = Math.sin(c.psi);
  c.steer += (steerIn - c.steer) * (1 - Math.exp(-dt / .06)); c.hurtT = Math.max(0, c.hurtT - dt); c.od = Math.max(0, c.od - dt);
  c.boosting = !!boostIn && c.boost > .02 && c.grounded; if (c.boosting) c.boost = Math.max(0, c.boost - dt * .5); else c.boost = Math.min(1, c.boost + dt * .07);
  if (c.grounded) {
    const e = .8, gx = (H(c.x + e, c.z) - H(c.x - e, c.z)) / (2 * e), gz = (H(c.x, c.z + e) - H(c.x, c.z - e)) / (2 * e); c.vx += -G * .55 * gx * dt; c.vz += -G * .55 * gz * dt;
    const along = c.vx * fx + c.vz * fz, cru = 19 * c.speedK * (c.od > 0 ? 1.25 : 1) + (c.boosting ? 16 : 0);
    if (along < cru) { const a = (c.boosting ? 32 : 15) * dt; c.vx += fx * a; c.vz += fz * a; } else { const k = (along - cru) * Math.min(1, .9 * dt); c.vx -= fx * k; c.vz -= fz * k; }
    const al = c.vx * fx + c.vz * fz; let lat = c.vx * rx + c.vz * rz; const sp = Math.hypot(c.vx, c.vz), grip = c.boosting ? 3.4 : (Math.abs(c.steer) > .8 && sp > 18 ? 4.4 : 6.5); lat *= Math.exp(-grip * dt); c.vx = fx * al + rx * lat; c.vz = fz * al + rz * lat;
    const spd = Math.hypot(c.vx, c.vz); c.psi += c.steer * 2.6 / (1 + spd / 22) * Math.min(1, spd / 6) * dt;
  } else { c.psi += c.steer * .5 * dt; const k = Math.exp(-.1 * dt); c.vx *= k; c.vz *= k; }
  c.x += c.vx * dt; c.z += c.vz * dt;
  const gnd = H(c.x, c.z);
  if (c.grounded) { const vg = (gnd - c.y) / Math.max(dt, 1e-4); if (vg < c.vy - G * dt - .8 - .05 * Math.hypot(c.vx, c.vz)) { c.grounded = false; c.vy = Math.min(c.vy, 16) - G * dt; c.y += c.vy * dt; } else { c.y = gnd; c.vy = clamp(vg, -30, 16); } }
  else { c.vy -= G * dt; c.y += c.vy * dt; if (c.y <= gnd) { const imp = -c.vy; c.y = gnd; c.vy = 0; c.grounded = true; if (imp > 8) landed(c, imp); } }
  const r = Math.hypot(c.x, c.z); if (r > R - 3) { const nx = c.x / r, nz = c.z / r; c.x = nx * (R - 3); c.z = nz * (R - 3); const vn = c.vx * nx + c.vz * nz; if (vn > 0) { c.vx -= 1.35 * vn * nx; c.vz -= 1.35 * vn * nz; if (vn > 10) wallHit(c, vn); } }
}
const OFFS = [-.9, 0, .9];
let shake = 0, hitStop = 0, slowT = 0, flash = 0, lightT = 0;
function carHit(a, b, nx, nz, closing) {
  const fa = Math.max(0, Math.sin(a.psi) * nx + -Math.cos(a.psi) * nz), fb = Math.max(0, -(Math.sin(b.psi) * nx + -Math.cos(b.psi) * nz)), base = Math.max(0, closing - 3.5) * 1.15;
  let da = base * (1 - .55 * fa) * (.65 + .9 * fb) / a.mass * (b.od > 0 ? 1.6 : 1), db = base * (1 - .55 * fb) * (.65 + .9 * fa) / b.mass * (a.od > 0 ? 1.6 : 1);
  da = Math.min(da, 45); db = Math.min(db, 45); damage(a, da, b); damage(b, db, a);
  const mx = (a.x + b.x) / 2, mz = (a.z + b.z) / 2, my = (a.y + b.y) / 2 + 1; const pw = clamp(closing / 18, .2, 1.5); sparks(mx, my, mz, Math.round(8 + closing), pw); sfxCrash(pw * (a.isPlayer || b.isPlayer ? 1 : .55));
  if (a.isPlayer || b.isPlayer) { shake = Math.max(shake, clamp(closing / 22, .15, 1)); if (closing > 12) { hitStop = .06; flash = Math.max(flash, .35); } }
}
function collide() {
  for (let i = 0; i < cars.length; i++) for (let j = i + 1; j < cars.length; j++) {
    const a = cars[i], b = cars[j]; if (!a.alive || !b.alive || Math.abs(a.y - b.y) > 2.4) continue; const dx0 = b.x - a.x, dz0 = b.z - a.z; if (dx0 * dx0 + dz0 * dz0 > 36) continue;
    let best = 0, bnx = 0, bnz = 0;
    for (const oa of OFFS) for (const ob of OFFS) { const ax = a.x + Math.sin(a.psi) * oa, az = a.z - Math.cos(a.psi) * oa, bx2 = b.x + Math.sin(b.psi) * ob, bz = b.z - Math.cos(b.psi) * ob, dx = bx2 - ax, dz = bz - az, d = Math.hypot(dx, dz), pen = 2.4 - d; if (pen > best && d > .01) { best = pen; bnx = dx / d; bnz = dz / d; } }
    if (best <= 0) continue;
    const ma = 1 / a.mass, mb = 1 / b.mass, tot = ma + mb; a.x -= bnx * best * ma / tot; a.z -= bnz * best * ma / tot; b.x += bnx * best * mb / tot; b.z += bnz * best * mb / tot;
    const vrel = (b.vx - a.vx) * bnx + (b.vz - a.vz) * bnz; if (vrel < 0) { const j2 = -(1.45) * vrel / tot; a.vx -= j2 * ma * bnx; a.vz -= j2 * ma * bnz; b.vx += j2 * mb * bnx; b.vz += j2 * mb * bnz; if (-vrel > 3.5 && (a.hitCd || 0) <= 0) { a.hitCd = b.hitCd = .12; carHit(a, b, bnx, bnz, -vrel); } }
  }
  for (const c of cars) c.hitCd = Math.max(0, (c.hitCd || 0) - 1 / 60);
}
function landed(c, imp) { if (c.isPlayer) { shake = Math.max(shake, clamp(imp / 26, .12, .7)); sfxLand(clamp(imp / 20, .3, 1)); } sparks(c.x, c.y + .3, c.z, 10, .6, .1); smoke(c.x, c.y + .3, c.z, 5, 3, false); if (imp > 20) damage(c, (imp - 20) * .6, null); }
function wallHit(c, vn) { sparks(c.x, c.y + 1, c.z, 6, .6); if (c.isPlayer) { shake = Math.max(shake, .3); sfxCrash(.5); } if (vn > 16) damage(c, (vn - 16) * .8, null); }
function damage(c, d, by) { if (!c.alive || d <= 0) return; c.hp -= d; c.hurtT = .3; if (c.hp <= 0) wreck(c, by); }

// ------------------------------------------------------------------ GAME STATE, CALLOUTS, SCREENS
const S = { mode: 'menu', t: 0, wrecks: 0, time: 0, countdown: 0, orbit: 0, over: null, streak: [], first: false };
const el = (tag, css, html) => { const e = document.createElement(tag); if (css) e.style.cssText = css; if (html !== undefined) e.innerHTML = html; return e; };
const callEl = el('div'); callEl.id = 'call'; UI.appendChild(callEl);
function callout(text, col, voice) { callEl.className = ''; void callEl.offsetWidth; callEl.textContent = text; callEl.style.color = col || '#fff'; callEl.className = 'go'; if (voice) say(typeof voice === 'string' ? voice : text); }
const feedEl = el('div', 'position:absolute;left:10px;top:64px;display:flex;flex-direction:column;gap:2px;pointer-events:none'); UI.appendChild(feedEl);
function feed(text, col) { const d = el('div', 'color:' + (col || '#fff'), text); d.className = 'feed'; feedEl.appendChild(d); while (feedEl.children.length > 4) feedEl.removeChild(feedEl.firstChild); setTimeout(() => d.remove(), 5000); }
const hudBox = el('div', 'position:absolute;left:10px;top:10px;width:clamp(96px,30vw,170px);display:flex;flex-direction:column;gap:5px'); hudBox.innerHTML = '<div class="tiny" id="hpL">HEALTH</div><div class="bar"><i id="hpB" style="background:#3dff8a"></i></div><div class="bar" style="height:6px"><i id="bsB" style="background:#19e6ff"></i></div>'; UI.appendChild(hudBox);
const leftEl = el('div', 'position:absolute;left:50%;top:10px;transform:translateX(-50%);font:900 clamp(13px,3.6vw,18px) system-ui,sans-serif;letter-spacing:.08em;text-shadow:0 0 6px #000,0 0 3px #000;white-space:nowrap'); UI.appendChild(leftEl);
const btnBoost = el('div', 'position:absolute;right:max(14px,env(safe-area-inset-right));bottom:max(18px,env(safe-area-inset-bottom));width:74px;height:74px;border-radius:50%', 'BOOST'); btnBoost.className = 'btn cool'; btnBoost.style.padding = '0'; btnBoost.style.fontSize = '14px';
btnBoost.addEventListener('pointerdown', (e) => { e.stopPropagation(); IN.boost = true; try { btnBoost.setPointerCapture(e.pointerId); } catch (er) { } }); const bUp = () => { IN.boost = false; }; btnBoost.addEventListener('pointerup', bUp); btnBoost.addEventListener('pointercancel', bUp); UI.appendChild(btnBoost);
const btnMute = el('div', 'position:absolute;right:max(10px,env(safe-area-inset-right));top:10px;min-width:46px;padding:0 12px', 'SOUND'); btnMute.className = 'btn'; btnMute.style.fontSize = '11px'; btnMute.onclick = () => { setSound(!SOUND); btnMute.style.opacity = SOUND ? 1 : .5; }; UI.appendChild(btnMute);
const btnCtr = el('div', 'position:absolute;right:max(10px,env(safe-area-inset-right));top:62px;width:46px;padding:0;display:none', '⌖'); btnCtr.className = 'btn'; btnCtr.style.fontSize = '22px'; btnCtr.setAttribute('aria-label', 'Centre'); btnCtr.onclick = headCentre; UI.appendChild(btnCtr);
const arrows = []; for (let i = 0; i < 3; i++) { const a = el('div'); a.className = 'arrow'; a.style.display = 'none'; UI.appendChild(a); arrows.push(a); }
const layer = el('div', 'position:absolute;inset:0;display:flex;align-items:center;justify-content:center;padding:8px;box-sizing:border-box'); UI.appendChild(layer);
function showHud(on) { hudBox.style.display = leftEl.style.display = btnBoost.style.display = on ? '' : 'none'; feedEl.style.display = on ? '' : 'none'; btnCtr.style.display = on && HEAD.on ? '' : 'none'; }
function menuCard() {
  layer.innerHTML = ''; showHud(false);
  const c = el('div'); c.className = 'card';
  c.innerHTML = '<div class="title">SMASH DERBY</div><div class="sub">Six cars. One bowl. Wreck them all and be the last one running.</div>';
  const row = el('div'); row.className = 'row'; const bf = el('div', '', 'STEER WITH FACE'); bf.className = 'btn hot'; const bt = el('div', '', 'TOUCH / KEYS'); bt.className = 'btn cool'; row.append(bf, bt); c.appendChild(row);
  const st = el('div'); st.className = 'tiny'; st.textContent = 'Face steering needs your camera. Nothing is recorded or sent.'; c.appendChild(st);
  const row2 = el('div'); row2.className = 'row'; const bc = el('div', '', CALM ? 'CALM FX: ON' : 'CALM FX: OFF'); bc.className = 'btn'; bc.style.cssText += ';min-height:36px;font-size:12px;padding:6px 14px'; bc.onclick = () => { CALM = !CALM; bc.textContent = CALM ? 'CALM FX: ON' : 'CALM FX: OFF'; }; row2.appendChild(bc); c.appendChild(row2);
  layer.appendChild(c);
  bt.onclick = () => { audioStart(); begin(false); };
  bf.onclick = async () => { audioStart(); bf.style.opacity = .6; st.textContent = 'Starting the camera...'; try { await headStart((m) => { st.textContent = m === 'camera' ? 'Starting the camera...' : m === 'model' ? 'Loading the face model...' : 'Look straight ahead...'; }); st.textContent = 'Look straight ahead...'; const t0 = performance.now(); const wait = () => { headFit(); if (HEAD.ready) { begin(true); } else if (performance.now() - t0 > 12000) { st.textContent = 'Could not see your face. Use touch or keys instead.'; bf.style.opacity = 1; } else { setTimeout(wait, 150); } }; wait(); } catch (e) { st.textContent = 'The camera did not start (' + ((e && e.message) || e) + '). Use touch or keys instead.'; bf.style.opacity = 1; } };
}
function endCard(win) {
  layer.innerHTML = ''; showHud(false); const c = el('div'); c.className = 'card';
  c.innerHTML = '<div class="title" style="font-size:clamp(28px,8.5vw,56px)">' + (win ? 'LAST CAR STANDING' : 'YOU WERE WRECKED') + '</div><div class="sub">' + (win ? 'Every rival is scrap. Nice driving.' : 'The bowl keeps what it breaks.') + '</div><div class="tiny">WRECKS ' + S.wrecks + '  ·  TIME ' + Math.round(S.time) + ' S</div>';
  const row = el('div'); row.className = 'row'; const ba = el('div', '', 'AGAIN'); ba.className = 'btn hot'; ba.onclick = () => begin(HEAD.on); row.appendChild(ba); c.appendChild(row); layer.appendChild(c);
}
function begin(head) { placeCars(); for (const p of PICK) { p.on = true; p.mesh.visible = true; } clearFx(); S.mode = 'count'; S.countdown = 3.6; S.wrecks = 0; S.time = 0; S.streak = []; S.first = false; S.over = null; S.lastN = 0; layer.innerHTML = ''; showHud(true); intensity = .5; feedEl.innerHTML = ''; }
function clearFx() { for (const m of debris) m.visible = false; }
function aliveRivals() { return cars.filter((c) => c.alive && !c.isPlayer); }

function wreck(c, by) {
  c.alive = false; c.hp = 0; sfxWreck(); sparks(c.x, c.y + 1, c.z, 70, 1.5); fire(c.x, c.y + 1, c.z, 30, 6); smoke(c.x, c.y + 1, c.z, 26, 5, true); debrisBurst(c, 12);
  c.bodyMat.color.setHex(0x1a1a22); c.glow.visible = false; if (c.sprite) c.sprite.visible = false; c.vx *= .3; c.vz *= .3; c.smokeT = 0;
  const near = Math.hypot(c.x - player.x, c.z - player.z); shake = Math.max(shake, clamp(1 - near / 60, .1, 1)); flash = Math.max(flash, .5 * clamp(1 - near / 50, 0, 1)); flashLight.position.set(c.x, c.y + 4, c.z); lightT = .5; if (near < 40) slowT = .5;
  const inRound = S.mode === 'play';
  if (inRound && by && by.isPlayer && c !== player) { S.wrecks++; by.wrecks++; S.streak.push(S.time); S.streak = S.streak.filter((t) => S.time - t < 4); const n = S.streak.length; const names = [null, S.first ? 'WRECKED' : 'FIRST WRECK', 'DOUBLE WRECK', 'TRIPLE WRECK', 'MEGA WRECK', 'GODLIKE']; const txt = names[Math.min(n, 5)]; S.first = true; callout(txt, ['', '#ffd23a', '#ff9a1f', '#ff4d8a', '#ff2fe0', '#19e6ff'][Math.min(n, 5)], true); }
  if (inRound) feed(c.name + (by ? ' was wrecked by ' + by.name : ' wrecked itself'), '#' + new THREE.Color(c.col).getHexString());
  if (inRound && by && !by.isPlayer && Math.random() < .5 && by.taunt) feed(by.name + ': ' + by.taunt, '#cfc4ff');
  if (inRound && c === player) { S.mode = 'dying'; S.over = { t: 1.7, win: false }; callout('WRECKED', '#ff3a3a', 'You are wrecked.'); }
  else if (inRound && aliveRivals().length === 0 && player.alive) { S.mode = 'dying'; S.over = { t: 1.6, win: true }; callout('LAST CAR STANDING', '#19e6ff', 'Last car standing.'); }
}

// ------------------------------------------------------------------ THE COMPUTER DRIVERS
function aiDrive(c, dt) {
  const A = c.ai; A.t -= dt; if (A.t <= 0 || !A.target || !A.target.alive) { A.t = rnd(1.2, 2.8); let best = null, bs = 1e9; for (const o of cars) { if (o === c || !o.alive) continue; let d = Math.hypot(o.x - c.x, o.z - c.z); if (o.isPlayer && !AUTO) d *= .72 * (2 - A.aggr); d += rnd(0, 30); if (d < bs) { bs = d; best = o; } } A.target = best; A.flee = c.hp < c.hpMax * .3 && Math.random() < .75 * A.caution + .1; }
  const T = A.target; let tx = 0, tz = 0, d = 99;
  if (T) { const lead = .5 * A.skill, back = 3.2 * A.skill; tx = T.x + T.vx * lead - Math.sin(T.psi) * back; tz = T.z + T.vz * lead + Math.cos(T.psi) * back; if (A.flee) { tx = c.x - (T.x - c.x) * 2; tz = c.z - (T.z - c.z) * 2; } }
  if (!A.flee) { const near = PICK.find((p) => p.on && Math.hypot(p.x - c.x, p.z - c.z) < 30 && (p.type === 'hp' ? c.hp < c.hpMax * .7 : p.type === 'trip')); if (near && (!T || Math.hypot(T.x - c.x, T.z - c.z) > 22)) { tx = near.x; tz = near.z; } }
  const r = Math.hypot(c.x, c.z); if (r > R - 20) { const k = clamp((r - (R - 20)) / 14, 0, 1); tx = lerp(tx, 0, k); tz = lerp(tz, 0, k); }
  d = Math.hypot(tx - c.x, tz - c.z); const ang = Math.atan2(tx - c.x, -(tz - c.z)); const err = wrap(ang - c.psi); A.wob += dt * 1.7;
  const steer = clamp(err * 2.4, -1, 1) * (.78 + .22 * A.skill) + Math.sin(A.wob) * .1 * (1 - A.skill); const boost = !A.flee && d < 28 && Math.abs(err) < .3 && c.boost > .4 && Math.random() < A.aggr * dt * 2.2;
  return { steer, boost };
}

// ------------------------------------------------------------------ THE MAIN LOOP
const postMat = new THREE.ShaderMaterial({ uniforms: { tex: { value: rt.texture }, uTime: U.uTime, uAb: { value: 0 }, uVig: { value: .5 }, uHue: { value: 0 }, uFlash: { value: 0 }, uWarp: { value: 0 }, uSpeed: { value: 0 } },
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }',
  fragmentShader: `uniform sampler2D tex; uniform float uTime, uAb, uVig, uHue, uFlash, uWarp, uSpeed; varying vec2 vUv;
    vec3 hueRot(vec3 c, float a){ float cs = cos(a), sn = sin(a); mat3 m = mat3(.299 + .701 * cs + .168 * sn, .299 - .299 * cs - .328 * sn, .299 - .3 * cs + 1.25 * sn, .587 - .587 * cs + .33 * sn, .587 + .413 * cs + .035 * sn, .587 - .588 * cs - 1.05 * sn, .114 - .114 * cs - .497 * sn, .114 - .114 * cs + .292 * sn, .114 + .886 * cs - .203 * sn); return m * c; }
    void main(){ vec2 c = vUv - .5; float r = length(c); vec2 uv = vUv + c * r * uWarp * sin(uTime * 1.3); vec2 dir = c * (.5 + r) ;
      vec3 col = vec3(0.); float tot = 0.; for (int i = 0; i < 5; i++) { float k = float(i) / 4.; vec2 o = -dir * uSpeed * k * .06; float w = 1. - k * .6; col.r += texture2D(tex, uv + o + dir * uAb * .012).r * w; col.g += texture2D(tex, uv + o).g * w; col.b += texture2D(tex, uv + o - dir * uAb * .012).b * w; tot += w; } col /= tot;
      col = hueRot(col, uHue); col *= 1. - uVig * smoothstep(.3, .95, r); col += uFlash * vec3(1., .85, .7); col *= .96 + .04 * sin(vUv.y * 900.); gl_FragColor = vec4(col, 1.); }` });
const post = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), postMat); post.frustumCulled = false; const postScene = new THREE.Scene(); postScene.add(post); const postCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
let last = performance.now(), fpsAcc = 0, fpsN = 0, camYaw = 0, camPitch = 0, camRoll = 0, camFov = 74, orbitA = 0;
function frame(now) {
  requestAnimationFrame(frame); let dtR = Math.min(.05, (now - last) / 1000); last = now; fpsAcc += dtR; fpsN++;
  let ts = 1; if (hitStop > 0) { hitStop -= dtR; ts = .03; } else if (slowT > 0) { slowT -= dtR; ts = .38; } const dt = dtR * ts; U.uTime.value += dtR; S.orbit += dtR;
  // state machine
  if (S.mode === 'count') { S.countdown -= dtR; const n = Math.ceil(S.countdown); if (n !== S.lastN && n >= 1 && n <= 3) { S.lastN = n; callout(String(n), '#ffd23a'); tone('square', 440, 0, .12, .25); } if (S.countdown <= 0) { S.mode = 'play'; S.lastN = 0; callout('GO GO GO', '#ff2fa0', 'Go!'); tone('square', 880, 0, .3, .3); intensity = 1; } }
  if (S.mode === 'play' || S.mode === 'dying') S.time += dtR;
  if (S.mode === 'menu' || S.mode === 'over') { const na = cars.filter((c) => c.alive).length; S.reset = na <= 2 ? (S.reset || 0) + dtR : 0; if (S.reset > 3) { S.reset = 0; placeCars(); clearFx(); } }
  if (S.mode === 'dying' && S.over) { S.over.t -= dtR; if (S.over.t <= 0) { const w = S.over.win; S.over = null; S.mode = 'over'; endCard(w); intensity = .4; } }
  // drive the cars (physics in small steps)
  const live = S.mode === 'play' || S.mode === 'dying' || S.mode === 'menu' || S.mode === 'over'; const moving = true;
  if (live) { const n = Math.max(1, Math.ceil(dt / (1 / 60))), h = dt / n; for (let k = 0; k < n; k++) { for (const c of cars) { if (!c.alive) { c.vx *= Math.exp(-1.2 * h); c.vz *= Math.exp(-1.2 * h); stepCar(c, h, 0, false); continue; } let ctl; if (!moving) ctl = { steer: 0, boost: false }; else if (c.isPlayer && !AUTO && (S.mode === 'play' || S.mode === 'dying')) ctl = { steer: readSteerCached, boost: IN.boost }; else ctl = aiDrive(c, h); stepCar(c, h, ctl.steer, ctl.boost); if (c.isPlayer && ctl.boost && c.boosting && !c.boostSfx) { c.boostSfx = .5; sfxBoost(); } c.boostSfx = Math.max(0, (c.boostSfx || 0) - h); } if (moving) collide(); } }
  if ((S.mode === 'play' || S.mode === 'dying' || S.mode === 'count') && !AUTO) readSteerCached = readSteer(dtR); else readSteerCached = 0;
  // pickups
  for (const p of PICK) { p.mesh.rotation.y += dtR * 2; p.mesh.position.y = H(p.x, p.z) + 1.7 + Math.sin(U.uTime.value * 3 + p.x) * .25; if (!p.on) { p.t -= dtR; if (p.t <= 0) { p.on = true; p.mesh.visible = true; const a = rnd(0, 6.283), rr = rnd(12, 62); p.x = Math.cos(a) * rr; p.z = Math.sin(a) * rr; } continue; } for (const c of cars) { if (!c.alive || Math.hypot(c.x - p.x, c.z - p.z) > 3.4 || Math.abs(c.y - p.mesh.position.y) > 4) continue; p.on = false; p.mesh.visible = false; p.t = 9; if (p.type === 'hp') c.hp = Math.min(c.hpMax, c.hp + 40); else if (p.type === 'boost') c.boost = 1; else { c.od = 6; if (c.isPlayer) callout('OVERDRIVE', '#ff2fe0', true); } if (c.isPlayer) sfxPick(p.type); sparks(p.x, p.y || 1, p.z, 18, .7, p.type === 'hp' ? .38 : p.type === 'boost' ? .52 : .85); break; } }
  // visuals of the cars
  for (const c of cars) {
    const m = c.mesh; m.position.set(c.x, c.y, c.z); const fx = Math.sin(c.psi), fz = -Math.cos(c.psi), a = H(c.x + fx * 2, c.z + fz * 2), b = H(c.x - fx * 2, c.z - fz * 2); m.rotation.x = clamp(Math.atan2(a - b, 4), -.6, .6); const rxs = Math.cos(c.psi), rzs = Math.sin(c.psi), lat = H(c.x + rxs, c.z + rzs) - H(c.x - rxs, c.z - rzs); m.rotation.z = clamp(-Math.atan2(lat, 2) * .8, -.5, .5) - c.steer * .07; m.rotation.y = -c.psi;
    if (!c.alive) { m.rotation.z += .0; } else { c.glow.material.opacity = .35 + .25 * Math.sin(U.uTime.value * 6 + c.x) + (c.od > 0 ? .3 : 0); }
    const frac = c.hp / c.hpMax; if (c.alive && c.tag && Math.abs(frac - c.tagHp) > .02) { c.tagHp = frac; drawTag(c.tag, frac); }
    c.smokeT -= dtR; if (c.smokeT <= 0) { const sp = Math.hypot(c.vx, c.vz); if (!c.alive) { c.smokeT = .07; smoke(c.x, c.y + 1.2, c.z, 1, 3.5, true); if (Math.random() < .35) fire(c.x, c.y + 1.2, c.z, 1, 3); } else if (frac < .4) { c.smokeT = frac < .2 ? .05 : .1; smoke(c.x - Math.sin(c.psi) * -1.6, c.y + 1.1, c.z + Math.cos(c.psi) * -1.6, 1, 2.5, true); if (frac < .2) fire(c.x, c.y + 1, c.z, 1, 3); } else if (c.boosting) { c.smokeT = .03; const fxs = Math.sin(c.psi), fzs = -Math.cos(c.psi); FX.spawn(c.x - fxs * 2.4, c.y + .7, c.z - fzs * 2.4, -fxs * 8 + rnd(-1, 1), rnd(0, 2), -fzs * 8 + rnd(-1, 1), 1, .55, .1, 1.5, .35, 0); } else if (c.grounded && sp > 6 && Math.abs(c.steer) > .7 && Math.random() < .5) { c.smokeT = .06; smoke(c.x, c.y + .3, c.z, 1, 2, false); } else c.smokeT = .05; }
  }
  FX.step(dtR); SMK.step(dtR); stepDebris(dt);
  // the arena show
  for (const b of beams) { const a = b.userData.a + U.uTime.value * .25, rr = R - 6; b.position.set(Math.cos(a) * rr, H(Math.cos(a) * rr, Math.sin(a) * rr) + 70, Math.sin(a) * rr); b.lookAt(Math.cos(a + 1.7) * 18, 0, Math.sin(a + 1.7) * 18); b.rotateX(Math.PI / 2); }
  lightT = Math.max(0, lightT - dtR); flashLight.intensity = lightT * 90; U.uTrip.value = lerp(U.uTrip.value, player && player.od > 0 ? 1 : 0, 1 - Math.exp(-dtR * 3));
  // camera
  const playing = (S.mode === 'play' || S.mode === 'count' || (S.mode === 'dying' && player.alive)) && !AUTO;
  const fp = playing || (AUTO && S.mode !== 'menu' && S.mode !== 'over' && player.alive); hood.visible = fp; hood.scale.x = clamp(camera.aspect / 1.9, .35, 1); player.mesh.visible = !fp && player.alive || (!fp && !player.alive);
  if (fp) { const c = player, sp = Math.hypot(c.vx, c.vz), fx = Math.sin(c.psi), fz = -Math.cos(c.psi); const ahead = H(c.x + fx * 10, c.z + fz * 10) - H(c.x, c.z), tp = clamp(Math.atan2(ahead, 10) * .7, -.35, .45); camPitch += (tp - camPitch) * Math.min(1, dtR * 6); camYaw = -c.psi; camRoll += ((-c.steer * .06) - camRoll) * Math.min(1, dtR * 6); const tf = 74 + sp * .32 + (c.boosting ? 14 : 0) + (c.od > 0 ? 8 : 0); camFov += (tf - camFov) * Math.min(1, dtR * 5);
    camera.position.set(c.x + fx * .5, c.y + 1.45 + (c.grounded ? 0 : 0), c.z + fz * .5); camera.rotation.set(camPitch, camYaw, camRoll); }
  else { orbitA += dtR * .16; const foc = S.mode === 'over' || S.mode === 'dying' ? player : null; const cx = foc ? foc.x : 0, cz = foc ? foc.z : 0, rr = foc ? 26 : 78; camera.position.set(cx + Math.cos(orbitA) * rr, (foc ? foc.y + 13 : 40), cz + Math.sin(orbitA) * rr); camera.lookAt(cx, foc ? foc.y + 1 : 4, cz); camFov += (70 - camFov) * Math.min(1, dtR * 4); }
  if (camFov !== camera.fov) { camera.fov = camFov; camera.updateProjectionMatrix(); }
  shake = Math.max(0, shake - dtR * 1.8); if (shake > 0) { camera.position.x += rnd(-1, 1) * shake * .35; camera.position.y += rnd(-1, 1) * shake * .3; camera.position.z += rnd(-1, 1) * shake * .35; camera.rotation.z += rnd(-1, 1) * shake * .03; }
  sky.position.copy(camera.position);
  // sound follows the player's car
  if (engOsc && AC) { const sp = player ? Math.hypot(player.vx, player.vz) : 0, on = SOUND && (S.mode === 'play' || S.mode === 'dying') && player.alive; engOsc.frequency.setTargetAtTime(48 + sp * 3.2 + (player.boosting ? 40 : 0), AC.currentTime, .05); engFilt.frequency.setTargetAtTime(260 + sp * 24, AC.currentTime, .05); engGain.gain.setTargetAtTime(on ? .07 : 0, AC.currentTime, .1); }
  // the screens and HUD
  if (player) { const f = clamp(player.hp / player.hpMax, 0, 1); document.getElementById('hpB').style.width = (f * 100) + '%'; document.getElementById('hpB').style.background = f > .5 ? '#3dff8a' : f > .25 ? '#ffd23a' : '#ff3a3a'; document.getElementById('bsB').style.width = (player.boost * 100) + '%'; leftEl.textContent = (S.mode === 'count' ? 'GET READY' : aliveRivals().length + (aliveRivals().length === 1 ? ' CAR LEFT' : ' CARS LEFT')); }
  if (S.mode === 'play') { const sorted = aliveRivals().map((c) => ({ c, d: Math.hypot(c.x - player.x, c.z - player.z) })).sort((a, b) => a.d - b.d).slice(0, 3); arrows.forEach((a, i) => { const s2 = sorted[i]; if (!s2 || !player.alive) { a.style.display = 'none'; return; } const rel = wrap(Math.atan2(s2.c.x - player.x, -(s2.c.z - player.z)) - player.psi), half = camera.fov * Math.PI / 360 * camera.aspect * .9; if (Math.abs(rel) < Math.min(half, 1.0) && s2.d > 6) { a.style.display = 'none'; return; } a.style.display = ''; const W2 = innerWidth, H2 = innerHeight; a.style.left = (W2 / 2 + Math.sin(rel) * W2 * .44) + 'px'; a.style.top = (H2 / 2 - Math.cos(rel) * H2 * .36) + 'px'; a.style.transform = 'rotate(' + rel + 'rad)'; a.style.borderBottomColor = '#' + new THREE.Color(s2.c.col).getHexString(); }); } else arrows.forEach((a) => { a.style.display = 'none'; });
  { const sc = renderer.domElement.height / (2 * Math.tan(camera.fov * Math.PI / 360)); FX.mat.uniforms.uScale.value = sc; SMK.mat.uniforms.uScale.value = sc; }
  // post pass
  { const sp = player ? Math.hypot(player.vx, player.vz) : 0, k = CALM ? .35 : 1; const od = player && player.od > 0 ? 1 : 0; postMat.uniforms.uAb.value = (.25 + sp * .04 + (player && player.boosting ? 1.2 : 0) + shake * 2) * k; postMat.uniforms.uSpeed.value = clamp((sp - 12) / 30, 0, 1) * .6 * k + (player && player.boosting ? .5 * k : 0); postMat.uniforms.uHue.value = od * Math.sin(U.uTime.value * .9) * .55 * k; postMat.uniforms.uWarp.value = (od * .05 + .01) * k; flash = Math.max(0, flash - dtR * 2.6); postMat.uniforms.uFlash.value = flash * (CALM ? .4 : 1) * .5; postMat.uniforms.uVig.value = .5 + (player && player.hp < player.hpMax * .3 ? .3 : 0); }
  renderer.setRenderTarget(rt); renderer.render(scene, camera); renderer.setRenderTarget(null); renderer.render(postScene, postCam);
  if (fpsAcc > 1) { window.__fps = Math.round(fpsN / fpsAcc); fpsAcc = 0; fpsN = 0; }
}
let readSteerCached = 0;
requestAnimationFrame(frame);
menuCard();
if (AUTO) { audioStart(); begin(false); }
window.__derby = { S, cars, IN, HEAD, H, endCard, menuCard, damage, get player() { return player; }, begin, headInject(yaw, roll, f5) { HEAD.on = true; HEAD.t = performance.now(); const f = [yaw, roll, f5]; HEAD.cur = HEAD.cur ? HEAD.cur.map((c, i) => c + (f[i] - c) * .7) : f; HEAD.fb.push([f[0] / 8, f[1] / 5, f[2] / 3.5]); } };

// PER-BIOME HORIZON: the distant ring of mountains is one mesh in every biome (pointy peaks). This builds a replacement silhouette for the biomes that should not have pointy peaks, in the same frame and size as the
// original ring (taken from its bounding box), as a vertex-coloured wall that the biome's own ring material then skins.
//   mesas      flat-topped plateaus of different heights, with steep sides            (desert)
//   skyline    blocks of towers, flat tops, a few taller landmarks                      (matrix)
//   hills      soft rounded bumps, like scoops of ice cream                             (candy)
//   retro      low symmetrical triangle peaks, evenly spaced, the 80s mountain range   (synthwave)
//   none       no ring at all (the tunnel is a tube)
export function ringShape(THREE, kind, orig) {
  if (kind === 'none') return null;
  if (!orig.boundingBox) orig.computeBoundingBox(); const b = orig.boundingBox, cx = (b.min.x + b.max.x) / 2, cz = (b.min.z + b.max.z) / 2, y0 = b.min.y, H = b.max.y - b.min.y, Rr = Math.min(b.max.x - b.min.x, b.max.z - b.min.z) / 2 * .97;
  const hash = (n) => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };
  const N = 720, P = [], C = [], I = [];
  const prof = (t) => {          // t in 0..1 around the ring -> height 0..1
    if (kind === 'mesas') { const k = Math.floor(t * 22), f = t * 22 - k, hh = .22 + .55 * hash(k + 3), edge = Math.min(f, 1 - f); return edge < .09 ? hh * (edge / .09) : hh * (1 + .04 * Math.sin(t * 300)); }
    if (kind === 'skyline') { const k = Math.floor(t * 120), f = t * 120 - k, hh = (.12 + .5 * Math.pow(hash(k + 11), 1.6)) * (hash(k * 7 + 2) > .93 ? 1.6 : 1), edge = Math.min(f, 1 - f); return edge < .06 ? 0 : hh; }
    if (kind === 'hills') { return .2 + .22 * (.5 + .5 * Math.sin(t * Math.PI * 2 * 9)) + .14 * (.5 + .5 * Math.sin(t * Math.PI * 2 * 23 + 1)); }
    if (kind === 'retro') { const f = (t * 26) % 1, tri = 1 - Math.abs(f - .5) * 2; return .1 + .32 * Math.pow(tri, 1.15) * (.65 + .35 * hash(Math.floor(t * 26))); }
    return .3;
  };
  for (let i = 0; i <= N; i++) { const t = i / N, a = t * Math.PI * 2, r = Rr * (1 + .02 * Math.sin(a * 5)), h = prof(t) * H * 1.15, x = cx + Math.cos(a) * r, z = cz + Math.sin(a) * r, col = .55 + .45 * (h / (H * 1.15));
    P.push(x, y0, z, x, y0 + h, z); C.push(.25, .25, .3, col, col, col); if (i < N) { const v = i * 2; I.push(v, v + 1, v + 2, v + 1, v + 3, v + 2); } }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3)); g.setAttribute('color', new THREE.Float32BufferAttribute(C, 3)); g.setIndex(I); g.computeVertexNormals(); return g;
}
export const RING_KIND = { desert: 'mesas', matrix: 'skyline', candy: 'hills', synthwave: 'retro', tunnel: 'none' };

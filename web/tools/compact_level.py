#!/usr/bin/env python3
"""Shrink a split level (web/tools/split_level.py + make_physics.py output) without changing its schema:   python compact_level.py <src_dir> <dst_dir> [--lossy]

What it does (all of it readable by the existing browser loader as it is):
  * WELDS every triangle mesh: Godot's SurfaceTool meshes repeat each vertex once per triangle. Identical (position, normal, uv, colour) vertices are merged and an index
    list ('i') is written, which gv.js's geoOf() already uses. The triangle stream is verified to be unchanged (positions to 1e-3, normals to 1e-2).
  * rounds floats: positions / uv / colour 3 decimals, normals 2, node and instance transforms 3, tree and obstacle positions 2.
  * drops the 'depth' field of nodes (nothing reads it) and materials that nothing references.
  * writes compact JSON (no spaces). stats.json is copied; physics.json is rounded the same way.
Run web/tools/check_long.py on dst_dir afterwards. Sizes before / after are printed."""
import json, os, sys, shutil, glob

def rnd(x, d):
    return round(x, d) + 0.0

def rl(a, d):
    return [rnd(x, d) for x in a] if isinstance(a, list) else a

def weld_surface(s):
    v = s.get('v') or []
    if s.get('prim') != 3 or len(v) < 3:
        return s, 0
    n, uv, c, idx = s.get('n'), s.get('uv'), s.get('c'), s.get('i')
    key_of, nv, nn, nuv, nc, remap = {}, [], [], [], [], [0] * len(v)
    for k in range(len(v)):
        pv = [rnd(x, 3) for x in v[k]]
        pn = [rnd(x, 2) for x in n[k]] if n else None
        pu = [rnd(x, 3) for x in uv[k]] if uv else None
        pc = [rnd(x, 3) for x in c[k]] if c else None
        key = (tuple(pv), tuple(pn) if pn else None, tuple(pu) if pu else None, tuple(pc) if pc else None)
        j = key_of.get(key)
        if j is None:
            j = len(nv); key_of[key] = j; nv.append(pv)
            if n: nn.append(pn)
            if uv: nuv.append(pu)
            if c: nc.append(pc)
        remap[k] = j
    stream = idx if idx else list(range(len(v)))
    ni = [remap[k] for k in stream]
    # verify: the triangle stream is the same
    for t in range(len(stream)):
        a = v[stream[t]]; b = nv[ni[t]]
        assert abs(a[0] - b[0]) < 1.2e-3 and abs(a[1] - b[1]) < 1.2e-3 and abs(a[2] - b[2]) < 1.2e-3, 'weld changed a position'
        if n:
            q = n[stream[t]]; w = nn[ni[t]]
            assert abs(q[0] - w[0]) < 1.2e-2 and abs(q[1] - w[1]) < 1.2e-2 and abs(q[2] - w[2]) < 1.2e-2, 'weld changed a normal'
    out = dict(s); out['v'] = nv
    if n: out['n'] = nn
    if uv: out['uv'] = nuv
    if c: out['c'] = nc
    out['i'] = ni
    return out, len(v) - len(nv)

def compact_mesh(md):
    saved = 0; surfs = []
    for s in md['surfaces']:
        o, sv = weld_surface(s); surfs.append(o); saved += sv
    out = dict(md); out['surfaces'] = surfs
    return out, saved

LOSSY = '--lossy' in sys.argv          # instance transforms (forest trees, rocks) to 2 decimals: about 1 cm and 0.3 degrees of error, a quarter fewer digits
def inst(t): return [rnd(x, 2) for x in t] if LOSSY else rl(t, 3)

def compact_node(nd):
    nd = dict(nd); nd.pop('depth', None)
    if 'xf' in nd: nd['xf'] = rl(nd['xf'], 3)
    if 'xfs' in nd: nd['xfs'] = [inst(t) for t in nd['xfs']]
    if 'cols' in nd and isinstance(nd['cols'], list): nd['cols'] = [rl(c, 3) for c in nd['cols']]
    return nd

def refs_of_nodes(nodes, meshes, used):
    for nd in nodes:
        for k in ('mat_override', 'cmat'):
            if nd.get(k): used.add(str(nd[k]))
    for md in meshes.values():
        for s in md['surfaces']:
            if s.get('mat') is not None: used.add(str(s['mat']))

def dump(obj, path):
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(obj, fh, separators=(',', ':'))

def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    meta = json.load(open(os.path.join(src, 'meta.json'), encoding='utf-8'))
    before = sum(os.path.getsize(f) for f in glob.glob(os.path.join(src, '*.json')))
    welded = 0
    # 1. weld and round every mesh, round every node
    allm = {}                      # (where, id) -> mesh
    for k, md in meta['meshes'].items():
        allm[('meta', k)], sv = compact_mesh(md); welded += sv
    meta['nodes'] = [compact_node(n) for n in meta['nodes']]
    rows = []
    for f in sorted(glob.glob(os.path.join(src, 'row_*.json'))):
        r = json.load(open(f, encoding='utf-8')); j = r['j']
        for k, md in r['meshes'].items():
            allm[(j, k)], sv = compact_mesh(md); welded += sv
        r['nodes'] = [compact_node(n) for n in r['nodes']]
        row = r['row']
        if isinstance(row.get('obs'), list): row['obs'] = [rnd(x, 2) for x in row['obs']]
        rows.append((os.path.basename(f), r))
    ph = None
    sp = os.path.join(src, 'physics.json')
    if os.path.exists(sp):
        ph = json.load(open(sp, encoding='utf-8'))
        for r in ph['rows'].values():
            if isinstance(r.get('obs'), list): r['obs'] = [rnd(x, 2) for x in r['obs']]
            if 'trees' in r: r['trees'] = [[rnd(a, 2), rnd(b, 2)] for a, b in r['trees']]
        ph['nodes'] = [compact_node(n) for n in ph['nodes']]
    # 2. dedupe identical meshes: one canonical id per distinct content, node references rewritten everywhere
    canon, by_key = {}, {}
    for (where, k), md in allm.items():
        key = json.dumps(md['surfaces'], separators=(',', ':'), sort_keys=True)
        c = by_key.setdefault(key, k); canon[k] = c
    ndup = len(allm) - len(by_key)
    def fix(nodes):
        for nd in nodes:
            if nd.get('mesh') in canon: nd['mesh'] = canon[nd['mesh']]
    fix(meta['nodes']);
    for _, r in rows: fix(r['nodes'])
    if ph: fix(ph['nodes'])
    # 3. where each distinct mesh lives: meta if a meta node or more than one row uses it, else in its row
    uses = {}
    for nd in meta['nodes']:
        if nd.get('mesh'): uses.setdefault(nd['mesh'], set()).add('meta')
    for _, r in rows:
        for nd in r['nodes']:
            if nd.get('mesh'): uses.setdefault(nd['mesh'], set()).add(r['j'])
    content = {}
    for (where, k), md in allm.items():
        if canon[k] == k: content[k] = md
    meta['meshes'] = {k: content[k] for k, u in uses.items() if k in content and ('meta' in u or len(u) > 1)}
    for _, r in rows:
        r['meshes'] = {k: content[k] for k, u in uses.items() if k in content and u == {r['j']}}
    # 4. materials nothing references any more
    used = set()
    for md in list(meta['meshes'].values()) + [m for _, r in rows for m in r['meshes'].values()]:
        for sf in md['surfaces']:
            if sf.get('mat') is not None: used.add(str(sf['mat']))
    for nds in [meta['nodes']] + [r['nodes'] for _, r in rows]:
        for nd in nds:
            for k in ('mat_override', 'cmat'):
                if nd.get(k): used.add(str(nd[k]))
    dropped = [k for k in meta['materials'] if str(k) not in used]
    meta['materials'] = {k: v for k, v in meta['materials'].items() if str(k) in used}
    if 'trailx' in meta: meta['trailx'] = [rnd(x, 2) for x in meta['trailx']]
    dump(meta, os.path.join(dst, 'meta.json'))
    for name, r in rows: dump(r, os.path.join(dst, name))
    if ph: dump(ph, os.path.join(dst, 'physics.json'))
    for extra in ('stats.json',):
        if os.path.exists(os.path.join(src, extra)): shutil.copy(os.path.join(src, extra), os.path.join(dst, extra))
    after = sum(os.path.getsize(f) for f in glob.glob(os.path.join(dst, '*.json')))
    print('welded away %d vertices; %d duplicate meshes removed; dropped %d unused materials; %.1f MB -> %.1f MB (%.0f%%)' % (welded, ndup, len(dropped), before / 1e6, after / 1e6, 100.0 * after / before))
    for nm in ('meta.json', 'physics.json'):
        p = os.path.join(dst, nm); q = os.path.join(src, nm)
        if os.path.exists(p): print('  %-13s %8.0f KB -> %8.0f KB' % (nm, os.path.getsize(q) / 1024, os.path.getsize(p) / 1024))
    rb = sum(os.path.getsize(f) for f in glob.glob(os.path.join(src, 'row_*.json'))); ra = sum(os.path.getsize(f) for f in glob.glob(os.path.join(dst, 'row_*.json')))
    print('  rows (%d)       %8.0f KB -> %8.0f KB (avg %.0f KB per row)' % (len(rows), rb / 1024, ra / 1024, ra / 1024 / max(1, len(rows))))

main()

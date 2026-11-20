#!/usr/bin/env python3
"""Check a split level (web/tools/split_level.py output):  python check_long.py <out_dir>
Asserts: every row has a ground mesh covering its slab, ground coverage is continuous from z=0 to the end, node counts add up to the original, rows are
self-contained (every mesh a row's nodes use is in the row or in meta, every material is in meta), anim and vortex-ring references resolve inside their row.
Prints per-row sizes and counts."""
import json, os, sys

def app(xf, o): return (xf[0]*o[0]+xf[3]*o[1]+xf[6]*o[2]+xf[9], xf[1]*o[0]+xf[4]*o[1]+xf[7]*o[2]+xf[10], xf[2]*o[0]+xf[5]*o[1]+xf[8]*o[2]+xf[11])

def main():
    out = sys.argv[1]
    meta = json.load(open(os.path.join(out, 'meta.json'), encoding='utf-8')); st = json.load(open(os.path.join(out, 'stats.json')))
    n = meta['nrows']; MATS = meta['materials']; bad = 0
    def fail(msg):
        nonlocal bad; bad += 1; print('FAIL', msg)
    cover = []; tot_nodes = 0
    print('row   KB    nodes  multimesh  ground z-range      pickups pads feats obs vx rings anims')
    for j in range(n):
        r = json.load(open(os.path.join(out, 'row_%02d.json' % j), encoding='utf-8')); kb = os.path.getsize(os.path.join(out, 'row_%02d.json' % j)) / 1024
        meshes = dict(meta['meshes']); meshes.update(r['meshes']); tot_nodes += len(r['nodes']); g = None; mm = 0; rings = 0
        for nd in r['nodes']:
            if nd['class'] == 'MultiMeshInstance3D': mm += 1
            m = nd.get('mesh')
            if m and m not in meshes: fail('row %d: node %s uses mesh %s that is in neither the row nor meta' % (j, nd['name'], m))
            for k in ('mat_override',):
                if nd.get(k) and nd[k] not in MATS: fail('row %d: material %s missing' % (j, nd[k]))
            if nd['class'] == 'MeshInstance3D' and m in meshes:
                code = ''
                for s in meshes[m]['surfaces']:
                    code += (MATS.get(str(nd.get('mat_override') or s.get('mat')), {}).get('shader_code') or '')[:4000]
                if 'MOIRE' in code:
                    zs = [app(nd['xf'], v)[2] for s in meshes[m]['surfaces'] for v in (s.get('v') or [])]
                    g = (min(zs), max(zs))
        if g is None: fail('row %d has no ground mesh' % j)
        else:
            cover.append(g)
            if g[0] > r['z1'] + 1 or g[1] < r['z0'] - 1: fail('row %d ground %s does not cover its slab (%d, %d)' % (j, g, r['z1'], r['z0']))
        iids = {nd.get('iid') for nd in r['nodes']}
        for a in r['anims']:
            if a.get('n') not in iids: fail('row %d: anim root %s not in this row' % (j, a.get('n')))
        for v in r['vx']:
            for rg in v['rings']:
                rings += 1
                if rg['iid'] not in iids: fail('row %d: vortex ring %s not in this row' % (j, rg['iid']))
        rw = r['row']
        print('%3d %6.0f %6d %6d   %s  %4d %4d %4d %4d %3d %4d %5d' % (j, kb, len(r['nodes']), mm, ('%d..%d' % (g[1], g[0])) if g else 'none', len(rw.get('buffs', [])), len(rw.get('pads', [])), len(rw.get('feats', [])), len(rw.get('obs', [])) // 4, len(r['vx']), rings, len(r['anims'])))
    for a, b in zip(cover, cover[1:]):
        if abs(a[0] - b[1]) > 1.5: fail('ground gap between %s and %s' % (a, b))
    if st['row_nodes'] != tot_nodes: fail('row node count %d != stats %d' % (tot_nodes, st['row_nodes']))
    if st['row_nodes'] + st['meta_nodes'] + st['dropped_top'] + st['dropped_unit_nodes'] != st['orig_nodes']:
        fail('node counts do not add up: %s' % st)
    print('rows', n, ' ground from z=%d to z=%d' % (cover[0][1] if cover else 0, cover[-1][0] if cover else 0), ' nodes: rows %d + meta %d + dropped %d + tail %d = %d' % (st['row_nodes'], st['meta_nodes'], st['dropped_top'], st['dropped_unit_nodes'], st['orig_nodes']))
    print('RESULT', 'FAIL (%d)' % bad if bad else 'OK')
    sys.exit(1 if bad else 0)
main()

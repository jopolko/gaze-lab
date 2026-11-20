"""Build physics.json for a split level (web/downhill-three/data/<dir>/): everything the game needs to know about EVERY row before its meshes are streamed in:
the rows' records (obstacles, pickups, pads, features, toys), the ramps and vortex rings, the pickups' animation entries, the tree positions (for collisions), and a slim copy of every node
(name, path, iid, class, xf, vis, mesh, mat_override: no multimesh instance arrays) so the game can look nodes up by name or iid before the row that holds them is loaded.
usage: python make_physics.py <level_dir>"""
import json, os, sys, glob

d = sys.argv[1]
meta = json.load(open(os.path.join(d, 'meta.json'), encoding='utf-8'))
MATS = meta['materials']
VEG_SIG = 'float hue = fract(wp.z * 0.012'
rows, vx, kick, anims, slim = {}, [], [], [], []
files = sorted(glob.glob(os.path.join(d, 'row_*.json')))
for f in files:
    r = json.load(open(f, encoding='utf-8'))
    meshes = dict(meta['meshes']); meshes.update(r.get('meshes', {}))
    trees = {}
    for n in r['nodes']:
        keep = {k: n[k] for k in ('class', 'path', 'iid', 'name', 'xf', 'vis', 'mesh', 'mat_override', 'count') if k in n}
        slim.append(keep)
        if n.get('class') == 'MultiMeshInstance3D' and n.get('mesh') and n.get('xfs'):
            md = meshes.get(n['mesh']); mid = n.get('mat_override')
            if not mid and md:
                for s in md['surfaces']:
                    if s.get('mat'): mid = s['mat']; break
            code = (MATS.get(str(mid), {}) or {}).get('shader_code') or ''
            if VEG_SIG in code:
                X = n['xf']
                for t in n['xfs']:
                    x = X[0] * t[9] + X[3] * t[10] + X[6] * t[11] + X[9]
                    z = X[2] * t[9] + X[5] * t[10] + X[8] * t[11] + X[11]
                    trees[(round(x), round(z))] = (round(x, 2), round(z, 2))
    row = dict(r['row']); row['trees'] = [list(v) for v in trees.values()]
    rows[str(r['j'])] = row
    vx += r.get('vx', []); kick += r.get('kickers', []); anims += r.get('anims', [])
out = {'rows': rows, 'vx': vx, 'kickers': kick, 'anims': anims, 'nodes': slim}
p = os.path.join(d, 'physics.json')
with open(p, 'w', encoding='utf-8') as fh:
    json.dump(out, fh, separators=(',', ':'))
print('rows', len(rows), 'nodes', len(slim), 'trees', sum(len(r['trees']) for r in rows.values()), 'size KB', os.path.getsize(p) // 1024)

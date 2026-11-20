#!/usr/bin/env python3
"""Split a long Godot level dump (godot/tests/dump_long.gd) into streamable chunk files for the browser.

    python split_level.py <big.json> <out_dir> [--rows N]

out_dir/meta.json     everything shared: seed, theme, ROW_GAP, W_HALF, SLOPE, pitch, trailx (whole run, 6 m steps), feat_off, nrows, start,
                      materials (all), meshes (only the ones used by more than one row or by a meta node), nodes (the non-row nodes: environment, sun,
                      theme fx / post pass, lights, the camera rig, the mountain ring and the skirt)
out_dir/row_NN.json   one 180 m slab of the course (NN = 00.., slab = z in (-180*(NN+1), -180*NN]): { j, z0, z1, nodes, meshes (the ones only this row uses, e.g. its
                      ground chunk), row (the rig's row record: obs, buffs, pads, feats, toys, gaps, zone, region ...), vx, kickers, anims }

A node belongs to a row by where it is in the world, not by its transform alone (ground chunks and forest multimeshes have their positions baked into the
vertices / instances, with an identity node transform): a mesh by the centre of its vertices, a multimesh by the centroid of its instances, a hierarchy by the median
of its parts. A hierarchy (a child of RunRig and everything under it) is never cut: it goes whole to the row of its root, so the path-based parents of pickups and
vortex rings stay together.  Rows at the end whose ground chunk was not built yet are dropped.
"""
import json, os, sys, statistics, collections

ROWLEN = 180.0
DROP_TOP = ('/MainLevel/UI', '/MainLevel/AudioHooks', '/MainLevel/Player', '/MainLevel/PlayerSpawn', '/MainLevel/Enemies', '/MainLevel/WaveDirector', '/MainLevel/Props', '/MainLevel/Decor', '/MainLevel/GazeTargeting', '/MainLevel/NavigationRegion3D')
RIG = '/MainLevel/RunRig'


def app(xf, o):
    return (xf[0] * o[0] + xf[3] * o[1] + xf[6] * o[2] + xf[9], xf[1] * o[0] + xf[4] * o[1] + xf[7] * o[2] + xf[10], xf[2] * o[0] + xf[5] * o[1] + xf[8] * o[2] + xf[11])


# what marks a row's ground chunk: the shader of each theme's ground (the psychedelic one says MOIRE; the others have their own wording; alpine's snow has the `grid` uniform)
GROUND_SIGS = ('MOIRE', 'frosting', 'dunes in flat bands', 'chevrons racing', 'flat poster colours', 'a drop runs down each column', 'A REGULAR LATTICE', 'uniform float grid', 'ALBEDO = c * 0.4')          # the last one is the realms' vertex-coloured emissive ground (Realms.gd)

def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    src, out = sys.argv[1], sys.argv[2]
    want_rows = int(sys.argv[sys.argv.index('--rows') + 1]) if '--rows' in sys.argv else None
    d = json.load(open(src, encoding='utf-8'))
    N, M, MATS = d['nodes'], d['meshes'], d['materials']
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.startswith('row_') or f == 'meta.json':
            os.remove(os.path.join(out, f))

    # ---- mesh centres in mesh space (cached)
    bbox = {}
    def mesh_box(mid):
        if mid in bbox: return bbox[mid]
        lo = [1e18] * 3; hi = [-1e18] * 3; any_v = False
        for s in M[mid]['surfaces']:
            for v in (s.get('v') or []):
                any_v = True
                for i in range(3):
                    if v[i] < lo[i]: lo[i] = v[i]
                    if v[i] > hi[i]: hi[i] = v[i]
        bbox[mid] = (lo, hi) if any_v else None
        return bbox[mid]

    def code_of(n):
        out_c = ''
        if n.get('mesh') and n['mesh'] in M:
            for s in M[n['mesh']]['surfaces']:
                mid = n.get('mat_override') or s.get('mat'); out_c += (MATS.get(str(mid), {}).get('shader_code') or '')[:4000]
        return out_c

    def node_z(n):
        """the world z of a node, or None when it has no position data"""
        if n['class'] == 'MultiMeshInstance3D' and n.get('xfs') and 'xf' in n:
            zs = [app(n['xf'], (x[9], x[10], x[11]))[2] for x in n['xfs']]
            return sum(zs) / len(zs)
        if n['class'] == 'MeshInstance3D' and n.get('mesh') and n['mesh'] in M and 'xf' in n:
            b = mesh_box(n['mesh'])
            if b:
                c = [(b[0][i] + b[1][i]) / 2 for i in range(3)]
                return app(n['xf'], c)[2]
        if 'xf' in n:
            return n['xf'][11]
        return None

    # ---- the rig's children are the units that go to a row; everything else is meta or dropped
    groups = collections.OrderedDict(); meta_nodes = []; dropped = collections.Counter(); order = {}
    for idx, n in enumerate(N):
        order[id(n)] = idx
        p = n['path']
        if p.startswith(RIG + '/'):
            groups.setdefault('/'.join(p.split('/')[:4]), []).append(n)
        elif p == RIG:
            meta_nodes.append(n)
        elif any(p == t or p.startswith(t + '/') for t in DROP_TOP):
            dropped[p.split('/')[2]] += 1
        else:
            meta_nodes.append(n)          # /MainLevel, WorldEnvironment, Sun, Lighting, ThemeFX (post pass), ...
    ring_names = set()
    unit_rows = {}; follower = []
    for key, g in groups.items():
        root = g[0]; cls = root['class']
        is_fol = False
        for n in g:
            if n.get('mesh') and n['mesh'] in M:
                if 'HORIZON BEND' in code_of(n) or 'shader_type sky' in code_of(n): is_fol = True
                if any(len(s.get('v') or []) == 1620 for s in M[n['mesh']]['surfaces']): is_fol = True          # the mountain ring (it follows the camera)
            xf0 = n.get('xf') or []
            if n.get('class') == 'MeshInstance3D' and len(xf0) == 12 and abs(xf0[9]) < 1 and abs(xf0[10] + 160) < 2 and abs(xf0[11]) < 1: is_fol = True          # the theme's own horizon (pyramids, candy hills) sits at the same spot as the mountain ring and follows the camera too
        if cls in ('Camera3D', 'CanvasLayer', 'OmniLight3D') or is_fol:
            follower.append(g); continue
        zs = [z for z in (node_z(n) for n in g if n['class'] in ('MeshInstance3D', 'MultiMeshInstance3D')) if z is not None]
        if not zs:
            z0 = node_z(root); zs = [z0] if z0 is not None else []
        unit_rows[key] = statistics.median(zs) if zs else None
    for g in follower:
        meta_nodes.extend(g)

    # ---- how many complete rows: a row needs its ground chunk
    ground_rows = set()
    for key, g in groups.items():
        for n in g:
            if n['class'] == 'MeshInstance3D' and any(sg in code_of(n) for sg in GROUND_SIGS):
                z = node_z(n); ground_rows.add(int(-z // ROWLEN) if z is not None else 0)
    nrows = 0
    while nrows in ground_rows: nrows += 1
    if want_rows: nrows = min(nrows, want_rows)
    print('rows with a ground chunk, contiguous from 0:', nrows, ' (total ground chunks', len(ground_rows), ')')

    def row_of_z(z):
        if z is None: return 0
        return max(0, min(nrows - 1, int(-z // ROWLEN)))

    rows = [dict(j=j, z0=-ROWLEN * j, z1=-ROWLEN * (j + 1), nodes=[], meshes={}, row={}, vx=[], kickers=[], anims=[]) for j in range(nrows)]
    dropped_units = 0; dropped_nodes = 0
    for key, g in groups.items():
        if key not in unit_rows: continue
        z = unit_rows[key]
        if z is not None and -z // ROWLEN >= nrows:
            dropped_units += 1; dropped_nodes += len(g); continue
        rows[row_of_z(z)]['nodes'].extend(g)
    node_by_iid = {n.get('iid'): n for n in N if 'iid' in n}

    # ---- rig row records, kickers/vortex rings and the animated pickups
    for k, rd in d['rows'].items():
        j = int(k)
        if j < nrows:
            rows[j]['row'] = {a: b for a, b in rd.items() if a != 'nodes'}
    def strict_row(z):          # None when the thing lies past the last complete row (its nodes were dropped, so it must be too)
        if z is None: return 0
        j = int(-z // ROWLEN) if z <= 0 else 0
        return j if 0 <= j < nrows else None
    for v in d.get('vx', []):
        j = strict_row(v['z'])
        if j is not None: rows[j]['vx'].append(v)
    for kk in d.get('kickers', []):
        j = strict_row(kk['z'])
        if j is not None: rows[j]['kickers'].append({a: b for a, b in kk.items() if a != 'vx'})
    for a in d.get('anims', []):
        nn = node_by_iid.get(a.get('n'))
        j = strict_row(node_z(nn) if nn else None)
        if j is not None: rows[j]['anims'].append(a)

    # ---- meshes: shared ones go to meta, a mesh that only one row uses goes into that row's file
    used_by = collections.defaultdict(set)
    for r in rows:
        for n in r['nodes']:
            if n.get('mesh'): used_by[n['mesh']].add(r['j'])
    meta_mesh = set()
    for n in meta_nodes:
        if n.get('mesh'): meta_mesh.add(n['mesh'])
    shared = {}
    for mid, rs in used_by.items():
        if len(rs) > 1 or mid in meta_mesh:
            shared[mid] = M[mid]
        else:
            rows[next(iter(rs))]['meshes'][mid] = M[mid]
    for mid in meta_mesh:
        if mid in M: shared[mid] = M[mid]

    meta = {k: d[k] for k in ('seed', 'theme', 'ROW_GAP', 'W_HALF', 'SLOPE', 'start', 'feat_off', 'pitch') if k in d}
    meta.update(nrows=nrows, segs=d.get('segs'), trailx=d['trailx'], materials=MATS, meshes=shared, nodes=meta_nodes)
    def dump(o, path):
        with open(path, 'w', encoding='utf-8') as f: json.dump(o, f, separators=(',', ':'))
        return os.path.getsize(path)
    sizes = [('meta.json', dump(meta, os.path.join(out, 'meta.json')))]
    for r in rows:
        sizes.append(('row_%02d.json' % r['j'], dump(r, os.path.join(out, 'row_%02d.json' % r['j']))))
    json.dump({'orig_nodes': len(N), 'row_nodes': sum(len(r['nodes']) for r in rows), 'meta_nodes': len(meta_nodes), 'dropped_top': sum(dropped.values()), 'dropped_unit_nodes': dropped_nodes}, open(os.path.join(out, 'stats.json'), 'w'))
    tot = sum(s for _, s in sizes)
    print('meta %.2f MB' % (sizes[0][1] / 1e6), ' rows %d  avg %.0f KB  max %.0f KB  total %.1f MB' % (nrows, statistics.mean(s for _, s in sizes[1:]) / 1e3, max(s for _, s in sizes[1:]) / 1e3, tot / 1e6))
    print('meta nodes', len(meta_nodes), ' shared meshes', len(shared), ' dropped (not in the world): ', dict(dropped), ' dropped units past the last complete row:', dropped_units, '(%d nodes)' % dropped_nodes)
    print('ground coverage end z: %d' % (-ROWLEN * nrows))


if __name__ == '__main__':
    main()

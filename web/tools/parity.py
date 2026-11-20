"""PARITY HARNESS (server + report).  How close is the three.js picture to Godot's, by the numbers.

  python web/tools/parity.py serve     serves web/ on http://localhost:8073 and waits for the browser run to post its results; then writes web/docs/PARITY_REPORT.md
                                      open  http://localhost:8073/downhill-three/parity.html?all=1&post=1   (window >= 960x540)
  python web/tools/parity.py report    rebuilds the report from the last saved results (web/tools/parity_result.json)
  python web/tools/parity.py godot     prints the Godot-side statistics of the reference PNGs only

Godot side: godot/tests/dump_parity.gd (copy of dump_level.gd + a per-shot sidecar: engine time, picture-pass uniforms, environment, lights, camera) writes godot_NN.png (with the pass),
godot_NN_nopost.png (the pass hidden) and godot_NN.json into a folder; copy them to web/downhill-three/shots_parity/ with level_parity_s7.json in web/downhill-three/data/.
Three side: parity.html renders each shot with the same camera, field of view and engine time, once before the picture pass (vmode 3) and once with it, and compares pixel by pixel.
Metrics (per region sky / mid / ground / all):  mae = mean absolute error per channel (0-255)   lf = the same on 8x8 block averages (robust to small shifts)   L, C = mean luma and chroma ours vs godot (gL, gC)   hueL1 = distance between chroma-weighted hue histograms.
"""
import http.server, json, os, socketserver, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__)); WEB = os.path.dirname(HERE)
RES = os.path.join(HERE, 'parity_result.json'); OUT = os.path.join(WEB, 'docs', 'PARITY_REPORT.md'); SH = os.path.join(WEB, 'downhill-three', 'shots_parity')
REG = {'sky': (0, .12), 'mid': (.35, .5), 'ground': (.7, 1), 'all': (0, 1)}


def godot_stats(path):
    a = np.asarray(Image.open(path).convert('RGB')).astype(float); h = a.shape[0]; out = {}
    for n, (f0, f1) in REG.items():
        r = a[int(h * f0):int(h * f1)]; L = .299 * r[..., 0] + .587 * r[..., 1] + .114 * r[..., 2]; C = r.max(2) - r.min(2); out[n] = (round(float(L.mean()), 1), round(float(C.mean()), 1))
    return out


def fmt(v):
    return ('%.1f' % v) if isinstance(v, (int, float)) else str(v)


def report():
    d = json.load(open(RES, encoding='utf-8')); shots = [s for s in d['shots'] if s.get('ok')]; L = []
    L.append('# Parity report: three.js vs Godot (numbers, not eyes)\n')
    L.append('Run %s. %d shots. Godot: forward_plus, MSAA 4x (value %s), 4.7.2. Three: gv.js viewer at the same camera, field of view and engine time.\n' % (d.get('when', '?'), len(shots), shots[0]['godot'].get('msaa') if shots else '?'))
    L.append('Metrics: **mae** = mean absolute error per channel (0-255), **lf** = the same on 8x8 block averages (robust to small shifts), **L / C** = mean luma / chroma of ours vs godot (gL / gC), **hueL1** = distance of chroma-weighted hue histograms (0 = same hues, 2 = opposite).\n')
    L.append('## What Godot had at each capture (from the sidecar)\n')
    L.append('| shot | engine time s | fov | trip | breathe | sharp | tube | horizon | buzz | ground speed | exposure | fog | glow |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|')
    for s in shots:
        g = s['godot']; L.append('| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |' % (s['shot'], fmt(g['time']), fmt(g['fov']), fmt(g.get('trip')), fmt(g.get('breathe')), fmt(g.get('sharp')), fmt(g.get('tube')), fmt(g.get('horizon')), fmt(g.get('buzz')), fmt(g.get('gspeed')), g['exposure'], g['fog'], g['glow']))
    up = {}
    for s in shots:
        for k, v in s.get('unportedPost', {}).items(): up.setdefault(k, []).append(v)
    L.append('\nPicture-pass uniforms Godot had set that the three.js pass has no counterpart for: ' + (', '.join('`%s` (%s)' % (k, ', '.join(fmt(x) if not isinstance(x, list) else str(x) for x in v[:4])) for k, v in up.items()) or 'none') + '\n')
    # per variant tables, averaged over the shots
    for dom, title in (('bypass', 'Before the picture pass (Godot `*_nopost.png`): lighting, fog, tonemap, glow, grade'), ('post', 'With the picture pass (Godot `godot_NN.png`)')):
        names = []
        for s in shots:
            for v in s['variants']:
                if v['domain'] == dom and v['name'] not in names: names.append(v['name'])
        rows = []
        for nm in names:
            vs = [v for s in shots for v in s['variants'] if v['domain'] == dom and v['name'] == nm]
            if not vs: continue
            m = lambda reg, key: float(np.mean([v['r'][reg][key] for v in vs]))
            rows.append((nm, m('all', 'lf'), m('all', 'mae'), m('sky', 'lf'), m('mid', 'lf'), m('ground', 'lf'), m('all', 'L'), m('all', 'gL'), m('all', 'C'), m('all', 'gC'), m('all', 'hueL1'), m('ground', 'C'), m('ground', 'gC')))
        L.append('## %s\n' % title)
        L.append('Means over the shots. Sorted by the low-frequency error of the whole picture (smaller is closer).\n')
        L.append('| variant | lf all | mae all | lf sky | lf mid | lf ground | L ours | L godot | C ours | C godot | hueL1 | ground C ours | ground C godot |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|')
        for r in sorted(rows, key=lambda r: r[1]):
            L.append('| %s | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.2f | %.1f | %.1f |' % r)
        base = [r for r in rows if r[0].startswith('base') or r[0].startswith('post base')]
        if base:
            b = base[0]; L.append('\n**Effect of each single factor** on lf-all, relative to `%s` (%.1f; negative = the change brings us closer to Godot):\n' % (b[0], b[1]))
            L.append('| change | delta lf all | delta lf sky | delta lf mid | delta lf ground | delta L | delta C |\n|---|---|---|---|---|---|---|')
            for r in sorted(rows, key=lambda r: r[1] - b[1]):
                if r[0] == b[0] or r[0].startswith('godot state') or r[0].startswith('shipped'): continue
                L.append('| %s | %+.1f | %+.1f | %+.1f | %+.1f | %+.1f | %+.1f |' % (r[0], r[1] - b[1], r[3] - b[3], r[4] - b[4], r[5] - b[5], r[6] - b[6], r[8] - b[8]))
    L.append('\n## Fits (per shot)\n')
    L.append('| shot | best exposure before the pass (lf, ours L, godot L) | best exposure with the pass | best TIME offsets s (offset, lf ground, lf sky, lf all) |\n|---|---|---|---|')
    for s in shots:
        f = s['fit']; L.append('| %d | %s | %s | %s |' % (s['shot'], [round(x, 1) if isinstance(x, float) else x for x in f['exposureBypass']], [round(x, 1) if isinstance(x, float) else x for x in f['exposurePost']], [[round(y, 1) for y in x] for x in f['timeOffsetTop3']]))
    L.append('\n## Godot-side statistics (mean luma, chroma per region)\n')
    L.append('| shot | image | sky | mid | ground | all |\n|---|---|---|---|---|---|')
    for i in range(len(shots)):
        for tag, fn in (('no pass', 'godot_%02d_nopost.png' % i), ('with pass', 'godot_%02d.png' % i)):
            p = os.path.join(SH, fn)
            if os.path.exists(p):
                st = godot_stats(p); L.append('| %d | %s | %s | %s | %s | %s |' % (i, tag, st['sky'], st['mid'], st['ground'], st['all']))
    open(OUT, 'w', encoding='utf-8').write('\n'.join(L) + '\n'); print('wrote', OUT)


class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=WEB, **k)

    def do_POST(self):
        if self.path != '/result': self.send_response(404); self.end_headers(); return
        n = int(self.headers.get('Content-Length', 0)); body = self.rfile.read(n)
        open(RES, 'wb').write(body)
        try: report(); self.send_response(200)
        except Exception as e: print('report failed', e); self.send_response(500)
        self.end_headers()

    def log_message(self, *a): pass


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'report'
    if cmd == 'serve':
        socketserver.ThreadingTCPServer.allow_reuse_address = True
        with socketserver.ThreadingTCPServer(('0.0.0.0', 8073), H) as srv: print('parity server on http://localhost:8073  (open /downhill-three/parity.html?all=1&post=1)'); srv.serve_forever()
    elif cmd == 'godot':
        for i in range(8):
            for fn in ('godot_%02d_nopost.png' % i, 'godot_%02d.png' % i):
                p = os.path.join(SH, fn)
                if os.path.exists(p): print(fn, godot_stats(p))
    else: report()

"""Analyse the live steering telemetry of gv.html?play (app 'gv', kind 'steer').
Usage:  python analyze_steer.py [file.jsonl ...]     (default: ../spike/logs/spike-<today>.jsonl, falling back to the VPS log over ssh)
Each record: {"app":"gv","kind":"steer","cols":"t head sIn steer heading x vx speed z hurt","flips":N,"lag":ms,"rows":[[...]]}  rows ~20 Hz, 90 per record.
Reports: head-signal sign flips per second, saturation fraction, response lag (cross-correlation sIn -> lateral velocity), time at the edge walls, hits per minute and where, speed over time."""
import sys, os, json, datetime, subprocess, math

def load(paths):
    recs = []
    for p in paths:
        txt = open(p, encoding='utf-8', errors='replace').read() if p != 'ssh' else subprocess.run(['ssh', 'nowservingto', 'cat /var/lib/gaze-lab-logs/three/%s.jsonl' % datetime.date.today().isoformat()], capture_output=True).stdout.decode('utf-8', 'replace')
        for ln in txt.splitlines():
            if '"gv"' not in ln or '"steer"' not in ln:
                continue
            try:
                d = json.loads(ln)
            except Exception:
                continue
            if d.get('app') == 'gv' and d.get('kind') == 'steer' and d.get('rows'):
                recs.append(d)
    return recs

def main():
    paths = sys.argv[1:]
    if not paths:
        local = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'spike', 'logs', 'spike-%s.jsonl' % datetime.date.today().isoformat())
        paths = [local] if os.path.exists(local) else ['ssh']
    recs = load(paths)
    if not recs:
        print('no gv steering records yet (play gv.html?play&head for a minute, then run again)'); return
    cols = recs[0]['cols'].split()
    ix = {c: i for i, c in enumerate(cols)}
    rows = []
    for d in recs:
        rows.extend(d['rows'])
    rows.sort(key=lambda r: r[0])
    n = len(rows); T = rows[-1][0] - rows[0][0]
    dt = T / max(n - 1, 1)
    col = lambda c: [r[ix[c]] for r in rows]
    head, sin, steer, x, vx, speed, z, hurt = (col(c) for c in ('head', 'sIn', 'steer', 'x', 'vx', 'speed', 'z', 'hurt'))
    print('samples %d over %.0f s (%.1f Hz)' % (n, T, 1 / max(dt, 1e-6)))
    # head sign flips (amplitude > .15 each side)
    flips = 0; last = 0
    for h in head:
        s = 0 if abs(h) < .15 else (1 if h > 0 else -1)
        if s and s != last:
            if last: flips += 1
            last = s
    print('head sign flips: %d  (%.2f / s)   mean |head| %.2f' % (flips, flips / max(T, 1), sum(abs(h) for h in head) / n))
    sat = sum(1 for s in steer if abs(s) > .98) / n
    print('steering saturated (|steer|=1): %.0f%% of the time' % (100 * sat))
    # response lag: correlate sIn(t-lag) with lateral speed vx(t)
    best, bl = -1e9, 0
    for lag in range(0, int(.6 / max(dt, 1e-3)) + 1):
        c = sum(sin[i - lag] * vx[i] for i in range(lag, n)) / max(n - lag, 1)
        if c > best: best, bl = c, lag
    print('response lag sIn -> sideways speed: ~%.0f ms (corr %.2f)' % (bl * dt * 1000, best))
    edge = sum(1 for v in x if abs(v) > 54) / n
    print('time within 4 m of the edge walls: %.0f%%   mean |x| %.1f m' % (100 * edge, sum(abs(v) for v in x) / n))
    hits = []; prev = 0
    for i, h in enumerate(hurt):
        if h and not prev: hits.append((z[i], x[i]))
        prev = h
    print('hits: %d  (%.1f / min)' % (len(hits), len(hits) / max(T / 60, 1e-3)))
    if hits:
        print('  where (z, x): ' + ', '.join('(%d, %.0f)' % h for h in hits[:20]))
        print('  mean |x| at a hit %.1f m' % (sum(abs(h[1]) for h in hits) / len(hits)))
    k = max(1, n // 10)
    print('speed (km/h) by tenth of the run: ' + ' '.join('%d' % (sum(speed[i:i + k]) / len(speed[i:i + k]) * 3.6) for i in range(0, n, k)))
    zig = sum(1 for i in range(1, n) if steer[i] * steer[i - 1] < 0) / max(T, 1)
    print('steer zero-crossings: %.1f / s  (more than ~1.5 / s means side-to-side hunting)' % zig)

main()

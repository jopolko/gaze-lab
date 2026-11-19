"""Trace the whole chain for a session: eyes -> model -> zone -> lane lock -> board -> what the row offered and what you got.
python trace.py [session id]   (default: the newest downhill-three session with the model columns)
For every row passed: what each lane offered, where the eyes were in the last 2.5 s before it (share of readings in each zone), which lane the game had locked, which lane the board was in, and what was
collected; then the timing of each stage (eye zone change -> lock change -> board half way across) and how often each stage agreed with the one before."""
import json, glob, os, sys, statistics as st, collections
LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'spike', 'logs')
S = {}
for f in sorted(glob.glob(os.path.join(LOG, 'spike-*.jsonl'))):
    for line in open(f, encoding='utf-8'):
        try: d = json.loads(line)
        except Exception: continue
        if d.get('app') != 'downhill-three' or 'mA' not in d.get('cols', ''): continue
        cols = d['cols'].split(',')
        S.setdefault(d['sid'], []).extend(dict(zip(cols, r)) for r in d['s'])
sid = sys.argv[1] if len(sys.argv) > 1 else [k for k, v in S.items() if len(v) > 300][-1]
R = S[sid]; n = len(R); LW = 22.0
NAME = {0: '-', 1: 'POINTS', 2: 'RING', 3: 'PICKUP', 4: 'RAMP', 5: 'ROCKS'}
def kinds(code):
    code = int(code); return [NAME[(code // 100) % 10], NAME[(code // 10) % 10], NAME[code % 10]]
# split the approach to each row: the distance to the nearest row falls, then jumps up when it is passed
segs, cur = [], [R[0]]
for a, b in zip(R, R[1:]):
    if b['dist'] - a['dist'] > 20: segs.append(cur); cur = []
    cur.append(b)
segs.append(cur)
print('session', sid, '%.0f s' % (n / 10), len(segs), 'rows')
print('%-5s %-8s %-8s %-8s | eyes L/M/R last 2.5s | lock board | got' % ('t', 'left', 'middle', 'right'))
agree = collections.Counter(); tot = 0
for sg in segs[1:-1]:
    end = sg[-1]; w = [r for r in R if end['t'] - 2.5 <= r['t'] <= end['t']]          # the 2.5 s before the pass, whatever row was nearest then
    z = [sum(1 for r in w if r['zone'] == v) for v in (-1, 0, 1)]
    eye = (-1, 0, 1)[z.index(max(z))]; lock = end['lock']; board = round(end['camX'] / LW)
    k = kinds(sg[0]['open']); got = k[board + 1]
    tot += 1
    agree['eyes=lock'] += eye == lock; agree['lock=board'] += lock == board; agree['eyes=board'] += eye == board
    print('%-5.0f %-8s %-8s %-8s |  %2d / %2d / %2d  (%s)  |  %s     %s  | %s' % (end['t'] - R[0]['t'], *k, *z, 'LMR'[eye + 1], 'LMR'[lock + 1], 'LMR'[board + 1], got))
print('\nagreement over %d rows: eyes->lock %.0f%%, lock->board %.0f%%, eyes->board %.0f%%' % (tot, 100 * agree['eyes=lock'] / tot, 100 * agree['lock=board'] / tot, 100 * agree['eyes=board'] / tot))
# timing: when the eye zone changes to a side/middle, how long until the lock follows, and until the board is half way across
lag_lock, lag_board, miss = [], [], 0
for i in range(1, n):
    if R[i]['zone'] != R[i - 1]['zone']:
        z = R[i]['zone']
        j = next((j for j in range(i, min(n, i + 40)) if R[j]['lock'] == z), None)
        if j is None: miss += 1; continue
        lag_lock.append((R[j]['t'] - R[i]['t']))
        if z != R[i]['lock'] or True:
            k = next((k for k in range(j, min(n, j + 40)) if abs(R[k]['camX'] - z * LW) < LW / 2 and abs(R[j]['camX'] - z * LW) >= LW / 2), None)
            if k is not None: lag_board.append(R[k]['t'] - R[j]['t'])
f = lambda v: ('median %.2f s  p90 %.2f s  (n=%d)' % (st.median(v), sorted(v)[int(.9 * len(v))], len(v))) if v else 'n/a'
print('eye zone change -> lock follows:', f(lag_lock), '| zone changes the lock never followed within 4 s:', miss)
print('lock change -> board half way across:', f(lag_board))
if 'pM' in R[0]:
    conf = [max(r['pL'], r['pM'], r['pR']) for r in R]
    print('model confidence: median %.2f, below 0.7 for %.0f%% of readings; noise sigma A %.4f B %.4f' % (st.median(conf), 100 * sum(1 for c in conf if c < .7) / n, st.median(r['sA2'] for r in R), st.median(r['sB2'] for r in R)))
print('model: tracker latency ~50 ms inference + ~66 ms frame interval; the game 16.7 ms per frame')

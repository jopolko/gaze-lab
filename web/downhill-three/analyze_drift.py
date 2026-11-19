"""How much of the slow drift of the eye reading do head and face features explain?
python analyze_drift.py [session id]   (default: the newest downhill-three session that has the head columns)
For each feature, the 3 s moving median of the reading (mean of the two eyes, and each eye) is compared with the 3 s moving median of the feature: correlation and R^2 of a straight line,
then all features together (ordinary least squares). Only readings while the model believed MIDDLE (zone 0) are used, so intent (looking left or right) does not count as drift."""
import json, sys, glob, os, statistics as st
import numpy as np
LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'spike', 'logs')
S = {}
for f in sorted(glob.glob(os.path.join(LOG, 'spike-*.jsonl'))):
    for line in open(f, encoding='utf-8'):
        try: d = json.loads(line)
        except Exception: continue
        if d.get('app') != 'downhill-three' or 'roll' not in d['cols']: continue
        cols = d['cols'].split(',')
        S.setdefault(d['sid'], []).extend(dict(zip(cols, r)) for r in d['s'])
if not S: sys.exit('no session with the head columns yet: play one first')
sid = sys.argv[1] if len(sys.argv) > 1 else list(S)[-1]
R = [r for r in S[sid] if r['zone'] == 0]
print(sid, len(S[sid]) / 10, 's total,', len(R), 'middle readings')
feat = ['yaw', 'pitch', 'roll', 'fx', 'fy', 'fsz', 'lA', 'lB']
def smooth(v, k=30): return np.array([np.median(v[max(0, i - k):i + 1]) for i in range(len(v))])
Y = {'avg': smooth([r['hx'] for r in R]), 'A': smooth([r['ha'] for r in R]), 'B': smooth([r['hb'] for r in R])}
X = {k: smooth([r[k] for r in R]) for k in feat}
for name, y in Y.items():
    print('\nreading', name, ' range of the slow part %.4f' % (y.max() - y.min()))
    for k in feat:
        x = X[k]
        if x.std() < 1e-9 or y.std() < 1e-9: print('   %-5s no variation' % k); continue
        c = np.corrcoef(x, y)[0, 1]; print('   %-5s corr %+.2f  R2 %.2f  (feature range %.4f)' % (k, c, c * c, x.max() - x.min()))
    M = np.column_stack([X[k] for k in feat] + [np.ones(len(y))]); beta, *_ = np.linalg.lstsq(M, y, rcond=None)
    res = y - M @ beta; print('   ALL together: R2 %.2f  (slow part %.4f -> %.4f after removing them)' % (1 - res.var() / y.var(), y.std(), res.std()))

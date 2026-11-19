"""Live monitor: follows the spike server's log while the game is played and prints one health line per ~10 s of play (100 readings), with flags.
python monitor.py            (prints only NEW data from now on)
Flags: FLAT (the eyes moved but the zone did not), STUCK (the board held a lane the eyes were not in), TWITCH (lane changes > 10 per 10 s), LEAN (one side >= 4x the other), CENTRE (model centre
more than 0.012 from the readings' median), NOMOVE (the signal barely moved: the player may be looking at one place)."""
import json, os, sys, time, glob, datetime, statistics as st
LOGDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'spike', 'logs')
buf = {}; pos = {}; cur = None
def path(): return os.path.join(LOGDIR, 'spike-%s.jsonl' % datetime.date.today().isoformat())
def summarize(sid, rows):
    n = len(rows); c = lambda k, v: sum(1 for r in rows if r[k] == v)
    z = [c('zone', -1), c('zone', 0), c('zone', 1)]; l = [c('lock', -1), c('lock', 0), c('lock', 1)]
    flips = sum(1 for a, b in zip(rows, rows[1:]) if a['zone'] != b['zone']); ch = sum(1 for a, b in zip(rows, rows[1:]) if a['lock'] != b['lock'])
    rg = lambda k: max(r[k] for r in rows) - min(r[k] for r in rows)
    gA = st.median(r['ha'] - r['mA'] for r in rows); gB = st.median(r['hb'] - r['mB'] for r in rows)
    disagree = sum(1 for r in rows if r['lock'] != r['zone']) / n
    fl = []
    if z[1] >= 0.95 * n and (rg('ha') + rg('hb')) / 2 > 0.04: fl.append('FLAT')
    if disagree > 0.6: fl.append('STUCK')
    if ch > 10: fl.append('TWITCH')
    if min(l[0], l[2]) * 4 <= max(l[0], l[2]) and max(l[0], l[2]) > 0.3 * n: fl.append('LEAN-' + ('L' if l[0] > l[2] else 'R'))
    if max(abs(gA), abs(gB)) > 0.012: fl.append('CENTRE')
    if (rg('ha') + rg('hb')) / 2 < 0.02: fl.append('NOMOVE')
    t = rows[-1]['t'] - rows[0]['t']
    return 'sid %s %3.0fs  zone L%02d M%02d R%02d | lock L%02d M%02d R%02d | flips %d lane-changes %d | range A %.3f B %.3f | centre gap A %+.3f B %+.3f | tune v%s | %s' % (
        sid, rows[-1]['t'] - 0, z[0], z[1], z[2], l[0], l[1], l[2], flips, ch, rg('ha'), rg('hb'), gA, gB, rows[-1].get('tv', '-'), ' '.join(fl) or 'ok')
print('monitor watching', path(), flush=True)
if os.path.exists(path()): pos[path()] = os.path.getsize(path())
tail = ''
while True:
    p = path()
    if not os.path.exists(p): time.sleep(1); continue
    if p not in pos: pos[p] = 0
    size = os.path.getsize(p)
    if size > pos[p]:
        with open(p, 'rb') as f:
            f.seek(pos[p]); data = f.read(size - pos[p]).decode('utf-8', 'replace'); pos[p] = size
        lines = (tail + data).split('\n'); tail = lines.pop()
        for line in lines:
            try: d = json.loads(line)
            except Exception: continue
            if d.get('app') != 'downhill-three' or 'mA' not in d.get('cols', ''): continue
            cols = d['cols'].split(','); sid = d['sid']
            for r in d['s']:
                row = dict(zip(cols, r)); row['tv'] = d.get('tv'); buf.setdefault(sid, []).append(row)
                if len(buf[sid]) >= 100:
                    print(summarize(sid, buf[sid]), flush=True); buf[sid] = []
    time.sleep(1)

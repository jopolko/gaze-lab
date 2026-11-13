"""Summarise everything collected so far (any time, no live watching needed):

    python tools/summarize.py [logs folder] [--since YYYYMMDD]

Reads tools/logs/<id>/<date>_<device>_<visit>.jsonl (written by serve.py) or the collector's logs/<id>/<date>.jsonl, and prints one block per person / device / app: how long they played,
frame rate, tracker rate, latency, jitter, how much of the screen the gaze covers, how often the board went through the gate they were looking at, and every fix the doctor made
(kept or put back). Nothing here is shared anywhere: it only reads files on this machine.
"""
import collections
import glob
import json
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
root = args[0] if args else os.path.join(here, "logs")
since = ""
if "--since" in sys.argv:
    since = sys.argv[sys.argv.index("--since") + 1]


def med(a):
    a = sorted(a)
    return a[len(a) // 2] if a else None


def fmt(v, nd=1):
    return "-" if v is None else ("%.*f" % (nd, v))


groups = collections.defaultdict(lambda: {"health": [], "barriers": [], "fixes": [], "notes": [], "hand": [], "visits": set(), "hw": None, "days": set()})
n_lines = 0
for path in glob.glob(os.path.join(root, "*", "*.jsonl")):
    day = os.path.basename(path)[:8]
    if since and day < since:
        continue
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except Exception:
            continue
        n_lines += 1
        key = (d.get("who", os.path.basename(os.path.dirname(path))), d.get("device", "?"), d.get("app", "?"))
        g = groups[key]
        g["visits"].add(d.get("sid", "?"))
        g["days"].add(day)
        k = d.get("kind")
        if k == "health":
            g["health"].append(d)
            if d.get("hw") and not g["hw"]:
                g["hw"] = d["hw"]
        elif k == "barrier":
            g["barriers"].append(d)
        elif k == "fix":
            g["fixes"].append(d)
        elif k == "note":
            g["notes"].append(d)
        elif k == "opt":
            g["hand"].append(d)

if not groups:
    print("nothing collected yet in", root)
    sys.exit(0)

print("%d lines from %d person/device/app groups\n" % (n_lines, len(groups)))
for (who, dev, app), g in sorted(groups.items()):
    h = [x for x in g["health"] if float(x.get("trackerFps", 0) or 0) > 0]
    print("== %s   %s   %s   (%d visits, %d days, about %d min of play with the camera on)" % (who, dev, app, len(g["visits"]), len(g["days"]), len(h) * 5 // 60))
    if g["hw"]:
        hw = g["hw"]
        print("   hardware: %s | %s cores | %s GB | %s | screen %s | dpr %s" % (hw.get("platform"), hw.get("cores"), hw.get("mem"), str(hw.get("gpu", ""))[:50], hw.get("screen"), hw.get("dpr")))
    if h:
        print("   game %s fps (frame p95 %s ms)   tracker %s fps   latency %s ms   jitter %s%% of the screen   gaze covers %s%% x %s%%" % (
            fmt(med([float(x.get("gameFps", 0)) for x in h]), 0), fmt(med([float(x.get("frameP95ms", 0)) for x in h]), 0), fmt(med([float(x.get("trackerFps", 0)) for x in h])),
            fmt(med([float(x.get("latencyMs", 0)) for x in h]), 0), fmt(100 * med([float(x.get("jitterOut", 0)) for x in h]), 1),
            fmt(100 * med([float(x.get("spanX", 0)) for x in h]), 0), fmt(100 * med([float(x.get("spanY", 0)) for x in h]), 0)))
    b = [x for x in g["barriers"] if int(x.get("n", 0)) >= 2]
    if b:
        agree = sum(1 for x in b if x.get("looked", -1) >= 0 and x.get("went") == x.get("looked"))
        locked = sum(1 for x in b if x.get("aim_end", -1) >= 0)
        print("   %d barriers with a choice: went through the gate they were looking at %d%%, the game locked a gate %d%%" % (len(b), 100 * agree // len(b), 100 * locked // len(b)))
    for f in g["fixes"]:
        if f.get("event") == "action":
            print("   FIX  %s: %s" % (f.get("issue"), f.get("action")))
        else:
            bs, af = (f.get("before") or {}).get("score"), (f.get("after") or {}).get("score")
            print("        -> %s (score %s -> %s)" % (str(f.get("verdict")).upper(), bs, af))
    for o in g["hand"]:
        print("   by hand: %s = %s" % (o.get("key"), o.get("value")))
    for n in g["notes"]:
        print("   NOTE: %s" % n.get("text"))
    print()

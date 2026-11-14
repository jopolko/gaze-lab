"""Score every tracker signal against the moving dot of the sweep test (?level=gaze&sweep).

    python tools/sweep_report.py [log file | latest]

For each number the tracker produced (raw packet fields, iris inside the eye, the geometry reading, the final cursor, head angles) it reports, per phase:
  r      how closely it follows the dot (correlation at the best delay; +-1 is perfect, 0 is nothing)
  delay  how many ms behind the dot it runs
  noise  what is left after the best straight-line fit, as a fraction of the screen (0.05 = 5% of the screen width)
  head   in the "turn your head" phase: how much of it is head yaw (correlation), which should be near 0 for a signal that means "eyes"
"""
import glob
import json
import os
import statistics as st
import sys

LOGS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")


def load(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("kind") == "sweep":
            for x in r.get("rows", []):
                rows.append(x)
    return rows


def latest():
    best = None
    for f in sorted(glob.glob(os.path.join(LOGS, "*", "*.jsonl")), key=os.path.getmtime, reverse=True):
        with open(f, encoding="utf-8") as fh:
            if '"kind": "sweep"' in fh.read():
                best = f
                break
    return best


def signals(row):
    out = {}
    for k, v in row.get("p", {}).items():
        if isinstance(v, (int, float)):
            out["pkt." + k] = float(v)
        elif isinstance(v, list):
            for i, e in enumerate(v):
                out["pkt.%s[%d]" % (k, i)] = float(e)
    for k in ("eih", "mix", "geo", "cur", "head"):
        for i, e in enumerate(row.get(k, [])):
            out["%s[%d]" % (k, i)] = float(e)
    return out


def corr(a, b):
    if len(a) < 8:
        return 0.0
    sa, sb = st.pstdev(a), st.pstdev(b)
    if sa < 1e-9 or sb < 1e-9:
        return 0.0
    ma, mb = st.mean(a), st.mean(b)
    return sum((x - ma) * (y - mb) for x, y in zip(a, b)) / len(a) / sa / sb


def interp(ts, vs, t):
    if t <= ts[0]:
        return vs[0]
    if t >= ts[-1]:
        return vs[-1]
    lo, hi = 0, len(ts) - 1
    while hi - lo > 1:
        m = (lo + hi) // 2
        if ts[m] <= t:
            lo = m
        else:
            hi = m
    f = (t - ts[lo]) / max(ts[hi] - ts[lo], 1e-6)
    return vs[lo] + (vs[hi] - vs[lo]) * f


def score(rows, key, axis):
    """Best-delay correlation of signal `key` with the dot on `axis` ('tx' / 'ty'), plus the noise after a straight-line fit."""
    ts = [r["tt"] for r in rows]
    tg = [r[axis] for r in rows]
    sg = [signals(r).get(key) for r in rows]
    if any(v is None for v in sg):
        return None
    best = (0.0, 0)
    for lag_ms in range(0, 601, 40):
        lag = lag_ms / 1000.0
        a, b = [], []
        for t, v in zip(ts, sg):
            if t - lag < ts[0]:
                continue
            a.append(interp(ts, tg, t - lag))
            b.append(v)
        c = corr(a, b)
        if abs(c) > abs(best[0]):
            best = (c, lag_ms)
    c, lag_ms = best
    lag = lag_ms / 1000.0
    a = [interp(ts, tg, t - lag) for t in ts]
    sa, sb = st.pstdev(a), st.pstdev(sg)
    if sa < 1e-9 or sb < 1e-9 or abs(c) < 1e-6:
        return {"r": 0.0, "lag": 0, "noise": None, "span": sb}
    slope = c * sa / sb                      # screen units per signal unit
    ma, mb = st.mean(a), st.mean(sg)
    resid = [(x - ma) - slope * (y - mb) for x, y in zip(a, sg)]
    return {"r": c, "lag": lag_ms, "noise": st.pstdev(resid), "span": sb, "gain": slope}


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "latest"
    path = latest() if arg == "latest" else arg
    if not path:
        print("no sweep recording found in", LOGS)
        return
    rows = load(path)
    print("file:", path)
    by = {}
    for r in rows:
        by.setdefault(r["ph"], []).append(r)
    for ph, rr in by.items():
        dur = rr[-1]["tt"] - rr[0]["tt"] if len(rr) > 1 else 0
        print("  phase %-5s %4d readings, %.1f per second" % (ph, len(rr), len(rr) / max(dur, 0.1)))
    keys = sorted(signals(rows[0]).keys()) if rows else []
    head_rows = by.get("head", [])
    yaw = [signals(r).get("head[0]", 0.0) for r in head_rows]
    for ph, axis, title in (("hx", "tx", "SIDE TO SIDE, gliding dot"), ("jump", "tx", "SIDE TO SIDE, jumping dot"), ("vy", "ty", "UP AND DOWN, gliding dot")):
        rr = by.get(ph, [])
        if len(rr) < 20:
            continue
        res = []
        for k in keys:
            s = score(rr, k, axis)
            if s is None or s["noise"] is None:
                continue
            leak = corr(yaw, [signals(r).get(k, 0.0) for r in head_rows]) if len(head_rows) > 20 else 0.0
            res.append((abs(s["r"]), k, s, leak))
        res.sort(reverse=True)
        print()
        print(title)
        print("  %-22s %6s %7s %8s %9s %7s" % ("signal", "r", "delay", "noise", "gain", "head"))
        for _, k, s, leak in res[:14]:
            print("  %-22s %+6.2f %5dms %7.1f%% %+9.2f %+7.2f" % (k, s["r"], s["lag"], 100.0 * s["noise"], s.get("gain", 0.0), leak))
    if len(head_rows) > 20:
        print()
        print("HEAD TURN, eyes on the middle (head yaw moved %.2f rad peak to peak)" % (max(yaw) - min(yaw)))
        for k in ("cur[0]", "geo[0]", "eih[0]"):
            v = [signals(r).get(k, 0.0) for r in head_rows]
            print("  %-8s moved %.2f (sd %.3f), correlation with head yaw %+.2f" % (k, max(v) - min(v), st.pstdev(v), corr(yaw, v)))


if __name__ == "__main__":
    main()

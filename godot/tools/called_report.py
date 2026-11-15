"""Score a called-gate test (?called): the game marked one opening per barrier and the player looked at it.

    python tools/called_report.py [log file | latest]

What it says:
  picked right   how often the opening the game held at the barrier was the marked one, overall and by where the marked one was (left / middle / right)
  off by         when it was wrong, how many openings away and to which side (a one-sided bias shows here)
  eye reading    while approaching (90 to 20 m out), was the marked opening the one NEAREST to where the game read the look? If yes but the pick was wrong, the pick logic is at
                 fault; if no, the eye reading is.
  look error     the look as the game read it minus where the marked opening was, in screen widths: the average (a constant offset to one side) and the spread
  reach          how far the look moves when the marked opening is further out (1.0 = as far as the opening, 0.5 = half as far: the look under-reaches)
  time to lock   seconds from the barrier appearing to the game holding the marked opening
"""
import glob
import json
import os
import statistics as st
import sys

LOGS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")


def items(path):
    for line in open(path, encoding="utf-8"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        for it in r.get("items", [r]):
            yield it


def latest():
    for f in sorted(glob.glob(os.path.join(LOGS, "*", "*.jsonl")), key=os.path.getmtime, reverse=True):
        with open(f, encoding="utf-8") as fh:
            if '"called_gate"' in fh.read():
                return f
    return None


def pos(call, n):
    if n <= 1:
        return "only"
    return "left" if call == 0 else ("right" if call == n - 1 else "middle")


def pct(a, b):
    return "%3d%% (%d of %d)" % (round(100.0 * a / b), a, b) if b else "  -  (none)"


def show(v):
    return "-" if v < 0 else str(v)


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "latest"
    path = latest() if arg == "latest" else arg
    if not path:
        print("no called-gate recording found in", LOGS)
        return
    gates, rows = [], []
    for it in items(path):
        if it.get("kind") == "called_gate":
            gates.append(it)
        elif it.get("kind") == "called":
            rows += it.get("rows", [])
    print("file:", path)
    print("barriers: %d, look samples: %d, phone blend in use: %s" % (len(gates), len(rows), "yes" if any(r[12] for r in rows) else "no"))
    if not gates:
        return
    ok = [g for g in gates if g["eyes"] == g["call"]]
    print()
    print("PICKED RIGHT at the barrier   %s" % pct(len(ok), len(gates)))
    for p in ("left", "middle", "right"):
        sub = [g for g in gates if pos(g["call"], g["n"]) == p]
        print("   marked one on the %-7s %s" % (p, pct(len([g for g in sub if g["eyes"] == g["call"]]), len(sub))))
    print("   first opening it held       %s" % pct(len([g for g in gates if g["first"] == g["call"]]), len(gates)))
    print("   went through the marked one %s" % pct(len([g for g in gates if g["through"] == g["call"]]), len(gates)))
    print("   held nothing at the barrier %s" % pct(len([g for g in gates if g["eyes"] < 0]), len(gates)))
    off = {}
    for g in gates:
        if g["eyes"] >= 0 and g["eyes"] != g["call"]:
            d = g["eyes"] - g["call"]
            off[d] = off.get(d, 0) + 1
    if off:
        print("OFF BY (openings; + = it picked one further RIGHT than marked): " + ", ".join("%+d: %d" % (k, off[k]) for k in sorted(off)))
    locks = [g["lock_s"] for g in gates if g["lock_s"] >= 0]
    if locks:
        print("TIME TO LOCK on the marked one: median %.1f s (%d of %d barriers ever locked it)" % (st.median(locks), len(locks), len(gates)))
    # the approach: 90 to 20 m out
    by = {}
    for r in rows:
        if 20.0 <= r[2] <= 90.0 and 0 <= r[3] < len(r[14]) and r[14][r[3]] >= 0:
            by.setdefault(r[1], []).append(r)
    errs, near_ok, held_ok, tot, xs, ys = [], 0, 0, 0, [], []
    for rr in by.values():
        for r in rr:
            sx = r[14]
            look = r[7]
            tgt = sx[r[3]]
            errs.append(look - tgt)
            vis = [(abs(look - v), i) for i, v in enumerate(sx) if v >= 0]
            if vis and min(vis)[1] == r[3]:
                near_ok += 1
            if r[4] == r[3]:
                held_ok += 1
            tot += 1
            xs.append(tgt - 0.5)
            ys.append(look - 0.5)
    if tot:
        print()
        print("ON THE APPROACH (90 to 20 m out, %d samples over %d barriers)" % (tot, len(by)))
        print("   eye reading: marked opening was the nearest to the look   %s" % pct(near_ok, tot))
        print("   pick: the game was holding the marked opening             %s" % pct(held_ok, tot))
        print("   look error: average %+.3f of the screen (+ = read too far RIGHT), spread %.3f" % (st.mean(errs), st.pstdev(errs)))
        mx, my = st.mean(xs), st.mean(ys)
        sxx = sum((a - mx) ** 2 for a in xs)
        sy = st.pstdev(ys)
        if sxx > 1e-9 and sy > 1e-9:
            sxy = sum((a - mx) * (b - my) for a, b in zip(xs, ys))
            print("   reach: %.2f (1.0 = the look goes as far as the opening), follows the marked opening r = %+.2f" % (sxy / sxx, sxy / len(xs) / (st.pstdev(xs) * sy)))
    print()
    print("EACH BARRIER   (openings numbered from the left, - = none)")
    print("   row  openings  marked  first-held  held-at-barrier  went-through  lock")
    for g in gates:
        lock = ("%.1f s" % g["lock_s"]) if g["lock_s"] >= 0 else "never"
        print("   %3d  %8d  %6s  %10s  %15s  %12s  %s%s" % (g["row"], g["n"], show(g["call"]), show(g["first"]), show(g["eyes"]), show(g["through"]), lock, "  CRASH" if g.get("crash") else ""))


if __name__ == "__main__":
    main()

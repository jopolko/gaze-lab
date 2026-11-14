"""Why did a session go badly? Reads the diagnostics the game sends (Telemetry.gd) and says it in words.

Run it on the log server (the logs live there, outside the web root):

    ssh <server> 'python3 - <who> [session id | latest]' < tools/diag_report.py

Sections: the device, the share of play time spent with each problem (dark face, backlit, bad angle, squint, too far, phone shaking or flat, low frame rate and whether the GPU or the CPU
was the limit, tracker slow or late, main-thread stalls, camera problems), the incidents in order, every gate (hit or missed, how far from the middle, whether your eyes had chosen it,
what was wrong at the time), and the 'THAT FELT BAD' moments with what was going on in the 40 seconds before.
"""
import glob
import json
import os
import statistics
import sys

ROOT = "/var/lib/gaze-lab-logs"


def load(who):
    rows = []
    for f in sorted(glob.glob(os.path.join(ROOT, who, "*.jsonl"))):
        for line in open(f, encoding="utf-8"):
            try:
                rows.append(json.loads(line))
            except Exception:
                pass
    return rows


def pct(a, p):
    if not a:
        return None
    a = sorted(a)
    return a[min(len(a) - 1, int(p * len(a)))]


def main():
    who = sys.argv[1] if len(sys.argv) > 1 else ""
    want = sys.argv[2] if len(sys.argv) > 2 else "latest"
    rows = load(who)
    sids = []
    for r in rows:
        if r.get("sid") and r.get("kind") in ("tick", "env", "gate", "incident", "feltbad", "sum") and r["sid"] not in sids:
            sids.append(r["sid"])
    if not sids:
        print("no diagnostics for", who)
        return
    sid = sids[-1] if want == "latest" else want
    R = [r for r in rows if r.get("sid") == sid]
    T = [r for r in R if r.get("kind") == "tick"]
    play = [r for r in T if not r.get("paused")]
    print("=" * 78)
    print("SESSION %s   tester %s   %d seconds recorded (%d while playing)" % (sid, who, len(T), len(play)))
    env = next((r.get("env") for r in R if r.get("kind") == "env"), {}) or {}
    print("device: %s | %s cores, %s GB | screen %s | %s" % ((env.get("gpu") or "?")[:60], env.get("cores"), env.get("mem"), env.get("scr"), (env.get("ua") or "")[:80]))
    if not play:
        print("(no play time recorded)")
        return

    fps = [r["fps"] for r in play if "fps" in r]
    print("\n--- PERFORMANCE")
    print("  frames per second: median %.0f, worst tenth %.0f, lowest %.0f" % (statistics.median(fps), pct(fps, 0.1), min(fps)))
    ft = [r["ft95"] for r in play if "ft95" in r]
    print("  slowest 5%% of frames: median %.0f ms, worst %.0f ms; longest single frame %.0f ms" % (statistics.median(ft), max(ft), max(r.get("ftmax", 0) for r in play)))
    cpu = [r["cpu"] for r in play if "cpu" in r]
    print("  script + physics time per frame: median %.1f ms (the rest of a slow frame is the GPU / the browser)" % statistics.median(cpu))
    print("  draw calls: median %d; 3D render scale: %s; JS heap: %s MB; battery: %s" % (statistics.median([r.get("draws", 0) for r in play]), sorted(set(r.get("rs") for r in play if r.get("rs") is not None)), (play[-1].get("js") or {}).get("heap"), (play[-1].get("js") or {}).get("bat")))
    lt = sum((r.get("js") or {}).get("lt", 0) for r in play)
    ltm = max([(r.get("js") or {}).get("ltmax", 0) for r in play] or [0])
    print("  main-thread stalls over 50 ms: %d, longest %d ms" % (lt, ltm))

    cam = [r for r in play if r.get("cam")]
    if cam:
        print("\n--- TRACKER (%d seconds with the camera on)" % len(cam))
        trk = [r["trk"] for r in cam if "trk" in r]
        lat = [r["lat"] for r in cam if r.get("lat", -1) > 0]
        mdl = [r["model"] for r in cam if r.get("model", -1) > 0]
        face = [r["face"] for r in cam if "face" in r]
        print("  readings per second: median %.0f, worst tenth %.0f | delay: median %s ms | face model: median %s ms | on the %s | video %s" % (
            statistics.median(trk) if trk else 0, pct(trk, 0.1) or 0, int(statistics.median(lat)) if lat else "?", int(statistics.median(mdl)) if mdl else "?", cam[-1].get("dlg"), cam[-1].get("video")))
        print("  face size in the picture: median %.2f (0.2-0.4 is good)" % (statistics.median(face) if face else 0))
        seen = sum(1 for r in cam if r.get("conf", 0) >= 0.3 and r.get("face", 0) >= 0.05)
        print("  face found in %d%% of the seconds" % (100 * seen / len(cam)))

    # ---- share of play time per problem
    counts = {}
    for r in play:
        for f in r.get("flags", []):
            counts[f] = counts.get(f, 0) + 1
    print("\n--- WHAT WAS WRONG, AS A SHARE OF PLAY TIME")
    if not counts:
        print("  nothing was flagged")
    for f, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print("  %-18s %3d%%  (%d s)  %s" % (f, 100 * n / len(play), n, WHAT.get(f, "")))

    # ---- incidents
    inc = [r for r in R if r.get("kind") == "incident"]
    if inc:
        print("\n--- INCIDENTS (a problem that lasted 2 s or more)")
        for r in inc[:60]:
            if r.get("state") == "start":
                c = r.get("ctx") or {}
                extra = []
                if c.get("light"):
                    extra.append("light %s" % c["light"])
                if c.get("head"):
                    extra.append("head %s" % c["head"])
                extra.append("fps %s, face %s, trk %s, delay %s" % (c.get("fps"), c.get("face"), c.get("trk"), c.get("lat")))
                print("  t=%6.1f  START %-18s %s" % (r.get("t", 0), r.get("what"), "; ".join(extra)))
            else:
                print("  t=%6.1f  END   %-18s after %.0f s" % (r.get("t", 0), r.get("what"), r.get("dur", 0)))

    # ---- gates
    G = [r for r in R if r.get("kind") == "gate"]
    if G:
        hits = sum(1 for g in G if g.get("hit"))
        print("\n--- GATES: %d barriers, %d went through an opening, %d with your eyes having chosen it, %d the game chose for you" % (
            len(G), hits, sum(1 for g in G if g.get("mine")), sum(1 for g in G if g.get("hit") and g.get("eyes") and not g.get("locked"))))
        for g in G[:80]:
            print("  t=%6.1f row %-3s %-5s off the middle %+5.1f m, %s km/h-ish %s, %s%s" % (g.get("t", 0), g.get("row"), "HIT" if g.get("hit") else "MISS", g.get("dx", 0), g.get("spd"), g.get("zone"),
                  "eyes chose it" if g.get("mine") else ("eyes chose another" if g.get("locked") else "eyes had not chosen"), ("   [" + ", ".join(g.get("flags", [])) + "]") if g.get("flags") else ""))

    # ---- felt bad
    FB = [r for r in R if r.get("kind") == "feltbad"]
    for r in FB:
        w = r.get("window") or []
        c = {}
        for x in w:
            for f in x.get("flags", []):
                c[f] = c.get(f, 0) + 1
        print("\n--- THAT FELT BAD at t=%.0f (%s): in the 40 s before: %s" % (r.get("t", 0), r.get("why"), ", ".join("%s %ds" % kv for kv in sorted(c.items(), key=lambda kv: -kv[1])) or "nothing flagged"))
        if w:
            print("    fps median %.0f, tracker median %s/s, face found %d%%" % (statistics.median([x.get("fps", 0) for x in w]), statistics.median([x.get("trk", 0) for x in w if "trk" in x] or [0]),
                  100 * sum(1 for x in w if x.get("conf", 0) >= 0.3) / len(w)))
    print("=" * 78)


WHAT = {
    "dark_face": "too little light on your face",
    "backlit_face": "a light behind or above you; your face is much darker than the room",
    "overexposed_face": "too much light on your face (a lamp above, a window)",
    "flat_picture": "the camera sees almost no contrast: covered, or pointed at a wall or the ceiling",
    "no_face": "the tracker could not find a face",
    "too_far": "your face is small in the picture: hold the phone closer",
    "too_close": "your face fills the picture",
    "bad_angle": "your head is turned or tilted a long way from the camera",
    "squint": "your eyes are nearly closed (the iris is hard to see)",
    "phone_shaking": "the phone is moving a lot (a bus, a bumpy lap)",
    "phone_flat": "the phone lies flat: the camera looks up at you",
    "low_fps": "the game ran below 30 frames a second",
    "gpu_bound": "slow frames with little script time: the graphics are the limit",
    "cpu_bound": "slow frames made of script time: the game logic or the face model is the limit",
    "freeze": "a single frame took over 150 ms",
    "tracker_slow": "under 10 eye readings a second",
    "tracker_late": "the eye readings arrive more than 250 ms late",
    "model_slow": "the face model takes over 90 ms a frame",
    "main_thread_busy": "the browser's main thread stalled for over 120 ms",
    "cam_stalled": "the camera stopped delivering frames",
    "js_errors": "the page logged script errors",
    "page_hidden": "the page was in the background",
}

if __name__ == "__main__":
    main()

"""Live view of the game's test stream (written by tools/serve.py as tools/tune_results.jsonl).
   python tools/watch_tune.py        prints one line per event worth seeing, and a health digest every 30 s."""
import json
import os
import sys
import time

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tune_results.jsonl")
open(path, "a").close()
f = open(path, encoding="utf-8")
f.seek(0, os.SEEK_END)
health = {}
last_digest = time.time()
while True:
    line = f.readline()
    if not line:
        if health and time.time() - last_digest > 30:
          for dev, hl in health.items():
            n = len(hl)
            avg = lambda k: sum(float(h.get(k, 0) or 0) for h in hl) / n
            h = hl[-1]
            print("HEALTH [%s] x%d  game %.0f fps (frame p95 %.0f ms)  tracker %.1f fps  latency %.0f ms  jitter raw %.3f out %.3f  gaze covers %.0f%% x %.0f%%  [%s kalman=%s hold=%s median=%s pick=%s auto=%s]" % (
                dev, n, avg("gameFps"), avg("frameP95ms"), avg("trackerFps"), avg("latencyMs"), avg("jitterRaw"), avg("jitterOut"), avg("spanX") * 100, avg("spanY") * 100,
                h.get("mode"), h.get("kalman"), h.get("hold"), h.get("median"), h.get("pick"), h.get("auto")), flush=True)
          health = {}
          last_digest = time.time()
        time.sleep(0.5)
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    k = d.get("kind", "tune")
    dv = "[%s/%s %s] " % (d.get("who", "?"), d.get("device", "?"), str(d.get("sid", ""))[:4])
    if k == "health":
        health.setdefault("%s/%s %s" % (d.get("who", "?"), d.get("device", "?"), str(d.get("sid", ""))[:4]), []).append(d)
    elif k == "trial":
        print(dv + "TRIAL %s #%s [%s] %s  looked(cursor) %.0f%%  looked(tracker) %.0f%%  lock %.1fs  went gate %s of %s (lit %s)  game ended on gate %s, changed its mind %s x, let go %s x" % (
            d.get("phase", ""), d.get("i"), d.get("cfg"), d.get("verdict"), 100 * float(d.get("look_cur", 0)), 100 * float(d.get("look_gaze", 0)), float(d.get("aim_t", -1)), d.get("went"), d.get("n"), d.get("target"), d.get("aim_end"), d.get("flips"), d.get("lost")), flush=True)
    elif k == "barrier":
        print(dv + "BARRIER gates at %s  you looked at %.2f (%.2f..%.2f)  went through %s  pick=%s" % (d.get("gates"), float(d.get("cur_med", 0)), float(d.get("cur_min", 0)), float(d.get("cur_max", 0)), d.get("went"), d.get("pick")), flush=True)
    elif k == "frame":
        print(dv + "FRAME %s %s  gaze %s  gates %s lit %s cursor %s aim %s" % (d.get("tag"), d.get("path"), d.get("gaze"), d.get("gates"), d.get("lit"), d.get("cursor"), d.get("aim")), flush=True)
    elif k == "note":
        print(dv + "NOTE: %s   [gaze %s, opts %s]" % (d.get("text"), d.get("gaze"), d.get("opts")), flush=True)
    elif k == "opt":
        print(dv + "OPTION CHANGED BY HAND: %s = %s" % (d.get("key"), d.get("value")), flush=True)
    elif k == "auto":
        print(dv + "AUTO " + str(d.get("msg")), flush=True)
    elif "summary" in d:
        print("SUMMARY best=%s" % d.get("best"), flush=True)
        for s in d["summary"]:
            print("   %-32s followed %s/%s  looked-not-followed %s  cursor-lost %s  never-reached %s  assist %s  lock %ss" % (s["name"], s["followed"], s["n"], s["looked_not_followed"], s["cursor_lost_it"], s["never_reached"], s["assist"], s["mean_lock_s"]), flush=True)

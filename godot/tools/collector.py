"""Collector for the anonymous performance numbers people choose to share (opt-in, asked once in the game). NOT run by the game or the dev server: this is for the VPS.

    python3 collector.py [port]            # listens on 127.0.0.1:8070
    nginx:  location = /gaze-lab/log { proxy_pass http://127.0.0.1:8070/log; client_max_body_size 32k; limit_req zone=gazelog burst=20; }

What it accepts: one small JSON object per POST (a health sample, a barrier record, a doctor fix ...). What it refuses: anything bigger than 32 KB, anything that is not a JSON object, and
anything carrying camera images (the game never sends any to this endpoint; frames only ever go to the developer's own laptop). Lines land in logs/<anonymous id>/<date>.jsonl.
"""
import datetime
import http.server
import json
import os
import sys
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8070
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
MAX_BODY = 32 * 1024
KEEP = ("kind", "t", "who", "sid", "app", "device", "hw", "gameFps", "frameP95ms", "trackerFps", "latencyMs", "modelMs", "confidence", "face", "jitterRaw", "jitterOut", "spanX", "spanY",
        "mode", "kalman", "hold", "median", "pick", "auto", "view", "camera", "eyeAim", "gaze", "eyeLook", "offset", "scale", "locked", "msg", "event", "issue", "evidence", "action", "before",
        "after", "verdict", "row", "n", "gates", "cur_med", "cur_min", "cur_max", "looked", "aim", "went", "steer", "pick", "aim_end", "flips", "lost", "lock_t", "verdict", "target", "look_cur",
        "look_gaze", "aim_t", "cfg", "phase", "i", "ci", "key", "value", "by")
_hits = {}


def safe(x):
    return "".join(c for c in str(x) if c.isalnum() or c in "-_")[:32] or "x"


class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        ip = self.headers.get("X-Real-IP") or self.client_address[0]
        now = time.time()
        recent = [t for t in _hits.get(ip, []) if now - t < 60]
        if len(recent) >= 240:
            self.send_response(429)
            self.end_headers()
            return
        recent.append(now)
        _hits[ip] = recent
        n = int(self.headers.get("Content-Length", "0") or 0)
        if n <= 0 or n > MAX_BODY:
            self.send_response(413)
            self.end_headers()
            return
        try:
            d = json.loads(self.rfile.read(n).decode("utf-8", "replace"))
        except Exception:
            d = None
        if not isinstance(d, dict) or any(k in d for k in ("face", "full", "jpg", "snap", "image")) and not isinstance(d.get("face"), (int, float)):
            self.send_response(400)
            self.end_headers()
            return
        rec = {k: d[k] for k in KEEP if k in d}
        folder = os.path.join(ROOT, safe(d.get("who", "unnamed")))
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, datetime.date.today().strftime("%Y%m%d") + ".jsonl"), "a", encoding="utf-8") as f:
            f.write(json.dumps(rec) + "\n")
        self.send_response(204)
        self.end_headers()

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    os.makedirs(ROOT, exist_ok=True)
    print("collecting on 127.0.0.1:%d into %s" % (PORT, ROOT), flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()

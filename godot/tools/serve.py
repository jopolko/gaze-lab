"""Serve the web export locally: python tools/serve.py [port]   ->  http://localhost:8060/
For other devices on the network (a phone, another laptop): python tools/serve.py --lan   ->  https://<this machine's address>:8443/
  (HTTPS with a throwaway self-signed certificate, because browsers only allow the camera on a secure page; the browser will warn once: accept it.)
Never cached, so a fresh export shows up on reload. localhost counts as a secure context, so the camera works.
(No special headers needed: the export is built without threads.)"""
import http.server
import os
import sys

LAN = "--lan" in sys.argv
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
PORT = int(ARGS[0]) if ARGS else (8443 if LAN else 8060)
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")


import base64
import datetime
import json

FRAMES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "frames")
LOGS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
TODAY = datetime.datetime.now().strftime("%Y%m%d")


def safe_name(x):
    return "".join(c for c in str(x) if c.isalnum() or c in "-_")[:32] or "x"

SESSION = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
_seq = [0]


def save_frame(d):
    """One captured frame: NNNN.face.jpg (face crop, raw camera orientation), NNNN.full.jpg (whole frame, small), NNNN.json (tracker numbers + game decision).
    Appends a line to tune_results.jsonl so the watcher prints it."""
    who = safe_name(((d.get("meta") or {}).get("who")) or "unnamed")
    sid = safe_name(((d.get("meta") or {}).get("sid")) or SESSION)
    folder = os.path.join(FRAMES, who, SESSION + "_" + sid)
    os.makedirs(folder, exist_ok=True)
    _seq[0] += 1
    n = "%04d" % _seq[0]
    snap = d.get("snap") or {}
    for key in ("face", "full"):
        url = snap.get(key)
        if url and "," in url:
            with open(os.path.join(folder, "%s.%s.jpg" % (n, key)), "wb") as f:
                f.write(base64.b64decode(url.split(",", 1)[1]))
    meta = d.get("meta") or {}
    rec = {"meta": meta, "pkt": snap.get("pkt"), "rot": snap.get("rot"), "size": [snap.get("w"), snap.get("h")], "crop": snap.get("crop")}
    with open(os.path.join(folder, n + ".json"), "w", encoding="utf-8") as f:
        json.dump(rec, f)
    line = {"kind": "frame", "who": meta.get("who"), "sid": meta.get("sid"), "path": os.path.join(folder, n).replace("\\", "/"), "device": meta.get("device"), "tag": meta.get("tag"), "gaze": meta.get("gaze"),
            "gates": meta.get("gates"), "lit": meta.get("lit"), "cursor": meta.get("cursor"), "aim": meta.get("aim")}
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "tune_results.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(line) + "\n")


class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".js": "text/javascript", ".pck": "application/octet-stream"}

    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        # test results from the game (tune sessions) are appended to tools/tune_results.jsonl, so they can be read while you play
        n = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        if self.path == "/tune" and body:
            with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "tune_results.jsonl"), "a", encoding="utf-8") as f:
                f.write(body.replace("\n", " ") + "\n")
            try:
                d0 = json.loads(body)
                who = safe_name(d0.get("who", "unnamed"))
                folder = os.path.join(LOGS, who)
                os.makedirs(folder, exist_ok=True)
                with open(os.path.join(folder, "%s_%s_%s.jsonl" % (TODAY, safe_name(d0.get("device", "x")), safe_name(d0.get("sid", "x")))), "a", encoding="utf-8") as f:
                    f.write(body.replace("\n", " ") + "\n")
            except Exception:
                pass
        if self.path == "/frame" and body:
            try:
                save_frame(json.loads(body))
            except Exception as e:
                print("frame save failed:", e, flush=True)
        self.send_response(204)
        self.end_headers()

    def log_message(self, *a):
        pass



def lan_ip():
    import socket
    try:
        t = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        t.connect(("10.255.255.255", 1))
        ip = t.getsockname()[0]
        t.close()
        return ip
    except Exception:
        return "127.0.0.1"


srv = http.server.ThreadingHTTPServer(("0.0.0.0" if LAN else "127.0.0.1", PORT), H)
if LAN:
    import ssl
    import subprocess
    here = os.path.dirname(os.path.abspath(__file__))
    crt, key = os.path.join(here, "dev-cert.pem"), os.path.join(here, "dev-key.pem")
    ip = lan_ip()
    if not (os.path.exists(crt) and os.path.exists(key)):
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "365", "-keyout", key, "-out", crt, "-subj", "/CN=gaze-lab-dev",
                        "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:%s" % ip], check=True, capture_output=True)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(crt, key)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    print("serving %s at https://%s:%d/  (self-signed: accept the browser warning once)" % (os.path.normpath(ROOT), ip, PORT), flush=True)
else:
    print("serving %s at http://localhost:%d/" % (os.path.normpath(ROOT), PORT), flush=True)
srv.serve_forever()

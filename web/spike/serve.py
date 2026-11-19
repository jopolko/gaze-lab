"""Serve the spike (and the vendored three.js / tracker next to it):  python serve.py   ->  http://localhost:8072/spike/
--lan for phones: https://<this machine>:8472/spike/ (self-signed certificate from godot/tools)."""
import http.server, os, ssl, sys

LAN = "--lan" in sys.argv
PORT = 8472 if LAN else 8072
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
TOOLS = os.path.join(ROOT, "..", "godot", "tools")


class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".js": "text/javascript", ".mjs": "text/javascript", ".task": "application/octet-stream"}

    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def translate_path(self, path):
        # /music/... is the Godot game's music folder (kept out of web/ so it is not copied around)
        if path.startswith("/music/"):
            return os.path.abspath(os.path.join(ROOT, "..", "godot", "music_web", path[len("/music/"):].split("?")[0]))
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        # the spike's own diagnostics: a batch of gaze samples, appended to logs/spike-<date>.jsonl so a run can be read back afterwards
        try:
            n = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(n).decode("utf-8", "replace")
            os.makedirs(os.path.join(HERE, "logs"), exist_ok=True)
            import datetime
            with open(os.path.join(HERE, "logs", "spike-%s.jsonl" % datetime.date.today().isoformat()), "a", encoding="utf-8") as f:
                f.write(body.strip() + "\n")
            self.send_response(204)
        except Exception:
            self.send_response(500)
        self.end_headers()

    def log_message(self, *a):
        pass


srv = http.server.ThreadingHTTPServer(("0.0.0.0" if LAN else "127.0.0.1", PORT), H)
if LAN:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(os.path.join(TOOLS, "dev-cert.pem"), os.path.join(TOOLS, "dev-key.pem"))
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
print("serving %s on %s://localhost:%d/spike/" % (ROOT, "https" if LAN else "http", PORT), flush=True)
srv.serve_forever()

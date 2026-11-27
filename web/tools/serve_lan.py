"""Serve the web folder over https on the local network, for a Quest headset (WebXR needs https).
  python tools/serve_lan.py [port]     ->  https://<this machine's address>:8447/   (default port 8447; 443 gives the bare address)
The headset warns once about the throwaway certificate: Advanced -> Proceed. Nothing is cached.
Paths:  /            the demo menu (web/menu.html)
        /godot/      the Godot web export (../godot/build/web), sent with the headers its threads need
        /vrlog       POST: the games send their frame-rate numbers here; they are appended to tools/vr_log.jsonl (numbers only)"""
import gzip, http.server, os, socket, ssl, sys

WEB = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GODOT = os.path.abspath(os.path.join(WEB, "..", "godot", "build", "web"))
TOOLS = os.path.join(WEB, "..", "godot", "tools")
LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vr_log.jsonl")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8447
GZ_EXT = {".html", ".js", ".mjs", ".json", ".css", ".wasm", ".pck", ".svg", ".txt", ".jsonl", ".webmanifest"}          # sent gzip-compressed (about a quarter of the size for the engine and the course data)
_GZ = {}
_GZ_BYTES = [0]


class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".js": "text/javascript", ".mjs": "text/javascript", ".pck": "application/octet-stream"}

    def __init__(self, *a, **k):
        super().__init__(*a, directory=WEB, **k)

    def translate_path(self, path):
        p = path.split("?")[0].split("#")[0]
        if p == "/godot" or p.startswith("/godot/"):
            rest = p[len("/godot"):].lstrip("/")
            full = os.path.normpath(os.path.join(GODOT, rest))
            if not full.startswith(GODOT):          # never leave the export folder
                return os.path.join(GODOT, "index.html")
            return os.path.join(full, "index.html") if os.path.isdir(full) else full
        return super().translate_path(path)

    def do_GET(self):
        p = self.path.split("?")[0]
        if p in ("/", "/index.html"):
            self.send_response(302)
            self.send_header("Location", "/menu.html")
            self.end_headers()
            return
        if p == "/godot":
            self.send_response(302)
            self.send_header("Location", "/godot/" + ("?" + self.path.split("?", 1)[1] if "?" in self.path else ""))
            self.end_headers()
            return
        path = self.translate_path(self.path)
        ext = os.path.splitext(path)[1].lower()
        if ext in GZ_EXT and os.path.isfile(path) and "gzip" in (self.headers.get("Accept-Encoding") or "") and not self.headers.get("Range"):
            try:
                st = os.stat(path)
                key = (path, st.st_mtime_ns, st.st_size)
                body = _GZ.get(key)
                if body is None:
                    with open(path, "rb") as f:
                        body = gzip.compress(f.read(), compresslevel=6)
                    if _GZ_BYTES[0] + len(body) < 700 * 1024 * 1024:
                        _GZ[key] = body
                        _GZ_BYTES[0] += len(body)
                self.send_response(200)
                self.send_header("Content-Type", self.guess_type(path))
                self.send_header("Content-Encoding", "gzip")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Vary", "Accept-Encoding")
                self.end_headers()
                self.wfile.write(body)
                return
            except (BrokenPipeError, ConnectionResetError):
                return
            except Exception:
                pass          # anything odd: fall through to the plain file
        super().do_GET()

    def do_POST(self):
        if self.path.split("?")[0] == "/vrlog":
            n = int(self.headers.get("Content-Length") or 0)
            if 0 < n <= 65536:
                with open(LOG, "ab") as f:
                    f.write(self.rfile.read(n).replace(b"\n", b" ") + b"\n")
            self.send_response(204)
            self.end_headers()
            return
        self.send_response(404)
        self.end_headers()

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        if self.path.split("?")[0].startswith("/godot"):          # Godot's threaded web build needs the page to be cross-origin isolated
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
            self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()

    def log_message(self, *a):
        pass


s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(("8.8.8.8", 80)); ip = s.getsockname()[0]
except Exception:
    ip = "<this machine's address>"
PLAIN = len(sys.argv) > 2 and sys.argv[2] == "http"          # python tools/serve_lan.py 8090 http : plain http on this machine only, for a desktop test
http.server.ThreadingHTTPServer.request_queue_size = 256          # the default backlog of 5 refused connections when a page asks for fifty modules at once ("connection refused", a page stuck on loading)
srv = http.server.ThreadingHTTPServer(("127.0.0.1" if PLAIN else "0.0.0.0", PORT), H)
if not PLAIN:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(os.path.join(TOOLS, "dev-cert.pem"), os.path.join(TOOLS, "dev-key.pem"))
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
print(("Open http://localhost:%d/" % PORT) if PLAIN else ("Open this in the Quest browser:  https://%s:%d/" % (ip, PORT)), flush=True)
srv.serve_forever()

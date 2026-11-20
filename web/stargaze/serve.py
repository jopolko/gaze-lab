"""Serve STARGAZE for testing.
  python serve.py          ->  http://localhost:8070/          (this machine; localhost may use the camera)
  python serve.py --lan    ->  https://<this machine's address>:8470/   (phones on the same Wi-Fi)
Phones only allow the camera on HTTPS, so --lan uses the throwaway self-signed certificate in godot/tools;
the phone warns once: choose Advanced -> Proceed. Nothing is cached, so a reload always shows the latest files."""
import http.server, os, ssl, sys

LAN = "--lan" in sys.argv
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
PORT = int(ARGS[0]) if ARGS else (8470 if LAN else 8070)
HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, "..", "..", "godot", "tools")


class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".js": "text/javascript", ".mjs": "text/javascript", ".task": "application/octet-stream"}

    def __init__(self, *a, **k):
        super().__init__(*a, directory=HERE, **k)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *a):
        pass


srv = http.server.ThreadingHTTPServer(("0.0.0.0" if LAN else "127.0.0.1", PORT), H)
if LAN:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(os.path.join(TOOLS, "dev-cert.pem"), os.path.join(TOOLS, "dev-key.pem"))
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
print("serving %s on %s://%s:%d/" % (HERE, "https" if LAN else "http", "0.0.0.0" if LAN else "localhost", PORT), flush=True)
srv.serve_forever()

"""Host-side canary endpoint for the sbx secret-injection test (T1).

Echoes back only whether the Authorization header carried the real canary, so the
real value is never printed into sandbox-visible output.

    CANARY=... python3 spike/sbx/echo-server.py 40199
"""
import http.server
import os
import sys

CANARY = os.environ["CANARY"]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get("Authorization", "")
        body = f"real_canary_received={CANARY in auth} header_len={len(auth)}\n".encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        print(f"{self.client_address[0]} {self.path} real_canary_received={CANARY in auth}", flush=True)


http.server.ThreadingHTTPServer(("0.0.0.0", int(sys.argv[1])), Handler).serve_forever()

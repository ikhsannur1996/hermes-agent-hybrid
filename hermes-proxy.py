#!/usr/bin/env python3
"""
Hermes API Proxy — OpenAI-compatible chat completions endpoint.

Primary:   local Ollama (qwen3:8b)
Fallback:  OpenRouter (qwen/qwen3-coder)
Auth:      handled by Nginx basic auth in front of this proxy.
Streaming: SSE responses are relayed chunk-by-chunk.

Config via env (also loaded from ~/.hermes/.env by systemd):
  OLLAMA_URL           default http://127.0.0.1:11434
  OLLAMA_MODEL         default qwen3:8b
  OPENROUTER_API_KEY   default "" (disables fallback)
  OPENROUTER_MODEL     default qwen/qwen3-coder
  HERMES_PROXY_HOST    default 127.0.0.1
  HERMES_PROXY_PORT    default 8643
"""
import json
import os
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen3:8b")
OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
OPENROUTER_MODEL = os.environ.get("OPENROUTER_MODEL", "qwen/qwen3-coder")
HOST = os.environ.get("HERMES_PROXY_HOST", "127.0.0.1")
PORT = int(os.environ.get("HERMES_PROXY_PORT", "8643"))
TIMEOUT = 300

CHAT_ENDPOINTS = ("/v1/chat/completions", "/v1/completions")


def _post_json(url, payload, headers=None):
    data = json.dumps(payload).encode("utf-8")
    h = {"Content-Type": "application/json"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, data=data, headers=h, method="POST")
    return urllib.request.urlopen(req, timeout=TIMEOUT)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    # ---------- helpers ----------

    def _json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _relay(self, upstream):
        """Copy upstream response back to client chunk-by-chunk (preserves SSE)."""
        self.send_response(upstream.status)
        ctype = upstream.headers.get("Content-Type", "application/json")
        self.send_header("Content-Type", ctype)
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            while True:
                chunk = upstream.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
        finally:
            upstream.close()
            self.wfile.flush()

    # ---------- routes ----------

    def do_GET(self):
        if self.path == "/health":
            ok = False
            try:
                with urllib.request.urlopen(OLLAMA_URL + "/api/tags", timeout=5) as r:
                    ok = r.status == 200
            except Exception:
                pass
            self._json(200, {
                "status": "ok",
                "local_ollama": ok,
                "openrouter": bool(OPENROUTER_API_KEY),
            })
        elif self.path == "/v1/models":
            self._json(200, {"object": "list", "data": [
                {"id": "hermes-agent", "object": "model", "owned_by": "hermes"},
                {"id": OLLAMA_MODEL, "object": "model", "owned_by": "ollama"},
                {"id": OPENROUTER_MODEL, "object": "model", "owned_by": "openrouter"},
            ]})
        else:
            self._json(404, {"error": {"message": "not found",
                                       "type": "not_found", "code": "not_found"}})

    def do_POST(self):
        if self.path not in CHAT_ENDPOINTS:
            self._json(404, {"error": {"message": "not found",
                                       "type": "not_found", "code": "not_found"}})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(length) or b"{}")
        except Exception as exc:
            self._json(400, {"error": {"message": f"bad request: {exc}",
                                       "type": "invalid_request_error",
                                       "code": "invalid_request"}})
            return

        # 1) Try local Ollama first
        local = dict(payload)
        local["model"] = OLLAMA_MODEL
        try:
            upstream = _post_json(OLLAMA_URL + "/v1/chat/completions", local)
            self._relay(upstream)
            return
        except Exception as local_err:
            # 2) Fallback to OpenRouter
            if not OPENROUTER_API_KEY:
                self._json(502, {"error": {"message": f"local model failed and no "
                                                      f"fallback configured: {local_err}",
                                           "type": "upstream_error",
                                           "code": "upstream_error"}})
                return
            remote = dict(payload)
            remote["model"] = OPENROUTER_MODEL
            try:
                upstream = _post_json(
                    "https://openrouter.ai/api/v1/chat/completions",
                    remote,
                    {"Authorization": f"Bearer {OPENROUTER_API_KEY}"},
                )
                self._relay(upstream)
            except Exception as remote_err:
                self._json(502, {"error": {
                    "message": f"local and fallback both failed: local={local_err} "
                               f"fallback={remote_err}",
                    "type": "upstream_error", "code": "upstream_error"}})


def main():
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"hermes-api-proxy listening on http://{HOST}:{PORT}/v1", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()

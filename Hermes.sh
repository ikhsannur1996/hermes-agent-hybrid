cat > /tmp/install-hermes-hybrid.sh <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# HERMES API HYBRID — Fully automated install
# ============================================================
# Provides:
#   - Local model via Ollama (qwen3:8b)
#   - Cloud fallback via OpenRouter (qwen/qwen3-coder)
#   - OpenAI-compatible API at http://IP:8642/v1
#   - Nginx reverse proxy with basic auth (admin/admin)
#   - Auto-start on boot (systemd for all services)
#
# Usage: OPENROUTER_API_KEY="sk-or-v1-xxx" bash Hermes.sh
# ============================================================

OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
OLLAMA_MODEL="qwen3:8b"
OPENROUTER_MODEL="qwen/qwen3-coder"
API_PORT="8642"
OLLAMA_URL="http://127.0.0.1:11434"
PROXY_PORT="8643"
PROXY_HOST="127.0.0.1"
BASIC_AUTH_USER="admin"
BASIC_AUTH_PASS="admin"

if [[ -z "$OPENROUTER_API_KEY" ]]; then
    echo
    echo "============================================================"
    echo " OpenRouter API Key Required"
    echo "============================================================"
    echo
    echo "Get your free key at: https://openrouter.ai/keys"
    echo
    echo "Usage: OPENROUTER_API_KEY=\"sk-or-v1-xxx\" bash Hermes.sh"
    echo
    exit 1
fi

API_SERVER_KEY="$(openssl rand -hex 32)"

echo
echo "============================================================"
echo " Hermes API Hybrid Installation"
echo "============================================================"
echo
echo "Local model      : ${OLLAMA_MODEL}"
echo "OpenRouter model : ${OPENROUTER_MODEL}"
echo "API port         : ${API_PORT} (Nginx with basic auth)"
echo "Browser login    : ${BASIC_AUTH_USER} / ${BASIC_AUTH_PASS}"
echo "API key (bearer) : ${API_SERVER_KEY}"
echo
echo "NOTE: Hermes API proxy replaces the Nous Research Hermes Agent"
echo "gateway, which does not provide an OpenAI-compatible endpoint."
echo "The proxy is a lightweight Python server that runs local-first"
echo "with automatic OpenRouter fallback."
echo

# ============================================================
# 1. SYSTEM PACKAGES
# ============================================================

echo "[1/10] Updating system..."

sudo apt-get update -y

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    wget \
    git \
    ca-certificates \
    build-essential \
    jq \
    unzip \
    tmux \
    htop \
    ripgrep \
    ffmpeg \
    python3 \
    python3-pip \
    openssl \
    ufw \
    nginx \
# ============================================================
# 2. INSTALL OLLAMA
# ============================================================

echo "[2/10] Installing Ollama..."

if ! command -v ollama >/dev/null 2>&1; then
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "Ollama already installed."
fi

sudo systemctl enable ollama
sudo systemctl restart ollama

echo "Waiting for Ollama to be ready..."
for i in $(seq 1 12); do
    if curl -fsS "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
        echo "Ollama is ready."
        break
    fi
    if [[ "$i" -eq 12 ]]; then
        echo "ERROR: Ollama failed to start after 60 seconds."
        sudo systemctl status ollama --no-pager || true
        exit 1
    fi
    sleep 5
done

# ============================================================
# 3. ENSURE OLLAMA IS RESPONDING
# ============================================================

echo "[3/10] Testing Ollama..."

if ! curl -fsS "${OLLAMA_URL}/api/tags" >/dev/null; then
    echo "ERROR: Ollama is not responding."
    sudo systemctl status ollama --no-pager || true
    exit 1
fi

echo "Ollama is running."

# ============================================================
# 4. PULL LOCAL MODEL
# ============================================================

echo "[4/10] Pulling local model (this may take a while)..."

ollama pull "${OLLAMA_MODEL}"

echo
echo "Installed models:"
ollama list
echo

# ============================================================
# 5. CONFIGURE OLLAMA 64K CONTEXT
# ============================================================

echo "[5/10] Configuring Ollama context..."

sudo mkdir -p /etc/systemd/system/ollama.service.d

sudo tee /etc/systemd/system/ollama.service.d/hermes.conf >/dev/null <<OLLAMA_CONF
[Service]
Environment="OLLAMA_NUM_CTX=65536"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
OLLAMA_CONF

sudo systemctl daemon-reload
sudo systemctl restart ollama

echo "Waiting for Ollama to reload..."
for i in $(seq 1 6); do
    if curl -fsS "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
        echo "Ollama reloaded with 64K context."
        break
    fi
    if [[ "$i" -eq 6 ]]; then
        echo "ERROR: Ollama failed to reload."
        exit 1
    fi
    sleep 5
done

# ============================================================
# 6. WRITE API PROXY + CONFIG
# ============================================================

echo "[6/10] Installing Hermes API proxy..."

mkdir -p "${HOME}/.hermes"
chmod 700 "${HOME}/.hermes"

cat > "${HOME}/.hermes/api-proxy.py" <<'PYEOF'
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
PYEOF
chmod 700 "${HOME}/.hermes/api-proxy.py"

# 7. WRITE SECRETS
echo "[7/10] Writing secrets..."

cat > "${HOME}/.hermes/.env" <<ENVEOF
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
OLLAMA_MODEL=${OLLAMA_MODEL}
OPENROUTER_MODEL=${OPENROUTER_MODEL}
OLLAMA_URL=${OLLAMA_URL}
HERMES_PROXY_HOST=${PROXY_HOST}
HERMES_PROXY_PORT=${PROXY_PORT}
API_SERVER_KEY=${API_SERVER_KEY}
ENVEOF
chmod 600 "${HOME}/.hermes/.env"

# ============================================================
# 8. SYSTEMD SERVICE (hermes-api)
# ============================================================

echo "[8/10] Creating hermes-api systemd service..."

HERMES_USER="$(id -un)"
HERMES_HOME="${HOME}"
HERMES_PY="$(command -v python3)"

cat > /tmp/hermes-api.service <<SVCEOF
[Unit]
Description=Hermes API Proxy (OpenAI-compatible)
After=network-online.target ollama.service
Wants=network-online.target
Requires=ollama.service

[Service]
Type=simple
User=${HERMES_USER}
Group=${HERMES_USER}
WorkingDirectory=${HERMES_HOME}
Environment=HOME=${HERMES_HOME}
Environment=PATH=/usr/local/bin:/usr/bin:/bin
EnvironmentFile=${HERMES_HOME}/.hermes/.env
ExecStart=${HERMES_PY} ${HERMES_HOME}/.hermes/api-proxy.py
Restart=always
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
SVCEOF

sudo cp /tmp/hermes-api.service /etc/systemd/system/hermes-api.service
sudo systemctl daemon-reload
sudo systemctl enable hermes-api
sudo systemctl restart hermes-api

# ============================================================
# 9. NGINX REVERSE PROXY WITH BASIC AUTH
# ============================================================

echo "[9/10] Configuring Nginx with basic auth..."

HTPASSWD=$(openssl passwd -apr1 "${BASIC_AUTH_PASS}")
echo "${BASIC_AUTH_USER}:${HTPASSWD}" | sudo tee /etc/nginx/.htpasswd >/dev/null
sudo chmod 644 /etc/nginx/.htpasswd

sudo rm -f /etc/nginx/sites-enabled/default

sudo tee /etc/nginx/sites-available/hermes >/dev/null <<NGINXEOF
server {
    listen ${API_PORT} default_server;
    listen [::]:${API_PORT} default_server;

    auth_basic "Hermes API";
    auth_basic_user_file /etc/nginx/.htpasswd;

    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Host \$http_host;
    proxy_set_header Authorization \$http_authorization;
    proxy_pass_header Authorization;

    location / {
        proxy_pass http://127.0.0.1:${PROXY_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;

        # Retry on 502/503 (while services warm up)
        proxy_next_upstream error timeout http_502 http_503;
        proxy_next_upstream_tries 3;
        proxy_next_upstream_timeout 15s;
    }
}
NGINXEOF

sudo ln -sf /etc/nginx/sites-available/hermes /etc/nginx/sites-enabled/hermes
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

# Make Nginx wait for hermes-api on boot (prevents 502)
sudo mkdir -p /etc/systemd/system/nginx.service.d
sudo tee /etc/systemd/system/nginx.service.d/wait-hermes.conf >/dev/null <<NGXWAIT
[Unit]
After=hermes-api.service
Wants=hermes-api.service
NGXWAIT

sudo systemctl daemon-reload
sudo nginx -t && sudo systemctl restart nginx

echo

# 10. FIREWALL + VERIFY + OUTPUT
# ============================================================

echo "[10/10] Configuring firewall..."

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow "${API_PORT}/tcp"
sudo ufw --force enable

echo
sudo ufw status
echo

echo "Waiting for Hermes API proxy..."
for i in $(seq 1 12); do
    if systemctl is-active --quiet hermes-api; then
        echo "Hermes API proxy is active."
        break
    fi
    if [[ "$i" -eq 12 ]]; then
        echo "WARNING: hermes-api not active yet. Check: sudo journalctl -u hermes-api -n 30"
    fi
    sleep 5
done

echo; echo "Hermes API service:"
sudo systemctl status hermes-api --no-pager || true

echo; echo "Checking API (direct to proxy on port ${PROXY_PORT})..."
PROXY_HEALTH="$(curl -sS --max-time 15 "http://127.0.0.1:${PROXY_PORT}/health" || echo FAILED)"
echo "Proxy direct: ${PROXY_HEALTH}"

echo "Checking API (via Nginx on port ${API_PORT} with basic auth)..."
NGINX_HEALTH="$(curl -sS --max-time 15 -u "${BASIC_AUTH_USER}:${BASIC_AUTH_PASS}" "http://127.0.0.1:${API_PORT}/health" || echo FAILED)"
echo "Nginx proxy: ${NGINX_HEALTH}"

echo
echo "Detecting public IP..."
PUBLIC_IP=""
if [[ -z "$PUBLIC_IP" ]]; then PUBLIC_IP="$(curl -4 -sS --max-time 5 https://api.ipify.org 2>/dev/null || true)"; fi
if [[ -z "$PUBLIC_IP" ]]; then PUBLIC_IP="$(curl -4 -sS --max-time 5 https://ifconfig.me 2>/dev/null || true)"; fi
if [[ -z "$PUBLIC_IP" ]]; then PUBLIC_IP="$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || true)"; fi
if [[ -z "$PUBLIC_IP" ]]; then PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"; fi
if [[ -z "$PUBLIC_IP" ]]; then PUBLIC_IP="YOUR_SERVER_IP"; fi
echo "Public IP: ${PUBLIC_IP}"
echo

# SAVE CONNECTION INFO
cat > "${HOME}/hermes-connection.txt" <<DATAEOF
Hermes Agent Hybrid
===================

Public API: http://${PUBLIC_IP}:${API_PORT}/v1
Health: http://${PUBLIC_IP}:${API_PORT}/health
Models: http://${PUBLIC_IP}:${API_PORT}/v1/models
Chat: http://${PUBLIC_IP}:${API_PORT}/v1/chat/completions

API Key (bearer): ${API_SERVER_KEY}
Browser Login: ${BASIC_AUTH_USER} / ${BASIC_AUTH_PASS}

Local Ollama: http://127.0.0.1:11434
Local Model: ${OLLAMA_MODEL}
OpenRouter Fallback: ${OPENROUTER_MODEL}
DATAEOF
chmod 600 "${HOME}/hermes-connection.txt"

echo; echo
echo "============================================================"
echo " INSTALLATION FINISHED"
echo "============================================================"
echo
echo "PUBLIC API (browser login: admin / admin)"
echo "  http://${PUBLIC_IP}:${API_PORT}/v1"
echo
echo "HEALTH"
echo "  http://${PUBLIC_IP}:${API_PORT}/health"
echo
echo "MODELS"
echo "  http://${PUBLIC_IP}:${API_PORT}/v1/models"
echo
echo "CHAT"
echo "  http://${PUBLIC_IP}:${API_PORT}/v1/chat/completions"
echo
echo "API KEY (bearer): ${API_SERVER_KEY}"
echo
echo "BROWSER LOGIN: ${BASIC_AUTH_USER} / ${BASIC_AUTH_PASS}"
echo
echo "Saved to: ${HOME}/hermes-connection.txt"
echo
echo "============================================================"
echo " TEST"
echo "============================================================"
echo
cat <<EOF
curl -X POST \\
  http://${PUBLIC_IP}:${API_PORT}/v1/chat/completions \\
  -H "Authorization: Bearer ${API_SERVER_KEY}" \\
  -H "Content-Type: application/json" \\
  -d '{"model": "hermes-agent", "messages": [{"role": "user", "content": "Hello!"}]}'
EOF
echo
echo "============================================================"
echo " IMPORTANT"
echo "============================================================"
echo
echo "Cloud firewall/security group must allow:"
echo '  TCP 22   - SSH'
echo '  TCP ${API_PORT} - Hermes API (with basic auth)'
echo
echo "Do NOT expose:"
echo '  TCP 11434 - Ollama'
echo '  TCP ${PROXY_PORT} - Hermes proxy (localhost only)'
echo
echo "Browser login: ${BASIC_AUTH_USER} / ${BASIC_AUTH_PASS}"
echo
echo "============================================================"
SCRIPT

chmod +x /tmp/install-hermes-hybrid.sh
/tmp/install-hermes-hybrid.sh

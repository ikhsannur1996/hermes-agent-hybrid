#!/usr/bin/env bash
set -Eeuo pipefail

# HERMES AGENT HYBRID — One-shot Install
# Usage:
#   export OPENROUTER_API_KEY="sk-or-v1-xxx"
#   curl -fsSL https://raw.githubusercontent.com/ikhsannur1996/hermes-agent-hybrid/main/install.sh | bash

OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-sk-or-REPLACE_ME}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3:8b}"
OPENROUTER_MODEL="${OPENROUTER_MODEL:-qwen/qwen3-coder}"
API_PORT="${API_PORT:-8642}"
OLLAMA_URL="http://127.0.0.1:11434"

if [[ "$OPENROUTER_API_KEY" == "sk-or-REPLACE_ME" ]]; then
    echo; echo "ERROR: Set your OpenRouter API key first."
    echo "  export OPENROUTER_API_KEY=\"sk-or-v1-xxx\""
    echo "  curl -fsSL https://raw.githubusercontent.com/ikhsannur1996/hermes-agent-hybrid/main/install.sh | bash"
    exit 1
fi

API_SERVER_KEY="$(openssl rand -hex 32)"
echo; echo "===== Hermes Hybrid Installation ====="; echo
echo "Local model      : ${OLLAMA_MODEL}"
echo "OpenRouter model : ${OPENROUTER_MODEL}"
echo "API port         : ${API_PORT}"
echo "Generated API key: ${API_SERVER_KEY}"; echo

# 1. SYSTEM PACKAGES
echo "[1/12] Updating system..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget git ca-certificates build-essential jq unzip tmux htop ripgrep ffmpeg python3 python3-pip openssl ufw

# 2. INSTALL OLLAMA
echo "[2/12] Installing Ollama..."
if ! command -v ollama >/dev/null 2>&1; then curl -fsSL https://ollama.com/install.sh | sh; fi
sudo systemctl enable ollama; sudo systemctl restart ollama
echo "Waiting for Ollama to be ready..."
for i in $(seq 1 12); do
    if curl -fsS "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then echo "Ollama is ready."; break; fi
    if [[ "$i" -eq 12 ]]; then echo "ERROR: Ollama failed to start after 60 seconds."; sudo systemctl status ollama --no-pager || true; exit 1; fi
    sleep 5
done

# 3. TEST OLLAMA
echo "[3/12] Testing Ollama..."
if ! curl -fsS "${OLLAMA_URL}/api/tags" >/dev/null; then echo "ERROR: Ollama is not responding."; sudo systemctl status ollama --no-pager || true; exit 1; fi
echo "Ollama is running."

# 4. PULL LOCAL MODEL
echo "[4/12] Pulling local model..."
ollama pull "${OLLAMA_MODEL}"
echo; echo "Installed models:"; ollama list; echo

# 5. CONFIGURE OLLAMA CONTEXT
echo "[5/12] Configuring Ollama context..."
sudo mkdir -p /etc/systemd/system/ollama.service.d
cat > /tmp/hermes-ollama-conf <<'OLLAMA_EOF'
[Service]
Environment="OLLAMA_NUM_CTX=65536"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
OLLAMA_EOF
sudo cp /tmp/hermes-ollama-conf /etc/systemd/system/ollama.service.d/hermes.conf
sudo systemctl daemon-reload; sudo systemctl restart ollama
echo "Waiting for Ollama to reload..."
for i in $(seq 1 6); do
    if curl -fsS "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then echo "Ollama reloaded with 64K context."; break; fi
    if [[ "$i" -eq 6 ]]; then echo "ERROR: Ollama failed to reload."; exit 1; fi
    sleep 5
done

# 6. INSTALL HERMES
echo "[6/12] Installing Hermes Agent..."
curl -fsSL --max-time 60 https://hermes-agent.nousresearch.com/install.sh | bash
export PATH="${HOME}/.local/bin:${PATH}"
if ! command -v hermes >/dev/null 2>&1; then echo "ERROR: Hermes installation failed."; exit 1; fi
echo; hermes --version; echo

# 7. CREATE DIRECTORIES
echo "[7/12] Creating Hermes configuration..."
mkdir -p "${HOME}/.hermes"
chmod 700 "${HOME}/.hermes"

# 8. SECRETS
echo "[8/12] Writing secrets..."
cat > "${HOME}/.hermes/.env" <<ENV_EOF
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=${API_PORT}
API_SERVER_KEY=${API_SERVER_KEY}
ENV_EOF
chmod 600 "${HOME}/.hermes/.env"

# 9. MODEL CONFIG
echo "[9/12] Configuring Hermes..."
cat > "${HOME}/.hermes/config.yaml" <<CONF_EOF
model:
  provider: custom
  default: ${OLLAMA_MODEL}
  base_url: ${OLLAMA_URL}/v1
  context_length: 65536
fallback_providers:
  - provider: openrouter
    model: ${OPENROUTER_MODEL}
terminal:
  backend: local
  timeout: 180
CONF_EOF
chmod 600 "${HOME}/.hermes/config.yaml"

# 10. FIREWALL
echo "[10/12] Configuring firewall..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow "${API_PORT}/tcp"
sudo ufw --force enable
echo; sudo ufw status; echo

# 11. SYSTEMD SERVICE
echo "[11/12] Creating Hermes gateway service..."
HERMES_USER="$(id -un)"
HERMES_HOME="${HOME}"
HERMES_BIN="${HOME}/.local/bin/hermes"
cat > /tmp/hermes-gateway.service <<'SVC_EOF'
[Unit]
Description=Hermes Agent Gateway
After=network-online.target ollama.service
Wants=network-online.target
Requires=ollama.service

[Service]
Type=simple
User=${HERMES_USER}
Group=${HERMES_USER}
WorkingDirectory=${HERMES_HOME}
Environment=HOME=${HERMES_HOME}
Environment=PATH=${HERMES_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin
EnvironmentFile=${HERMES_HOME}/.hermes/.env
ExecStart=${HERMES_BIN} gateway run
Restart=always
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
SVC_EOF
sudo cp /tmp/hermes-gateway.service /etc/systemd/system/hermes-gateway.service
sudo systemctl daemon-reload
sudo systemctl enable hermes-gateway
sudo systemctl restart hermes-gateway

# 12. VERIFY
echo "[12/12] Waiting for Hermes..."
echo "Waiting for Hermes gateway..."
for i in $(seq 1 12); do
    if systemctl is-active --quiet hermes-gateway; then
        echo "Hermes gateway is active."; break
    fi
    if [[ "$i" -eq 12 ]]; then
        echo "WARNING: Hermes gateway not active yet. Check logs: sudo journalctl -u hermes-gateway -n 30"
    fi
    sleep 5
done

echo; echo "Hermes service:"
sudo systemctl status hermes-gateway --no-pager || true

echo; echo "Checking API..."
LOCAL_HEALTH="$(curl -sS --max-time 15 -H "Authorization: Bearer ${API_SERVER_KEY}"
  "http://127.0.0.1:${API_PORT}/health" || true)"
echo "${LOCAL_HEALTH}"
PUBLIC_IP="$(curl -4 -sS --max-time 10 https://api.ipify.org || echo "YOUR_PUBLIC_IP")"

# SAVE CONNECTION INFO
cat > "${HOME}/hermes-connection.txt" <<DATA_EOF
Hermes Agent Hybrid
===================

Public API:
http://${PUBLIC_IP}:${API_PORT}/v1

Health:
http://${PUBLIC_IP}:${API_PORT}/health

Models:
http://${PUBLIC_IP}:${API_PORT}/v1/models

Chat:
http://${PUBLIC_IP}:${API_PORT}/v1/chat/completions

API Key:
${API_SERVER_KEY}

Local Ollama:
http://127.0.0.1:11434

Local Model:
${OLLAMA_MODEL}

OpenRouter Fallback:
${OPENROUTER_MODEL}
DATA_EOF
chmod 600 "${HOME}/hermes-connection.txt"

echo; echo
echo "============================================================"
echo " INSTALLATION FINISHED"
echo "============================================================"
echo
echo "PUBLIC API"
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
echo "API KEY: ${API_SERVER_KEY}"
echo
echo "Saved to: ${HOME}/hermes-connection.txt"
echo
echo "============================================================"
echo " IMPORTANT"
echo "============================================================"
echo
echo "Cloud firewall/security group must allow:"
echo '  TCP 22   - SSH'
echo '  TCP ${API_PORT} - Hermes API'
echo
echo "Do NOT expose:"
echo '  TCP 11434 - Ollama'
echo
echo "============================================================"

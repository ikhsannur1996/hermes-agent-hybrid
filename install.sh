#!/usr/bin/env bash
set -Eeuo pipefail

# HERMES AGENT HYBRID — One-shot Install
# You will be prompted for your OpenRouter API key.
# Get one at: https://openrouter.ai/keys

OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3:8b}"
OPENROUTER_MODEL="${OPENROUTER_MODEL:-qwen/qwen3-coder}"
API_PORT="${API_PORT:-8642}"
HERMES_INTERNAL_PORT="${HERMES_INTERNAL_PORT:-8643}"
OLLAMA_URL="http://127.0.0.1:11434"
BASIC_AUTH_USER="${BASIC_AUTH_USER:-admin}"
BASIC_AUTH_PASS="${BASIC_AUTH_PASS:-admin}"

# Prompt for API key
echo; echo "===== Hermes Hybrid Installation ====="
echo; echo "Get your free OpenRouter API key at: https://openrouter.ai/keys"
echo -n "Enter your OpenRouter API key (sk-or-v1-...): "
read -r OPENROUTER_API_KEY
echo; if [[ -z "$OPENROUTER_API_KEY" ]]; then echo "ERROR: No API key provided."; exit 1; fi

API_SERVER_KEY="$(openssl rand -hex 32)"
echo; echo "===== Configuration ====="; echo
echo "Local model         : ${OLLAMA_MODEL}"
echo "OpenRouter model    : ${OPENROUTER_MODEL}"
echo "Public API port     : ${API_PORT} (Nginx + basic auth)"
echo "Browser login       : ${BASIC_AUTH_USER} / ${BASIC_AUTH_PASS}"
echo "Generated API key   : ${API_SERVER_KEY}"
echo

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
    if [[ "$i" -eq 12 ]]; then echo "ERROR: Ollama failed to start."; sudo systemctl status ollama --no-pager || true; exit 1; fi
    sleep 5
done

# 3. TEST OLLAMA
echo "[3/12] Testing Ollama..."
if ! curl -fsS "${OLLAMA_URL}/api/tags" >/dev/null; then echo "ERROR: Ollama not responding."; sudo systemctl status ollama --no-pager || true; exit 1; fi
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
mkdir -p "${HOME}/.hermes"; chmod 700 "${HOME}/.hermes"

# 8. SECRETS
echo "[8/12] Writing secrets..."
cat > "${HOME}/.hermes/.env" <<ENV_EOF
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=${HERMES_INTERNAL_PORT}
API_SERVER_KEY=${API_SERVER_KEY}
ENV_EOF
chmod 600 "${HOME}/.hermes/.env"

# DETECT PUBLIC IP
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
cat > "${HOME}/hermes-connection.txt" <<DATA_EOF
Hermes Agent Hybrid
===================

Public API: http://${PUBLIC_IP}:${API_PORT}/v1
Health: http://${PUBLIC_IP}:${API_PORT}/health
Models: http://${PUBLIC_IP}:${API_PORT}/v1/models
Chat: http://${PUBLIC_IP}:${API_PORT}/v1/chat/completions

API Key: ${API_SERVER_KEY}
Browser Login: ${BASIC_AUTH_USER} / ${BASIC_AUTH_PASS}

Local Ollama: http://127.0.0.1:11434
Local Model: ${OLLAMA_MODEL}
OpenRouter Fallback: ${OPENROUTER_MODEL}
DATA_EOF
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
echo "API KEY: ${API_SERVER_KEY}"
echo
echo "BROWSER LOGIN: ${BASIC_AUTH_USER} / ${BASIC_AUTH_PASS}"
echo
echo "Saved to: ${HOME}/hermes-connection.txt"
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
echo '  TCP ${HERMES_INTERNAL_PORT} - Hermes internal (localhost only)'
echo
echo "Browser login: ${BASIC_AUTH_USER} / ${BASIC_AUTH_PASS}"
echo
echo "============================================================"

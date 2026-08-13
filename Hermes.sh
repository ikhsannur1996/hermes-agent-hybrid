cat > /tmp/install-hermes-hybrid.sh <<'SCRIPT'
#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# HERMES AGENT HYBRID TEST SERVER
#
# VM:
#   4 vCPU
#   16 GB RAM
#   Ubuntu 24.04
#   No GPU
#
# PUBLIC API:
#   http://PUBLIC_IP:8642/v1
#
# AI:
#   PRIMARY  -> Ollama
#   FALLBACK -> OpenRouter
#
# ============================================================

# =========================
# USER CONFIGURATION
# =========================

OPENROUTER_API_KEY="sk-or-REPLACE_ME"

# Local model.
#
# IMPORTANT:
# Hermes requires >=64K context.
# Set Ollama context explicitly below.
#
# If this model is unavailable on your Ollama version,
# replace it with another tool-capable model.
OLLAMA_MODEL="qwen3:8b"

# OpenRouter fallback.
#
# Change to any current 64K+ model available in your
# OpenRouter account/catalog.
OPENROUTER_MODEL="qwen/qwen3-coder"

API_PORT="8642"

# Ollama remains localhost-only.
OLLAMA_URL="http://127.0.0.1:11434"

# =========================
# VALIDATION
# =========================

if [[ "$OPENROUTER_API_KEY" == "sk-or-REPLACE_ME" ]]; then
    echo
    echo "ERROR:"
    echo "Set OPENROUTER_API_KEY in this script first."
    echo
    exit 1
fi

# =========================
# GENERATE API KEY
# =========================

API_SERVER_KEY="$(openssl rand -hex 32)"

echo
echo "============================================================"
echo " Hermes Hybrid Installation"
echo "============================================================"
echo
echo "Local model      : ${OLLAMA_MODEL}"
echo "OpenRouter model : ${OPENROUTER_MODEL}"
echo "API port         : ${API_PORT}"
echo
echo "Generated API key:"
echo "${API_SERVER_KEY}"
echo

# ============================================================
# 1. SYSTEM PACKAGES
# ============================================================

echo "[1/12] Updating system..."

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
    ufw

# ============================================================
# 2. INSTALL OLLAMA
# ============================================================

echo "[2/12] Installing Ollama..."

if ! command -v ollama >/dev/null 2>&1; then
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "Ollama already installed."
fi

sudo systemctl enable ollama
sudo systemctl restart ollama

sleep 8

# ============================================================
# 3. ENSURE OLLAMA IS RESPONDING
# ============================================================

echo "[3/12] Testing Ollama..."

if ! curl -fsS "${OLLAMA_URL}/api/tags" >/dev/null; then
    echo "ERROR: Ollama is not responding."
    sudo systemctl status ollama --no-pager || true
    exit 1
fi

echo "Ollama is running."

# ============================================================
# 4. PULL LOCAL MODEL
# ============================================================

echo "[4/12] Pulling local model..."

ollama pull "${OLLAMA_MODEL}"

echo
echo "Installed models:"
ollama list
echo

# ============================================================
# 5. CONFIGURE OLLAMA CONTEXT
# ============================================================

echo "[5/12] Configuring Ollama context..."

# Hermes requires at least 64K context.
#
# OLLAMA_NUM_CTX is applied to the Ollama service.
# 65536 can consume significant RAM on CPU.
#
# On 16 GB RAM this is intentionally conservative:
# one model, low concurrency.
#
sudo mkdir -p /etc/systemd/system/ollama.service.d

sudo tee /etc/systemd/system/ollama.service.d/hermes.conf >/dev/null <<EOF
[Service]
Environment="OLLAMA_NUM_CTX=65536"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama

sleep 8

# ============================================================
# 6. INSTALL HERMES
# ============================================================

echo "[6/12] Installing Hermes Agent..."

curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

export PATH="${HOME}/.local/bin:${PATH}"

if ! command -v hermes >/dev/null 2>&1; then
    echo "ERROR: Hermes installation failed."
    exit 1
fi

echo
hermes --version
echo

# ============================================================
# 7. CREATE HERMES DIRECTORIES
# ============================================================

echo "[7/12] Creating Hermes configuration..."

mkdir -p "${HOME}/.hermes"

chmod 700 "${HOME}/.hermes"

# ============================================================
# 8. SECRETS
# ============================================================

echo "[8/12] Writing secrets..."

cat > "${HOME}/.hermes/.env" <<EOF
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}

API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=${API_PORT}
API_SERVER_KEY=${API_SERVER_KEY}
EOF

chmod 600 "${HOME}/.hermes/.env"

# ============================================================
# 9. HERMES MODEL CONFIG
# ============================================================

echo "[9/12] Configuring Hermes..."

cat > "${HOME}/.hermes/config.yaml" <<EOF
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
EOF

chmod 600 "${HOME}/.hermes/config.yaml"

# ============================================================
# 10. FIREWALL
# ============================================================

echo "[10/12] Configuring firewall..."

sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH
sudo ufw allow 22/tcp

# Hermes API
sudo ufw allow "${API_PORT}/tcp"

sudo ufw --force enable

echo
sudo ufw status
echo

# ============================================================
# 11. SYSTEMD SERVICE
# ============================================================

echo "[11/12] Creating Hermes gateway service..."

HERMES_USER="$(id -un)"
HERMES_HOME="${HOME}"
HERMES_BIN="${HOME}/.local/bin/hermes"

sudo tee /etc/systemd/system/hermes-gateway.service >/dev/null <<EOF
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
EOF

sudo systemctl daemon-reload
sudo systemctl enable hermes-gateway
sudo systemctl restart hermes-gateway

# ============================================================
# 12. VERIFY
# ============================================================

echo "[12/12] Waiting for Hermes..."

sleep 12

echo
echo "Hermes service:"
sudo systemctl status hermes-gateway --no-pager || true

echo
echo "Checking API..."

LOCAL_HEALTH="$(curl -sS \
    --max-time 15 \
    -H "Authorization: Bearer ${API_SERVER_KEY}" \
    "http://127.0.0.1:${API_PORT}/health" || true)"

echo "${LOCAL_HEALTH}"

# ============================================================
# PUBLIC IP
# ============================================================

PUBLIC_IP="$(curl -4 -sS --max-time 10 https://api.ipify.org || echo "YOUR_PUBLIC_IP")"

# ============================================================
# SAVE CONNECTION INFO
# ============================================================

cat > "${HOME}/hermes-connection.txt" <<EOF
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
${OLLAMA_URL}:11434

Local Model:
${OLLAMA_MODEL}

OpenRouter Fallback:
${OPENROUTER_MODEL}
EOF

chmod 600 "${HOME}/hermes-connection.txt"

# ============================================================
# FINAL OUTPUT
# ============================================================

echo
echo
echo "============================================================"
echo " INSTALLATION FINISHED"
echo "============================================================"
echo
echo "PUBLIC API"
echo
echo "  http://${PUBLIC_IP}:${API_PORT}/v1"
echo
echo "HEALTH"
echo
echo "  http://${PUBLIC_IP}:${API_PORT}/health"
echo
echo "MODELS"
echo
echo "  http://${PUBLIC_IP}:${API_PORT}/v1/models"
echo
echo "CHAT"
echo
echo "  http://${PUBLIC_IP}:${API_PORT}/v1/chat/completions"
echo
echo "API KEY"
echo
echo "  ${API_SERVER_KEY}"
echo
echo "Saved to:"
echo
echo "  ${HOME}/hermes-connection.txt"
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
  -d '{
    "model": "hermes-agent",
    "messages": [
      {
        "role": "user",
        "content": "Hello. Tell me which AI agent you are."
      }
    ]
  }'
EOF

echo
echo
echo "============================================================"
echo " IMPORTANT"
echo "============================================================"
echo
echo "Cloud firewall/security group must allow:"
echo
echo "  TCP 22   - SSH"
echo "  TCP ${API_PORT} - Hermes API"
echo
echo "Do NOT expose:"
echo
echo "  TCP 11434 - Ollama"
echo
echo "============================================================"
SCRIPT

chmod +x /tmp/install-hermes-hybrid.sh
/tmp/install-hermes-hybrid.sh
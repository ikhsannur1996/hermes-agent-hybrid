# Hermes Agent Hybrid — Installation Tutorial

This tutorial walks through a complete installation of the Hermes Agent hybrid server.

## Prerequisites

### 1. Hardware / Cloud VM

- **4 vCPU**
- **16 GB RAM**
- **Ubuntu 24.04** (or recent Debian-based distro)
- No GPU required

### 2. OpenRouter API Key

1. Go to [openrouter.ai](https://openrouter.ai)
2. Sign up / log in
3. Go to **Keys** → **Create Key**
4. Copy the key — it looks like `sk-or-v1-...`

### 3. Firewall / Security Group

Before installing, open these ports in your cloud provider's firewall:

| Port | Purpose |
|------|---------|
| `22`  | SSH (usually already open) |
| `8642` | Hermes API |

> ⚠️ **Do NOT** expose port `11434` (Ollama) publicly.

## Step 1 — Configure the Script

Open `Hermes.sh` and edit the **USER CONFIGURATION** block at the top:

```bash
# =========================
# USER CONFIGURATION
# =========================

OPENROUTER_API_KEY="sk-or-v1-your-key-here"

OLLAMA_MODEL="qwen3:8b"
OPENROUTER_MODEL="qwen/qwen3-coder"
API_PORT="8642"
```

| Setting | Default | What it does |
|---------|---------|--------------|
| `OPENROUTER_API_KEY` | *(required)* | Cloud fallback key |
| `OLLAMA_MODEL` | `qwen3:8b` | Local model (needs 64K+ context) |
| `OPENROUTER_MODEL` | `qwen/qwen3-coder` | Fallback model on OpenRouter |
| `API_PORT` | `8642` | Public API port |
| `OLLAMA_URL` | `http://127.0.0.1:11434` | Local Ollama address — leave as-is |

> The script aborts with an error if `OPENROUTER_API_KEY` is still `sk-or-REPLACE_ME`.

## Step 2 — Run the Installer

```bash
bash Hermes.sh
```

The script runs **12 steps**:

| Step | What happens |
|------|--------------|
| 1 | Installs system packages (curl, git, python3, ufw, etc.) |
| 2 | Installs and starts **Ollama** |
| 3 | Verifies Ollama is responding on `127.0.0.1:11434` |
| 4 | Pulls the local model (e.g. `qwen3:8b`, several GB — be patient) |
| 5 | Configures Ollama for 64K context |
| 6 | Installs the **Hermes Agent** binary |
| 7 | Creates `~/.hermes/` config directory |
| 8 | Writes API secrets to `~/.hermes/.env` |
| 9 | Writes Hermes model config to `~/.hermes/config.yaml` |
| 10 | Configures UFW firewall |
| 11 | Creates the `hermes-gateway` systemd service |
| 12 | Verifies the service and prints connection info |

## Step 3 — What You Should See

When it finishes, the script prints:

```
============================================================
 INSTALLATION FINISHED
============================================================

PUBLIC API
  http://YOUR_SERVER_IP:8642/v1

HEALTH
  http://YOUR_SERVER_IP:8642/health

MODELS
  http://YOUR_SERVER_IP:8642/v1/models

CHAT
  http://YOUR_SERVER_IP:8642/v1/chat/completions

API KEY
  <random 64-char hex key>
```

All connection details are also saved to **`~/hermes-connection.txt`** (permissions `600` — readable only by you).

> 🔑 **Write down the API key now.** It's generated randomly at install time and stored in `~/hermes-connection.txt` and `~/.hermes/.env`.

## Step 4 — Test the Installation

```bash
curl -X POST \
  http://YOUR_SERVER_IP:8642/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "hermes-agent",
    "messages": [
      {"role": "user", "content": "Hello. Tell me which AI agent you are."}
    ]
  }'
```

You should get a JSON response with the model's reply.

## Post-Install Verification

```bash
# Service status
sudo systemctl status hermes-gateway

# Health check
curl -H "Authorization: Bearer YOUR_API_KEY" http://127.0.0.1:8642/health

# List available models
curl -H "Authorization: Bearer YOUR_API_KEY" http://127.0.0.1:8642/v1/models

# Check the local model
ollama list

# Firewall rules
sudo ufw status
```

## Troubleshooting Quick Tips

| Problem | Check |
|---------|-------|
| Service won't start | `journalctl -u hermes-gateway -n 50 --no-pager` |
| Slow first reply | The 8B model takes time to load into RAM the first time |
| Model not found | `ollama list`; run `ollama pull qwen3:8b` manually |
| OpenRouter errors | Verify your key at openrouter.ai → Keys |

## Next Tutorial

→ [03-configuration.md](03-configuration.md)
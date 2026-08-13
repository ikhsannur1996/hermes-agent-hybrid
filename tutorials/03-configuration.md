# Hermes Agent Hybrid — Configuration Reference

This tutorial explains every configuration file created by the install script.  
**You don't need to edit any of these for normal use** — all defaults work out of the box.

## Configuration Files

| File | Purpose | Permissions |
|------|---------|-------------|
| `~/.hermes/.env` | Secrets (API keys, server settings) | `600` |
| `~/.hermes/config.yaml` | Model routing, provider settings | `600` |

---

## 1. Secrets — `~/.hermes/.env`

```bash
OPENROUTER_API_KEY=sk-or-v1-xxxxxxxxx

API_SERVER_ENABLED=true
API_SERVER_HOST=127.0.0.1
API_SERVER_PORT=8643
API_SERVER_KEY=abc123...def
```

### Variables

| Variable | Description |
|----------|-------------|
| `OPENROUTER_API_KEY` | Your OpenRouter key for cloud fallback |
| `API_SERVER_ENABLED` | Must be `true` to run the gateway |
| `API_SERVER_HOST` | `127.0.0.1` — localhost only (Nginx proxies public traffic) |
| `API_SERVER_PORT` | `8643` — internal port (Hermes itself, not exposed) |
| `API_SERVER_KEY` | Bearer token for API authentication (auto-generated) |

> **Changing the API key:** Generate a new one with `openssl rand -hex 32` and update this file, then `sudo systemctl restart hermes-gateway`.

---

## 2. Model Config — `~/.hermes/config.yaml`

```yaml
model:
  provider: custom
  default: qwen3:8b
  base_url: http://127.0.0.1:11434/v1
  context_length: 65536

fallback_providers:
  - provider: openrouter
    model: qwen/qwen3-coder

terminal:
  backend: local
  timeout: 180
```

| Field | Default | Description |
|-------|---------|-------------|
| `provider` | `custom` | OpenAI-compatible endpoint |
| `default` | `qwen3:8b` | The model name as Ollama knows it |
| `base_url` | `http://127.0.0.1:11434/v1` | Ollama's OpenAI-compatible endpoint |
| `context_length` | `65536` | Maximum context in tokens (64K) |

**Changing the local model:**
```bash
ollama pull <new-model>
sed -i 's/default: qwen3:8b/default: <new-model>/' ~/.hermes/config.yaml
sudo systemctl restart hermes-gateway
```

---

## 3. Nginx Reverse Proxy

Nginx is installed on port `8642` with HTTP basic auth:

| Setting | Value |
|---------|-------|
| Public port | `8642` |
| Internal proxy | `127.0.0.1:8643` |
| Basic auth user | `admin` |
| Basic auth pass | `admin` |
| Config file | `/etc/nginx/sites-available/hermes` |
| Password file | `/etc/nginx/.htpasswd` |

Both `Authorization: Bearer` (API key) **and** basic auth (browser login) work — Nginx passes the API key header through to Hermes.

---

## 4. Ollama Service Config

The installer creates a systemd drop-in at `/etc/systemd/system/ollama.service.d/hermes.conf`:

```ini
[Service]
Environment="OLLAMA_NUM_CTX=65536"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
```

> **On a machine with more RAM:** Increase `OLLAMA_MAX_LOADED_MODELS` and `OLLAMA_NUM_PARALLEL` for higher throughput.

---

## 5. Systemd Service — `hermes-gateway`

```bash
# View logs
sudo journalctl -u hermes-gateway -f

# Restart
sudo systemctl restart hermes-gateway

# Stop
sudo systemctl stop hermes-gateway

# Disable auto-start
sudo systemctl disable hermes-gateway
```

Boot order: `Ollama → Hermes Gateway → Nginx`

---

## Next Tutorial

→ [04-api-usage.md](04-api-usage.md)
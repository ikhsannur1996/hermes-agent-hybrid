# Hermes Agent Hybrid — Configuration Tutorial

This tutorial explains every configuration file and setting in the Hermes hybrid deployment.

## Configuration Files

There are two files to care about:

| File | Purpose | Permissions |
|------|---------|-------------|
| `~/.hermes/.env` | Secrets (API keys, server settings) | `600` |
| `~/.hermes/config.yaml` | Model routing, provider settings | `600` |

---

## 1. Secrets — `~/.hermes/.env`

```bash
OPENROUTER_API_KEY=sk-or-v1-xxxxxxxxx

API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
API_SERVER_KEY=abc123...def
```

### Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENROUTER_API_KEY` | ✅ | Your OpenRouter key for cloud fallback |
| `API_SERVER_ENABLED` | — | Must be `true` to run the gateway |
| `API_SERVER_HOST` | — | `0.0.0.0` binds to all interfaces |
| `API_SERVER_PORT` | — | Public API port (default `8642`) |
| `API_SERVER_KEY` | ✅ | Bearer token for API authentication |

> **Changing the API key:** Generate a new one with `openssl rand -hex 32` and update this file, then restart the service.

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

### Top-level Keys

| Key | Description |
|-----|-------------|
| `model` | Primary model (local via Ollama) |
| `fallback_providers` | Ordered list of fallback providers |
| `terminal` | Terminal backend settings |

### `model` Section

| Field | Default | Description |
|-------|---------|-------------|
| `provider` | `custom` | Use `custom` for any OpenAI-compatible endpoint |
| `default` | `qwen3:8b` | The model name as Ollama knows it |
| `base_url` | `http://127.0.0.1:11434/v1` | Ollama's OpenAI-compatible endpoint |
| `context_length` | `65536` | Maximum context in tokens (64K) |

**Changing the local model:**
1. Pull the new model: `ollama pull <new-model>`
2. Update `default` in `config.yaml`
3. Restart: `sudo systemctl restart hermes-gateway`

### `fallback_providers` Section

An ordered list. Hermes tries the **primary model** first. If it fails (timeout, error, overload), Hermes moves down the fallback list.

```yaml
fallback_providers:
  - provider: openrouter
    model: qwen/qwen3-coder
  - provider: openrouter     # second fallback
    model: openai/gpt-4o
```

| Field | Description |
|-------|-------------|
| `provider` | Must be `openrouter` (for this setup) |
| `model` | Any model available on your OpenRouter account |

### `terminal` Section

Controls the **terminal backend** used when invoking Hermes interactively.

| Field | Default | Description |
|-------|---------|-------------|
| `backend` | `local` | Terminal emulation (`local` uses your system terminal) |
| `timeout` | `180` | Seconds before a tool call times out |

---

## 3. Ollama Service Config

The installer creates a systemd drop-in at `/etc/systemd/system/ollama.service.d/hermes.conf`:

```ini
[Service]
Environment="OLLAMA_NUM_CTX=65536"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=1"
```

| Variable | Value | Why |
|----------|-------|-----|
| `OLLAMA_NUM_CTX` | `65536` | 64K context required by Hermes |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | Keep only one model in memory (RAM constraint) |
| `OLLAMA_NUM_PARALLEL` | `1` | One request at a time (RAM constraint) |

> **On a machine with more RAM:** Increase `OLLAMA_MAX_LOADED_MODELS` and `OLLAMA_NUM_PARALLEL` for higher throughput.

---

## 4. Systemd Service — `hermes-gateway`

The gateway is managed as a systemd service:

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

---

## Example: Switching to a Different Local Model

```bash
# 1. Pull a new model
ollama pull llama3.2:3b

# 2. Edit config
sed -i 's/default: qwen3:8b/default: llama3.2:3b/' ~/.hermes/config.yaml

# 3. Restart
sudo systemctl restart hermes-gateway

# 4. Verify
curl -H "Authorization: Bearer $(grep API_SERVER_KEY ~/.hermes/.env | cut -d= -f2)" \
  http://127.0.0.1:8642/v1/models
```

## Next Tutorial

→ [04-api-usage.md](04-api-usage.md)
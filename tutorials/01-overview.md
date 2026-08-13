# Hermes Agent Hybrid — Overview

## What Is Hermes?

Hermes is an AI agent gateway from **Nous Research** that provides an OpenAI-compatible API endpoint. This hybrid deployment runs a local model via **Ollama** (for speed, privacy, offline capability) and falls back to **OpenRouter** (for complex tasks the local model can't handle).

## Architecture

```
┌───────────────┐      ┌───────────────────┐      ┌──────────────┐
│  Your App /   │ ──►  │  Hermes Gateway   │ ──►  │  Ollama      │
│  curl / http  │       │  (port 8642)      │       │  (local)     │
│  client       │ ◄──  │  OpenAI-compat    │ ◄──  │  qwen3:8b    │
└───────────────┘      └───────┬───────────┘      └──────────────┘
                               │
                               │ fallback
                               ▼
                        ┌───────────────┐
                        │  OpenRouter   │
                        │  (cloud)      │
                        └───────────────┘
```

## Key Features

| Feature | Detail |
|---------|--------|
| **Local-first** | Primary model runs on your own hardware |
| **Cloud fallback** | OpenRouter kicks in when local model is overloaded or can't handle the task |
| **OpenAI-compatible** | Use any OpenAI SDK/client — just point the base URL at your server |
| **64K context** | Configured for long conversations and large code files |
| **Systemd service** | Auto-starts on boot, auto-restarts on crash |
| **API key auth** | Secure bearer-token authentication |

## Specs

The deployment is designed for a **4 vCPU / 16 GB RAM** Ubuntu 24.04 VM with no GPU.

| Component | Role | Default Model |
|-----------|------|---------------|
| **Ollama** | Local inference engine | `qwen3:8b` |
| **Hermes Gateway** | Routing, API server, fallback logic | `hermes-agent` (virtual model) |
| **OpenRouter** | Cloud fallback | `qwen/qwen3-coder` |

## Quick Start

```bash
# 1. Edit the install script — set your OpenRouter API key
# 2. Run it
bash Hermes.sh

# 3. Test it
curl -X POST http://YOUR_SERVER_IP:8642/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "hermes-agent",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Next Tutorial

→ [02-Installation.md](02-installation.md)
# Hermes Agent Hybrid — Overview

## What Is Hermes?

Hermes is an AI agent gateway from **Nous Research** that provides an OpenAI-compatible API endpoint. This hybrid deployment runs a local model via **Ollama** (for speed, privacy, offline capability) and falls back to **OpenRouter** (for complex tasks the local model can't handle).

All settings use sensible defaults — you just provide your OpenRouter API key and run.

## Architecture

```
 Browser ──► Nginx (port 8642) ──► Hermes Gateway (port 8643) ──► Ollama (local)
                 │                                                       │
           login prompt:                                           fallback
           admin / admin                                               │
                                                                 OpenRouter
```

## Key Features

| Feature | Detail |
|---------|--------|
| **Local-first** | Primary model runs on your own hardware |
| **Cloud fallback** | OpenRouter kicks in when local model is overloaded or can't handle the task |
| **OpenAI-compatible** | Use any OpenAI SDK/client — just point the base URL at your server |
| **Nginx reverse proxy** | Port 8642 with basic auth (admin/admin) for browser access |
| **64K context** | Configured for long conversations and large code files |
| **Systemd service** | Auto-starts on boot, auto-restarts on crash |
| **API key auth** | Secure bearer-token authentication |
| **Zero-config install** | Hardcoded defaults — just set `OPENROUTER_API_KEY` and run |

## Specs

The deployment is designed for a **4 vCPU / 16 GB RAM** Ubuntu 24.04 VM with no GPU.

| Component | Role | Default Model |
|-----------|------|---------------|
| **Ollama** | Local inference engine | `qwen3:8b` |
| **Hermes Gateway** | Routing, API server, fallback logic | `hermes-agent` (virtual model) |
| **Nginx** | Reverse proxy with basic auth | `admin` / `admin` |
| **OpenRouter** | Cloud fallback | `qwen/qwen3-coder` |

## Quick Start

```bash
OPENROUTER_API_KEY="sk-or-v1-xxx" bash Hermes.sh
```

That's it. One command, fully automated, all defaults accepted.

Then test:

```bash
curl -X POST http://YOUR_SERVER_IP:8642/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"Hello!"}]}'
```

## Next Tutorial

→ [02-Installation.md](02-installation.md)
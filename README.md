# Hermes Agent Hybrid

A self-hosted AI agent gateway with **local-first inference** via Ollama, **automatic cloud fallback** via OpenRouter, and **Nginx reverse proxy** with basic auth for browser access.

## Quick Start

```bash
# Fully automated — just set your API key and run
OPENROUTER_API_KEY="sk-or-v1-xxx" bash Hermes.sh
```

> **That's it.** One command, no prompts, no editing files. The script installs everything — Ollama, Hermes Agent, 64K context, Nginx reverse proxy with basic auth (admin/admin), firewall, and systemd service. Full install takes 5-15 minutes.

### Test your server

```bash
curl -X POST http://YOUR_SERVER_IP:8642/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"Hello!"}]}'
```

> Or open `http://YOUR_SERVER_IP:8642` in a browser — you'll see a login prompt (admin / admin), then the API response.

> The API key is printed at the end of the install and saved to `~/hermes-connection.txt`.

## Specs

| Component | Role | Default |
|-----------|------|---------|
| Local model | Fast, private, offline-capable | `qwen3:8b` via Ollama |
| Cloud fallback | Handles complex tasks | `qwen/qwen3-coder` via OpenRouter |
| API gateway | OpenAI-compatible endpoint | Port `8643` (internal), `8642` (public via Nginx) |
| Browser auth | Basic auth login prompt | `admin` / `admin` |
| VM target | 4 vCPU, 16 GB RAM, Ubuntu 24.04 | No GPU needed |

## Tutorials

| # | Topic | File |
|---|-------|------|
| 1 | Architecture & features | [tutorials/01-overview.md](tutorials/01-overview.md) |
| 2 | Step-by-step installation | [tutorials/02-installation.md](tutorials/02-installation.md) |
| 3 | Configuration reference | [tutorials/03-configuration.md](tutorials/03-configuration.md) |
| 4 | API usage (curl, Python, Node.js) | [tutorials/04-api-usage.md](tutorials/04-api-usage.md) |
| 5 | Monitoring, tuning, security | [tutorials/05-advanced.md](tutorials/05-advanced.md) |
| 6 | Troubleshooting guide | [tutorials/06-troubleshooting.md](tutorials/06-troubleshooting.md) |

## What's Inside

```
Hermes.sh              — Install script (set OPENROUTER_API_KEY env var and run)
install.sh             — One-shot installer for piping from URL
deploy.sh              — Deploy via SSH to remote server
tutorials/
├── 01-overview.md     — What Hermes is and how it works
├── 02-installation.md — Complete install walkthrough
├── 03-configuration.md— All config files explained
├── 04-api-usage.md    — API examples with curl, Python, Node.js
├── 05-advanced.md     — Performance, security, monitoring
└── 06-troubleshooting.md — Common issues & fixes
README.md              — This file
```

## Architecture

```
Browser ──► Nginx (port 8642) ──► Hermes Gateway (port 8643) ──► Ollama (local)
                │                                                       │
          login prompt:                                           fallback
          admin / admin                                               │
                                                                OpenRouter
```

## Requirements

- Ubuntu 24.04 (or recent Debian-based distro)
- 4 vCPU, 16 GB RAM
- [OpenRouter API key](https://openrouter.ai/keys) — pass via `OPENROUTER_API_KEY` env var
- Ports `22` (SSH) and `8642` (Hermes via Nginx) open in firewall

## Important Notes

- **Do not expose** port `11434` (Ollama) or port `8643` (Hermes internal) publicly
- The script generates a random API key on each install — save it from the output
- First request is slow (model loads into RAM)
- `qwen3:8b` requires ~4.7 GB download on first install
- Browser access to `http://YOUR_IP:8642` requires login: **admin** / **admin**
- API client access (`curl`, SDKs) uses `Authorization: Bearer <API_KEY>` — both auth methods work

## License

This project is an installation wrapper for [Hermes Agent](https://hermes-agent.nousresearch.com) by Nous Research and [Ollama](https://ollama.com).
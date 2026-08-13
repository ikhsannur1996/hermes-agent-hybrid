# Hermes Agent Hybrid

A self-hosted AI agent gateway with **local-first inference** via Ollama and **automatic cloud fallback** via OpenRouter.

## Quick Start

```bash
# 1. Edit Hermes.sh — set your OpenRouter API key
OPENROUTER_API_KEY="sk-or-v1-your-key-here"

# 2. Run
bash Hermes.sh

# 3. Test
curl -X POST http://YOUR_SERVER_IP:8642/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"Hello!"}]}'
```

## Specs

| Component | Role | Default |
|-----------|------|---------|
| Local model | Fast, private, offline-capable | `qwen3:8b` via Ollama |
| Cloud fallback | Handles complex tasks | `qwen/qwen3-coder` via OpenRouter |
| API gateway | OpenAI-compatible endpoint | Port `8642`, bearer auth |
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
Hermes.sh              — Full install script (self-contained)
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
Your App ──► Hermes Gateway ──► Ollama (local)
                   │
                   └──► OpenRouter (fallback)
```

## Requirements

- Ubuntu 24.04 (or recent Debian-based distro)
- 4 vCPU, 16 GB RAM
- [OpenRouter API key](https://openrouter.ai/keys)
- Ports `22` (SSH) and `8642` (Hermes) open in firewall

## Important Notes

- **Do not expose port 11434** (Ollama) publicly
- The script generates a random API key on each install — save it from the output
- First request is slow (model loads into RAM)
- `qwen3:8b` requires ~4.7 GB download on first install

## License

This project is an installation wrapper for [Hermes Agent](https://hermes-agent.nousresearch.com) by Nous Research and [Ollama](https://ollama.com).
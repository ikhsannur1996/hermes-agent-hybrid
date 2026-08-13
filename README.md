# Hermes Agent Hybrid

A self-hosted OpenAI-compatible AI API with **local-first inference** via Ollama and **automatic cloud fallback** via OpenRouter, behind **Nginx basic auth** (admin/admin) for browser access.

## Quick Start

```bash
# One command — fully automated
OPENROUTER_API_KEY="sk-or-v1-xxx" bash Hermes.sh
```

> **That's it.** No prompts, no editing files. The script installs Ollama (local model), the Hermes API proxy (OpenRouter fallback), Nginx basic auth, and systemd auto-start. Takes 5-15 minutes.

---

## How to Run (3 Ways)

### Option 1: Clone the repo and run

```bash
git clone https://github.com/ikhsannur1996/hermes-agent-hybrid.git
cd hermes-agent-hybrid

# Copy to your Linux server:
scp -r . root@YOUR_SERVER_IP:~/hermes-agent-hybrid
ssh root@YOUR_SERVER_IP
cd ~/hermes-agent-hybrid
OPENROUTER_API_KEY="sk-or-v1-xxx" bash Hermes.sh
```

### Option 2: Pipe from URL (no clone needed)

```bash
curl -fsSL https://raw.githubusercontent.com/ikhsannur1996/hermes-agent-hybrid/main/install.sh | OPENROUTER_API_KEY="sk-or-v1-xxx" bash
```

### Option 3: Deploy via SSH (from your local machine)

```bash
git clone https://github.com/ikhsannur1996/hermes-agent-hybrid.git
cd hermes-agent-hybrid
OPENROUTER_API_KEY="sk-or-v1-xxx" ./deploy.sh root@YOUR_SERVER_IP
```

---

## After Installation

### Test the API

```bash
curl -X POST http://YOUR_SERVER_IP:8642/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"Hello!"}]}'
```

### Access in Browser

Open `http://YOUR_SERVER_IP:8642` — login prompt:

```
Username: admin
Password: admin
```

---

## Architecture

```
App/Browser --> Nginx (8642, admin/admin)
                  |
                  v
        hermes-api proxy (8643, Python)
                  |
        +---------+----------+
        |                    |
        v                    v
     Ollama              OpenRouter
     (qwen3:8b)          (fallback)
     local-first
```

## Components

| Component | Role | Default |
|-----------|------|---------|
| Ollama | Local model server | `qwen3:8b`, port 11434 |
| hermes-api proxy | OpenAI-compatible API + fallback logic | port 8643 (localhost) |
| Nginx | Reverse proxy + basic auth | port 8642 (public) |
| OpenRouter | Cloud fallback | `qwen/qwen3-coder` |
| Browser login | Basic auth | `admin` / `admin` |

## Files

```
Hermes.sh              - Main installer (embeds everything)
install.sh             - Same as Hermes.sh inner script (for piping from URL)
hermes-proxy.py        - The OpenAI-compatible proxy (local + fallback)
deploy.sh              - SSH deploy helper
tutorials/             - Documentation
```

## Requirements

- Ubuntu 24.04 (or recent Debian-based)
- 4 vCPU, 16 GB RAM
- [OpenRouter API key](https://openrouter.ai/keys)
- Ports 22 (SSH) and 8642 (Hermes) open in firewall

## Notes

- **Do NOT expose** port 11434 (Ollama) or 8643 (proxy) publicly
- Browser login: `admin` / `admin`
- API clients use any bearer token (Nginx auth is the gate)
- Hermes API proxy replaces the Nous Hermes Agent gateway, which does not expose an OpenAI-compatible endpoint

# Hermes Agent Hybrid — Troubleshooting Guide

## Quick Diagnostic Commands

```bash
# 1. Is the gateway running?
sudo systemctl status hermes-gateway

# 2. Is Ollama running?
sudo systemctl status ollama

# 3. Is the local model loaded?
ollama list

# 4. Is the API reachable?
curl -H "Authorization: Bearer $(grep API_SERVER_KEY ~/.hermes/.env | cut -d= -f2)" \
  http://127.0.0.1:8642/health

# 5. What does the log say?
sudo journalctl -u hermes-gateway -n 50 --no-pager
```

---

## Common Issues

### 1. Service Won't Start

**Symptom:** `sudo systemctl start hermes-gateway` fails.

**Check:**
```bash
sudo journalctl -u hermes-gateway -n 50 --no-pager
```

**Common causes:**
- Missing `/home/user/.hermes/.env` — re-run the installer
- Ollama not running — `sudo systemctl restart ollama`
- Wrong permissions — `chmod 600 ~/.hermes/.env ~/.hermes/config.yaml`

**Fix:**
```bash
sudo systemctl daemon-reload
sudo systemctl restart hermes-gateway
```

---

### 2. "401 Unauthorized" on API Calls

**Symptom:** Every request returns `401`.

**Check:**
```bash
cat ~/.hermes/.env | grep API_SERVER_KEY
```

**Fix:** Make sure you're using the exact key from the file. If regenerating:
```bash
NEW_KEY=$(openssl rand -hex 32)
sed -i "s/API_SERVER_KEY=.*/API_SERVER_KEY=${NEW_KEY}/" ~/.hermes/.env
sudo systemctl restart hermes-gateway
echo "New key: $NEW_KEY"
```

---

### 3. Slow Responses / Timeouts

**Symptom:** Requests take 30+ seconds or time out.

**Causes & fixes:**

| Cause | Fix |
|-------|-----|
| Model loading into RAM (first request) | Wait — subsequent requests are faster |
| Not enough RAM | Check `free -h`; close other processes |
| 64K context consuming resources | Reduce `OLLAMA_NUM_CTX` in the drop-in config |
| High load | Check `htop` for CPU/memory usage |

---

### 4. "Model Not Found" Error

**Symptom:** API returns 500 with "model not found".

**Check:**
```bash
ollama list
cat ~/.hermes/config.yaml | grep default
```

**Fix:**
```bash
# Pull the model if missing
ollama pull qwen3:8b

# Or update the config to match an existing model
# Edit ~/.hermes/config.yaml, then:
sudo systemctl restart hermes-gateway
```

---

### 5. OpenRouter Fallback Not Working

**Symptom:** Requests fail when the local model is down (no fallback).

**Check:**
```bash
# Verify the API key is set
cat ~/.hermes/.env | grep OPENROUTER_API_KEY

# Verify the model name is correct
cat ~/.hermes/config.yaml | grep -A2 fallback
```

**Fix:**
```bash
# Test the key directly
curl https://openrouter.ai/api/v1/auth/key \
  -H "Authorization: Bearer sk-or-v1-xxx"

# Check your OpenRouter account has access to the model
# Go to https://openrouter.ai/models
```

---

### 6. Ollama Won't Start

**Symptom:** `sudo systemctl status ollama` shows "failed".

**Check:**
```bash
sudo journalctl -u ollama -n 50 --no-pager
```

**Common fixes:**
```bash
# Restart
sudo systemctl restart ollama

# Reinstall
curl -fsSL https://ollama.com/install.sh | sh

# Check logs for CUDA/GPU errors (no GPU is fine)
```

---

### 7. Firewall Blocking Access

**Symptom:** Can't connect from outside the server.

**Check:**
```bash
sudo ufw status
```

**Fix:**
```bash
# Allow Hermes API port
sudo ufw allow 8642/tcp

# Also check your cloud provider's security group / firewall
```

---

### 8. Port Already in Use

**Symptom:** Gateway fails to start — port 8642 is in use.

**Check:**
```bash
sudo lsof -i :8642
```

**Fix:**
```bash
# Kill the process using the port, or change API_PORT in ~/.hermes/.env
sudo systemctl restart hermes-gateway
```

---

## Logs Reference

### Gateway Logs

```bash
# All logs
sudo journalctl -u hermes-gateway --no-pager

# Errors only
sudo journalctl -u hermes-gateway -p err --no-pager

# Live tail
sudo journalctl -u hermes-gateway -f
```

### Ollama Logs

```bash
# All logs
sudo journalctl -u ollama --no-pager

# Live tail
sudo journalctl -u ollama -f
```

---

## Recovery Procedures

### Full Reinstall

```bash
# 1. Stop services
sudo systemctl stop hermes-gateway ollama

# 2. Remove config
rm -rf ~/.hermes

# 3. Re-run the installer
cd ~/Hermes\ -\ Projcet
bash Hermes.sh
```

### Preserve Data During Reinstall

```bash
# 1. Backup config
cp -r ~/.hermes ~/.hermes.backup

# 2. Reinstall
bash Hermes.sh

# 3. Restore key and config
cp ~/.hermes.backup/.env ~/.hermes/.env
cp ~/.hermes.backup/config.yaml ~/.hermes/config.yaml
sudo systemctl restart hermes-gateway
```

---

## Still Stuck?

1. Check the logs: `sudo journalctl -u hermes-gateway -n 100 --no-pager`
2. Check Ollama: `ollama list` and `curl http://127.0.0.1:11434/api/tags`
3. Check the install script's steps in `Hermes.sh`
4. Visit Nous Research Hermes documentation at [hermes-agent.nousresearch.com](https://hermes-agent.nousresearch.com)

---

## Tutorial Index

| Tutorial | Description |
|----------|-------------|
| [01-overview.md](01-overview.md) | Architecture and features |
| [02-installation.md](02-installation.md) | Step-by-step install guide |
| [03-configuration.md](03-configuration.md) | All config files explained |
| [04-api-usage.md](04-api-usage.md) | API examples (curl, Python, Node.js) |
| [05-advanced.md](05-advanced.md) | Monitoring, tuning, security |
| [06-troubleshooting.md](06-troubleshooting.md) | Problems and fixes |
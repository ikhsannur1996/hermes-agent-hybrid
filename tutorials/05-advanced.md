# Hermes Agent Hybrid — Advanced Tutorials

## 1. Monitoring with journalctl

The gateway logs everything to systemd journal:

```bash
# Follow live logs
sudo journalctl -u hermes-gateway -f

# Last 100 lines
sudo journalctl -u hermes-gateway -n 100 --no-pager

# Filter by time
sudo journalctl -u hermes-gateway --since "5 minutes ago"

# Export to file
sudo journalctl -u hermes-gateway --no-pager > hermes-debug.log
```

### Key Log Patterns

| Log message | What it means |
|-------------|---------------|
| `routing to primary` | Using local Ollama model |
| `fallback to openrouter` | Local model failed or timed out |
| `unauthorized request` | Wrong/missing API key |
| `model <name> not found` | Ollama doesn't have the configured model |

---

## 2. Adding Multiple Fallback Providers

You can chain multiple fallback models in `~/.hermes/config.yaml`:

```yaml
fallback_providers:
  - provider: openrouter
    model: qwen/qwen3-coder
  - provider: openrouter
    model: meta-llama/llama-3.3-70b-instruct
  - provider: openrouter
    model: openai/gpt-4o
```

Hermes tries the **primary** (local) model first, then each fallback in order.

---

## 3. Performance Tuning

### Ollama Context Window

The installer sets 64K context. On a machine with more RAM you can increase it:

```bash
sudo tee /etc/systemd/system/ollama.service.d/hermes.conf >/dev/null <<EOF
[Service]
Environment="OLLAMA_NUM_CTX=131072"    # 128K
Environment="OLLAMA_MAX_LOADED_MODELS=2"
Environment="OLLAMA_NUM_PARALLEL=2"
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama
```

### RAM Budget Guide

| Context | Est. RAM for 8B model | Notes |
|---------|----------------------|-------|
| 32K     | ~8 GB | Minimal |
| 64K     | ~10 GB | Default |
| 128K    | ~14 GB | Needs 16 GB+ |

---

## 4. Updating the Local Model

```bash
# Pull the latest version of the current model
ollama pull qwen3:8b

# Restart the gateway
sudo systemctl restart hermes-gateway
```

---

## 5. Updating Hermes Agent

```bash
# Re-run the Hermes install script
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

# Restart the gateway
sudo systemctl restart hermes-gateway

# Check version
hermes --version
```

---

## 6. Backing Up Configuration

```bash
# Backup the config directory
tar czf ~/hermes-config-backup-$(date +%Y%m%d).tar.gz \
  ~/.hermes/.env \
  ~/.hermes/config.yaml

# Restore
tar xzf hermes-config-backup-*.tar.gz -C ~/
sudo systemctl restart hermes-gateway
```

---

## 7. Running Multiple Local Models

You can pull additional models in Ollama and switch between them by changing the config:

```bash
# Pull a small model for quick tasks
ollama pull llama3.2:3b

# Pull a larger model for complex tasks
ollama pull qwen3:8b
```

To switch, edit `~/.hermes/config.yaml` and change `default:` to the other model name, then restart.

---

## 8. Using the CLI Directly

Hermes also has a CLI mode for interactive use:

```bash
# Interactive terminal
hermes

# Single prompt
hermes -p "Explain the CAP theorem"
```

---

## 9. Prometheus / Grafana (Optional)

You can add a simple health-check loop for monitoring:

```bash
#!/bin/bash
# Save as ~/hermes-monitor.sh
API_KEY=$(grep API_SERVER_KEY ~/.hermes/.env | cut -d= -f2)
URL="http://127.0.0.1:8642/health"

while true; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $API_KEY" "$URL")
  echo "$(date +%Y-%m-%dT%H:%M:%S) $STATUS"
  sleep 60
done
```

---

## 10. Security Hardening

### Restrict API Access by IP

Use UFW to limit access to specific IPs:

```bash
# Deny Hermes API from all
sudo ufw deny 8642/tcp

# Allow only your IP
sudo ufw allow from YOUR_IP to any port 8642/tcp

sudo ufw reload
```

### Rotate API Key

```bash
# Generate a new key
NEW_KEY=$(openssl rand -hex 32)

# Update the env file
sed -i "s/API_SERVER_KEY=.*/API_SERVER_KEY=${NEW_KEY}/" ~/.hermes/.env

# Restart the service
sudo systemctl restart hermes-gateway
```

### Certificate (HTTPS) with Reverse Proxy

For production, put Hermes behind Nginx with Let's Encrypt:

```nginx
# /etc/nginx/sites-available/hermes
server {
    listen 443 ssl;
    server_name hermes.example.com;

    ssl_certificate /etc/letsencrypt/live/hermes.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/hermes.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8642;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Authorization $http_authorization;
        proxy_pass_header Authorization;
    }
}
```

---

## Next Tutorial

→ [06-troubleshooting.md](06-troubleshooting.md)
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# HERMES REMOTE DEPLOY
# ============================================================
# Copies the repo to a remote Linux server via SSH and runs
# the fully automated install.
#
# Usage:
#   OPENROUTER_API_KEY="sk-or-v1-xxx" ./deploy.sh user@server-ip
# ============================================================

if [[ $# -lt 1 ]]; then
    echo "Usage: OPENROUTER_API_KEY=\"sk-or-v1-xxx\" $0 user@server-ip"
    echo
    echo "Examples:"
    echo "  OPENROUTER_API_KEY=\"sk-or-v1-xxx\" $0 root@192.168.1.100"
    echo "  OPENROUTER_API_KEY=\"sk-or-v1-xxx\" $0 ubuntu@my-vm.example.com"
    echo
    echo "Requirements:"
    echo "  - SSH access to the remote server (password or key)"
    echo "  - OpenRouter API key (set via env var)"
    exit 1
fi

REMOTE="$1"
REPO_DIR="${2:-hermes-agent-hybrid}"

echo "============================================================"
echo " Hermes Remote Deploy"
echo "============================================================"
echo
echo "Target    : ${REMOTE}"
echo "Directory : ~/${REPO_DIR}"
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Copying files to ${REMOTE}..."
echo

ssh "${REMOTE}" "mkdir -p ~/${REPO_DIR}"
scp -r "${SCRIPT_DIR}/." "${REMOTE}:~/${REPO_DIR}/"

echo
echo "Files copied. Running install on remote server..."
echo

ssh -t "${REMOTE}" "cd ~/${REPO_DIR} && OPENROUTER_API_KEY=\"${OPENROUTER_API_KEY}\" bash Hermes.sh"

echo
echo "============================================================"
echo " Done"
echo "============================================================"
echo
echo "To SSH into the server:"
echo "  ssh ${REMOTE}"
echo
echo "To check the service:"
echo "  ssh ${REMOTE} 'sudo systemctl status hermes-gateway'"
echo
echo "Connection info saved on server at:"
echo "  ~/hermes-connection.txt"
echo
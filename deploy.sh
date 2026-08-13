#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# HERMES REMOTE DEPLOY
# ============================================================
# Copies the Hermes Agent Hybrid repo to a remote Linux server
# via SSH and runs the install script.
#
# Usage:
#   ./deploy.sh user@server-ip
#
# Example:
#   ./deploy.sh root@192.168.1.100
# ============================================================

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 user@server-ip"
    echo
    echo "Examples:"
    echo "  $0 root@192.168.1.100"
    echo "  $0 ubuntu@my-vm.example.com"
    echo
    echo "Before running:"
    echo "  1. Copy .env.example to .env and set your OpenRouter API key"
    echo "  2. Make sure SSH access is set up (password or key)"
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

# Check for .env file
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
    echo "WARNING: No .env file found."
    echo "The install will use defaults from Hermes.sh."
    echo "Press Enter to continue, or Ctrl+C to abort and create .env first."
    read -r
else
    echo "Found .env — will be deployed with the repo."
fi

echo
echo "Copying files to ${REMOTE}..."
echo

# Create remote directory and copy everything except .git
ssh "${REMOTE}" "mkdir -p ~/${REPO_DIR}"
scp -r "${SCRIPT_DIR}/." "${REMOTE}:~/${REPO_DIR}/"

echo
echo "Files copied. Running install on remote server..."
echo

# Run the install script remotely
ssh -t "${REMOTE}" "cd ~/${REPO_DIR} && bash Hermes.sh"

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
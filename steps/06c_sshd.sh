#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 06c: Enabling OpenSSH server (sshd)"

ensure_package openssh-server

if systemctl is-enabled --quiet sshd && systemctl is-active --quiet sshd; then
  log_debug "sshd already enabled and running"
else
  log_info "Enabling and starting sshd"
  run_sudo systemctl enable sshd --now
fi

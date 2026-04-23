#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 16: Installing Yazi terminal file manager via COPR"

# --- Ensure COPR repository is enabled ---
if ! dnf repolist --enabled | grep -q lihaohong-yazi; then
  log_info "Enabling Yazi COPR repository (lihaohong/yazi)"
  sudo dnf -y copr enable lihaohong/yazi
else
  log_debug "Yazi COPR repository already enabled"
fi

# --- Install Yazi package ---
ensure_package "yazi"

log_info "Yazi installation complete"

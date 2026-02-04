#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Installing vpn-slice (system-wide)"

# --- Ensure python3-pip is installed ---
ensure_package python3-pip

# --- Install vpn-slice system-wide via pip ---
# This is needed so vpn-slice works when openconnect is run with sudo
if ! sudo pip show vpn-slice &>/dev/null; then
  log_info "Installing vpn-slice system-wide using pip"
  sudo pip install --break-system-packages vpn-slice
else
  log_info "vpn-slice is already installed system-wide, upgrading..."
  sudo pip install --break-system-packages --upgrade vpn-slice
fi

# Verify installation
if sudo which vpn-slice &>/dev/null; then
  log_info "vpn-slice installed successfully at: $(sudo which vpn-slice)"
else
  log_error "vpn-slice installation failed"
  exit 1
fi

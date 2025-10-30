#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Installing vpn-slice"

# --- Ensure python3-pip is installed ---
ensure_package python3-pip

# --- Install vpn-slice via pip ---
if ! python3 -m pip show vpn-slice &>/dev/null; then
  log_info "Installing vpn-slice using pip"
  python3 -m pip install --upgrade pip
  python3 -m pip install vpn-slice
else
  log_info "vpn-slice is already installed, upgrading..."
  python3 -m pip install --upgrade vpn-slice
fi

log_info "vpn-slice installed successfully."

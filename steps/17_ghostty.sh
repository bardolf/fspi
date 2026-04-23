#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 17: Installing Ghostty terminal emulator via COPR"

# --- Ensure COPR repository is enabled ---
if ! dnf repolist --enabled | grep -q scottames-ghostty; then
  log_info "Enabling Ghostty COPR repository (scottames/ghostty)"
  sudo dnf -y copr enable scottames/ghostty
else
  log_debug "Ghostty COPR repository already enabled"
fi

# --- Install Ghostty package ---
ensure_package "ghostty"

log_info "Ghostty installation complete"

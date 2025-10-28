#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 11: Installing Mise CLI via COPR"

# --- Ensure COPR repository is enabled ---
if ! dnf repolist --enabled | grep -q jdxcode-mise; then
  log_info "Enabling Mise COPR repository"
  sudo dnf -y copr enable jdxcode/mise
else
  log_debug "Mise COPR repository already enabled"
fi

# --- Install Mise package ---
if ! command -v mise &>/dev/null; then
  log_info "Installing Mise CLI via DNF"
  sudo dnf -y install mise
else
  log_debug "Mise CLI already installed at $(command -v mise)"
fi

# --- Add shims directory to PATH for current session ---
SHIMS_DIR="$HOME/.local/share/mise/shims"
if [[ ":$PATH:" != *":$SHIMS_DIR:"* ]]; then
  export PATH="$SHIMS_DIR:$PATH"
  log_info "Added Mise shims directory to PATH for current session"
fi

# --- Add shims directory to shell rc for future sessions ---
SHELL_RC="$HOME/.bashrc"
if ! grep -q "$SHIMS_DIR" "$SHELL_RC"; then
  log_info "Adding Mise shims directory to $SHELL_RC"
  echo "" >>"$SHELL_RC"
  echo "# Added by Mise installation script" >>"$SHELL_RC"
  echo "export PATH=\"$SHIMS_DIR:\$PATH\"" >>"$SHELL_RC"
fi

# --- Activate Mise automatically (non-interactive) ---
log_info "Activating Mise (non-interactive)"
mise activate --non-interactive || log_warn "Mise activation failed. Check documentation at https://mise.jdx.dev"

log_info "Mise installation and activation complete"

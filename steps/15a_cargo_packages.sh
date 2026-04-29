#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 15a: Installing cargo packages"

# --- Cargo packages to install ---
CARGO_PACKAGES=(
  resvg
)

# --- Ensure Rust toolchain is available ---
ensure_package rust
ensure_package cargo

# --- Make sure ~/.cargo/bin is on PATH for this session ---
CARGO_BIN="$HOME/.cargo/bin"
if [[ ":$PATH:" != *":$CARGO_BIN:"* ]]; then
  export PATH="$CARGO_BIN:$PATH"
fi

# --- Install each package idempotently ---
for pkg in "${CARGO_PACKAGES[@]}"; do
  if cargo install --list 2>/dev/null | grep -q "^${pkg} v"; then
    log_debug "Cargo package already installed: $pkg"
  else
    log_info "Installing cargo package: $pkg"
    cargo install "$pkg"
  fi
done

log_info "Cargo packages installation complete"

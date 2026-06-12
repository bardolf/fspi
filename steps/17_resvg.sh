#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# resvg is no longer packaged for Fedora ("No match for argument: resvg").
# yazi's "svg" previewer (config/yazi/yazi.toml) shells out to the resvg CLI,
# so build it from crates.io into ~/.local/bin (already on PATH via zshrc).

if check_command resvg; then
  log_debug "resvg already installed, skipping"
else
  log_info "Installing resvg via cargo (no Fedora package available)"
  ensure_package cargo
  cargo install resvg --root "$HOME/.local"
  log_info "resvg installed to $HOME/.local/bin"
fi

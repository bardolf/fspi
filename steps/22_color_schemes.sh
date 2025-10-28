#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 22_: Import iTerm2 color schemes for WezTerm"

# --- Target directory for color schemes ---
COLOR_SCHEMES_DIR="$HOME/.local/share/iTerm2-color-schemes"

# --- Clone or update repository ---
if [[ ! -d "$COLOR_SCHEMES_DIR/.git" ]]; then
  log_info "Cloning iTerm2-Color-Schemes repository into $COLOR_SCHEMES_DIR"
  git clone --depth 1 https://github.com/mbadolato/iTerm2-Color-Schemes.git "$COLOR_SCHEMES_DIR"
else
  log_info "iTerm2-Color-Schemes already exists, pulling latest changes..."
  git -C "$COLOR_SCHEMES_DIR" pull --ff-only || log_warn "Failed to pull latest changes"
fi

log_info "Color schemes are ready at $COLOR_SCHEMES_DIR"

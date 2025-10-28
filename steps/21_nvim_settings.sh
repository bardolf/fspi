#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 21: Applying permanent Neovim settings"

# --- Functions (copied from step 20_) ---
config_step_copy() {
  local origin="$1"
  local target="$2"

  if [[ ! -f "$origin" ]]; then
    log_warn "Source file $origin does not exist, skipping..."
    return
  fi

  if [[ ! -f "$target" ]]; then
    log_info "Copying $origin → $target (target did not exist)"
    mkdir -p "$(dirname "$target")"
    cp "$origin" "$target"
    return
  fi

  if cmp -s "$origin" "$target"; then
    log_info "Target $target is up to date, skipping."
    return
  fi

  local timestamp
  timestamp=$(date +%Y%m%d%H%M%S)
  local backup="${target}.${timestamp}"
  log_info "Backing up $target → $backup and copying $origin → $target"
  cp "$target" "$backup"
  cp "$origin" "$target"
}

# --- Prepare Neovim user settings file ---

TEMP_DIR=$(mktemp -d)
CUSTOM_SETTINGS_SRC="$TEMP_DIR/settings.lua"

cat >"$CUSTOM_SETTINGS_SRC" <<'EOF'
-- Custom user settings for Neovim

-- Show all Markdown syntax (no hidden characters)
vim.opt.conceallevel = 0

-- Enable system clipboard integration
vim.opt.clipboard = "unnamedplus"

-- Optional: Better line wrapping
vim.opt.linebreak = true

-- Optional: Always show sign column
vim.opt.signcolumn = "yes"

vim.opt.mouse = "r"  -- allow mouse for scrolling and resizing only
EOF

# --- Copy configuration to Neovim directory ---

NVIM_USER_DIR="$HOME/.config/nvim/lua/config"
NVIM_SETTINGS_DEST="$NVIM_USER_DIR/options.lua"

log_info "Installing custom Neovim settings..."
mkdir -p "$NVIM_USER_DIR"

config_step_copy "$CUSTOM_SETTINGS_SRC" "$NVIM_SETTINGS_DEST"

# Clean up temp files
rm -rf "$TEMP_DIR"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 20: Installing and managing configuration files"

# -------------------------
# Functions for copying configs
# -------------------------

# Copy a single file with logic: target exists/does not exist, same/different content
config_step_copy() {
  local origin="$1"
  local target="$2"

  # Source file does not exist
  if [[ ! -f "$origin" ]]; then
    log_warn "Source file $origin does not exist, skipping..."
    return
  fi

  # Target file does not exist → just copy
  if [[ ! -f "$target" ]]; then
    log_info "Copying $origin → $target (target did not exist)"
    mkdir -p "$(dirname "$target")"
    cp "$origin" "$target"
    return
  fi

  # Target exists → compare content
  if cmp -s "$origin" "$target"; then
    log_info "Target $target is up to date, skipping."
    return
  fi

  # Target exists and is different → backup with timestamp and copy
  local timestamp
  timestamp=$(date +%Y%m%d%H%M%S)
  local backup="${target}.${timestamp}"
  log_info "Backing up $target → $backup and copying $origin → $target"
  cp "$target" "$backup"
  cp "$origin" "$target"
}

# Copy multiple files at once (source/target pairs)
config_step_copy_collection() {
  local args=("$@")
  local total=${#args[@]}
  if ((total % 2 != 0)); then
    log_error "config_step_copy_collection requires pairs of source and target paths"
    return 1
  fi

  for ((i = 0; i < total; i += 2)); do
    config_step_copy "${args[i]}" "${args[i + 1]}"
  done
}

# -------------------------
# Call the step for specific configs
# -------------------------

log_info "Installing configuration files (foot, sway, waybar, etc.)"

config_step_copy_collection \
  "$SCRIPT_DIR/config/waybar/config.jsonc" "$HOME/.config/waybar/config.jsonc" \
  "$SCRIPT_DIR/config/waybar/style.css" "$HOME/.config/waybar/style.css" \
  "$SCRIPT_DIR/config/foot/foot.ini" "$HOME/.config/foot/foot.ini" \
  "$SCRIPT_DIR/config/git/gitconfig" "$HOME/.gitconfig" \
  "$SCRIPT_DIR/config/mise/config.toml" "$HOME/.config/mise/config.toml" \
  "$SCRIPT_DIR/config/wezterm/wezterm.lua" "$HOME/.config/wezterm/wezterm.lua" \
  "$SCRIPT_DIR/config/dunst/dunstrc" "$HOME/.config/dunst/dunstrc" \
  "$SCRIPT_DIR/config/nvim/lua/config/options.lua" "$HOME/.config/nvim/lua/config/options.lua" \
  "$SCRIPT_DIR/config/nvim/lua/plugins/disabled.lua" "$HOME/.config/nvim/lua/plugins/disabled.lua" \
  "$SCRIPT_DIR/config/nvim/lua/plugins/blink.lua" "$HOME/.config/nvim/lua/plugins/blink.lua" \
  "$SCRIPT_DIR/config/satty/config.toml" "$HOME/.config/satty/config.toml" \
  "$SCRIPT_DIR/config/sway/config" "$HOME/.config/sway/config" \
  "$SCRIPT_DIR/config/sway/config.d/10-displays.conf" "$HOME/.config/sway/config.d/10-displays.conf" \
  "$SCRIPT_DIR/config/sway/config.d/50-rules-browser.conf" "$HOME/.config/sway/config.d/50-rules-browser.conf" \
  "$SCRIPT_DIR/config/sway/config.d/60-bindings-screenshot.conf" "$HOME/.config/sway/config.d/60-bindings-screenshot.conf" \
  "$SCRIPT_DIR/config/opencode/plugins/notification.js" "$HOME/.config/opencode/plugins/notification.js"

# Calcurse caldav config contains user credentials after setup — only deploy the
# template if the user doesn't have one yet, to never overwrite their secrets.
CALDAV_CONFIG="$HOME/.config/calcurse/caldav/config"
if [[ ! -f "$CALDAV_CONFIG" ]]; then
  config_step_copy "$SCRIPT_DIR/config/calcurse/caldav/config" "$CALDAV_CONFIG"
else
  log_info "Calcurse caldav config already exists, skipping (won't overwrite credentials)."
fi

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

log_info "Installing Foot and Sway configuration files"

config_step_copy_collection \
  "$SCRIPT_DIR/config/foot/foot.ini" "$HOME/.config/foot/foot.ini" \
  "$SCRIPT_DIR/config/wezterm/wezterm.lua" "$HOME/.config/wezterm/wezterm.lua" \
  "$SCRIPT_DIR/config/sway/config" "$HOME/.config/sway/config"

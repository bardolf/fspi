#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 30: Installing user scripts to ~/scripts"

SRC_DIR="$SCRIPT_DIR/scripts"
TARGET_DIR="$HOME/scripts"

mkdir -p "$TARGET_DIR"

# --- Function to copy with backup logic ---
copy_with_backup() {
  local src="$1"
  local dest="$2"

  if [[ ! -f "$dest" ]]; then
    log_info "Copying $src → $dest"
    cp "$src" "$dest"
  elif ! cmp -s "$src" "$dest"; then
    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)
    log_info "Backing up existing $dest → ${dest}.${timestamp}"
    mv "$dest" "${dest}.${timestamp}"
    log_info "Copying $src → $dest"
    cp "$src" "$dest"
  else
    log_debug "$dest is identical to source, skipping"
  fi
}

# --- Copy all top-level scripts ---
for script_file in "$SRC_DIR"/*; do
  [[ -f "$script_file" ]] || continue
  target_file="$TARGET_DIR/$(basename "$script_file")"
  copy_with_backup "$script_file" "$target_file"
done

# --- Copy scripts from subdirectories (e.g., waybar/) ---
# Excludes directories starting with underscore (like _in_progress/)
for subdir in "$SRC_DIR"/*/; do
  [[ -d "$subdir" ]] || continue
  subdir_name=$(basename "$subdir")
  
  # Skip directories starting with underscore
  [[ "$subdir_name" == _* ]] && continue
  
  # Create target subdirectory
  target_subdir="$TARGET_DIR/$subdir_name"
  mkdir -p "$target_subdir"
  
  log_info "Installing scripts from $subdir_name/"
  
  for script_file in "$subdir"*; do
    [[ -f "$script_file" ]] || continue
    target_file="$target_subdir/$(basename "$script_file")"
    copy_with_backup "$script_file" "$target_file"
  done
done

log_info "All user scripts installed to $TARGET_DIR"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 26: Configure rclone bisync for Dropbox"

ensure_command rclone

# --- Local Dropbox folder ---
DROPBOX_DIR="$HOME/Dropbox"
if [[ -d "$DROPBOX_DIR" ]]; then
  log_debug "Local Dropbox folder already exists: $DROPBOX_DIR"
else
  log_info "Creating local Dropbox folder: $DROPBOX_DIR"
  mkdir -p "$DROPBOX_DIR"
fi

# --- Deploy systemd user units ---
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"
ensure_file_copy "$SCRIPT_DIR/files/systemd/rclone-dropbox.service" "$SYSTEMD_USER_DIR/rclone-dropbox.service"
ensure_file_copy "$SCRIPT_DIR/files/systemd/rclone-dropbox.timer"   "$SYSTEMD_USER_DIR/rclone-dropbox.timer"

systemctl --user daemon-reload

if systemctl --user is-enabled --quiet rclone-dropbox.timer; then
  log_debug "rclone-dropbox.timer already enabled"
else
  log_info "Enabling rclone-dropbox.timer"
  systemctl --user enable --now rclone-dropbox.timer
fi

# --- First-run setup hints ---
if ! rclone listremotes 2>/dev/null | grep -q '^dropbox:$'; then
  log_warn "No 'dropbox' remote configured for rclone. Run interactively:"
  log_warn "  rclone config"
  log_warn "    n)ew -> name: dropbox -> storage: Dropbox -> blank client_id/secret"
  log_warn "    -> y)es auto-config (browser OAuth) -> n) no advanced/team"
elif [[ ! -d "$HOME/.cache/rclone/bisync" ]] || [[ -z "$(ls -A "$HOME/.cache/rclone/bisync" 2>/dev/null)" ]]; then
  log_warn "Bisync state not initialized. Run this once before the timer can succeed:"
  log_warn "  rclone bisync dropbox: $DROPBOX_DIR --resync --verbose"
  log_warn "(this seeds bisync's state; subsequent runs are incremental)"
else
  log_debug "rclone dropbox remote and bisync state present, no action needed"
fi

log_info "Step 26 complete"

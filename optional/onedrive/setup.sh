#!/usr/bin/env bash
set -euo pipefail

STEP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$STEP_DIR/../.." && pwd)
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

log_info "Optional: Configure rclone backup (~/Dropbox -> OneDrive)"

ensure_command rclone

# --- Sources: selected Dropbox subfolders must exist ---
for sub in Docs Chess; do
  src="$HOME/Dropbox/$sub"
  if [[ ! -d "$src" ]]; then
    log_warn "Source folder $src does not exist yet."
    log_warn "Run optional/dropbox/setup.sh first, or wait for Dropbox to mirror it."
  fi
done

# --- Deploy systemd user units ---
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"
ensure_file_copy "$STEP_DIR/files/systemd/rclone-onedrive-backup.service" "$SYSTEMD_USER_DIR/rclone-onedrive-backup.service"
ensure_file_copy "$STEP_DIR/files/systemd/rclone-onedrive-backup.timer"   "$SYSTEMD_USER_DIR/rclone-onedrive-backup.timer"

systemctl --user daemon-reload

if systemctl --user is-enabled --quiet rclone-onedrive-backup.timer; then
  log_debug "rclone-onedrive-backup.timer already enabled"
else
  log_info "Enabling rclone-onedrive-backup.timer"
  systemctl --user enable --now rclone-onedrive-backup.timer
fi

# --- First-run setup hints ---
if ! rclone listremotes 2>/dev/null | grep -q '^onedrive:$'; then
  log_warn "No 'onedrive' remote configured for rclone. Run interactively:"
  log_warn "  rclone config"
  log_warn "    n)ew -> name: onedrive -> storage: Microsoft OneDrive"
  log_warn "    -> blank client_id/secret -> y)es auto-config (browser OAuth)"
  log_warn "    -> select your account type (OneDrive Personal / Business / SharePoint)"
else
  log_debug "rclone onedrive remote configured, no action needed"
fi

log_info "Optional OneDrive backup setup complete"

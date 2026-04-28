#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 25: Configure vdirsyncer + khal for Google Calendar sync"

# --- Deploy vdirsyncer config (only if missing — preserves user's secrets on re-run) ---
VDIRSYNCER_CONFIG="$HOME/.config/vdirsyncer/config"
if [[ -f "$VDIRSYNCER_CONFIG" ]]; then
  log_debug "vdirsyncer config already exists, leaving untouched (would overwrite user's OAuth secrets)"
else
  log_info "Installing vdirsyncer config template at $VDIRSYNCER_CONFIG"
  mkdir -p "$(dirname "$VDIRSYNCER_CONFIG")"
  cp "$SCRIPT_DIR/config/vdirsyncer/config" "$VDIRSYNCER_CONFIG"
fi
chmod 600 "$VDIRSYNCER_CONFIG"

# --- Deploy khal config ---
ensure_file_copy "$SCRIPT_DIR/config/khal/config" "$HOME/.config/khal/config"

# --- Deploy systemd user units ---
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"
ensure_file_copy "$SCRIPT_DIR/files/systemd/vdirsyncer.service" "$SYSTEMD_USER_DIR/vdirsyncer.service"
ensure_file_copy "$SCRIPT_DIR/files/systemd/vdirsyncer.timer" "$SYSTEMD_USER_DIR/vdirsyncer.timer"

systemctl --user daemon-reload

if systemctl --user is-enabled --quiet vdirsyncer.timer; then
  log_debug "vdirsyncer.timer already enabled"
else
  log_info "Enabling vdirsyncer.timer"
  systemctl --user enable --now vdirsyncer.timer
fi

# --- First-run setup hints ---
TOKEN_FILE="$HOME/.config/vdirsyncer/google_calendar_token"
if grep -q "PASTE_GOOGLE_OAUTH" "$VDIRSYNCER_CONFIG" 2>/dev/null; then
  log_warn "vdirsyncer config still has placeholder OAuth credentials"
  log_warn "Edit $VDIRSYNCER_CONFIG and replace:"
  log_warn "  PASTE_GOOGLE_OAUTH_CLIENT_ID_HERE     -> your Google OAuth Client ID"
  log_warn "  PASTE_GOOGLE_OAUTH_CLIENT_SECRET_HERE -> your Google OAuth Client Secret"
  log_warn "(create them at https://console.cloud.google.com -> OAuth client ID -> Desktop app)"
elif [[ ! -f "$TOKEN_FILE" ]]; then
  log_warn "No OAuth token found at $TOKEN_FILE"
  log_warn "Run this once to authorize Google Calendar access:"
  log_warn "  vdirsyncer discover google_calendar"
  log_warn "(opens a browser; pick the Google account, allow calendar scope)"
else
  log_debug "OAuth token already present, no action needed"
fi

log_info "Step 25 complete"

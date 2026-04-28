#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 25: Configure vdirsyncer + khal for Google Calendar sync"

# --- Deploy vdirsyncer config (no secrets inside; safe to overwrite) ---
VDIRSYNCER_CONFIG="$HOME/.config/vdirsyncer/config"
ensure_file_copy "$SCRIPT_DIR/config/vdirsyncer/config" "$VDIRSYNCER_CONFIG"
chmod 600 "$VDIRSYNCER_CONFIG"

# --- Seed OAuth secret files (left untouched if they already exist) ---
CLIENT_ID_FILE="$HOME/.config/vdirsyncer/.client_id"
CLIENT_SECRET_FILE="$HOME/.config/vdirsyncer/.client_secret"

seed_secret_file() {
  local path="$1" placeholder="$2"
  if [[ -f "$path" ]]; then
    log_debug "Secret file already exists: $path"
  else
    log_info "Seeding placeholder secret file: $path"
    printf '%s\n' "$placeholder" > "$path"
    chmod 600 "$path"
  fi
}

seed_secret_file "$CLIENT_ID_FILE"     "PASTE_GOOGLE_OAUTH_CLIENT_ID_HERE"
seed_secret_file "$CLIENT_SECRET_FILE" "PASTE_GOOGLE_OAUTH_CLIENT_SECRET_HERE"

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
if grep -q "PASTE_GOOGLE_OAUTH" "$CLIENT_ID_FILE" "$CLIENT_SECRET_FILE" 2>/dev/null; then
  log_warn "OAuth credentials not yet populated. Replace placeholders with your Google OAuth values:"
  log_warn "  echo 'YOUR_CLIENT_ID'     > $CLIENT_ID_FILE"
  log_warn "  echo 'YOUR_CLIENT_SECRET' > $CLIENT_SECRET_FILE"
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

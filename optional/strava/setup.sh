#!/usr/bin/env bash
set -euo pipefail

STEP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$STEP_DIR/../.." && pwd)
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

log_info "Optional: Strava description cleanup timer"

ensure_command python3

# --- Sanity-check the cleanup script exists where the unit expects it ---
SCRIPT_PATH="$STEP_DIR/strava-cleanup.py"
if [[ ! -x "$SCRIPT_PATH" ]]; then
  log_error "Cleanup script missing or not executable: $SCRIPT_PATH"
  exit 1
fi

# --- Warn (don't fail) if credentials haven't been provisioned yet ---
CRED_PATH="$HOME/.config/strava/credentials.json"
if [[ ! -f "$CRED_PATH" ]]; then
  log_warn "No Strava credentials at $CRED_PATH"
  log_warn "  Timer will install but the service will fail until you complete"
  log_warn "  the one-time OAuth setup documented at the top of strava-cleanup.py"
fi

# --- Deploy systemd user units ---
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"
ensure_file_copy "$STEP_DIR/files/systemd/strava-cleanup.service" "$SYSTEMD_USER_DIR/strava-cleanup.service"
ensure_file_copy "$STEP_DIR/files/systemd/strava-cleanup.timer"   "$SYSTEMD_USER_DIR/strava-cleanup.timer"

systemctl --user daemon-reload

if systemctl --user is-enabled --quiet strava-cleanup.timer; then
  log_debug "strava-cleanup.timer already enabled"
else
  log_info "Enabling strava-cleanup.timer"
  systemctl --user enable --now strava-cleanup.timer
fi

log_info "Optional Strava cleanup timer setup complete"
log_info "  Inspect:  systemctl --user list-timers strava-cleanup.timer"
log_info "  Logs:     journalctl --user -u strava-cleanup.service"
log_info "  Trigger:  systemctl --user start strava-cleanup.service"

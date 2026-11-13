#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 33: Záloha genealogie na NAS (systemd user timer, každé 3 dny)"

# Skript samotný nasazuje step 30 (scripts/ → ~/scripts); tady jen jednotky a timer.
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"
ensure_file_copy "$SCRIPT_DIR/files/systemd/zaloha-genealogie.service" "$SYSTEMD_USER_DIR/zaloha-genealogie.service"
ensure_file_copy "$SCRIPT_DIR/files/systemd/zaloha-genealogie.timer" "$SYSTEMD_USER_DIR/zaloha-genealogie.timer"

systemctl --user daemon-reload

if systemctl --user is-enabled --quiet zaloha-genealogie.timer; then
  log_debug "zaloha-genealogie.timer already enabled"
else
  log_info "Enabling zaloha-genealogie.timer"
  systemctl --user enable --now zaloha-genealogie.timer
fi

log_info "Step 33 done (ruční spuštění: systemctl --user start zaloha-genealogie.service)"

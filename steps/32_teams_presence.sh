#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 32: Keep Teams presence in step with the screen lock"

# Both scripts land in ~/scripts via step 30, which is why this step sits after
# it. See scripts/teams-presence-watcher.sh for why presence is polled off the
# lock instead of hooked onto swayidle's timeout/resume events.

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
UNIT="teams-presence-watcher.service"
UNIT_SRC="$SCRIPT_DIR/files/systemd/$UNIT"
UNIT_DEST="$SYSTEMD_USER_DIR/$UNIT"

mkdir -p "$SYSTEMD_USER_DIR"

# ensure_file_copy does not report whether it changed anything, so compare
# first: a rewritten unit needs a restart to take effect, an unchanged one
# must not disturb a running watcher.
unit_changed=false
cmp -s "$UNIT_SRC" "$UNIT_DEST" 2>/dev/null || unit_changed=true

ensure_file_copy "$UNIT_SRC" "$UNIT_DEST"
systemctl --user daemon-reload

if systemctl --user is-enabled --quiet "$UNIT"; then
  log_debug "$UNIT already enabled"
else
  log_info "Enabling $UNIT"
  systemctl --user enable "$UNIT"
fi

# --now is safe here, unlike the audio guard in step 31: the watcher only reads
# pidof and writes one small file, so starting it mid-install has no effect
# beyond putting the presence state where it already belongs.
if ! systemctl --user is-active --quiet "$UNIT"; then
  log_info "Starting $UNIT"
  systemctl --user start "$UNIT"
elif $unit_changed; then
  log_info "Unit file changed, restarting $UNIT"
  systemctl --user restart "$UNIT"
else
  log_debug "$UNIT already running"
fi

log_info "Step 32 complete"

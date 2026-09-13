#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 31: Guard against ALSA cards that enumerate no profiles"

# The guard itself lands in ~/scripts via step 30, which is why this step sits
# after it. See scripts/audio-card-profile-guard.sh and audio-mic-setup.md for
# what it works around (a card with no active profile segfaults Steam).

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"
ensure_file_copy "$SCRIPT_DIR/files/systemd/audio-card-profile-guard.service" \
  "$SYSTEMD_USER_DIR/audio-card-profile-guard.service"

systemctl --user daemon-reload

# enable, never --now: the guard restarts wireplumber, and mid-install that
# would pull the audio stack out from under whatever is already connected. It
# is a login-time check, so the next login is soon enough.
if systemctl --user is-enabled --quiet audio-card-profile-guard.service; then
  log_debug "audio-card-profile-guard.service already enabled"
else
  log_info "Enabling audio-card-profile-guard.service"
  systemctl --user enable audio-card-profile-guard.service
fi

log_info "Step 31 complete"

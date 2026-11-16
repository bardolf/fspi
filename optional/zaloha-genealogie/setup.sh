#!/usr/bin/env bash
# optional: genealogy backup to NAS every 3 days (only where genealogy-* + Gramps Web live)
# installed: systemctl --user is-enabled --quiet zaloha-genealogie.timer
set -euo pipefail

STEP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$STEP_DIR/../.." && pwd)
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

log_info "Optional: Genealogy backup to NAS (systemd user timer, every 3 days)"

# Jen pro stroj, kde leží genealogy-trees + genealogy-tools a v dockeru běží
# Gramps Web — jinde záloha nemá co zálohovat. Unit spouští skript přímo
# z repa (stejně jako optional/strava), takže git pull se projeví hned.

ensure_command rsync
ensure_command ssh
ensure_command docker

# --- Skript musí ležet tam, kam míří ExecStart v unitě ---
SCRIPT_PATH="$STEP_DIR/zaloha-genealogie.sh"
if [[ ! -x "$SCRIPT_PATH" ]]; then
  log_error "Backup script missing or not executable: $SCRIPT_PATH"
  exit 1
fi
if [[ "$PROJECT_ROOT" != "$HOME/projects/fspi" ]]; then
  log_warn "Repo is at $PROJECT_ROOT, but the unit runs %h/projects/fspi/optional/zaloha-genealogie/zaloha-genealogie.sh"
  log_warn "  The service will fail until the repo lives at ~/projects/fspi"
fi

# --- Varovat (ne selhat), když tu zdroje zálohy nejsou ---
for dir in "$HOME/projects/genealogy-trees" "$HOME/projects/genealogy-tools"; do
  if [[ -d "$dir" ]]; then
    log_debug "Backup source present: $dir"
  else
    log_warn "Backup source not found: $dir — the backup will fail on this machine"
  fi
done

# --- Deploy systemd user units ---
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"
ensure_file_copy "$STEP_DIR/files/systemd/zaloha-genealogie.service" "$SYSTEMD_USER_DIR/zaloha-genealogie.service"
ensure_file_copy "$STEP_DIR/files/systemd/zaloha-genealogie.timer"   "$SYSTEMD_USER_DIR/zaloha-genealogie.timer"

systemctl --user daemon-reload

if systemctl --user is-enabled --quiet zaloha-genealogie.timer; then
  log_debug "zaloha-genealogie.timer already enabled"
else
  log_info "Enabling zaloha-genealogie.timer"
  systemctl --user enable --now zaloha-genealogie.timer
fi

log_info "Optional genealogy backup setup complete"
log_info "  Inspect:  systemctl --user list-timers zaloha-genealogie.timer"
log_info "  Logs:     journalctl --user -u zaloha-genealogie.service  (+ ~/.cache/zaloha-genealogie/zaloha.log)"
log_info "  Trigger:  systemctl --user start zaloha-genealogie.service"

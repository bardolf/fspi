#!/usr/bin/env bash
# logging.sh — jednoduché logování s barvami a časem

LOG_FILE="${LOG_FILE:-$HOME/.local/share/fedora-setup/install.log}"
mkdir -p "$(dirname "$LOG_FILE")"

# Barvy (pokud není TTY, vypni je)
if [[ -t 1 ]]; then
  COLOR_RESET="\033[0m"
  COLOR_INFO="\033[1;34m"
  COLOR_WARN="\033[1;33m"
  COLOR_ERROR="\033[1;31m"
  COLOR_DEBUG="\033[0;36m"
else
  COLOR_RESET=""
  COLOR_INFO=""
  COLOR_WARN=""
  COLOR_ERROR=""
  COLOR_DEBUG=""
fi

# Interní funkce: zapisuje do logu se značkou času
_log() {
  local level="$1"
  shift
  local color="$1"
  shift
  local msg="$*"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  echo -e "${color}[${level}]${COLOR_RESET} ${msg}"
  echo "[$timestamp] [$level] $msg" >>"$LOG_FILE"
}

log_info() { _log "INFO" "$COLOR_INFO" "$*"; }
log_warn() { _log "WARN" "$COLOR_WARN" "$*"; }
log_error() { _log "ERROR" "$COLOR_ERROR" "$*"; }
log_debug() {
  if [[ "${DEBUG:-0}" == "1" || "${DEBUG:-}" == "true" ]]; then
    _log "DEBUG" "$COLOR_DEBUG" "$*"
  fi
}

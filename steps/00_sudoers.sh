#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

CURRENT_USER="$USER"

log_info "Ensuring $CURRENT_USER has passwordless sudo access"

# Ujisti se, že máme sudo (může být potřeba zadat heslo poprvé)
ensure_command sudo

# Přidej uživatele do sudoers (NOPASSWD)
ensure_sudo_nopasswd "$CURRENT_USER"

log_info "Sudoers configuration complete for user: $CURRENT_USER"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

log_info "Disabling SELinux (if enabled)"

CFG_FILE="/etc/selinux/config"

if [[ ! -f "$CFG_FILE" ]]; then
    log_warn "SELinux config file not found at $CFG_FILE"
    exit 0
fi

CURRENT_MODE=$(grep ^SELINUX= "$CFG_FILE" | cut -d= -f2)

if [[ "$CURRENT_MODE" == "disabled" ]]; then
    log_debug "SELinux already disabled in config."
else
    log_info "Setting SELINUX=disabled in $CFG_FILE"
    sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' "$CFG_FILE"
    log_warn "SELinux has been set to 'disabled' in config file."
fi

# Try to disable immediately for current session
if command -v setenforce &>/dev/null; then
    if selinuxenabled 2>/dev/null; then
        log_info "Disabling SELinux for current session..."
        sudo setenforce 0 || log_warn "Failed to set SELinux permissive mode (maybe already disabled)"
    fi
fi

# Verify
STATUS=$(sestatus | grep "Current mode" || true)
log_info "Current SELinux mode: ${STATUS:-unknown}"

log_warn "A reboot is required for full SELinux disable to take effect."

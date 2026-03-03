#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

log_info "Enabling SysRq (Magic SysRq key)"

SYSRQ_CONF="/etc/sysctl.d/90-sysrq.conf"
SYSRQ_VALUE="1"

# Check current runtime value
current_value=$(cat /proc/sys/kernel/sysrq)

if [[ -f "$SYSRQ_CONF" ]] && grep -qx "kernel.sysrq = $SYSRQ_VALUE" "$SYSRQ_CONF" 2>/dev/null; then
  log_debug "SysRq sysctl config already set in $SYSRQ_CONF"
else
  log_info "Writing kernel.sysrq = $SYSRQ_VALUE to $SYSRQ_CONF"
  echo "kernel.sysrq = $SYSRQ_VALUE" | sudo tee "$SYSRQ_CONF" >/dev/null
fi

# Apply immediately if not already correct
if [[ "$current_value" != "$SYSRQ_VALUE" ]]; then
  log_info "Applying sysrq setting for current session"
  sudo sysctl -w kernel.sysrq="$SYSRQ_VALUE" >/dev/null
else
  log_debug "SysRq already enabled (current value: $current_value)"
fi

log_info "SysRq enabled — all SysRq functions available"

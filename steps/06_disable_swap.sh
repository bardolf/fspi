#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

log_info "Disabling swap (zram)"

ZRAM_CONF="/etc/systemd/zram-generator.conf"

# Check if zram swap is currently active
if swapon --show | grep -q zram; then
    log_info "zram swap is currently active, disabling..."
    
    # Turn off all swap
    sudo swapoff -a || log_warn "Failed to turn off swap (may already be off)"
fi

# Create empty zram-generator.conf to disable zram swap
# An empty file overrides /usr/lib/systemd/zram-generator.conf and disables zram
if [[ -f "$ZRAM_CONF" ]] && [[ ! -s "$ZRAM_CONF" ]]; then
    log_debug "Empty zram-generator.conf already exists, swap already disabled."
else
    log_info "Creating empty $ZRAM_CONF to disable zram swap"
    sudo touch "$ZRAM_CONF"
    # Ensure the file is empty (in case it existed with content)
    sudo truncate -s 0 "$ZRAM_CONF"
fi

# Stop zram setup service if running
if systemctl is-active --quiet systemd-zram-setup@zram0.service 2>/dev/null; then
    log_info "Stopping systemd-zram-setup@zram0.service"
    sudo systemctl stop systemd-zram-setup@zram0.service || true
fi

# Verify swap is disabled
if swapon --show | grep -q .; then
    log_warn "Some swap is still active:"
    swapon --show
else
    log_info "Swap successfully disabled"
fi

log_info "Swap will remain disabled after reboot"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

TARGET_TZ="Europe/Prague"

log_info "Setting system timezone to $TARGET_TZ"

CURRENT_TZ=$(timedatectl show -p Timezone --value)

if [[ "$CURRENT_TZ" == "$TARGET_TZ" ]]; then
    log_debug "Timezone already set to $CURRENT_TZ"
else
    log_info "Changing timezone from $CURRENT_TZ to $TARGET_TZ"
    sudo timedatectl set-timezone "$TARGET_TZ"
fi

# Verify result
NEW_TZ=$(timedatectl show -p Timezone --value)
log_info "Current timezone: $NEW_TZ"

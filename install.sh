#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Starting Fedora Sway setup"

for step in "$SCRIPT_DIR"/steps/*.sh; do
    log_info "Running step: $(basename "$step")"
    bash "$step" || { log_error "Step failed: $step"; exit 1; }
done

log_info "Setup complete!"

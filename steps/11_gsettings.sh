#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

log_info "Applying GSettings tweaks"

# schema  key  value   (space-separated triples)
SETTINGS=(
  "org.gnome.desktop.interface gtk-enable-primary-paste true"
)

if ! command -v gsettings &>/dev/null; then
  log_warn "gsettings not found — skipping"
  exit 0
fi

for entry in "${SETTINGS[@]}"; do
  read -r schema key value <<< "$entry"
  current=$(gsettings get "$schema" "$key" 2>/dev/null || echo "")
  if [[ "$current" == "$value" ]]; then
    log_debug "$schema $key already $value"
  else
    log_info "Setting $schema $key = $value (was: ${current:-unset})"
    gsettings set "$schema" "$key" "$value"
  fi
done

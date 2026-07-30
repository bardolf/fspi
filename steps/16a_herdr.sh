#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# herdr — terminal workspace manager for AI coding agents: persistent
# server/client sessions like tmux, plus a sidebar that tracks each agent pane
# as working/blocked/done/idle. Not packaged for Fedora; upstream ships an
# install script (https://herdr.dev/docs/install/) that drops the binary into
# ~/.local/bin, already on PATH via zshrc — same as azcopy and resvg.
#
# Config: config/herdr/config.toml, deployed by steps/20_config.sh.
# Upgrades are herdr's own job: `herdr update` (channel via `herdr channel set`),
# so this step only handles the initial install.

log_info "Step 16a: Installing herdr terminal workspace manager"

ensure_command curl

if check_command herdr; then
  log_debug "herdr already installed ($(herdr --version)), skipping"
else
  log_info "Installing herdr from herdr.dev (no Fedora package available)"
  curl -fsSL https://herdr.dev/install.sh | sh || {
    log_error "herdr install script failed"
    exit 1
  }

  hash -r
  if ! check_command herdr; then
    log_error "herdr not on PATH after install; expected $HOME/.local/bin/herdr"
    exit 1
  fi
  log_info "herdr installed ($(herdr --version))"
fi

log_info "Step 16a complete"

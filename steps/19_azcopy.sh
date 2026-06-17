#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# azcopy — Microsoft's bulk Azure Blob transfer tool. Not packaged for Fedora;
# ships as a standalone v10 tarball from aka.ms. Needed for uploading large
# static tile trees to Azure Blob (e.g. crisp-basemap: ~730k small .pbf files,
# where `az storage blob upload-batch` is far too slow). Installed to
# ~/.local/bin (already on PATH via zshrc), same as resvg.

if check_command azcopy; then
  log_debug "azcopy already installed, skipping"
else
  log_info "Installing azcopy from aka.ms (no Fedora package available)"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  log_info "Downloading azcopy v10 tarball"
  curl -fsSL "https://aka.ms/downloadazcopy-v10-linux" -o "$tmp/azcopy.tar.gz"
  tar -xzf "$tmp/azcopy.tar.gz" -C "$tmp"

  bin="$(find "$tmp" -type f -name azcopy | head -1)"
  if [[ -z "$bin" ]]; then
    log_error "azcopy binary not found in downloaded tarball"
    exit 1
  fi

  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$bin" "$HOME/.local/bin/azcopy"
  log_info "azcopy installed to $HOME/.local/bin/azcopy ($("$HOME/.local/bin/azcopy" --version | awk '{print $NF}'))"
fi

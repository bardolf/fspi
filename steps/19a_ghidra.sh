#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# Ghidra is not packaged for Fedora — the NSA ships it only as a fat
# ghidra_<ver>_PUBLIC_<date>.zip on GitHub releases. Layout used here:
#
#   ~/opt/ghidra_<ver>_PUBLIC/   unpacked release (one dir per version)
#   ~/opt/ghidra   ->  the above (symlink; what files/desktop/ghidra.desktop
#                      and files/icons/ghidra.png reference)
#   ~/.local/bin/ghidra -> ghidraRun (terminal launcher, ~/.local/bin is on
#                      PATH via zshrc)
#
# The latest release is resolved on every run, so a re-run upgrades in place
# by unpacking the new version next to the old one and repointing the symlink.
# Old ~/opt/ghidra_*_PUBLIC dirs are left alone — they keep their .gpr project
# metadata and can be deleted by hand once the upgrade is proven good.

GHIDRA_API="https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest"
GHIDRA_LINK="$HOME/opt/ghidra"

log_info "Installing Ghidra (reverse engineering suite)"

# Ghidra's LaunchSupport needs bin/javac and a non-headless JVM for its Swing
# GUI; 02_packages.sh installs java-25-openjdk-devel for exactly this reason,
# repeated here so the step also works when run standalone.
ensure_package java-25-openjdk-devel
ensure_package unzip
ensure_package jq

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- Resolve the latest release ---
if ! curl -fsSL "$GHIDRA_API" -o "$tmp/release.json"; then
  if [[ -x "$GHIDRA_LINK/ghidraRun" ]]; then
    log_warn "Could not reach the GitHub API; keeping the installed Ghidra"
    exit 0
  fi
  log_error "Could not reach $GHIDRA_API and no Ghidra is installed yet"
  exit 1
fi

asset_name=$(jq -r '.assets[] | select(.name | test("^ghidra_.+_PUBLIC_.+\\.zip$")) | .name' "$tmp/release.json" | head -1)
asset_url=$(jq -r '.assets[] | select(.name | test("^ghidra_.+_PUBLIC_.+\\.zip$")) | .browser_download_url' "$tmp/release.json" | head -1)

if [[ -z "$asset_name" || -z "$asset_url" ]]; then
  log_error "No ghidra_*_PUBLIC_*.zip asset found in the latest release"
  exit 1
fi

# ghidra_12.1.3_PUBLIC_20260817.zip -> ghidra_12.1.3_PUBLIC (the dir inside the zip)
install_dir="$HOME/opt/${asset_name%_*.zip}"

# --- Download and unpack ---
if [[ -x "$install_dir/ghidraRun" ]]; then
  log_debug "$(basename "$install_dir") already unpacked, skipping download"
else
  log_info "Downloading $asset_name (~400 MB)"
  curl -fSL --progress-bar "$asset_url" -o "$tmp/ghidra.zip"

  log_info "Unpacking to $install_dir"
  unzip -q "$tmp/ghidra.zip" -d "$tmp/unpacked"

  unpacked=$(find "$tmp/unpacked" -maxdepth 1 -mindepth 1 -type d -name 'ghidra_*_PUBLIC' | head -1)
  if [[ -z "$unpacked" ]]; then
    log_error "No ghidra_*_PUBLIC directory inside $asset_name"
    exit 1
  fi

  mkdir -p "$HOME/opt"
  rm -rf "$install_dir"
  mv "$unpacked" "$install_dir"
fi

# --- Point ~/opt/ghidra at it ---
# ensure_symlink would `ln -sf` *into* a real directory, so refuse that case
# rather than nesting the symlink inside a half-finished install.
if [[ -e "$GHIDRA_LINK" && ! -L "$GHIDRA_LINK" ]]; then
  log_error "$GHIDRA_LINK exists as a real directory; move it aside and re-run"
  exit 1
fi
ensure_symlink "$install_dir" "$GHIDRA_LINK"
ensure_symlink "$GHIDRA_LINK/ghidraRun" "$HOME/.local/bin/ghidra"

log_info "Ghidra installed: $(grep -m1 '^application.version=' "$install_dir/Ghidra/application.properties" | cut -d= -f2) → $GHIDRA_LINK"

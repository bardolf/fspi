#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

# RustDesk (remote desktop) není ve Fedora repozitářích ani v Terře — Terra má
# jen doplňkový rustdesk-selinux, samotný balík ne. Flatpak z Flathubu ale
# potřeba není: upstream vydává na GitHub releases hotové .rpm a všechny jeho
# závislosti (gtk3, alsa-lib, gstreamer1-plugins-base, libva, libxcb, pam)
# jsou stock Fedora balíky. Nativní RPM je tady lepší než sandboxovaný
# flatpak — RustDesk potřebuje na screen capture / input injection přístup
# k Waylandu i /dev/uinput.
#
# RPM není podepsaný (Signature: none), takže dnf install jde s --nogpgcheck.
#
# Terra rustdesk-selinux má Supplements: rustdesk, takže si ho dnf přitáhne
# sám jako weak dep. Nechává se být — 03_se_linux_disabled.sh SELinux vypíná,
# takže je to jen neaktivní policy modul, ne problém.
#
# Verze se řeší proti latest release na každém běhu, takže re-run upgraduje.

RUSTDESK_API="https://api.github.com/repos/rustdesk/rustdesk/releases/latest"

log_info "Installing RustDesk (remote desktop client)"

ensure_package jq

installed_ver=""
if rpm -q rustdesk &>/dev/null; then
  installed_ver=$(rpm -q --queryformat '%{VERSION}' rustdesk)
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- Resolve the latest release ---
if ! curl -fsSL "$RUSTDESK_API" -o "$tmp/release.json"; then
  if [[ -n "$installed_ver" ]]; then
    log_warn "Could not reach the GitHub API; keeping RustDesk $installed_ver"
    exit 0
  fi
  log_error "Could not reach $RUSTDESK_API and no RustDesk is installed yet"
  exit 1
fi

# Assety obsahují i .x86_64-suse.rpm (openSUSE build) — ten je potřeba vyloučit.
asset_name=$(jq -r '.assets[] | select(.name | test("^rustdesk-.+-0\\.x86_64\\.rpm$")) | .name' "$tmp/release.json" | head -1)
asset_url=$(jq -r '.assets[] | select(.name | test("^rustdesk-.+-0\\.x86_64\\.rpm$")) | .browser_download_url' "$tmp/release.json" | head -1)
latest_ver=$(jq -r '.tag_name' "$tmp/release.json")

if [[ -z "$asset_name" || -z "$asset_url" ]]; then
  log_error "No rustdesk-*-0.x86_64.rpm asset found in the latest release"
  exit 1
fi

if [[ "$installed_ver" == "$latest_ver" ]]; then
  log_debug "RustDesk $installed_ver already installed, skipping"
else
  if [[ -n "$installed_ver" ]]; then
    log_info "Upgrading RustDesk $installed_ver -> $latest_ver"
  else
    log_info "Downloading $asset_name (~30 MB)"
  fi

  curl -fSL --progress-bar "$asset_url" -o "$tmp/$asset_name"
  run_sudo dnf install -y --nogpgcheck "$tmp/$asset_name"
fi

# --- Vypnutí démona pro příchozí spojení ---
# Upstream %post rustdesk.service enabluje i startuje. Ta služba je unattended
# access — drží stroj registrovaný na public rendezvous serveru a přijímá
# příchozí spojení. Chceme jen odchozí klienta, takže ji vypínáme. Kdo by chtěl
# vzdálený přístup na tenhle stroj, spustí:
#   sudo systemctl enable --now rustdesk
if systemctl is-enabled rustdesk.service &>/dev/null || systemctl is-active rustdesk.service &>/dev/null; then
  log_info "Disabling rustdesk.service (incoming/unattended access not wanted)"
  run_sudo systemctl disable --now rustdesk.service
else
  log_debug "rustdesk.service already disabled, skipping"
fi

log_info "RustDesk installed: $(rpm -q --queryformat '%{VERSION}' rustdesk)"

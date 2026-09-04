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

did_install=0
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
  did_install=1
fi

# --- Vypnutí démona pro příchozí spojení ---
# Upstream %post rustdesk.service enabluje i startuje. Ta služba je unattended
# access: jako root drží injektážní kanál /dev/uinput a v přihlášeném sezení
# udržuje proces `rustdesk --server`, a právě `--server` je to, co registruje
# stroj na public rendezvous serveru. Chceme jen odchozí klienta, takže unit
# vypínáme z bootu.
#
# Pozor, "vypnutá služba + klient na obou stranách" spojení nenaváže. RustDesk
# vybírá wayland backendy podle toho, jestli existuje proces `--server`
# (upstream is_server_running() v libs/scrap/src/wayland/pipewire.rs): se
# službou jde obraz přes ScreenCast portal a vstup přes uinput, bez ní jde
# obraz *i* vstup přes RemoteDesktop portal. Ten xdg-desktop-portal-wlr
# neumí — inzeruje jen Screenshot a ScreenCast, viz
# /usr/share/xdg-desktop-portal/portals/wlr.portal — takže příchozí sezení
# umře ještě před prvním framem. Na sway je root služba jediná cesta.
#
# Když je vzdálený přístup na tenhle stroj potřeba, zapne se na jedno sezení:
#   ~/scripts/rustdesk-inbound.sh on     # a `off`, až to dohraje
# (deployuje 30_scripts.sh; řeší i flag stop-service, modul uinput a restart
# GUI okna). Trvale by to bylo `sudo systemctl enable --now rustdesk`.
if ((did_install)); then
  log_info "Disabling rustdesk.service (inbound is opt-in, see rustdesk-inbound.sh)"
  run_sudo systemctl disable --now rustdesk.service
elif systemctl is-active rustdesk.service &>/dev/null; then
  # Někdo si právě zapnul inbound na sezení — nebrat mu ho pod rukama, jen
  # zajistit, že to nepřežije reboot.
  log_info "rustdesk.service is running (on-demand inbound session), leaving it up"
  if systemctl is-enabled rustdesk.service &>/dev/null; then
    log_info "Removing rustdesk.service from boot"
    run_sudo systemctl disable rustdesk.service
  fi
elif systemctl is-enabled rustdesk.service &>/dev/null; then
  log_info "Disabling rustdesk.service (inbound is opt-in, see rustdesk-inbound.sh)"
  run_sudo systemctl disable --now rustdesk.service
else
  log_debug "rustdesk.service already disabled, skipping"
fi

# --- Flag stop-service: samotné GUI stroj nikam nepřihlásí ---
# Bez běžící služby si GUI spustí server ve vlastním procesu (core_main.rs →
# start_server(false, …)) a zaregistruje ID na rendezvous serveru. Stroj je pak
# vidět a adresovatelný, i když sdílení obrazovky by na sway stejně selhalo —
# a file transfer nebo terminál žádný capture nepotřebují. Flag
# `stop-service = 'Y'` v [options] souboru RustDesk2.toml tuhle registraci
# vypíná (rendezvous_mediator.rs) a je to přesně ten přepínač, který nabízí
# samotné GUI. Nastavujeme ho jen když tam žádná hodnota není: explicitní volbu
# (třeba od rustdesk-inbound.sh) nepřepisovat.
rustdesk_conf="${XDG_CONFIG_HOME:-$HOME/.config}/rustdesk/RustDesk2.toml"

if systemctl is-active rustdesk.service &>/dev/null; then
  log_debug "rustdesk.service is running, not touching stop-service"
elif [[ -f "$rustdesk_conf" ]] && grep -qE "^[[:space:]]*stop-service[[:space:]]*=" "$rustdesk_conf"; then
  log_debug "stop-service already set explicitly in $rustdesk_conf, leaving it"
else
  log_info "Setting stop-service='Y' (the GUI alone will not register this machine)"
  if [[ ! -f "$rustdesk_conf" ]]; then
    mkdir -p "$(dirname "$rustdesk_conf")"
    # Každé pole Config2 je #[serde(default)], takže soubor s jedinou tabulkou
    # [options] se načte a při prvním uložení se dopíše zbytek.
    printf "[options]\nstop-service = 'Y'\n" >"$rustdesk_conf"
  elif grep -qE "^\[options\]" "$rustdesk_conf"; then
    sed -i "/^\[options\]/a stop-service = 'Y'" "$rustdesk_conf"
  else
    printf "\n[options]\nstop-service = 'Y'\n" >>"$rustdesk_conf"
  fi
  if pgrep -u "$USER" -f '(^|/)rustdesk$' >/dev/null; then
    log_warn "RustDesk is open — restart the window, it may rewrite the config from memory"
  fi
fi

log_info "RustDesk installed: $(rpm -q --queryformat '%{VERSION}' rustdesk) (outgoing only)"

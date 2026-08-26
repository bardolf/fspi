#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Step 06b: Enabling earlyoom (userspace OOM killer)"

# Krok 06 vypíná swap (zram), takže při vyčerpání paměti nemá kernel kam
# odkládat a stroj zamrzne dřív, než se probudí in-kernel OOM killer.
# earlyoom hlídá MemAvailable z userspace a killne žrouta ještě předtím.
#
# systemd-oomd tuhle roli nezastane — rozhoduje se podle PSI tlaku, který
# se bez swapu prakticky nerozjede, takže zabíjí až moc pozdě.

EARLYOOM_DEFAULTS="/etc/default/earlyoom"

# Fedora default je "-m 4 -M 409600" a earlyoom si z -m/-M bere ten NIŽŠÍ
# (na pořadí flagů nezáleží), takže na 46GiB stroji reálně střílí až pod
# ~400 MiB volné paměti. To je bez swapu pozdě — v tu chvíli už stroj stojí
# v direct reclaim. -M proto vypouštíme úplně a jedeme na procentech:
#   -m 6,3 → SIGTERM pod 6 % (~2,8 GiB), SIGKILL pod 3 % (~1,4 GiB).
#
# --prefer/--avoid zůstávají z Fedora defaultu (schválené Workstation SIG):
# sway, systemd i dbus jsou v --avoid, takže nám to neustřelí session.
# Držíme celý EARLYOOM_ARGS, ne jen sed na prahy — jinak by se změna
# upstream formátu tiše minula a prahy by zůstaly stock.
read -r -d '' EARLYOOM_DESIRED <<'CONF' || true
# Managed by fspi (steps/06b_earlyoom.sh) — local edits get overwritten.
# Thresholds raised from the Fedora default: swap is disabled on this box
# (see steps/06_disable_swap.sh), so ~400 MiB is too late to react.

EARLYOOM_ARGS="-r 0 -m 6,3 --prefer '^(Web Content|Isolated Web Co)$' --avoid '^(dnf|packagekitd|gnome-shell|gnome-session-c|gnome-session-b|lightdm|sddm|sddm-helper|gdm|gdm-wayland-ses|gdm-session-wor|gdm-x-session|Xorg|Xwayland|systemd|systemd-logind|dbus-daemon|dbus-broker|cinnamon|cinnamon-sessio|kwin_x11|kwin_wayland|plasmashell|ksmserver|plasma_session|startplasma-way|sway|i3|xfce4-session|mate-session|marco|lxqt-session|openbox|cryptsetup)$'"

# More documentation at `man earlyoom` or `earlyoom -h`.
CONF

ensure_package earlyoom

config_changed=0
if [[ -f "$EARLYOOM_DEFAULTS" ]] && [[ "$(cat "$EARLYOOM_DEFAULTS")" == "$EARLYOOM_DESIRED" ]]; then
  log_debug "earlyoom thresholds already configured in $EARLYOOM_DEFAULTS"
else
  log_info "Writing raised OOM thresholds to $EARLYOOM_DEFAULTS"
  printf '%s\n' "$EARLYOOM_DESIRED" | run_sudo tee "$EARLYOOM_DEFAULTS" >/dev/null
  config_changed=1
fi

if systemctl is-enabled --quiet earlyoom && systemctl is-active --quiet earlyoom; then
  log_debug "earlyoom already enabled and running"
  if [[ "$config_changed" -eq 1 ]]; then
    log_info "Restarting earlyoom to pick up new thresholds"
    run_sudo systemctl restart earlyoom
  fi
else
  log_info "Enabling and starting earlyoom"
  run_sudo systemctl enable earlyoom --now
fi

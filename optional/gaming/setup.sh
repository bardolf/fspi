#!/usr/bin/env bash
set -euo pipefail

STEP_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$STEP_DIR/../.." && pwd)
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

log_info "Optional: Steam + gaming performance tooling (AMD / RADV desktop)"

# Opt-in, ne součást install.sh: tenhle stack dává smysl jen na desktopu
# s Radeonem. Na notebooku s Intel HD 620 si Steam přitáhne ~190 balíků
# včetně celého i686 stacku a nic z toho se nepoužije.

# --- Terra vs. falcond ---
# Steam se tady neinstaluje z RPM Fusion, ale z Terry — ta má vyšší verzi
# (1.0.0.87-5 vs. -3), takže ji dnf vybere i při rovnocenné prioritě repa.
# Terra Steam má Recommends: falcond (jejich vlastní herní daemon) a falcond
# má Conflicts: gamemode. Bez tohohle excludu se falcond přitáhne jako weak
# dependency a `dnf install gamemode` pak skončí na konfliktu.
#
# terra.repo si sám v hlavičce říká, že se nemá editovat a že overrides
# patří do /etc/dnf/repos.override.d/ — tak to děláme.
OVERRIDE_SRC="$STEP_DIR/files/99-terra-no-falcond.repo"
OVERRIDE_DEST=/etc/dnf/repos.override.d/99-terra-no-falcond.repo

if sudo cmp -s "$OVERRIDE_SRC" "$OVERRIDE_DEST" 2>/dev/null; then
  log_debug "Terra falcond exclude already up-to-date: $OVERRIDE_DEST"
else
  log_info "Excluding falcond from Terra (conflicts with gamemode): $OVERRIDE_DEST"
  run_sudo install -d -m 755 -o root -g root "$(dirname "$OVERRIDE_DEST")"
  run_sudo install -m 644 -o root -g root "$OVERRIDE_SRC" "$OVERRIDE_DEST"
fi

# falcond už mohl přijít dřív (weak dependency dřívější instalace Steamu).
# Exclude ho z repa jen schová, nainstalovaný ho nechá — a konflikt trvá.
stale=()
for pkg in falcond falcond-profiles falcond-gui; do
  rpm -q "$pkg" &>/dev/null && stale+=("$pkg")
done
if ((${#stale[@]})); then
  log_info "Removing previously pulled falcond packages (block gamemode): ${stale[*]}"
  run_sudo dnf remove -y "${stale[@]}"
else
  log_debug "No falcond packages installed"
fi

# --- Balíky ---
PACKAGES=(
  # Nativní balík (ne Flatpak), aby hry viděly gamemode a mangohud
  # nainstalované v systému. Přitáhne si sadu i686 závislostí včetně
  # mesa-vulkan-drivers.i686 — samotný klient je 32bitový, hry (CS2)
  # běží 64bitově na RADV.
  steam
  # gamemoderun v launch options přepne CPU governor na performance po dobu
  # běhu hry; mangohud je overlay s FPS a frametime. Obojí přes `%command%`.
  gamemode
  mangohud
  # vulkaninfo — ověření, že hra vidí RADV a ne llvmpipe.
  vulkan-tools
)

for pkg in "${PACKAGES[@]}"; do
  ensure_package "$pkg"
done

log_info "Optional gaming setup complete"
log_info "  Steam launch options:  gamemoderun mangohud %command%"
log_info "  Check the driver:      vulkaninfo --summary | grep driverName   (expect radv)"
log_info "  Check gamemode:        gamemoded -s   (while a game runs)"

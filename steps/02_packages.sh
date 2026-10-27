#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/utils.sh"

log_info "Installing essential packages"

# --- Basic command line tools ---
PACKAGES=(
  vim
  mc
  htop
  btop
  flatpak
  chromium
  qalc
  mpv
  yt-dlp
  xournalpp
  okular
  feh
  texlive-scheme-medium
  gimp
  inkscape
  graphviz
  libreoffice
  grim
  slurp
  jq
  yq
  wl-clipboard
  wtype
  clipman
  qalculate-qt
  libnotify
  azure-cli
  k9s
  wayland-utils
  # vainfo — diagnostika VA-API (hardwarové dekódování videa na amdgpu).
  libva-utils
  # Fedora vyřezává z mesy H.264 a HEVC kvůli patentům, takže stock
  # radeonsi_drv_video.so umí jen VP9/AV1/MPEG2. Freeworld verze z RPM
  # Fusion je doplňuje (dekód i enkód). Není to swap — instaluje se do
  # /usr/lib64/dri-freeworld/, kam se libva dívá dřív než do /usr/lib64/dri.
  mesa-va-drivers-freeworld
  vivaldi-stable
  google-chrome-stable
  libxkbcommon-devel
  postgresql
  ocrmypdf
  tesseract-langpack-ces
  ddcutil
  lm_sensors
  git-secret
  meld
  glab
  lazygit
  ShellCheck
  krita
  kitty-kitten
  zoxide
  vdirsyncer
  python3-aiohttp-oauthlib
  khal
  rclone
  ghostty
  tuned-ppd
  mise
  # uv + uvx — Python projekty a MCP servery (např. genealogy-tools).
  uv
  musescore
  # Fedora ships jen java-*-openjdk-headless (JRE bez javac a bez AWT).
  # Ghidra v ~/opt/ghidra vyžaduje plný JDK — jeho LaunchSupport hledá
  # bin/javac, a bez non-headless balíku by Swing GUI vůbec nenaběhlo.
  # -devel si non-headless java-25-openjdk přitáhne jako závislost.
  java-25-openjdk-devel
  # scripts/nas-tmp montuje NAS přes sshfs (fusermount3 na odpojení).
  fuse-sshfs
  # vncviewer — wayvnc na desktopu přes SSH tunel:
  # vncviewer -via desktop localhost::5900  (pozor: host:5900 = display 5900).
  tigervnc
  # remote-viewer — výchozí klient scripts/vnc-desktop.sh: nativní Wayland,
  # na scale 1.3 ukáže celou 4K plochu (TigerVNC přes XWayland jen výřez).
  virt-viewer
)

for pkg in "${PACKAGES[@]}"; do
  ensure_package "$pkg"
done

log_info "Base packages installed successfully."

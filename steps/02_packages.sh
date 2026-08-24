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
  flameshot
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
  vivaldi-stable
  libxkbcommon-devel
  postgresql
  ocrmypdf
  tesseract-langpack-ces
  earlyoom
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
  musescore
  # Fedora ships jen java-*-openjdk-headless (JRE bez javac a bez AWT).
  # Ghidra v ~/opt/ghidra vyžaduje plný JDK — jeho LaunchSupport hledá
  # bin/javac, a bez non-headless balíku by Swing GUI vůbec nenaběhlo.
  # -devel si non-headless java-25-openjdk přitáhne jako závislost.
  java-25-openjdk-devel
  # scripts/nas-tmp montuje NAS přes sshfs (fusermount3 na odpojení).
  fuse-sshfs
)

for pkg in "${PACKAGES[@]}"; do
  ensure_package "$pkg"
done

log_info "Base packages installed successfully."

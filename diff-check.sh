#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

# -------------------------
# Argument parsing
# -------------------------

DETAIL=false
for arg in "$@"; do
  case "$arg" in
  -d | --detail) DETAIL=true ;;
  -h | --help)
    echo "Usage: $(basename "$0") [-d|--detail] [-h|--help]"
    echo ""
    echo "Compare repo files against deployed system files."
    echo "Under each drifting file, prints the cp command that syncs it (repo → system)."
    echo ""
    echo "Options:"
    echo "  -d, --detail  Show unified diffs for changed files"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Set DEBUG=1 to also show files that are identical."
    exit 0
    ;;
  *)
    log_error "Unknown option: $arg"
    exit 1
    ;;
  esac
done

# -------------------------
# Colors (extend logging.sh)
# -------------------------

if [[ -t 1 ]]; then
  COLOR_OK="\033[1;32m"
  COLOR_HEADER="\033[1;35m"
else
  COLOR_OK=""
  COLOR_HEADER=""
fi

# -------------------------
# Counters
# -------------------------

total=0
diff_count=0
missing_count=0

# -------------------------
# Core functions
# -------------------------

print_section() {
  local title="$1"
  echo ""
  echo -e "${COLOR_HEADER}--- $title ---${COLOR_RESET}"
}

# Print the ready-to-paste command that syncs system_file from repo_file, right
# under the drift line. Pure cp, mirroring how the install steps deploy it
# (sudo install for the CA anchors, sudo cp for anything else outside $HOME).
print_fix() {
  local repo_file="$1" system_file="$2"

  if [[ "$system_file" == /etc/pki/ca-trust/source/anchors/* ]]; then
    echo "            sudo install -m 0644 \"$repo_file\" \"$system_file\" && sudo update-ca-trust"
  elif [[ "$system_file" == "$HOME"/* ]]; then
    echo "            cp -f \"$repo_file\" \"$system_file\""
  else
    echo "            sudo cp -f \"$repo_file\" \"$system_file\""
  fi
}

check_file() {
  local repo_file="$1"
  local system_file="$2"
  local optional="${3:-false}"

  if [[ ! -f "$repo_file" ]]; then
    return
  fi

  if [[ ! -f "$system_file" ]]; then
    if $optional; then
      log_debug "[SKIP]    $system_file (optional, not installed)"
      return
    fi
    ((total++)) || true
    ((missing_count++)) || true
    echo -e "  ${COLOR_ERROR}[MISSING]${COLOR_RESET} $system_file"
    print_fix "$repo_file" "$system_file"
    return
  fi

  ((total++)) || true

  if cmp -s "$repo_file" "$system_file"; then
    log_debug "[OK]      $system_file"
    return
  fi

  ((diff_count++)) || true
  echo -e "  ${COLOR_WARN}[DIFF]${COLOR_RESET}    $system_file"
  print_fix "$repo_file" "$system_file"

  if $DETAIL; then
    diff -u --color=auto "$system_file" "$repo_file" || true
    echo ""
  fi
}

# =========================================================
# Section 1: Configs (mirrors steps/20_config.sh)
# =========================================================

print_section "Configs"

CONFIG_PAIRS=(
  "config/waybar/config.jsonc" "$HOME/.config/waybar/config.jsonc"
  "config/waybar/style.css" "$HOME/.config/waybar/style.css"
  "config/foot/foot.ini" "$HOME/.config/foot/foot.ini"
  "config/git/gitconfig" "$HOME/.gitconfig"
  "config/mise/config.toml" "$HOME/.config/mise/config.toml"
  "config/wezterm/wezterm.lua" "$HOME/.config/wezterm/wezterm.lua"
  "config/dunst/dunstrc" "$HOME/.config/dunst/dunstrc"
  "config/nvim/lua/config/options.lua" "$HOME/.config/nvim/lua/config/options.lua"
  "config/nvim/lua/plugins/disabled.lua" "$HOME/.config/nvim/lua/plugins/disabled.lua"
  "config/nvim/lua/plugins/blink.lua" "$HOME/.config/nvim/lua/plugins/blink.lua"
  "config/satty/config.toml" "$HOME/.config/satty/config.toml"
  "config/sway/config" "$HOME/.config/sway/config"
  "config/swaylock/effects.conf" "$HOME/.config/swaylock/effects.conf"
  "config/sway/config.d/10-displays.conf" "$HOME/.config/sway/config.d/10-displays.conf"
  "config/sway/config.d/50-rules-browser.conf" "$HOME/.config/sway/config.d/50-rules-browser.conf"
  "config/sway/config.d/50-rules-floating.conf" "$HOME/.config/sway/config.d/50-rules-floating.conf"
  "config/sway/config.d/50-rules-jetbrains.conf" "$HOME/.config/sway/config.d/50-rules-jetbrains.conf"
  "config/sway/config.d/55-ffm-jetbrains.conf" "$HOME/.config/sway/config.d/55-ffm-jetbrains.conf"
  "config/sway/config.d/60-bindings-screenshot.conf" "$HOME/.config/sway/config.d/60-bindings-screenshot.conf"
  "config/sway/config.d/60-bindings-screenrecord.conf" "$HOME/.config/sway/config.d/60-bindings-screenrecord.conf"
  "config/sway/config.d/60-bindings-mouse.conf" "$HOME/.config/sway/config.d/60-bindings-mouse.conf"
  "config/sway/config.d/90-swayidle.conf" "$HOME/.config/sway/config.d/90-swayidle.conf"
  "config/ghostty/config.ghostty" "$HOME/.config/ghostty/config.ghostty"
  "config/yazi/yazi.toml" "$HOME/.config/yazi/yazi.toml"
  "config/yazi/keymap.toml" "$HOME/.config/yazi/keymap.toml"
  "config/yazi/theme.toml" "$HOME/.config/yazi/theme.toml"
  "config/yazi/plugins/smart-enter.yazi/main.lua" "$HOME/.config/yazi/plugins/smart-enter.yazi/main.lua"
  "config/mimeapps.list" "$HOME/.config/mimeapps.list"
  "config/zsh/zshrc" "$HOME/.zshrc"
  "config/zsh/zshenv" "$HOME/.zshenv"
  "config/ssh/config" "$HOME/.ssh/config"
)

for ((i = 0; i < ${#CONFIG_PAIRS[@]}; i += 2)); do
  check_file "$SCRIPT_DIR/${CONFIG_PAIRS[i]}" "${CONFIG_PAIRS[i + 1]}"
done

# =========================================================
# Section 2: Scripts (mirrors steps/30_scripts.sh)
# =========================================================

print_section "Scripts"

SRC_DIR="$SCRIPT_DIR/scripts"
TARGET_DIR="$HOME/scripts"

# Top-level scripts
for script_file in "$SRC_DIR"/*; do
  [[ -f "$script_file" ]] || continue
  check_file "$script_file" "$TARGET_DIR/$(basename "$script_file")"
done

# Subdirectory scripts (skip _* dirs)
for subdir in "$SRC_DIR"/*/; do
  [[ -d "$subdir" ]] || continue
  subdir_name=$(basename "$subdir")
  [[ "$subdir_name" == _* ]] && continue
  for script_file in "$subdir"*; do
    [[ -f "$script_file" ]] || continue
    check_file "$script_file" "$TARGET_DIR/$subdir_name/$(basename "$script_file")"
  done
done

# =========================================================
# Section 3: Desktop entries & icons (mirrors steps/23_desktop_icon.sh)
# =========================================================

print_section "Desktop entries & icons"

DESKTOP_SRC="$SCRIPT_DIR/files/desktop"
ICONS_SRC="$SCRIPT_DIR/files/icons"
DESKTOP_TARGET="$HOME/.local/share/applications"
ICONS_TARGET="$HOME/.local/share/icons"

for file in "$DESKTOP_SRC"/*.desktop; do
  [[ -f "$file" ]] || continue
  check_file "$file" "$DESKTOP_TARGET/$(basename "$file")"
done

for file in "$ICONS_SRC"/*.png "$ICONS_SRC"/*.svg "$ICONS_SRC"/*.xpm; do
  [[ -f "$file" ]] || continue
  check_file "$file" "$ICONS_TARGET/$(basename "$file")"
done

# =========================================================
# Section 4: Calendar sync (mirrors steps/25_calendar_sync.sh)
# =========================================================

print_section "Calendar sync (vdirsyncer + khal + systemd)"

CALENDAR_PAIRS=(
  "config/vdirsyncer/config" "$HOME/.config/vdirsyncer/config"
  "config/khal/config" "$HOME/.config/khal/config"
  "files/systemd/vdirsyncer.service" "$HOME/.config/systemd/user/vdirsyncer.service"
  "files/systemd/vdirsyncer.timer" "$HOME/.config/systemd/user/vdirsyncer.timer"
)

for ((i = 0; i < ${#CALENDAR_PAIRS[@]}; i += 2)); do
  check_file "$SCRIPT_DIR/${CALENDAR_PAIRS[i]}" "${CALENDAR_PAIRS[i + 1]}"
done

# =========================================================
# Section 5: CETIN CA certs (mirrors steps/00d_cetin_certs.sh)
# =========================================================

print_section "CETIN CA certificates"

CERTS_SRC="$SCRIPT_DIR/files/certs"
ANCHOR_TARGET="/etc/pki/ca-trust/source/anchors"

for cert in "$CERTS_SRC"/*.crt; do
  [[ -f "$cert" ]] || continue
  check_file "$cert" "$ANCHOR_TARGET/$(basename "$cert")"
done

# =========================================================
# Section 6: Optional - Dropbox sync (mirrors optional/dropbox/setup.sh)
# Skipped silently if the optional component was never installed.
# =========================================================

print_section "Optional: Dropbox sync (rclone + systemd)"

DROPBOX_PAIRS=(
  # rclone.conf intentionally not tracked: it holds the OAuth token,
  # which is per-machine and generated by `rclone config`.
  "optional/dropbox/files/systemd/rclone-dropbox.service" "$HOME/.config/systemd/user/rclone-dropbox.service"
  "optional/dropbox/files/systemd/rclone-dropbox.timer"   "$HOME/.config/systemd/user/rclone-dropbox.timer"
)

for ((i = 0; i < ${#DROPBOX_PAIRS[@]}; i += 2)); do
  check_file "$SCRIPT_DIR/${DROPBOX_PAIRS[i]}" "${DROPBOX_PAIRS[i + 1]}" true
done

# =========================================================
# Section 7: Optional - Samba/CIFS mounts (mirrors optional/samba/setup.sh)
# The fstab block lives between markers inside /etc/fstab, so we extract that
# block and compare it to the repo file. Credentials files are intentionally
# not checked: they hold secrets and the repo only ships empty templates.
# Skipped silently if the optional component was never installed.
# =========================================================

print_section "Optional: Samba/CIFS mounts (/etc/fstab block)"

SAMBA_BLOCK="$SCRIPT_DIR/optional/samba/files/fstab-cifs.block"
SAMBA_BEGIN="# >>> fspi samba cifs mounts >>>"
SAMBA_END="# <<< fspi samba cifs mounts <<<"

if [[ -f "$SAMBA_BLOCK" ]] && grep -qF "$SAMBA_BEGIN" /etc/fstab 2>/dev/null; then
  extracted=$(awk -v b="$SAMBA_BEGIN" -v e="$SAMBA_END" '
    $0==e {skip=1} !skip && started {print} $0==b {started=1}
  ' /etc/fstab)
  ((total++)) || true
  if [[ "$extracted" == "$(cat "$SAMBA_BLOCK")" ]]; then
    log_debug "[OK]      /etc/fstab (managed CIFS block)"
  else
    ((diff_count++)) || true
    echo -e "  ${COLOR_WARN}[DIFF]${COLOR_RESET}    /etc/fstab (managed CIFS block)"
    # Managed block, not a plain file: no cp can reproduce it. Point at the setup step.
    echo "            # managed block — re-run: bash \"$SCRIPT_DIR/optional/samba/setup.sh\""
    if $DETAIL; then
      diff -u --color=auto <(printf '%s\n' "$extracted") "$SAMBA_BLOCK" || true
      echo ""
    fi
  fi
else
  log_debug "[SKIP]    /etc/fstab CIFS block (optional, not installed)"
fi

# =========================================================
# Summary
# =========================================================

echo ""
echo "═══════════════════════════════════════════"
printf "  Summary: %d checked, %d differ, %d missing\n" "$total" "$diff_count" "$missing_count"
echo "═══════════════════════════════════════════"

if ((diff_count + missing_count > 0)); then
  exit 1
else
  log_info "All deployed files match the repo."
  exit 0
fi

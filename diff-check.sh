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

check_file() {
  local repo_file="$1"
  local system_file="$2"

  if [[ ! -f "$repo_file" ]]; then
    return
  fi

  ((total++)) || true

  if [[ ! -f "$system_file" ]]; then
    ((missing_count++)) || true
    echo -e "  ${COLOR_ERROR}[MISSING]${COLOR_RESET} $system_file"
    return
  fi

  if cmp -s "$repo_file" "$system_file"; then
    log_debug "[OK]      $system_file"
    return
  fi

  ((diff_count++)) || true
  echo -e "  ${COLOR_WARN}[DIFF]${COLOR_RESET}    $system_file"

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
  "config/sway/config.d/10-displays.conf" "$HOME/.config/sway/config.d/10-displays.conf"
  "config/sway/config.d/50-rules-browser.conf" "$HOME/.config/sway/config.d/50-rules-browser.conf"
  "config/sway/config.d/60-bindings-screenshot.conf" "$HOME/.config/sway/config.d/60-bindings-screenshot.conf"
  "config/sway/config.d/60-bindings-mouse.conf" "$HOME/.config/sway/config.d/60-bindings-mouse.conf"
  "config/ghostty/config.ghostty" "$HOME/.config/ghostty/config.ghostty"
  "config/yazi/yazi.toml" "$HOME/.config/yazi/yazi.toml"
  "config/yazi/keymap.toml" "$HOME/.config/yazi/keymap.toml"
  "config/yazi/theme.toml" "$HOME/.config/yazi/theme.toml"
  "config/yazi/plugins/smart-enter.yazi/main.lua" "$HOME/.config/yazi/plugins/smart-enter.yazi/main.lua"
  "config/mimeapps.list" "$HOME/.config/mimeapps.list"
  "config/zsh/zshrc" "$HOME/.zshrc"
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

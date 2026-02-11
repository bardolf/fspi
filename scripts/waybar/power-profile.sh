#!/usr/bin/env bash
# Waybar module: Power Profile indicator and switcher
# Output: "⚡ balanced" (with icon per profile)
#
# Usage:
#   power-profile.sh         - Output current profile as JSON for waybar
#   power-profile.sh toggle  - Cycle to next profile
#
# Profiles cycle: balanced → performance → power-saver → balanced

# ============================================
# Check if powerprofilesctl is available
# ============================================
if ! command -v powerprofilesctl &>/dev/null; then
    # Output empty text - waybar will hide the module
    echo '{"text": "", "tooltip": "powerprofilesctl not installed", "class": "unavailable"}'
    exit 0
fi

# ============================================
# Profile definitions (using Nerd Font icons)
# ============================================
declare -A PROFILE_ICONS=(
    ["balanced"]="󰗑"
    ["performance"]="󰓅"
    ["power-saver"]="󰌪"
)

declare -A PROFILE_DESCRIPTIONS=(
    ["balanced"]="Balanced - default profile"
    ["performance"]="Performance - maximum power"
    ["power-saver"]="Power Saver - battery saving"
)

# Order for cycling
PROFILES=("balanced" "performance" "power-saver")

# ============================================
# Get current profile
# ============================================
get_current_profile() {
    powerprofilesctl get 2>/dev/null || echo "unknown"
}

# ============================================
# Get next profile in cycle
# ============================================
get_next_profile() {
    local current="$1"
    local count=${#PROFILES[@]}
    
    for i in "${!PROFILES[@]}"; do
        if [[ "${PROFILES[$i]}" == "$current" ]]; then
            local next_idx=$(( (i + 1) % count ))
            echo "${PROFILES[$next_idx]}"
            return 0
        fi
    done
    
    # Fallback to balanced if current profile not found
    echo "balanced"
}

# ============================================
# Toggle to next profile
# ============================================
toggle_profile() {
    local current
    current=$(get_current_profile)
    local next
    next=$(get_next_profile "$current")
    
    powerprofilesctl set "$next" 2>/dev/null
}

# ============================================
# Output JSON for waybar
# ============================================
output_json() {
    local profile
    profile=$(get_current_profile)
    
    local icon="${PROFILE_ICONS[$profile]:-"?"}"
    local description="${PROFILE_DESCRIPTIONS[$profile]:-"Unknown profile"}"
    
    local text="${icon} ${profile}"
    local tooltip="Power Profile: ${description}\nClick to switch profile"
    
    jq -nc \
        --arg text "$text" \
        --arg tooltip "$tooltip" \
        --arg class "$profile" \
        '{text: $text, tooltip: $tooltip, class: $class}'
}

# ============================================
# Main
# ============================================
case "${1:-}" in
    toggle)
        toggle_profile
        ;;
    *)
        output_json
        ;;
esac

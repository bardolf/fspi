#!/usr/bin/env bash
# Waybar module: Audio status (volume + mic + BT device name + battery)
#
# Detects connected Bluetooth audio devices from a known list.
# Shows device short name and battery (if available).
# Supports scroll-to-change-volume via on-scroll-up/down in waybar config.
#
# Uses Nerd Font icons (https://www.nerdfonts.com/cheat-sheet)

# ============================================
# Known Bluetooth audio devices
# Format: MAC:SHORT_NAME
# ============================================
KNOWN_DEVICES=(
    "84:AC:60:94:72:9F:APW"
    "08:DF:1F:4A:91:6A:BOSE"
)

# ============================================
# Handle volume change (called with argument)
# ============================================
if [[ "$1" == "up" ]]; then
    wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
    exit 0
elif [[ "$1" == "down" ]]; then
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
    exit 0
fi

# ============================================
# Get output volume (sink)
# ============================================
get_output_volume() {
    local vol_raw
    vol_raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)

    if echo "$vol_raw" | grep -q "\[MUTED\]"; then
        echo "muted"
        return
    fi

    echo "$vol_raw" | awk '{printf "%.0f", $2 * 100}'
}

# ============================================
# Get input volume (source/mic)
# @DEFAULT_AUDIO_SOURCE@ can incorrectly resolve to a sink
# when a BT speaker (sink-only) is connected. Instead, find
# the actual source from wpctl status. Prefer the default
# source (marked with *), fall back to the first one listed.
# ============================================
get_input_volume() {
    local sources_block source_id
    sources_block=$(wpctl status 2>/dev/null | awk '/Audio/,/Video/' | awk '/Sources:/,/Filters:/' | grep -v 'Sources:\|Filters:')

    # Prefer default source (line with *)
    source_id=$(echo "$sources_block" | grep '\*' | grep -oP '[0-9]+\.' | head -1 | tr -d '.')

    # Fall back to first source listed
    if [[ -z "$source_id" ]]; then
        source_id=$(echo "$sources_block" | grep -oP '[0-9]+\.' | head -1 | tr -d '.')
    fi

    if [[ -z "$source_id" ]]; then
        echo ""
        return
    fi

    local vol_raw
    vol_raw=$(wpctl get-volume "$source_id" 2>/dev/null)

    if echo "$vol_raw" | grep -q "\[MUTED\]"; then
        echo "muted"
        return
    fi

    echo "$vol_raw" | awk '{printf "%.0f", $2 * 100}'
}

# ============================================
# Find connected BT audio device from known list
# Returns: SHORT_NAME|BATTERY (battery empty if not available)
# ============================================
get_bt_device() {
    for entry in "${KNOWN_DEVICES[@]}"; do
        local mac short_name info
        mac="${entry%:*}"
        # MAC has 5 colons (6 parts), short_name is after the 6th colon
        mac=$(echo "$entry" | cut -d: -f1-6)
        short_name=$(echo "$entry" | cut -d: -f7)

        info=$(bluetoothctl info "$mac" 2>/dev/null)

        if echo "$info" | grep -q "Connected: yes"; then
            local battery
            battery=$(echo "$info" | grep "Battery Percentage" | awk '{print $4}' | tr -d '()%')
            echo "${short_name}|${battery}"
            return
        fi
    done
    echo ""
}

# ============================================
# Build output
# ============================================

out_vol=$(get_output_volume)
in_vol=$(get_input_volume)
bt_result=$(get_bt_device)

bt_name=""
battery=""
if [[ -n "$bt_result" ]]; then
    bt_name="${bt_result%%|*}"
    battery="${bt_result##*|}"
fi

# Volume icons - Nerd Font
# 󰕾 = volume high, 󰖀 = volume low, 󰝟 = muted
if [[ "$out_vol" == "muted" ]]; then
    out_text="󰝟"
else
    if [[ "$out_vol" -lt 30 ]]; then
        out_icon="󰕿"
    elif [[ "$out_vol" -lt 70 ]]; then
        out_icon="󰖀"
    else
        out_icon="󰕾"
    fi
    out_text="${out_icon} ${out_vol}%"
fi

# Mic icons - Nerd Font
# 󰍬 = mic, 󰍭 = mic muted
if [[ "$in_vol" == "muted" ]]; then
    in_text="󰍭"
else
    in_text="󰍬 ${in_vol}%"
fi

# Battery icons (Nerd Font)
# 󰁺󰁻󰁼󰁽󰁾󰁿󰂀󰂁󰂂󰁹 = battery levels 10-100%
bat_text=""
if [[ -n "$battery" ]]; then
    if [[ "$battery" -lt 10 ]]; then
        bat_icon="󰂎"
    elif [[ "$battery" -lt 20 ]]; then
        bat_icon="󰁺"
    elif [[ "$battery" -lt 30 ]]; then
        bat_icon="󰁻"
    elif [[ "$battery" -lt 40 ]]; then
        bat_icon="󰁼"
    elif [[ "$battery" -lt 50 ]]; then
        bat_icon="󰁽"
    elif [[ "$battery" -lt 60 ]]; then
        bat_icon="󰁾"
    elif [[ "$battery" -lt 70 ]]; then
        bat_icon="󰁿"
    elif [[ "$battery" -lt 80 ]]; then
        bat_icon="󰂀"
    elif [[ "$battery" -lt 90 ]]; then
        bat_icon="󰂁"
    else
        bat_icon="󰁹"
    fi
    bat_text="${bat_icon} ${battery}%"
fi

# BT device name + bluetooth icon
bt_text=""
if [[ -n "$bt_name" ]]; then
    bt_text="󰂯 ${bt_name}"
fi

# Combine output: volume | mic | [BT name] [battery]
parts=("${out_text}" "${in_text}")
if [[ -n "$bt_text" ]]; then
    parts+=("${bt_text}")
fi
if [[ -n "$bat_text" ]]; then
    parts+=("${bat_text}")
fi

echo "${parts[*]}"

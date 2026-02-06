#!/usr/bin/env bash
# Waybar module: Audio status (volume + mic + headset battery)
# Matches pulseaudio module format with added battery
#
# Uses Nerd Font icons (https://www.nerdfonts.com/cheat-sheet)

# Configuration - set your Bluetooth headset MAC address
HEADSET_MAC="${HEADSET_MAC:-84:AC:60:94:72:9F}"

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
# ============================================
get_input_volume() {
    local vol_raw
    vol_raw=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)
    
    if echo "$vol_raw" | grep -q "\[MUTED\]"; then
        echo "muted"
        return
    fi
    
    echo "$vol_raw" | awk '{printf "%.0f", $2 * 100}'
}

# ============================================
# Get headset battery (if connected)
# ============================================
get_headset_battery() {
    local info
    info=$(bluetoothctl info "$HEADSET_MAC" 2>/dev/null)
    
    if ! echo "$info" | grep -q "Connected: yes"; then
        echo ""
        return
    fi
    
    echo "$info" | grep "Battery Percentage" | awk '{print $4}' | tr -d '()%'
}

# ============================================
# Build output
# ============================================

out_vol=$(get_output_volume)
in_vol=$(get_input_volume)
battery=$(get_headset_battery)

# Volume icons (Nerd Font)
# 󰕾 = volume high, 󰖀 = volume medium, 󰕿 = volume low, 󰝟 = muted
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
    out_text="${out_vol}% ${out_icon}"
fi

# Mic icons (Nerd Font)
# 󰍬 = mic, 󰍭 = mic muted
if [[ "$in_vol" == "muted" ]]; then
    in_text="󰍭"
else
    in_text="${in_vol}% 󰍬"
fi

# Battery icons (Nerd Font) - only if headset connected
# 󰁺󰁻󰁼󰁽󰁾󰁿󰂀󰂁󰂂󰁹 = battery levels 10-100%
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
else
    bat_text=""
fi

# Combine: "58% 󰖀 81% 󰍬 󰂀 70%"
echo "${out_text} ${in_text} ${bat_text}"

#!/usr/bin/env bash
# Waybar module: Headset info (battery + volume)
# Outputs JSON for waybar custom module
# 
# Usage in waybar config:
#   "custom/headset": {
#     "exec": "~/scripts/waybar/headset-info.sh",
#     "interval": 10,
#     "return-type": "json",
#     "format": "{}",
#     "signal": 10
#   }
#
# To force refresh: pkill -SIGRTMIN+10 waybar

# Configuration - set your Bluetooth headset MAC address
# Find it with: bluetoothctl devices
HEADSET_MAC="${HEADSET_MAC:-84:AC:60:94:72:9F}"

# ============================================
# Helper functions
# ============================================

get_headset_info() {
    bluetoothctl info "$HEADSET_MAC" 2>/dev/null
}

is_headset_connected() {
    local info="$1"
    echo "$info" | grep -q "Connected: yes"
}

get_headset_name() {
    local info="$1"
    echo "$info" | grep "Name:" | cut -d ' ' -f2-
}

get_headset_battery() {
    local info="$1"
    # Battery Percentage: 0x55 (85)
    echo "$info" | grep "Battery Percentage" | awk '{print $4}' | tr -d '()%'
}

get_current_volume() {
    # Get volume from default sink using wpctl (pipewire)
    # wpctl get-volume @DEFAULT_AUDIO_SINK@ outputs: "Volume: 0.70"
    local vol_raw
    vol_raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
    
    if [[ -z "$vol_raw" ]]; then
        echo ""
        return
    fi
    
    # Check if muted
    if echo "$vol_raw" | grep -q "\[MUTED\]"; then
        echo "M"
        return
    fi
    
    # Extract volume (0.70 -> 70)
    local vol
    vol=$(echo "$vol_raw" | awk '{print $2}' | awk '{printf "%.0f", $1 * 100}')
    echo "$vol"
}

get_mic_status() {
    # Get microphone mute status
    local mic_raw
    mic_raw=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)
    
    if echo "$mic_raw" | grep -q "\[MUTED\]"; then
        echo "muted"
    else
        echo "on"
    fi
}

# ============================================
# Main logic
# ============================================

headset_info=$(get_headset_info)
volume=$(get_current_volume)
mic=$(get_mic_status)

# Build the display text and tooltip
if is_headset_connected "$headset_info"; then
    name=$(get_headset_name "$headset_info")
    battery=$(get_headset_battery "$headset_info")
    
    # Build text: battery icon + percentage, volume icon + percentage
    if [[ -n "$battery" ]]; then
        # Battery icon based on level
        if [[ "$battery" -lt 20 ]]; then
            bat_icon=""
        elif [[ "$battery" -lt 50 ]]; then
            bat_icon=""
        elif [[ "$battery" -lt 80 ]]; then
            bat_icon=""
        else
            bat_icon=""
        fi
        bat_text="${bat_icon} ${battery}%"
    else
        bat_text=""
    fi
    
    # Volume display
    if [[ "$volume" == "M" ]]; then
        vol_text="󰝟"
    elif [[ -n "$volume" ]]; then
        vol_text=" ${volume}%"
    else
        vol_text=""
    fi
    
    # Combine text
    if [[ -n "$bat_text" && -n "$vol_text" ]]; then
        text="| ${bat_text}  ${vol_text}"
    elif [[ -n "$bat_text" ]]; then
        text="| ${bat_text}"
    elif [[ -n "$vol_text" ]]; then
        text="| ${vol_text}"
    else
        text="| "
    fi
    
    # Tooltip with full info
    tooltip="${name}\nBattery: ${battery:-N/A}%\nVolume: ${volume:-N/A}%\nMic: ${mic}"
    
    # Class based on battery level
    if [[ -n "$battery" && "$battery" -lt 20 ]]; then
        class="low-battery"
    else
        class="connected"
    fi
else
    # Headset not connected - just show volume
    if [[ "$volume" == "M" ]]; then
        text="| 󰝟"
        class="muted"
    elif [[ -n "$volume" ]]; then
        text="|  ${volume}%"
        class=""
    else
        text=""
        class=""
    fi
    tooltip="Headset disconnected\nVolume: ${volume:-N/A}%\nMic: ${mic}"
fi

# Output JSON for waybar
# Escape tooltip for JSON (replace newlines with \n literal)
tooltip_escaped=$(echo -e "$tooltip" | sed ':a;N;$!ba;s/\n/\\n/g')

echo "{\"text\": \"${text}\", \"tooltip\": \"${tooltip_escaped}\", \"class\": \"${class}\"}"

#!/usr/bin/env bash
# Waybar module: CPU info (usage + temperature)
# Output: "󰍛 45% 38°C"
#
# Uses Nerd Font icons

# Temperature sensor (k10temp for AMD CPUs)
TEMP_FILE="/sys/class/hwmon/hwmon1/temp1_input"

# ============================================
# Get CPU usage percentage
# ============================================
get_cpu_usage() {
  # Read CPU stats twice with small delay
  read -r cpu user1 nice1 system1 idle1 rest1 </proc/stat
  sleep 0.2
  read -r cpu user2 nice2 system2 idle2 rest2 </proc/stat

  # Calculate differences
  idle_diff=$((idle2 - idle1))
  total1=$((user1 + nice1 + system1 + idle1))
  total2=$((user2 + nice2 + system2 + idle2))
  total_diff=$((total2 - total1))

  # Calculate usage percentage
  if [[ $total_diff -gt 0 ]]; then
    usage=$(((total_diff - idle_diff) * 100 / total_diff))
    echo "$usage"
  else
    echo "0"
  fi
}

# ============================================
# Get CPU temperature
# ============================================
get_cpu_temp() {
  if [[ -f "$TEMP_FILE" ]]; then
    temp=$(cat "$TEMP_FILE")
    echo $((temp / 1000))
  else
    echo "N/A"
  fi
}

# ============================================
# Build output
# ============================================

cpu_usage=$(get_cpu_usage)
cpu_temp=$(get_cpu_temp)

# Icon: 󰍛 (nf-md-chip)
echo "󰍛 ${cpu_usage}% 󰔏 ${cpu_temp}°C"

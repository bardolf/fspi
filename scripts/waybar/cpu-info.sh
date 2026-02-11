#!/usr/bin/env bash
# Waybar module: CPU info (usage + temperature)
# Output: "󰍛 45% 38°C"
#
# Uses Nerd Font icons
# Supports Intel (coretemp), AMD (k10temp), and thermal zones

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
# Find CPU temperature source
# ============================================
find_cpu_temp_source() {
  # Check cache first (valid for 60 seconds)
  local cache_file="/tmp/waybar-cpu-temp-source-$USER"
  if [[ -f "$cache_file" ]]; then
    local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
    if [[ $cache_age -lt 60 ]]; then
      cat "$cache_file"
      return 0
    fi
  fi

  # Priority 1: Intel coretemp
  for hwmon in /sys/class/hwmon/hwmon*/; do
    if [[ -f "${hwmon}name" ]] && [[ "$(cat "${hwmon}name" 2>/dev/null)" == "coretemp" ]]; then
      if [[ -f "${hwmon}temp1_input" ]]; then
        echo "${hwmon}temp1_input" | tee "$cache_file" >/dev/null
        cat "$cache_file"
        return 0
      fi
    fi
  done

  # Priority 2: AMD k10temp
  for hwmon in /sys/class/hwmon/hwmon*/; do
    if [[ -f "${hwmon}name" ]] && [[ "$(cat "${hwmon}name" 2>/dev/null)" == "k10temp" ]]; then
      if [[ -f "${hwmon}temp1_input" ]]; then
        echo "${hwmon}temp1_input" | tee "$cache_file" >/dev/null
        cat "$cache_file"
        return 0
      fi
    fi
  done

  # Priority 3: Fallback to thermal_zone0
  if [[ -f "/sys/class/thermal/thermal_zone0/temp" ]]; then
    echo "/sys/class/thermal/thermal_zone0/temp" | tee "$cache_file" >/dev/null
    cat "$cache_file"
    return 0
  fi

  # No temperature source found
  echo "N/A" | tee "$cache_file" >/dev/null
  echo "N/A"
  return 1
}

# ============================================
# Get CPU temperature
# ============================================
get_cpu_temp() {
  local temp_source
  temp_source=$(find_cpu_temp_source)
  
  if [[ "$temp_source" == "N/A" ]] || [[ ! -f "$temp_source" ]]; then
    echo "N/A"
  else
    local temp=$(cat "$temp_source" 2>/dev/null || echo "0")
    echo $((temp / 1000))
  fi
}

# ============================================
# Build output
# ============================================

cpu_usage=$(get_cpu_usage)
cpu_temp=$(get_cpu_temp)

# Get CPU model name
cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)

# Build bar display
bar_text="󰍛 ${cpu_usage}% 󰔏 ${cpu_temp}°C"

# Build tooltip (use printf to get actual newlines)
tooltip=$(printf "CPU: %s\nUsage: %s%%\nTemperature: %s°C" "$cpu_model" "$cpu_usage" "$cpu_temp")

# Output JSON (compact single-line with -c)
jq -nc \
  --arg text "$bar_text" \
  --arg tooltip "$tooltip" \
  '{text: $text, tooltip: $tooltip}'

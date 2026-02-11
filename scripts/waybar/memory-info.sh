#!/usr/bin/env bash
# Waybar module: Memory info
# Output: "󰘚 8G/32G 25%"
#
# Uses Nerd Font icons

# ============================================
# Get memory usage
# ============================================
get_memory_info() {
    local mem_total mem_available
    while read -r key value _; do
        case "$key" in
            MemTotal:) mem_total="$value" ;;
            MemAvailable:) mem_available="$value" ;;
        esac
    done < /proc/meminfo

    if [[ -n "$mem_total" && -n "$mem_available" && "$mem_total" -gt 0 ]]; then
        local mem_used=$((mem_total - mem_available))
        local usage=$((mem_used * 100 / mem_total))
        # Convert kB to GB (integer, rounded)
        local used_gb=$(( (mem_used + 524288) / 1048576 ))
        local total_gb=$(( (mem_total + 524288) / 1048576 ))
        echo "${used_gb}G/${total_gb}G ${usage}%"
    else
        echo "0G/0G 0%"
    fi
}

# ============================================
# Build output
# ============================================

mem_info=$(get_memory_info)

# Parse memory values for tooltip
used_gb=$(echo "$mem_info" | cut -d' ' -f1 | cut -d'/' -f1)
total_gb=$(echo "$mem_info" | cut -d' ' -f1 | cut -d'/' -f2)
usage_pct=$(echo "$mem_info" | cut -d' ' -f2)

# Calculate available
used_num=${used_gb%G}
total_num=${total_gb%G}
available_gb=$((total_num - used_num))

# Build bar display
bar_text="󰘚 ${mem_info}"

# Build tooltip (use printf to get actual newlines)
tooltip=$(printf "Memory Usage: %s\nUsed: %s\nAvailable: %sG\nTotal: %s" "$usage_pct" "$used_gb" "$available_gb" "$total_gb")

# Add swap info only if actively used
swap_used=$(awk '/SwapTotal/ {total=$2} /SwapFree/ {free=$2} END {print total-free}' /proc/meminfo)
if [[ $swap_used -gt 0 ]]; then
  swap_used_gb=$(( (swap_used + 524288) / 1048576 ))
  tooltip=$(printf "%s\nSwap Used: %sG" "$tooltip" "$swap_used_gb")
fi

# Output JSON (compact single-line with -c)
jq -nc \
  --arg text "$bar_text" \
  --arg tooltip "$tooltip" \
  '{text: $text, tooltip: $tooltip}'

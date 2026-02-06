#!/usr/bin/env bash
# Waybar module: Memory info
# Output: "󰘚 65%"
#
# Uses Nerd Font icons

# ============================================
# Get memory usage percentage
# ============================================
get_memory_usage() {
    # Read from /proc/meminfo
    while read -r key value _; do
        case "$key" in
            MemTotal:) mem_total="$value" ;;
            MemAvailable:) mem_available="$value" ;;
        esac
    done < /proc/meminfo
    
    if [[ -n "$mem_total" && -n "$mem_available" && "$mem_total" -gt 0 ]]; then
        mem_used=$((mem_total - mem_available))
        usage=$((mem_used * 100 / mem_total))
        echo "$usage"
    else
        echo "0"
    fi
}

# ============================================
# Build output
# ============================================

mem_usage=$(get_memory_usage)

# Icon: 󰘚 (nf-md-memory)
echo "󰘚 ${mem_usage}%"

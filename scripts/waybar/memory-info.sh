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

# Icon: 󰘚 (nf-md-memory)
echo "󰘚 ${mem_info}"

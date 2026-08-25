#!/usr/bin/env bash
# Waybar module: AMD GPU info (power + temperatures + VRAM)
# Output: "󰢮 78W 󰔏 61/68°C 󰘚 2.4G/8G"
#
# Uses Nerd Font icons. Reads amdgpu sysfs directly — no rocm-smi, so it stays
# cheap enough for a short interval and needs no extra packages.
#
# Prints NOTHING when there is no AMD GPU, which makes Waybar hide the module.
# The same deployed file therefore works on machines without a Radeon.

# ============================================
# Locate the amdgpu hwmon directory
# ============================================
# Sensor numbering is not stable across boots (hwmon3 here, hwmon2 elsewhere),
# so match on the driver name instead of a fixed path. Cached because the glob
# walk is the most expensive part of the whole script.
find_amdgpu_hwmon() {
  local cache_file="/tmp/waybar-gpu-hwmon-$USER"
  if [[ -f "$cache_file" ]]; then
    local cached
    cached=$(cat "$cache_file" 2>/dev/null)
    # Revalidate: a stale path after reboot must not silently blank the module.
    if [[ -n "$cached" && -f "$cached/temp1_input" ]]; then
      echo "$cached"
      return 0
    fi
  fi

  local hwmon
  for hwmon in /sys/class/drm/card*/device/hwmon/hwmon*; do
    [[ -d "$hwmon" ]] || continue
    [[ -f "$hwmon/name" ]] || continue
    if [[ "$(cat "$hwmon/name" 2>/dev/null)" == "amdgpu" ]]; then
      echo "$hwmon" | tee "$cache_file" >/dev/null
      echo "$hwmon"
      return 0
    fi
  done
  return 1
}

# ============================================
# Read a labelled temperature
# ============================================
# amdgpu exposes edge / junction / mem, but the temp*_input numbering differs
# between generations — resolve by label rather than assuming temp2 = junction.
read_temp_by_label() {
  local hwmon="$1" want="$2" label_file label
  for label_file in "$hwmon"/temp*_label; do
    [[ -f "$label_file" ]] || continue
    label=$(cat "$label_file" 2>/dev/null)
    if [[ "$label" == "$want" ]]; then
      local input="${label_file%_label}_input"
      [[ -f "$input" ]] || return 1
      local millideg
      millideg=$(cat "$input" 2>/dev/null) || return 1
      echo $(( (millideg + 500) / 1000 ))
      return 0
    fi
  done
  return 1
}

# ============================================
# Collect everything
# ============================================
HWMON=$(find_amdgpu_hwmon) || exit 0   # no Radeon → module hidden
CARD_DEV=$(dirname "$(dirname "$HWMON")")

# Power draw (µW → W). power1_average is the running mean; some cards only
# have power1_input.
power_w="N/A"
for pf in "$HWMON/power1_average" "$HWMON/power1_input"; do
  if [[ -f "$pf" ]]; then
    micro=$(cat "$pf" 2>/dev/null)
    if [[ -n "$micro" && "$micro" -gt 0 ]]; then
      power_w=$(( (micro + 500000) / 1000000 ))
      break
    fi
  fi
done

temp_edge=$(read_temp_by_label "$HWMON" edge || echo "")
temp_junction=$(read_temp_by_label "$HWMON" junction || echo "")
temp_mem=$(read_temp_by_label "$HWMON" mem || echo "")

# VRAM (bytes). Reported in MiB/GiB the way the GPU tools do.
vram_used_mib=0
vram_total_mib=0
if [[ -f "$CARD_DEV/mem_info_vram_used" && -f "$CARD_DEV/mem_info_vram_total" ]]; then
  used_b=$(cat "$CARD_DEV/mem_info_vram_used" 2>/dev/null || echo 0)
  total_b=$(cat "$CARD_DEV/mem_info_vram_total" 2>/dev/null || echo 0)
  vram_used_mib=$(( used_b / 1048576 ))
  vram_total_mib=$(( total_b / 1048576 ))
fi

# One decimal for used (it moves), integer for total (it does not).
vram_used_txt=$(awk -v m="$vram_used_mib" 'BEGIN{printf "%.1fG", m/1024}')
vram_total_txt=$(awk -v m="$vram_total_mib" 'BEGIN{printf "%.0fG", m/1024}')
vram_pct=0
[[ "$vram_total_mib" -gt 0 ]] && vram_pct=$(( vram_used_mib * 100 / vram_total_mib ))

fan_rpm=""
[[ -f "$HWMON/fan1_input" ]] && fan_rpm=$(cat "$HWMON/fan1_input" 2>/dev/null)

# GPU model — lspci is comparatively slow, so cache it for the session.
name_cache="/tmp/waybar-gpu-name-$USER"
if [[ -s "$name_cache" ]]; then
  gpu_name=$(cat "$name_cache")
else
  gpu_name=$(lspci -mm 2>/dev/null | awk -F'"' '/VGA compatible controller/ {print $6; exit}')
  [[ -z "$gpu_name" ]] && gpu_name="AMD GPU"
  printf '%s' "$gpu_name" > "$name_cache"
fi

# ============================================
# Build output
# ============================================
# Bar shows junction and memory temperature — the two that actually gate
# clocks and matter for a card under load. Edge sits in the tooltip.
temps_txt=""
if [[ -n "$temp_junction" && -n "$temp_mem" ]]; then
  temps_txt=$(printf '%2d/%2d°C' "$temp_junction" "$temp_mem")
elif [[ -n "$temp_junction" ]]; then
  temps_txt=$(printf '%2d°C' "$temp_junction")
elif [[ -n "$temp_edge" ]]; then
  temps_txt=$(printf '%2d°C' "$temp_edge")
fi

# Fixní šířky: spotřeba skáče mezi jedno- a trojcifernou hodnotou a bez
# odsazení by při každé změně posunula všechny moduly nalevo od téhle.
# Font je monospace, takže vycpávka mezerou drží konstantní šířku.
if [[ "$power_w" == "N/A" ]]; then
  power_txt="N/A"
else
  power_txt=$(printf '%3dW' "$power_w")
fi
bar_text="󰢮 ${power_txt}"
[[ -n "$temps_txt" ]] && bar_text="${bar_text} 󰔏 ${temps_txt}"
bar_text="${bar_text} 󰘚 ${vram_used_txt}/${vram_total_txt}"

tooltip=$(printf "GPU: %s\nPower: %s W" "$gpu_name" "$power_w")
[[ -n "$temp_edge" ]]     && tooltip=$(printf "%s\nTemp edge: %s°C" "$tooltip" "$temp_edge")
[[ -n "$temp_junction" ]] && tooltip=$(printf "%s\nTemp junction: %s°C" "$tooltip" "$temp_junction")
[[ -n "$temp_mem" ]]      && tooltip=$(printf "%s\nTemp memory: %s°C" "$tooltip" "$temp_mem")
tooltip=$(printf "%s\nVRAM: %s / %s (%s%%)" "$tooltip" "$vram_used_txt" "$vram_total_txt" "$vram_pct")
[[ -n "$fan_rpm" ]] && tooltip=$(printf "%s\nFan: %s RPM" "$tooltip" "$fan_rpm")

# Output JSON (compact single-line with -c)
jq -nc \
  --arg text "$bar_text" \
  --arg tooltip "$tooltip" \
  '{text: $text, tooltip: $tooltip}'

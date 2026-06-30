#!/bin/bash
# Prints host-specific Chromium/Chrome command-line flags (space-separated, may
# be empty). Single source of truth for both launch_webapp.sh and
# launch_browser.sh.
#
# NVIDIA proprietary driver + Wayland triggers severe compositing artifacts in
# Chromium-based apps (black rectangles, stale tiles, bad region repaint).
# Disabling GPU *compositing* fixes it while keeping GPU rasterization, so the
# perf hit on a desktop is negligible. Gated on the driver actually being
# loaded, so non-NVIDIA machines stay fully GPU-composited and the deployed file
# is identical everywhere (no diff-check drift).

flags=()

if [[ -e /proc/driver/nvidia/version ]]; then
  flags+=(--disable-gpu-compositing)
fi

echo "${flags[*]}"

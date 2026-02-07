#!/usr/bin/env bash
# Launch calcurse in wezterm.
# Syncs with Google Calendar (via calcurse-caldav) on open and close.
# See ~/.config/calcurse/caldav/config for Google Calendar setup instructions.

CALDAV_CONFIG="$HOME/.config/calcurse/caldav/config"

# Sync before opening (silently, only if caldav is configured)
if [[ -f "$CALDAV_CONFIG" ]]; then
    calcurse-caldav >/dev/null 2>&1
fi

# Open calcurse in a floating wezterm window
flatpak run org.wezfurlong.wezterm start --always-new-process -- calcurse

# Sync after closing (silently, only if caldav is configured)
if [[ -f "$CALDAV_CONFIG" ]]; then
    calcurse-caldav >/dev/null 2>&1
fi

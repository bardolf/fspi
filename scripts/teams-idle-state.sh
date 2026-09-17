#!/usr/bin/env bash
set -euo pipefail

# Drive Teams presence from sway's idle timers: `inactive` flips Teams to Away,
# `active` puts the pre-idle status back. Called from
# ~/.config/sway/config.d/90-swayidle.conf (timeout / resume).
#
# Why a file at all: teams-for-linux asks Electron's powerMonitor for the idle
# state, and under sway that answer is always "active" — Chromium's Linux idle
# query needs either X11's XScreenSaver extension (we run the Wayland ozone
# backend) or an org.freedesktop.ScreenSaver owner on the session bus, and
# nothing in this session owns that name. So `awayOnSystemIdle` alone never
# fires and Teams stays green all night. teams-for-linux's answer is
# `idleDetection.forceState`, where the app polls this file instead and only
# falls back to powerMonitor when the file is absent.
#
# The path must stay under $HOME and in sync with
# config/teams-for-linux/config.json. Upstream's default lives in /tmp, which
# cannot work for the flatpak: the sandbox gets a private /tmp, so anything
# written there by sway is invisible to the app. $HOME is shared both ways.
#
# The app polls every appIdleTimeoutCheckInterval (10s) while active and every
# appActiveCheckInterval (2s) while idle, so Away lags by up to ~10s and the
# return to Available is near-instant. teams-for-linux deletes this file when
# it quits; absent means "no override", which is the right default.

STATE_FILE="$HOME/.local/state/teams-for-linux-idle-state"

if [[ $# -ne 1 || ( "$1" != "active" && "$1" != "inactive" ) ]]; then
  echo "Usage: $(basename "$0") {active|inactive}" >&2
  exit 2
fi

mkdir -p "$(dirname "$STATE_FILE")"
printf '%s\n' "$1" >"$STATE_FILE"

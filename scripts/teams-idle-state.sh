#!/usr/bin/env bash
set -euo pipefail

# Owns the teams-for-linux idle state file: `inactive` makes Teams go Away,
# `active` puts the pre-idle status back, `status` prints what the file says.
# Driven every interval by teams-presence-watcher.sh; also the thing to run by
# hand when testing.
#
# Why the file exists at all: teams-for-linux asks Electron's powerMonitor for
# the idle state, and under sway that answer is always "active" — Chromium's
# Linux idle query needs either X11's XScreenSaver extension (we run the
# Wayland ozone backend) or an org.freedesktop.ScreenSaver owner on the session
# bus, and nothing in this session owns that name. So `awayOnSystemIdle` alone
# never fires and Teams stays green all night. teams-for-linux's answer is
# `idleDetection.forceState`, where the app polls this file instead and only
# falls back to powerMonitor when the file is absent.
#
# The path must stay under $HOME and in sync with
# config/teams-for-linux/config.json. Upstream's default lives in /tmp, which
# cannot work for the flatpak: the sandbox gets a private /tmp, so anything
# written there by the host is invisible to the app. $HOME is shared both ways.
#
# The app polls every appIdleTimeoutCheckInterval (10s) while it thinks we are
# active and every appActiveCheckInterval (2s) while it thinks we are idle, so
# Away lags the file by up to ~10s. How long Teams then takes to publish the
# change to everyone else is Microsoft's side and not ours: a quick there-and-
# back measured ~8s, a return from a multi-minute Away took about a minute.
#
# teams-for-linux deletes this file when it exits cleanly; absent means "no
# override", which is the right default. The watcher compares against the file
# rather than against a remembered value precisely so that deletion heals.

STATE_FILE="$HOME/.local/state/teams-for-linux-idle-state"

case "${1-}" in
active | inactive)
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '%s\n' "$1" >"$STATE_FILE"
  ;;
status)
  # `absent` rather than an empty line, so callers can tell the two apart.
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
  else
    echo absent
  fi
  ;;
*)
  echo "Usage: $(basename "$0") {active|inactive|status}" >&2
  exit 2
  ;;
esac

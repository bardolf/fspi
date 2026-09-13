#!/usr/bin/env bash
set -euo pipefail

# Restart WirePlumber once at login if an ALSA card came up with no profiles.
#
# The tell-tale state is a card that `pactl list cards` prints WITHOUT an
# "Active Profile:" line, while pipewire-pulse logs:
#
#   mod.protocol-pulse: card N port 0 profiles inconsistent (0 < 1)
#
# The card object exists and even carries its port, but ACP's EnumProfile came
# back empty, so pa_card_info.active_profile resolves to NULL. That is legal in
# the PulseAudio API and most clients cope. The Steam client does not: its
# bundled libaudio.so dereferences the pointer in the
# pa_context_get_card_info_list callback and segfaults during startup, before
# it can launch anything:
#
#   #0 libaudio.so                              <- Steam's callback, NULL deref
#   #1 context_get_card_info_callback  libpulse.so.0
#   #2 run_action                      libpulsecommon-17.0.so
#
# Steam self-updates outside dnf, so waiting for a fix there is not a plan.
#
# On this box it is the Microsoft LifeCam HD-5000 (a capture-only USB card that
# is also the only working microphone) that lands in that state, intermittently
# and only at boot: seen 2026-09-06 and 2026-09-13, with every boot in between
# clean. Restarting WirePlumber always cures it — the ACP probe then enumerates
# off / pro-audio / input:mono-fallback normally and the mic reappears as a
# source. It is not reproducible on demand: twelve consecutive WirePlumber
# restarts probed the card correctly every time, so this is a cold-boot timing
# flake inside the ACP probe, not a configuration problem. Hence a guard rather
# than a fix.
#
# Deliberately generic: it keys off "card with no active profile", not off the
# webcam, because that state kills Steam whichever card produces it.
#
# Runs from audio-card-profile-guard.service at login, when nothing is playing
# yet and a WirePlumber restart costs nothing. Mid-session the same cure is
# `systemctl --user restart wireplumber`, but clients that were connected do
# not all reattach (Teams loses its streams silently), which is why the guard
# refuses to do it on its own once streams exist.

WAIT_STACK_SECS=30
SETTLE_SECS=2
SETTLE_TRIES=8

# --- waiting for the audio stack ----------------------------------------

wait_for_pulse() {
  local waited=0
  while ! pactl info >/dev/null 2>&1; do
    ((waited >= WAIT_STACK_SECS)) && return 1
    sleep 1
    waited=$((waited + 1))
  done
  return 0
}

# Cards are created one by one as WirePlumber walks the udev list, so a single
# early sample can miss the card that is about to break. Wait for the count to
# hold still instead of guessing a delay.
wait_for_cards_to_settle() {
  local previous="" current tries=0
  while ((tries < SETTLE_TRIES)); do
    current=$(pactl list short cards 2>/dev/null | wc -l)
    [[ "$current" == "$previous" && "$current" != "0" ]] && return 0
    previous="$current"
    sleep "$SETTLE_SECS"
    tries=$((tries + 1))
  done
  return 0
}

# --- the check -----------------------------------------------------------

# Prints the device.name of every card that has no "Active Profile:" line.
cards_without_profile() {
  pactl list cards 2>/dev/null | awk '
    /^Card #/            { if (name != "" && !active) print name; name = ""; active = 0 }
    /^\tName: /          { name = $2 }
    /^\tActive Profile:/ { active = 1 }
    END                  { if (name != "" && !active) print name }
  '
}

streams_running() {
  local n
  n=$(pactl list short sink-inputs source-outputs 2>/dev/null | wc -l)
  ((n > 0))
}

# --- main ----------------------------------------------------------------

if ! wait_for_pulse; then
  echo "pipewire-pulse did not answer within ${WAIT_STACK_SECS}s — nothing to check" >&2
  exit 1
fi

wait_for_cards_to_settle

broken=$(cards_without_profile)
if [[ -z "$broken" ]]; then
  echo "All ALSA cards enumerated a profile"
  exit 0
fi

echo "Card(s) with an empty profile list — Steam would segfault on this:"
awk '{ print "  " $0 }' <<<"$broken"

if streams_running; then
  echo "Streams are running, not restarting WirePlumber. Fix it by hand with:" >&2
  echo "  systemctl --user restart wireplumber" >&2
  exit 1
fi

echo "Restarting wireplumber to re-probe"
systemctl --user restart wireplumber

if ! wait_for_pulse; then
  echo "pipewire-pulse did not come back within ${WAIT_STACK_SECS}s" >&2
  exit 1
fi
wait_for_cards_to_settle

broken=$(cards_without_profile)
if [[ -z "$broken" ]]; then
  echo "Profiles enumerated after the restart"
  exit 0
fi

echo "Still without a profile after the restart:" >&2
awk '{ print "  " $0 }' <<<"$broken" >&2
echo "Re-probe by hand and capture the ACP log with:" >&2
echo "  systemctl --user set-environment WIREPLUMBER_DEBUG=D,acp:5,alsa:5" >&2
echo "  systemctl --user restart wireplumber" >&2
echo "  journalctl --user -t wireplumber -b | grep -A5 'probe card'" >&2
exit 1

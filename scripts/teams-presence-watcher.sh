#!/usr/bin/env bash
set -euo pipefail

# Keep Teams presence in step with the screen lock by polling, rather than by
# hanging the presence writes off swayidle's timeout/resume events.
#
# Why polling. The state file is an override that wins over everything, so a
# wrong value in it is sticky, and swayidle's `resume` only fires when its own
# `timeout` fired first. Anything that writes `inactive` outside that pair — a
# hand-edit while sitting at the desk, or teams-for-linux getting SIGKILLed
# while idle so its cleanup never runs and the file survives into the next
# start — pins the status to Away with nothing in the session able to correct
# it. This loop re-derives the answer from scratch every interval and compares
# it against the file's real contents, so any drift heals within one cycle.
#
# Why the lock rather than idle time. "Seconds since the last keypress" cannot
# be polled on sway: ext-idle-notify-v1 is subscribe-only, sway never populates
# logind's IdleHint (it reads 0 even after minutes of idle) and no idle-time
# tool is installed. The lock is the signal that matters anyway — being
# unlocked means someone is here, and swayidle locks after $lock_timeout, so
# the moment Away arrives is unchanged from the old event-driven version.
#
# Deliberately independent of sway: nothing here opens a Wayland connection, so
# the unit needs no graphical-session ordering, and a dead swayidle degrades to
# "unlocked, therefore present" instead of to a stuck state.
#
# There is no ExecStopPost writing `active` on the unit. It would fire on
# Restart=on-failure too, flipping a genuinely-away session to Available for
# one interval, which is the wrong direction to fail in. A stop while locked
# can only be reached deliberately, and the next start corrects it anyway.

STATE_CMD="$HOME/scripts/teams-idle-state.sh"
INTERVAL="${TEAMS_PRESENCE_INTERVAL:-30}"

# pidof, not pgrep -x: /proc/PID/comm is truncated to 15 chars and
# "swaylock-effects" is 16, so pgrep/pkill -x against the full name never
# match. Stock swaylock is checked too — sway-config-fedora keeps it installed
# and any lock path that reached for it should count the same.
locked() {
  pidof -q swaylock-effects swaylock
}

while :; do
  if locked; then
    desired=inactive
  else
    desired=active
  fi

  current=$("$STATE_CMD" status)
  if [[ "$current" != "$desired" ]]; then
    "$STATE_CMD" "$desired"
    echo "state -> $desired (was $current)"
  fi

  sleep "$INTERVAL"
done

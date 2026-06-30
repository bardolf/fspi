#!/bin/bash
# Vivaldi launcher used by the vivaldi-stable.desktop override. Injects
# host-specific Chromium flags (see chromium_host_flags.sh) ahead of whatever
# the desktop action passes (%U, --new-window, --incognito). On machines that
# don't need the workaround it adds nothing and behaves like a plain launch.

DIR=$(dirname "$(readlink -f "$0")")
read -ra EXTRA <<< "$("$DIR/chromium_host_flags.sh")"

exec /usr/bin/vivaldi-stable "${EXTRA[@]}" "$@"

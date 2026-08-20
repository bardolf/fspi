#!/usr/bin/env bash
# Clipboard history picker on top of clipman's history file.
#
#   Enter      — copy the entry and paste it into the window underneath
#   Ctrl+Enter — copy only, do not paste
#   Delete     — remove the entry from the history and stay in the list
#
# clipman's own `pick -t rofi` cannot do any of that: it owns the rofi
# invocation, so there is no way to hand rofi extra keybindings. We render the
# list ourselves and edit the JSON history directly instead.
set -euo pipefail

HIST_FILE="${CLIPMAN_HISTFILE:-$HOME/.local/share/clipman.json}"
MAX_ITEMS="${CLIPMAN_MAX_ITEMS:-50}"

# Pasting has to wait for the compositor to hand focus back to the window that
# was underneath rofi, otherwise the keystroke lands nowhere.
FOCUS_DELAY="${CLIPMAN_FOCUS_DELAY:-0.15}"

# Matches the $mod+v binding in the sway config.
paste_into_focused_window() {
  sleep "$FOCUS_DELAY"
  wtype -M shift -k Insert
}

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send -a "Clipboard" "$1" "${2:-}"
}

# Newest first, capped at MAX_ITEMS, NUL-separated so multiline entries survive.
list_items() {
  python3 - "$HIST_FILE" "$MAX_ITEMS" <<'PY'
import json, sys

path, limit = sys.argv[1], int(sys.argv[2])
try:
    with open(path, encoding="utf-8") as fh:
        items = json.load(fh)
except (OSError, ValueError):
    items = []

out = sys.stdout.buffer
for item in list(reversed(items))[:limit]:
    if isinstance(item, str):
        out.write(item.encode("utf-8") + b"\0")
PY
}

# Drop the entry given on stdin. The history is re-read here rather than reusing
# the snapshot from list_items, so a concurrent `clipman store` is not clobbered.
# The script goes through `-c` so that stdin stays free for the entry itself.
delete_item() {
  local script
  script=$(
    cat <<'PY'
import json, os, sys, tempfile

path = sys.argv[1]
victim = sys.stdin.buffer.read().decode("utf-8")

with open(path, encoding="utf-8") as fh:
    items = json.load(fh)

kept = [item for item in items if item != victim]
if len(kept) == len(items):
    sys.exit(1)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".clipman-", suffix=".json")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(kept, fh, ensure_ascii=False)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
except BaseException:
    os.unlink(tmp)
    raise
PY
  )
  python3 -c "$script" "$HIST_FILE"
}

if [[ ! -s "$HIST_FILE" ]]; then
  notify "Clipboard history is empty"
  exit 0
fi

while true; do
  mapfile -d '' -t items < <(list_items)
  if ((${#items[@]} == 0)); then
    notify "Clipboard history is empty"
    exit 0
  fi

  # One rofi row per entry: newlines and tabs shown as escapes, like clipman does.
  rows=()
  for item in "${items[@]}"; do
    row=${item//$'\r'/}
    row=${row//$'\n'/\\n}
    row=${row//$'\t'/\\t}
    rows+=("$row")
  done

  status=0
  index=$(printf '%s\n' "${rows[@]}" | rofi -dmenu -i \
    -p "Clipboard" \
    -mesg "Enter: paste — Ctrl+Enter: copy only — Delete: remove entry" \
    -format i \
    -no-custom \
    -kb-remove-char-forward "" \
    -kb-accept-custom "" \
    -kb-custom-1 "Delete" \
    -kb-custom-2 "Control+Return") || status=$?

  # Bail out on Escape, and on anything that is not a usable row index
  # (a bare -1 would otherwise index the array from the end).
  [[ "$index" =~ ^[0-9]+$ ]] || exit 0
  ((index < ${#items[@]})) || exit 0

  case "$status" in
    0)
      printf '%s' "${items[index]}" | wl-copy
      paste_into_focused_window
      exit 0
      ;;
    11)
      printf '%s' "${items[index]}" | wl-copy
      exit 0
      ;;
    10)
      printf '%s' "${items[index]}" | delete_item ||
        notify "Could not remove that entry" "It is no longer in the history."
      ;;
    *)
      exit 0
      ;;
  esac
done

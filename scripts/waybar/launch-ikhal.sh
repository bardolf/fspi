#!/usr/bin/env bash
TERMINAL="${TERMINAL:-$(command -v ghostty || command -v foot || command -v xterm)}"
exec "$TERMINAL" -e ikhal

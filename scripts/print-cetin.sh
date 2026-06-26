#!/usr/bin/env bash
set -euo pipefail

# print-cetin.sh — print a document to the CETIN office printer with the
# options I usually pick by hand: page range, duplex mode, N pages per sheet,
# on A4. Needs the CETIN VPN up (queue 'cetin' talks SMB to printer.ad.cetin).

PRINTER=cetin
PAGES=""
DUPLEX=short        # short | long | none
NUP=2               # 1 | 2 | 4
COPIES=1
MEDIA=A4

usage() {
  cat <<'EOF'
Usage: print-cetin.sh [options] <file>

  -p, --pages RANGE    page range, e.g. 1-46 or 1-4,7,9 (default: all pages)
  -d, --duplex MODE    short | long | none            (default: short)
  -n, --nup N          pages per sheet: 1 | 2 | 4      (default: 2)
  -c, --copies N       number of copies                (default: 1)
  -P, --printer NAME   target CUPS queue               (default: cetin)
  -m, --media SIZE     paper size                       (default: A4)
  -h, --help           show this help

Examples:
  print-cetin.sh report.pdf                  # all pages, 2-up, short-edge duplex
  print-cetin.sh -p 1-46 report.pdf          # only pages 1-46
  print-cetin.sh -d none -n 1 letter.pdf     # single-sided, one page per sheet
  print-cetin.sh -d long -n 4 -c 2 slides.pdf
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--pages)   PAGES="${2:?--pages needs a value}"; shift 2 ;;
    -d|--duplex)  DUPLEX="${2:?--duplex needs a value}"; shift 2 ;;
    -n|--nup)     NUP="${2:?--nup needs a value}"; shift 2 ;;
    -c|--copies)  COPIES="${2:?--copies needs a value}"; shift 2 ;;
    -P|--printer) PRINTER="${2:?--printer needs a value}"; shift 2 ;;
    -m|--media)   MEDIA="${2:?--media needs a value}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    --)           shift; break ;;
    -*)           echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *)            break ;;
  esac
done

FILE="${1:-}"
[[ -n "$FILE" ]] || { echo "Error: no file given." >&2; usage >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "Error: file not found: $FILE" >&2; exit 1; }

case "$DUPLEX" in
  short) SIDES=two-sided-short-edge ;;
  long)  SIDES=two-sided-long-edge ;;
  none)  SIDES=one-sided ;;
  *) echo "Error: --duplex must be short|long|none (got: $DUPLEX)" >&2; exit 1 ;;
esac

case "$NUP" in
  1|2|4) ;;
  *) echo "Error: --nup must be 1|2|4 (got: $NUP)" >&2; exit 1 ;;
esac

if ! lpstat -p "$PRINTER" >/dev/null 2>&1; then
  echo "Warning: queue '$PRINTER' not found — set it up with optional/printer-cetin." >&2
fi

# Page selection. CUPS applies page-ranges AFTER number-up imposition, so with
# -n>1 a CUPS-side range selects imposed sheets, not source pages (e.g.
# `-p 1-4 -n 2` would print original pages 1-8). Extract the range from the PDF
# ourselves so -p always means original document pages.
REQ_PAGES="$PAGES"
ORIG_FILE="$FILE"
CLEANUP=""
trap '[[ -n "$CLEANUP" ]] && rm -f "$CLEANUP"' EXIT

is_pdf() {
  [[ "${1,,}" == *.pdf ]] && return 0
  [[ "$(file -b --mime-type "$1" 2>/dev/null)" == application/pdf ]]
}

if [[ -n "$PAGES" ]]; then
  if command -v mutool >/dev/null 2>&1 && is_pdf "$FILE"; then
    CLEANUP="$(mktemp --suffix=.pdf)"
    if ! mutool merge -o "$CLEANUP" "$FILE" "$PAGES" 2>/dev/null; then
      echo "Error: could not extract pages '$PAGES' from $FILE" >&2
      exit 1
    fi
    FILE="$CLEANUP"
    PAGES=""   # already applied; must NOT also hand it to CUPS
  else
    echo "Warning: passing page range to CUPS as-is (not a PDF, or mutool missing);" >&2
    echo "         with -n>1 it may count imposed sheets, not source pages." >&2
  fi
fi

opts=(-d "$PRINTER" -n "$COPIES"
      -o "media=$MEDIA"
      -o "sides=$SIDES"
      -o "number-up=$NUP")
[[ -n "$PAGES" ]] && opts+=(-o "page-ranges=$PAGES")

echo "Printing '$ORIG_FILE' -> $PRINTER (pages=${REQ_PAGES:-all}, duplex=$DUPLEX, ${NUP}-up, copies=$COPIES, $MEDIA)"
lp "${opts[@]}" "$FILE"

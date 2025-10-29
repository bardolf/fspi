#!/bin/bash
# ovládání bluetooth headsetu APW Mesa ANC (AWC)

CARD="bluez_card.84_AC_60_94_72_9F"

# mapování profilů
A2DP="a2dp-sink"
HSP="headset-head-unit"

# přečti argument
TARGET="$1"

# získej aktuální profil
CURRENT=$(pactl list cards | grep -A20 "$CARD" | grep "Active Profile:" | awk '{print $3}')

if [[ -z "$TARGET" ]]; then
  # bez parametru přepni na opačný
  if [[ "$CURRENT" == "$A2DP"* ]]; then
    TARGET="hsp"
  else
    TARGET="a2dp"
  fi
fi

case "$TARGET" in
a2dp)
  pactl set-card-profile "$CARD" "$A2DP"
  echo "AWC přepnuto na A2DP (HiFi)"
  ;;
hsp)
  pactl set-card-profile "$CARD" "$HSP"
  echo "AWC přepnuto na Headset (s mikrofonem)"
  ;;
*)
  echo "Použití: $0 [a2dp|hsp]"
  exit 1
  ;;
esac

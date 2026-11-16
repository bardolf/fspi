#!/usr/bin/env bash
# CETIN CA do cacerts každého JDK z mise. Temurin si nese vlastní truststore
# a systémový /etc/pki nečte, takže bez toho Java nevěří artifactory.cetin,
# devops.cetin ani Harboru (makalu README: "Add CETIN CA certificates").
#
# Zdroj certifikátů jsou systémové kotvy, kam je dává fspi step 00d
# (files/certs/*.crt) — skript tak nezávisí na tom, kde leží repo.
# Spouští ho mise hook postinstall (config/mise/config.toml), step 19d a dá
# se pustit ručně kdykoli; co už v JDK je (podle otisku SHA-256), přeskočí.
#
#   jdk-cetin-certs.sh                  všechna JDK z mise
#   jdk-cetin-certs.sh <JAVA_HOME>...   jen vybraná JDK
set -euo pipefail

ANCHORS=/etc/pki/ca-trust/source/anchors
MISE_JAVA="${MISE_DATA_DIR:-$HOME/.local/share/mise}/installs/java"
STOREPASS=changeit

# Z hooku: nic nedělat, pokud mise právě neinstalovalo Javu
if [[ -n "${MISE_INSTALLED_TOOLS:-}" && "$MISE_INSTALLED_TOOLS" != *'"name":"java"'* ]]; then
  exit 0
fi

shopt -s nullglob nocaseglob
certs=("$ANCHORS"/*cetin*.crt)
shopt -u nocaseglob
if ((${#certs[@]} == 0)); then
  exit 0 # stroj bez CETIN CA (step 00d neproběhl) — není co přidávat
fi

if (($# > 0)); then
  jdks=("$@")
else
  jdks=()
  for d in "$MISE_JAVA"/*/; do
    [[ -L "${d%/}" ]] || jdks+=("${d%/}") # 25, latest… jsou jen symlinky mise
  done
fi

added=0
for jh in "${jdks[@]}"; do
  ks="$jh/lib/security/cacerts"
  [[ -f "$ks" ]] || ks="$jh/jre/lib/security/cacerts" # JDK 8
  kt="$jh/bin/keytool"
  if [[ ! -f "$ks" || ! -x "$kt" ]]; then
    echo "jdk-cetin-certs: skipping $jh (no cacerts/keytool)" >&2
    continue
  fi
  present=$("$kt" -list -keystore "$ks" -storepass "$STOREPASS" 2>/dev/null | grep -oE '([0-9A-F]{2}:){31}[0-9A-F]{2}' || true)
  for c in "${certs[@]}"; do
    fp=$(openssl x509 -in "$c" -noout -fingerprint -sha256 | cut -d= -f2)
    grep -qx "$fp" <<<"$present" && continue
    alias="fspi-$(basename "$c" .crt | tr '[:upper:]' '[:lower:]')"
    "$kt" -importcert -noprompt -keystore "$ks" -storepass "$STOREPASS" -alias "$alias" -file "$c" >/dev/null
    echo "jdk-cetin-certs: $(basename "$c") -> $(basename "$jh")"
    ((added++)) || true
  done
done

if [[ -t 1 ]] && ((added == 0)); then
  echo "jdk-cetin-certs: all ${#jdks[@]} JDK(s) already trust the ${#certs[@]} CETIN CA cert(s)"
fi

#!/usr/bin/env bash
# "~/…" je v celém skriptu doslovný text ze secrets.list, ne cesta k expanzi.
# shellcheck disable=SC2088
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

# Inventář tajemství mimo repo (secrets.list): co na stroji je, doplnění
# z jiného stroje přes ssh a hledání tajemství, která v seznamu chybí.
# Nikdy nevypisuje obsah, jen cesty.

LIST="$SCRIPT_DIR/secrets.list"

# Smyčky přes seznam čtou z fd 3: ssh uvnitř by jinak spolklo stdin.

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

  status        show which secrets.list entries exist on this machine
  pull <host>   copy missing 'copy' entries from <host> over ssh (never overwrites;
                local files that differ from <host> are only reported)
  scan          list secret-looking files that secrets.list does not mention yet

Entries and their meaning: see the header of secrets.list.
EOF
}

# --- secrets.list → řádky "režim<TAB>cesta<TAB>popis" (cesta tak, jak je v listu) ---
entries() {
  local mode path desc
  while read -r -u 3 mode path desc; do
    [[ -z "$mode" || "$mode" == \#* ]] && continue
    case "$mode" in
    copy | local | ignore) ;;
    *)
      log_error "secrets.list: unknown mode '$mode' for $path"
      exit 1
      ;;
    esac
    printf '%s\t%s\t%s\n' "$mode" "$path" "$desc"
  done 3<"$LIST"
}

# ~/x → $HOME/x (lokálně)
local_path() { [[ "$1" == "~/"* ]] && echo "$HOME/${1#\~/}" || echo "$1"; }
# ~/x → x (vzdáleně: rsync i ssh berou relativní cestu od domova)
remote_path() { [[ "$1" == "~/"* ]] && echo "${1#\~/}" || echo "$1"; }
is_system() { [[ "$1" == /* ]]; }

# /etc/... bývá čitelné jen pro roota (system-connections, cifs-credentials)
local_exists() {
  if is_system "$1"; then sudo -n test -e "$1" 2>/dev/null; else [[ -e "$1" ]]; fi
}

# Šablony, které nasazují samy stepy, nejsou tajemství, jen místo pro něj:
# step 25 seeduje PASTE_…_HERE, optional/samba a printer-cetin *.cred s prázdným
# password=. Takový soubor se počítá jako chybějící a pull ho smí nahradit.
is_placeholder() {
  local f="$1" s=()
  is_system "$f" && s=(sudo -n)
  "${s[@]}" grep -q 'PASTE_[A-Z_]*_HERE' "$f" 2>/dev/null && return 0
  [[ "$f" == *.cred ]] && ! "${s[@]}" grep -Eq '^password=.+' "$f" 2>/dev/null && return 0
  return 1
}

# Soubor nebo adresář, ve kterém je aspoň jedna šablona
has_placeholder() {
  local p="$1" s=() f
  is_system "$p" && s=(sudo -n)
  while IFS= read -r -d '' f; do
    is_placeholder "$f" && return 0
  done < <("${s[@]}" find "$p" -type f -print0 2>/dev/null)
  return 1
}

# =========================================================
# status
# =========================================================

cmd_status() {
  local mode path desc lp lp_ok note present=0 missing=0
  while IFS=$'\t' read -r -u 3 mode path desc; do
    [[ "$mode" == ignore ]] && continue
    lp=$(local_path "$path")
    note=""
    if [[ "$path" == "~/.gnupg" ]]; then
      # Adresář existuje i bez klíče — rozhoduje, jestli je tu nějaký privátní klíč
      gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:' && lp_ok=1 || lp_ok=0
    elif local_exists "$lp"; then
      lp_ok=1
      if has_placeholder "$lp"; then
        lp_ok=0 note=" (only a placeholder template)"
      fi
    else
      lp_ok=0
    fi
    if ((lp_ok)); then
      ((present++)) || true
      log_debug "[OK]      $path"
    else
      ((missing++)) || true
      if [[ "$mode" == copy ]]; then
        echo -e "  ${COLOR_WARN}[MISSING]${COLOR_RESET} $path$note  — $desc"
      else
        echo -e "  ${COLOR_INFO}[LOCAL]${COLOR_RESET}   $path  — $desc"
      fi
    fi
  done 3< <(entries)
  echo ""
  echo "  $present present, $missing missing  (DEBUG=1 lists present ones too)"
  echo "  [MISSING] → ./secrets.sh pull <host>   [LOCAL] → create on this machine, see description"
}

# =========================================================
# pull
# =========================================================

pull_gnupg() {
  local host="$1" remote_fprs local_fprs fpr need=0
  remote_fprs=$(ssh -o BatchMode=yes "$host" 'gpg --list-secret-keys --with-colons 2>/dev/null' | awk -F: '$1=="fpr"{print $10}')
  if [[ -z "$remote_fprs" ]]; then
    log_debug "~/.gnupg: no secret keys on $host"
    return
  fi
  local_fprs=$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '$1=="fpr"{print $10}' || true)
  for fpr in $remote_fprs; do
    grep -qx "$fpr" <<<"$local_fprs" || need=1
  done
  if ((!need)); then
    log_debug "[OK]      ~/.gnupg (all secret keys from $host present)"
    return
  fi
  # Celý ~/.gnupg kopírovat nejde (přepsal by místní keybox/trustdb). Privátní
  # klíče jsou soubory agenta, zbytek se přenese přes export/import — veřejné
  # klíče ani ownertrust heslo ke klíči nepotřebují, takže to jde bez pinentry.
  log_info "Importing GPG secret keys from $host"
  mkdir -p "$HOME/.gnupg/private-keys-v1.d"
  chmod 700 "$HOME/.gnupg" "$HOME/.gnupg/private-keys-v1.d"
  rsync -a --ignore-existing "$host:.gnupg/private-keys-v1.d/" "$HOME/.gnupg/private-keys-v1.d/"
  ssh -o BatchMode=yes "$host" 'gpg --export --armor' | gpg --batch --quiet --import
  ssh -o BatchMode=yes "$host" 'gpg --export-ownertrust' | gpg --batch --quiet --import-ownertrust
  ((copied++)) || true
}

cmd_pull() {
  local host="${1:-}"
  if [[ -z "$host" ]]; then
    usage
    exit 1
  fi
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" true || {
    log_error "Cannot ssh to $host without a password (BatchMode)"
    exit 1
  }

  local mode path desc rel root rcd rsudo lsudo proj remote_sums local_sums missing changed f kept
  copied=0 differ=0 absent=0 ok=0
  while IFS=$'\t' read -r -u 3 mode path desc; do
    [[ "$mode" == copy ]] || continue
    if [[ "$path" == "~/.gnupg" ]]; then
      pull_gnupg "$host"
      continue
    fi

    # Přenáší se tarem přes ssh, ne rsyncem: u /etc musí mít sudo jen tar na
    # obou koncích, ssh pořád běží jako uživatel (root tu klíč na host nemá).
    if is_system "$path"; then
      root=/ rcd=/ rel=${path#/} rsudo="sudo -n" lsudo=(sudo -n)
    else
      root=$HOME rcd=. rel=$(remote_path "$path") rsudo="" lsudo=()
    fi

    # Projekt, který tu (zatím) není, nezakládat — git clone by pak narazil
    if [[ "$path" == "~/projects/"* ]]; then
      proj=${rel#projects/}
      proj=${proj%%/*}
      if [[ ! -d "$HOME/projects/$proj" ]]; then
        log_debug "[SKIP]    $path (project $proj not on this machine)"
        continue
      fi
    fi

    # -L / tar -h: položka smí být symlink (~/work/cetin/vpn → aktuální YYYY_MM_vpn),
    # přenese se obsah cíle, takže cesta v listu přežije výměnu certifikátu.
    remote_sums=$(ssh -o BatchMode=yes "$host" "cd $rcd && $rsudo find -L '$rel' -type f -exec sha256sum {} + 2>/dev/null" || true)
    if [[ -z "$remote_sums" ]]; then
      ((absent++)) || true
      log_debug "[ABSENT]  $path (not on $host)"
      continue
    fi
    local_sums=$(cd "$root" && "${lsudo[@]}" find -L "$rel" -type f -exec sha256sum {} + 2>/dev/null || true)

    # sha256sum: 64 znaků hash, 2 mezery, cesta. Chybí tu / tu je, ale jinak:
    missing=$(awk 'NR==FNR {l[substr($0,67)]=1; next} $0 != "" && !(substr($0,67) in l) {print substr($0,67)}' \
      <(printf '%s\n' "$local_sums") <(printf '%s\n' "$remote_sums"))
    changed=$(awk 'NR==FNR {r[substr($0,67)]=substr($0,1,64); next} (substr($0,67) in r) && r[substr($0,67)] != substr($0,1,64) {print substr($0,67)}' \
      <(printf '%s\n' "$remote_sums") <(printf '%s\n' "$local_sums"))

    # Místní šablona (placeholder) se nahradí, skutečný rozdíl zůstane
    kept=""
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if is_placeholder "${root%/}/$f"; then
        "${lsudo[@]}" rm -f "${root%/}/$f"
        missing+=$'\n'"$f"
      else
        kept+="$f"$'\n'
      fi
    done <<<"$changed"
    changed=${kept%$'\n'}
    missing=$(sed '/^$/d' <<<"$missing")

    if [[ -n "$missing" ]]; then
      # --skip-old-files: existující soubory zůstanou (archiv nese jen cestu z listu, ne rodiče)
      ssh -o BatchMode=yes "$host" "cd $rcd && $rsudo tar -chf - '$rel'" |
        (cd "$root" && "${lsudo[@]}" tar -xpf - --skip-old-files)
      ((copied++)) || true
      log_info "Copied $path ($(wc -l <<<"$missing") file(s))"
    fi
    if [[ -n "$changed" ]]; then
      ((differ++)) || true
      log_warn "Differs from $host, kept local: $path"
      # shellcheck disable=SC2001
      sed "s#^#            ${root%/}/#" <<<"$changed"
    elif [[ -z "$missing" ]]; then
      ((ok++)) || true
      log_debug "[OK]      $path"
    fi
  done 3< <(entries)

  echo ""
  echo "  $copied copied, $differ differ (kept local), $ok already identical, $absent not on $host"
}

# =========================================================
# scan
# =========================================================

# Kde tajemství nehledat: cache, prohlížeče, balíčkové a build adresáře.
SCAN_PRUNE=(
  .cache .local/state .local/share/Trash .local/share/containers .local/share/claude
  .local/share/nvim .local/share/JetBrains .local/lib .var .mozilla
  .config/chromium .config/google-chrome .config/vivaldi .config/BraveSoftware
  .config/Code .config/JetBrains .vscode .vscode-shared
  .npm .bun .cargo .rustup .m2/repository .gradle/caches .gradle/wrapper .gradle/daemon
  .nuget .dotnet .java .android .platformio .espressif opt
)
SCAN_PRUNE_NAMES=(.git node_modules .venv venv build dist target __pycache__ db_backups postgres-data)

cmd_scan() {
  local -a find_args=() covered=()
  local p n mode path desc f dir
  for p in "${SCAN_PRUNE[@]}"; do find_args+=(-path "$HOME/$p" -o); done
  for n in "${SCAN_PRUNE_NAMES[@]}"; do find_args+=(-name "$n" -o); done
  find_args+=(-path "$HOME/.texlive*")

  while IFS=$'\t' read -r -u 3 mode path desc; do
    covered+=("$(local_path "$path")")
  done 3< <(entries)

  local found=0
  while IFS= read -r -d '' f; do
    # Pokryté položkou seznamu (soubor sám nebo cokoli pod adresářem)?
    for p in "${covered[@]}"; do
      [[ "$f" == "$p" || "$f" == "$p"/* ]] && continue 2
    done
    # V git repu je tajemství jen to, co git nesleduje
    dir=$(dirname "$f")
    if git -C "$dir" rev-parse --git-dir &>/dev/null &&
      git -C "$dir" ls-files --error-unmatch -- "$(basename "$f")" &>/dev/null; then
      continue
    fi
    echo "  ${f/#$HOME/\~}"
    ((found++)) || true
  done < <(find "$HOME" -maxdepth 7 \( "${find_args[@]}" \) -prune -o -type f \
    \( -iname '*token*' -o -iname '*secret*' -o -iname '*credential*' -o -name '*.cred' \
    -o -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name '*.pfx' -o -name '*.jks' \
    -o -name '*.keystore' -o -name '*.kdbx' -o -name '.netrc*' -o -name '.pgpass' \
    -o -name 'auth.json' -o -name '.npmrc' -o -name 'gradle.properties' -o -name 'rclone.conf' \
    -o -name '*.ovpn' -o -name 'id_rsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' \
    -o -name '.env' -o -name '.env.*' \) \
    ! -name '*.pub' ! -name '.env.example' ! -name '.env.sample' ! -name '.env.template' \
    -print0 2>/dev/null)

  echo ""
  if ((found)); then
    echo "  $found unlisted candidate(s) — add each to secrets.list as copy / local / ignore"
  else
    log_info "Every secret-looking file is covered by secrets.list"
  fi
}

entries >/dev/null # chyba v secrets.list ukončí skript tady, ne v subshellu

case "${1:-}" in
status) cmd_status ;;
pull) cmd_pull "${2:-}" ;;
scan) cmd_scan ;;
-h | --help | "") usage ;;
*)
  log_error "Unknown command: $1"
  usage
  exit 1
  ;;
esac

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/logging.sh"

# Nabídka volitelných komponent (optional/*/setup.sh). install.sh ji volá na
# konci, jde spustit i samostatně:
#   ./optional.sh                  přehled + výběr (v terminálu)
#   ./optional.sh fingerprint 3    rovnou spustit vybrané (jména i čísla)
# Každý optional/<jméno>/setup.sh nese hned pod shebangem dva řádky:
#   # optional: <popis na jeden řádek>
#   # installed: <shell test, exit 0 = už nainstalováno>
# Bez nich se komponenta v nabídce ukáže bez popisu a stavu.

names=() descs=() states=()
for setup in "$SCRIPT_DIR"/optional/*/setup.sh; do
  name=$(basename "$(dirname "$setup")")
  desc=$(sed -n 's/^# optional: //p' "$setup" | head -1)
  check=$(sed -n 's/^# installed: //p' "$setup" | head -1)
  state=""
  if [[ -n "$check" ]] && bash -c "$check" &>/dev/null; then
    state="installed"
  fi
  names+=("$name")
  descs+=("${desc:-(no '# optional:' line in setup.sh)}")
  states+=("$state")
done

echo ""
echo "Optional components — not run by install.sh, safe to re-run:"
for i in "${!names[@]}"; do
  printf "  %2d) %-18s %-12s %s\n" $((i + 1)) "${names[i]}" "${states[i]:+[${states[i]}]}" "${descs[i]}"
done
echo ""

picks=("$@")
if ((${#picks[@]} == 0)); then
  if [[ ! -t 0 ]]; then
    log_info "Not a terminal — nothing selected. Run ./optional.sh, or bash optional/<name>/setup.sh"
    exit 0
  fi
  read -r -p "Install which? Numbers or names separated by spaces, Enter = none: " -a picks || true
fi
if ((${#picks[@]} == 0)); then
  log_info "No optional component selected"
  exit 0
fi

failed=()
for p in "${picks[@]}"; do
  name=""
  if [[ "$p" =~ ^[0-9]+$ ]] && ((p >= 1 && p <= ${#names[@]})); then
    name=${names[p - 1]}
  else
    for n in "${names[@]}"; do [[ "$n" == "$p" ]] && name=$n; done
  fi
  if [[ -z "$name" ]]; then
    log_warn "Ignoring '$p' (not 1-${#names[@]} or a component name)"
    continue
  fi
  log_info "Running optional/$name/setup.sh"
  bash "$SCRIPT_DIR/optional/$name/setup.sh" || {
    log_error "optional/$name failed"
    failed+=("$name")
  }
done

if ((${#failed[@]} > 0)); then
  log_error "Failed optional components: ${failed[*]}"
  exit 1
fi

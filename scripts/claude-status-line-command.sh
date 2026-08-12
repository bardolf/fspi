#!/usr/bin/env bash
# Claude Code status line – globální konfigurace
# Zobrazuje: account | model | context bar | cwd | git změny

input=$(cat)

# Diagnostika: CLAUDE_STATUSLINE_DUMP=1 uloží přijatý payload, ať se dá ověřit,
# co Claude Code na stdin skutečně posílá – schéma se mezi verzemi mění.
if [ -n "$CLAUDE_STATUSLINE_DUMP" ]; then
  printf '%s' "$input" > "${TMPDIR:-/tmp}/claude-statusline-payload.json" 2>/dev/null
fi

# ---------------------------------------------------------------------------
# 1. ACCOUNT (který účet je přihlášený – kvůli přepínání mezi nimi)
# ---------------------------------------------------------------------------
# Payload na stdin identitu účtu NENESE. Ověřeno ve v2.1.228: statusline objekt
# má cwd, session_name, model, workspace, version, output_style, cost,
# context_window, exceeds_200k_tokens, fast_mode, effort, thinking, rate_limits,
# vim, agent, remote, pr, worktree – nic o účtu. Zdrojem je proto ~/.claude.json
# → .oauthAccount, což je to, co přepíše /login.
#
# Pozor na jeden důsledek: čte se stav souboru, ne token té konkrétní session.
# Když přepneš účet v jiném okně, tahle už běžící session ukáže nový účet, i když
# sama dál jede na tom původním. Po /login ve vlastním okně je to správně.
account_part=""

acct_cfg="$HOME/.claude.json"
[ -n "$CLAUDE_CONFIG_DIR" ] && [ -f "$CLAUDE_CONFIG_DIR/.claude.json" ] \
  && acct_cfg="$CLAUDE_CONFIG_DIR/.claude.json"

if [ -n "$ANTHROPIC_API_KEY" ] || [ -n "$ANTHROPIC_AUTH_TOKEN" ]; then
  # API key/token přebíjí OAuth, takže .oauthAccount by tady lhal.
  account_part=$(printf "\033[1;97;41m API-KEY \033[0m")
elif [ -f "$acct_cfg" ] && command -v jq >/dev/null 2>&1; then
  # Jedno jq volání pro obě hodnoty – status line se překresluje po každé zprávě.
  # Každá hodnota na vlastní řádek, ne @tsv do `read a b`: tabulátor je pro read
  # whitespace IFS znak, takže chybějící e-mail zahodí prázdné pole a org se
  # posune na jeho místo – pak se organizace vypíše, jako by to byl e-mail.
  { IFS= read -r acct_email; IFS= read -r acct_org; } < <(
    jq -r '.oauthAccount | (.emailAddress // ""), (.organizationName // "")' \
      "$acct_cfg" 2>/dev/null
  )

  if [ -n "$acct_email" ]; then
    # Známé účty – jméno a barva pozadí. Přidej si sem další, jak budeš přepínat.
    # Kódy barev: 44 modrá, 42 zelená, 45 magenta, 46 cyan, 43 žlutá, 100 šedá.
    # Červená (41) je vyhrazená pro API-KEY, ať se to nedá zaměnit.
    acct_bg=""
    case "$acct_email" in
      milan.nemec@cetin.cz) acct_label="CETIN"; acct_bg=44 ;;
      *)                    acct_label="${acct_email%%@*}" ;;
    esac

    # Neznámý účet dostane barvu odvozenou z e-mailu – pořád stabilní, takže i
    # nepojmenovaný účet má vždy tu svou a přepnutí si všimneš bez čtení textu.
    if [ -z "$acct_bg" ]; then
      acct_palette=(42 45 46 43 100)
      acct_hash=$(printf '%s' "$acct_email" | cksum 2>/dev/null | awk '{print $1}')
      [ -z "$acct_hash" ] && acct_hash=0
      acct_bg=${acct_palette[$((acct_hash % ${#acct_palette[@]}))]}
    fi

    account_part=$(printf "\033[1;97;%sm %s \033[0m" "$acct_bg" "$acct_label")
  elif [ -n "$acct_org" ]; then
    account_part=$(printf "\033[1;97;100m %s \033[0m" "$acct_org")
  fi
fi

# ---------------------------------------------------------------------------
# 2. CONTEXT / RATE LIMIT PROGRESS BAR
# ---------------------------------------------------------------------------
BAR_WIDTH=5

make_bar() {
  local pct="$1"
  local filled=$(echo "$pct $BAR_WIDTH" | awk '{printf "%d", int($1 / 100 * $2 + 0.5)}')
  local empty=$((BAR_WIDTH - filled))
  local bar=""
  for i in $(seq 1 $filled); do bar="${bar}█"; done
  for i in $(seq 1 $empty); do bar="${bar}░"; done
  echo "$bar"
}

# Context window (tokeny)
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
# Rate limits – 5h session a 7day týdenní
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

usage_part=""

if [ -n "$ctx_used" ]; then
  bar=$(make_bar "$ctx_used")
  ctx_int=$(printf "%.0f" "$ctx_used")
  # Barva: zelená < 60 %, žlutá < 85 %, červená >= 85 %
  if [ "$ctx_int" -ge 85 ]; then
    color="\033[31m" # svítivá červená
  elif [ "$ctx_int" -ge 80 ]; then
    color="\033[33m" # svítivá žlutá
  elif [ "$ctx_int" -ge 60 ]; then
    color="\033[2;33m" # tlumená žlutá
  else
    color="\033[2;32m" # tlumená zelená
  fi
  reset="\033[0m"
  usage_part=$(printf "${color}Ctx [%s] %d%%${reset}" "$bar" "$ctx_int")
fi

# Přidej rate limit info pokud je k dispozici
if [ -n "$five_pct" ]; then
  five_int=$(printf "%.0f" "$five_pct")
  bar5=$(make_bar "$five_pct")
  if [ "$five_int" -ge 80 ]; then
    limit_color="\033[35m" # svítivá magenta
  else
    limit_color="\033[2;35m" # tlumená magenta
  fi
  # Vypočítat zbývající čas do resetu limitu
  if [ -n "$five_reset" ]; then
    now=$(date +%s)
    remaining=$((five_reset - now))
    if [ "$remaining" -lt 0 ]; then remaining=0; fi
    hh=$((remaining / 3600))
    mm=$(((remaining % 3600) / 60))
    five_label=$(printf "%02d:%02d" "$hh" "$mm")
  else
    five_label="5h" # fallback pokud data ještě nejsou k dispozici
  fi
  if [ -n "$usage_part" ]; then
    usage_part=$(printf "%s  ${limit_color}Limit %s [%s] %d%%\033[0m" "$usage_part" "$five_label" "$bar5" "$five_int")
  else
    usage_part=$(printf "${limit_color}Limit %s [%s] %d%%\033[0m" "$five_label" "$bar5" "$five_int")
  fi
fi

# Přidej týdenní rate limit info pokud je k dispozici
if [ -n "$week_pct" ]; then
  week_int=$(printf "%.0f" "$week_pct")
  barw=$(make_bar "$week_pct")
  if [ "$week_int" -ge 80 ]; then
    week_color="\033[36m" # svítivá cyan
  else
    week_color="\033[2;36m" # tlumená cyan
  fi
  # Vypočítat zbývající čas do resetu týdenního limitu ve formátu Xd H:MM
  if [ -n "$week_reset" ]; then
    now=$(date +%s)
    w_remaining=$((week_reset - now))
    if [ "$w_remaining" -lt 0 ]; then w_remaining=0; fi
    w_days=$((w_remaining / 86400))
    w_hh=$(((w_remaining % 86400) / 3600))
    w_mm=$(((w_remaining % 3600) / 60))
    week_label=$(printf "%dd %d:%02d" "$w_days" "$w_hh" "$w_mm")
  else
    week_label="7d" # fallback pokud data ještě nejsou k dispozici
  fi
  if [ -n "$usage_part" ]; then
    usage_part=$(printf "%s  ${week_color}Weekly %s [%s] %d%%\033[0m" "$usage_part" "$week_label" "$barw" "$week_int")
  else
    usage_part=$(printf "${week_color}Weekly %s [%s] %d%%\033[0m" "$week_label" "$barw" "$week_int")
  fi
fi

# ---------------------------------------------------------------------------
# 3. MODEL + EFFORT + FAST MODE
# ---------------------------------------------------------------------------
model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
model_short=$(echo "$model_name" | sed 's/Claude //i' | sed 's/ (.*)//')

# Effort level. V payloadu je jen u modelů, které ho podporují, takže při jeho
# absenci se nic nevypisuje. Hodnota je PO případném tichém downgradu – max na
# modelu bez podpory spadne na high – takže tady je vidět skutečně použitý
# effort, ne jen to, co je nastavené. Možnosti: low, medium, high, xhigh, max.
effort_part=""
effort_level=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$effort_level" ]; then
  # Barva roste s cenou, ať si drahé nastavení nechtěně nenechám zapnuté.
  case "$effort_level" in
    low)    effort_label="low";   effort_color="\033[2;37m" ;;
    medium) effort_label="med";   effort_color="\033[2;37m" ;;
    high)   effort_label="high";  effort_color="\033[37m" ;;
    xhigh)  effort_label="xhigh"; effort_color="\033[33m" ;;
    max)    effort_label="max";   effort_color="\033[1;31m" ;;
    *)      effort_label="$effort_level"; effort_color="\033[2;37m" ;;
  esac
  effort_part=$(printf "${effort_color}%s\033[0m" "$effort_label")
fi

# Fast mode (/fast) – stejný model Opus, jen rychlejší výstup. Utrácí kredit
# rychleji a má vlastní rate limit, oddělený od těch dvou výše, takže se hodí
# vědět, že je zapnutý. Po startu session je vypnutý a přepnutí modelu ho vypne,
# takže se vypisuje jen když je aktivní – prázdno je normální stav.
fast_part=""
if [ "$(echo "$input" | jq -r '.fast_mode // false')" = "true" ]; then
  fast_part=$(printf "\033[1;33m⚡\033[0m")
fi

# ---------------------------------------------------------------------------
# 4. PRACOVNÍ ADRESÁŘ (zkrácený – max 4 segmenty od konce)
# ---------------------------------------------------------------------------
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
if [ -z "$cwd" ]; then cwd=$(pwd); fi
# Zkrátit na posledních 3 složky, předřadit ~ pokud je v $HOME
home_prefix="${HOME}"
if [[ "$cwd" == "$home_prefix"* ]]; then
  cwd="~${cwd#$home_prefix}"
fi
# Max 4 segmenty
short_cwd=$(echo "$cwd" | awk -F'/' '{
  n = NF
  if (n <= 4) { print $0 }
  else {
    out = "…"
    for (i = n-2; i <= n; i++) out = out "/" $i
    print out
  }
}')

# ---------------------------------------------------------------------------
# 5. GIT ZMĚNY V SESSION (počet změněných souborů)
# ---------------------------------------------------------------------------
git_part=""
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
if [ -z "$project_dir" ]; then project_dir="$cwd"; fi
# Rozvinout ~ pokud je potřeba
project_dir_real=$(echo "$project_dir" | sed "s|^~|$HOME|")

if [ -d "$project_dir_real" ] && git -C "$project_dir_real" rev-parse --git-dir >/dev/null 2>&1; then
  changed=$(git -C "$project_dir_real" diff --stat HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+ file' | grep -oE '[0-9]+')
  unstaged=$(git -C "$project_dir_real" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  staged=$(git -C "$project_dir_real" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  total=$((unstaged + staged))
  if [ "$total" -gt 0 ]; then
    git_part=$(printf "\033[33mGit: ~%d changes\033[0m" "$total")
  else
    git_part=$(printf "\033[2;32mGit: Clean\033[0m")
  fi
fi

# ---------------------------------------------------------------------------
# VÝSLEDNÝ ŘÁDEK
# ---------------------------------------------------------------------------
sep=$(printf "\033[90m│\033[0m")

line=""

append() {
  local part="$1"
  if [ -n "$part" ]; then
    if [ -n "$line" ]; then
      line="$line $sep $part"
    else
      line="$part"
    fi
  fi
}

append "$account_part"
# Model, fast mode a effort jsou jedna buňka – obojí je vlastnost modelu, ne
# samostatný údaj. Blesk vede, ať je vidět na první pohled, když je zapnutý.
model_cell=$(printf "\033[34m%s\033[0m" "$model_short")
if [ -n "$effort_part" ]; then
  model_cell=$(printf "%s\033[90m·\033[0m%s" "$model_cell" "$effort_part")
fi
if [ -n "$fast_part" ]; then
  model_cell="${fast_part}${model_cell}"
fi
append "$model_cell"
append "$usage_part"
append "$(printf "\033[2;33m%s\033[0m" "$short_cwd")"
[ -n "$git_part" ] && append "$git_part"

printf "%b\n" "$line"

#!/usr/bin/env bash
# PiP přehrávač pro $mod+Shift+Y (viz config/sway/config.d/50-rules-pip.conf).
# URL bere z argumentu, jinak ze schránky.
#
# Živý přenos od začátku:
# YouTube drží v HLS playlistu celý přenos (EXT-X-MEDIA-SEQUENCE:0), ale bez
# EXT-X-ENDLIST ho ffmpeg bere jako živý — nezná délku, takže dopředu jde
# skočit jen po načtenou hranici a mpv se tam musí prokousat segment po
# segmentu. googlevideo po pár stech rychlých požadavcích vrátí 403 a ffmpeg
# pak ten segment opakuje donekonečna: přehrávání zamrzne uprostřed.
#
# Proto playlist stáhneme, doplníme PLAYLIST-TYPE:VOD + ENDLIST a mpv dostane
# lokální kopii. Zná pak přesnou délku a při seeku skočí přímo na cílový
# segment, takže se nic mezitím netahá a na 403 nedojde.
#
# Snímek je ale statický a končí na živé hraně z okamžiku stažení — proto jede
# mpv s pip_resume.lua: jak playlist dojde (nebo se přehrávání rozbije), řekne
# si přes "--snapshot" o novější snímek a naváže na stejné pozici. Okno přitom
# zůstává, takže nepřeskočí na výchozí pozici.

set -euo pipefail

SELF=$(readlink -f "$0")
LUA="$(dirname "$SELF")/pip_resume.lua"

# Živé HLS formáty jsou muxované — jedna varianta, ne video+audio zvlášť.
LIVE_FORMAT="best[height<=?720]/best"
# Malé okno, 720p stačí; vyšší rozlišení jen žere CPU.
FORMAT="bestvideo[height<=?720]+bestaudio/best[height<=?720]/best"

# Playlist živého přenosu → statický VOD snímek. Volá i pip_resume.lua.
write_snapshot() {
  local video_url="$1" out="$2" playlist_url
  playlist_url=$(yt-dlp --no-warnings -f "$LIVE_FORMAT" -g "$video_url" 2>/dev/null | head -1)
  [[ -n "$playlist_url" ]] || return 1
  curl -fsS --max-time 20 "$playlist_url" -o "$out" || return 1
  # MEDIA-SEQUENCE:0 = playlist má přenos od první sekundy. Když ne, je to
  # klouzavé okno (Twitch a spol.) a přepis na VOD by uřízl i to málo, co je
  # k dispozici — takový přenos se pustí normálně na živé hraně.
  grep -q '^#EXT-X-MEDIA-SEQUENCE:0[[:space:]]*$' "$out" || return 1
  sed -i '/^#EXTM3U/a #EXT-X-PLAYLIST-TYPE:VOD' "$out"
  printf '#EXT-X-ENDLIST\n' >> "$out"
}

# Režim pro pip_resume.lua: jen přepiš snímek novějším a skonči.
if [[ "${1:-}" == "--snapshot" ]]; then
  write_snapshot "$2" "$3"
  exit
fi

URL="${1:-$(wl-paste 2>/dev/null || true)}"

if [[ -z "$URL" ]]; then
  notify-send -a pip "PiP" "Schránka je prázdná" 2>/dev/null || true
  exit 1
fi

MPV_OPTS=(
  --title=pip
  --autofit=640
  --force-seekable=yes
  --demuxer-max-back-bytes=400MiB
)

play_direct() {
  # exec nahradí shell, takže EXIT trap už neproběhne — uklidit musíme tady.
  rm -f "${snapshot:-}"
  exec mpv "${MPV_OPTS[@]}" --ytdl-format="$FORMAT" "$URL"
}

info=$(yt-dlp --no-warnings --print live_status --print title "$URL" 2>/dev/null) || info=""
live_status=$(sed -n 1p <<<"$info")
media_title=$(sed -n 2p <<<"$info")

# Cokoli jiného než běžící přenos (včetně was_live/post_live) je normální video.
[[ "$live_status" == "is_live" ]] || play_direct

snapshot=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/pip-live-XXXXXX.m3u8")
trap 'rm -f "$snapshot"' EXIT

write_snapshot "$URL" "$snapshot" || play_direct

# Lokální .m3u8 by mpv jinak přečetl vlastním parserem playlistů jako seznam
# souborů; allowed_extensions kvůli segmentům bez přípony, protocol_whitelist
# protože u lokálního playlistu ffmpeg http(s) sám nepovolí.
# --idle + --force-window drží okno naživu i mezi snímky.
PIP_URL="$URL" PIP_HELPER="$SELF" PIP_SNAPSHOT="$snapshot" \
  mpv "${MPV_OPTS[@]}" \
  --force-media-title="${media_title:-pip}" \
  --demuxer=lavf --demuxer-lavf-format=hls \
  --demuxer-lavf-o-append=allowed_extensions=ALL \
  --demuxer-lavf-o-append=protocol_whitelist=file,http,https,tcp,tls,crypto \
  --script="$LUA" \
  --idle=yes --force-window=yes \
  "$snapshot"

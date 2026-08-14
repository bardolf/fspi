#!/usr/bin/env bash
# PiP přehrávač pro $mod+Shift+Y (viz config/sway/config.d/50-rules-pip.conf).
# URL bere z argumentu, jinak ze schránky.
#
# Živý přenos od začátku:
# YouTube drží v HLS playlistu celý přenos (EXT-X-MEDIA-SEQUENCE:0), ale bez
# EXT-X-ENDLIST ho ffmpeg bere jako živý — nezná délku, takže dopředu jde
# skočit jen po načtenou hranici a mpv se tam musí prokousat segment po
# segmentu. Po ~300 rychlých požadavcích vrátí googlevideo 403 Forbidden a
# ffmpeg ten segment opakuje donekonečna: přehrávání zamrzne uprostřed a
# vypadá to, že video skončilo, i když přenos běží dál.
#
# Proto si playlist stáhneme, doplníme PLAYLIST-TYPE:VOD + ENDLIST a mpv
# dostane lokální kopii. Zná pak přesnou délku a při seeku skočí přímo na
# cílový segment, takže se nic mezitím netahá a na 403 nedojde.
# Snímek je ale statický: přenos pokračuje, tahle instance mpv skončí na živé
# hraně z okamžiku spuštění. Pro pokračování stačí spustit znovu.

set -euo pipefail

URL="${1:-$(wl-paste 2>/dev/null || true)}"

if [[ -z "$URL" ]]; then
  notify-send -a pip "PiP" "Schránka je prázdná" 2>/dev/null || true
  exit 1
fi

# Malé okno — 720p stačí, vyšší rozlišení jen žere CPU.
FORMAT="bestvideo[height<=?720]+bestaudio/best[height<=?720]/best"
# Živé HLS formáty jsou muxované, tady chceme jednu variantu, ne video+audio.
LIVE_FORMAT="best[height<=?720]/best"

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

# Jedno volání yt-dlp na všechno, co potřebujeme — extrakce je nejdražší část.
info=$(yt-dlp --no-warnings -f "$LIVE_FORMAT" \
  --print live_status --print title --print urls "$URL" 2>/dev/null) || info=""

live_status=$(sed -n 1p <<<"$info")
media_title=$(sed -n 2p <<<"$info")
playlist_url=$(sed -n 3p <<<"$info")

# Cokoli jiného než běžící přenos (včetně was_live/post_live) je normální video.
if [[ "$live_status" != "is_live" || -z "$playlist_url" ]]; then
  play_direct
fi

snapshot=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/pip-live-XXXXXX.m3u8")
trap 'rm -f "$snapshot"' EXIT

if ! curl -fsS --max-time 20 "$playlist_url" -o "$snapshot"; then
  play_direct
fi

# MEDIA-SEQUENCE:0 = playlist obsahuje přenos od první sekundy. Když ne, je to
# klouzavé okno (Twitch a spol.) a přepis na VOD by uřízl i to málo, co je
# k dispozici — takový přenos pustíme normálně na živé hraně.
if ! grep -q '^#EXT-X-MEDIA-SEQUENCE:0[[:space:]]*$' "$snapshot"; then
  play_direct
fi

sed -i '/^#EXTM3U/a #EXT-X-PLAYLIST-TYPE:VOD' "$snapshot"
printf '#EXT-X-ENDLIST\n' >> "$snapshot"

# Lokální .m3u8 by mpv jinak přečetl vlastním parserem playlistů jako seznam
# souborů; allowed_extensions kvůli segmentům bez přípony, protocol_whitelist
# protože u lokálního playlistu ffmpeg http(s) sám nepovolí.
mpv "${MPV_OPTS[@]}" \
  --force-media-title="${media_title:-pip}" \
  --demuxer=lavf --demuxer-lavf-format=hls \
  --demuxer-lavf-o-append=allowed_extensions=ALL \
  --demuxer-lavf-o-append=protocol_whitelist=file,http,https,tcp,tls,crypto \
  "$snapshot"

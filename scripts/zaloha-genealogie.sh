#!/usr/bin/env bash
# Záloha genealogie na NAS (fspi: scripts/zaloha-genealogie.sh → ~/scripts, timer files/systemd/zaloha-genealogie.*, step 33)
# (ssh `server`, /media/disk3/zaloha-genealogie):
# stromy nemec + kohakova + kniha-ukazka + knihy (vč. snímků mimo git), workbench (.env, CLAUDE.local.md)
# a dump Gramps Web (databáze + uživatelé). Snímky podle data přes rsync --link-dest
# (nezměněné soubory = hardlink na předchozí zálohu). Drží posledních KEEP záloh.
# Cache archivů (~/.cache/genealogy-workbench) se nezálohuje — dá se stáhnout znovu.
set -euo pipefail

HOST=server
DEST=/media/disk3/zaloha-genealogie
KEEP=10
TREES=/home/milan/projects/genealogy-trees
WB=/home/milan/projects/genealogy-tools
STAGE=$HOME/.cache/zaloha-genealogie
STAMP=$(date +%Y-%m-%d_%H%M)
LOG=$STAGE/zaloha.log

mkdir -p "$STAGE/gramps"
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date '+%F %T') záloha $STAMP"

# 1) Dump Gramps Web (jen čtení volume; kontejnery běží dál)
IMG=$(docker inspect gramps-web-grampsweb-1 --format '{{.Config.Image}}' 2>/dev/null || echo ghcr.io/gramps-project/grampsweb:26.10.1)
rm -f "$STAGE"/gramps/*.tar.gz
for v in gramps_db gramps_users gramps_secret; do
  docker run --rm --entrypoint tar -v "gramps-web_${v}:/data:ro" -v "$STAGE/gramps:/out" "$IMG" \
    czf "/out/${v}.tar.gz" -C /data . && echo "dump $v ok"
done
cp "$WB/infra/gramps-web/.env" "$STAGE/gramps/gramps-web.env" 2>/dev/null || true
cp "$WB/infra/gramps-web/docker-compose.yml" "$STAGE/gramps/" 2>/dev/null || true

# 2) Nová záloha vedle předchozí (hardlinky na nezměněné soubory)
ssh "$HOST" "mkdir -p '$DEST/snimky'"
PREV=$(ssh "$HOST" "[ -L '$DEST/posledni' ] && readlink -f '$DEST/posledni' || true")
# --link-dest musí ukazovat na stejnou podsložku jako cíl (genealogy-trees), jinak se nic nepropojí
LINK=(); [ -n "$PREV" ] && LINK=(--link-dest="$PREV/genealogy-trees")
NEW="$DEST/snimky/$STAMP"
ssh "$HOST" "mkdir -p '$NEW/genealogy-trees' '$NEW/gramps-web' '$NEW/workbench'"

RS=(rsync -aH --info=stats1 --exclude='__pycache__/' --exclude='.venv/' --exclude='node_modules/' "${LINK[@]}")
"${RS[@]}" "$TREES/nemec" "$TREES/kohakova" "$TREES/kniha-ukazka" "$TREES/knihy" "$HOST:$NEW/genealogy-trees/"
rsync -a "$STAGE/gramps/" "$HOST:$NEW/gramps-web/"
rsync -a "$WB/CLAUDE.local.md" "$WB/genealogy.toml" "$HOST:$NEW/workbench/" 2>/dev/null || true

# 3) Přepnout „posledni“ a smazat staré zálohy (drží KEEP nejnovějších)
ssh "$HOST" "cd '$DEST' && ln -sfn 'snimky/$STAMP' posledni && ls -1d snimky/*/ | sort | head -n -$KEEP | xargs -r rm -rf"
ssh "$HOST" "du -sh '$NEW' '$DEST' 2>/dev/null; ls -1 '$DEST/snimky'"
echo "=== $(date '+%F %T') hotovo"

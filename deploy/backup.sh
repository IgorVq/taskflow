#!/usr/bin/env bash
# Usage : ./backup.sh   (staging : COMPOSE_FILE=compose.staging.yaml ./backup.sh)
# Restauration :
#   gunzip -c backups/taskflow-XXXX.sql.gz | docker compose -f compose.prod.yaml exec -T db psql -q -U taskflow -d taskflow
set -euo pipefail

cd "$(dirname "$0")"
export COMPOSE_FILE="${COMPOSE_FILE:-compose.prod.yaml}"
DOSSIER="${BACKUP_DIR:-backups}"
RETENTION="${RETENTION_DAYS:-7}"

mkdir -p "$DOSSIER"
chmod 700 "$DOSSIER"

FICHIER="$DOSSIER/taskflow-$(date +%Y%m%d-%H%M%S).sql.gz"
PARTIEL="$FICHIER.partial"
trap 'rm -f "$PARTIEL"' EXIT

echo "==> Dump de la base vers $FICHIER"
docker compose exec -T db pg_dump -U taskflow -d taskflow --clean --if-exists \
  | gzip -9 > "$PARTIEL"

gzip -t "$PARTIEL" || { echo "Archive corrompue" >&2; exit 1; }
gunzip -c "$PARTIEL" | tail -n 5 | grep -q 'PostgreSQL database dump complete' \
  || { echo "Dump incomplet" >&2; exit 1; }

mv "$PARTIEL" "$FICHIER"
chmod 600 "$FICHIER"

echo "==> Rotation : suppression des sauvegardes de plus de $RETENTION jours"
find "$DOSSIER" -name 'taskflow-*.sql.gz' -mtime "+$RETENTION" -print -delete

echo "==> OK : $(du -h "$FICHIER" | cut -f1) ; $(find "$DOSSIER" -name 'taskflow-*.sql.gz' | wc -l | tr -d ' ') sauvegarde(s) conservée(s)"

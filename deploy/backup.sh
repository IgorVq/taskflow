#!/usr/bin/env bash
# ============================================================================
# backup.sh : sauvegarde de la base PostgreSQL (pg_dump compressé et vérifié).
#
#     ./backup.sh                                     # prod
#     COMPOSE_FILE=compose.staging.yaml ./backup.sh   # staging
#
# Produit backups/taskflow-AAAAMMJJ-HHMMSS.sql.gz et garde RETENTION_DAYS jours (7).
# Planifiable par cron :  0 3 * * * ~/taskflow-prod/backup.sh >> ~/taskflow-prod/backups/backup.log 2>&1
#
# RESTAURATION (à répéter régulièrement : une sauvegarde jamais restaurée ne prouve rien) :
#     gunzip -c backups/taskflow-XXXX.sql.gz \
#       | docker compose -f compose.prod.yaml exec -T db psql -q -U taskflow -d taskflow
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")"
export COMPOSE_FILE="${COMPOSE_FILE:-compose.prod.yaml}"
DOSSIER="${BACKUP_DIR:-backups}"
RETENTION="${RETENTION_DAYS:-7}"

mkdir -p "$DOSSIER"
chmod 700 "$DOSSIER"          # un dump contient toutes les données des utilisateurs

FICHIER="$DOSSIER/taskflow-$(date +%Y%m%d-%H%M%S).sql.gz"
PARTIEL="$FICHIER.partial"
# Quoi qu'il arrive, on ne laisse pas traîner un fichier incomplet qu'on prendrait
# plus tard pour une vraie sauvegarde.
trap 'rm -f "$PARTIEL"' EXIT

echo "==> Dump de la base vers $FICHIER"
# -T : pas de pseudo-terminal (obligatoire dans un script ou un cron).
# --clean --if-exists : le dump commence par supprimer les tables, il se rejoue
# donc sur une base existante sans conflit.
docker compose exec -T db pg_dump -U taskflow -d taskflow --clean --if-exists \
  | gzip -9 > "$PARTIEL"

# Vérifications : archive gzip intacte ET dump arrivé jusqu'au bout
# (pg_dump écrit cette ligne en tout dernier).
gzip -t "$PARTIEL" || { echo "Archive corrompue" >&2; exit 1; }
# (tail lit tout le flux : un « grep -q » direct couperait gunzip en plein
# milieu, et pipefail prendrait ce SIGPIPE pour un échec.)
gunzip -c "$PARTIEL" | tail -n 5 | grep -q 'PostgreSQL database dump complete' \
  || { echo "Dump incomplet" >&2; exit 1; }

mv "$PARTIEL" "$FICHIER"
chmod 600 "$FICHIER"

echo "==> Rotation : suppression des sauvegardes de plus de $RETENTION jours"
find "$DOSSIER" -name 'taskflow-*.sql.gz' -mtime "+$RETENTION" -print -delete

echo "==> OK : $(du -h "$FICHIER" | cut -f1) ; $(find "$DOSSIER" -name 'taskflow-*.sql.gz' | wc -l | tr -d ' ') sauvegarde(s) conservée(s)"

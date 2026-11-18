#!/usr/bin/env bash
# Usage : ./deploy.sh <tag>   (staging : COMPOSE_FILE=compose.staging.yaml ./deploy.sh <tag>)
# Rollback : ./deploy.sh "$(cat .previous_tag)"
set -euo pipefail

etape() { printf '\n==> %s\n' "$*"; }
stop()  { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

TAG="${1:-}"
[ -n "$TAG" ] || stop "usage : ./deploy.sh <tag>   (ex. ./deploy.sh 259c62d)"
[[ "$TAG" =~ ^([0-9a-f]{7}|latest)$ ]] || stop "tag invalide « $TAG » (SHA court de 7 caractères ou latest)"

cd "$(dirname "$0")"
export COMPOSE_FILE="${COMPOSE_FILE:-compose.prod.yaml}"
export IMAGE_TAG="$TAG"

[ -f "$COMPOSE_FILE" ] || stop "$COMPOSE_FILE introuvable dans $PWD"
[ -f .env ] || stop ".env introuvable dans $PWD"
[ "$(ls -l .env | cut -c5-10)" = "------" ] || stop ".env lisible par d'autres utilisateurs : chmod 600 .env"
docker compose config --quiet || stop "configuration Compose invalide"

ACTUEL="$(cat .deployed_tag 2>/dev/null || true)"
etape "$COMPOSE_FILE : ${ACTUEL:-rien} -> $TAG"

if [ -n "$ACTUEL" ] && [ "$ACTUEL" != "$TAG" ]; then
  echo "$ACTUEL" > .previous_tag
fi

etape "Téléchargement des images"
docker compose pull --quiet

etape "Mise à jour des services"
docker compose up -d --remove-orphans --wait --wait-timeout 120

if docker compose config --services | grep -qx proxy; then
  etape "Rechargement du proxy"
  docker compose exec -T proxy nginx -t -q
  docker compose exec -T proxy nginx -s reload
fi

echo "$TAG" > .deployed_tag
printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$COMPOSE_FILE" "$TAG" >> .deploy_history

docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}'
docker image prune -f >/dev/null

etape "Déployé : $TAG (précédent : $(cat .previous_tag 2>/dev/null || echo aucun))"

#!/usr/bin/env bash
# ============================================================================
# deploy.sh : passe un environnement TaskFlow (prod ou staging) à une version.
#
# À lancer dans le dossier de l'environnement (PROD_DIR ou STAGING_DIR) :
#     ./deploy.sh <tag>                                    # prod
#     COMPOSE_FILE=compose.staging.yaml ./deploy.sh <tag>  # staging
# <tag> = SHA court (7 caractères hexadécimaux) d'une image publiée, ou « latest ».
#
# Rollback = relancer avec l'ancienne version :  ./deploy.sh "$(cat .previous_tag)"
# Idempotent : relancer avec le même tag ne recrée rien et ne casse rien.
# Compatible bash 3.2 (macOS) et Linux.
# ============================================================================
set -euo pipefail

etape() { printf '\n==> %s\n' "$*"; }
stop()  { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

TAG="${1:-}"
[ -n "$TAG" ] || stop "usage : ./deploy.sh <tag>   (ex. ./deploy.sh 259c62d)"
[[ "$TAG" =~ ^([0-9a-f]{7}|latest)$ ]] || stop "tag invalide « $TAG » (SHA court de 7 caractères ou latest)"

cd "$(dirname "$0")"
# Compose lit lui-même ces deux variables : plus besoin de -f ni de IMAGE_TAG=... devant chaque commande.
export COMPOSE_FILE="${COMPOSE_FILE:-compose.prod.yaml}"
export IMAGE_TAG="$TAG"

# --- Vérifications avant de toucher à quoi que ce soit ------------------------
[ -f "$COMPOSE_FILE" ] || stop "$COMPOSE_FILE introuvable dans $PWD"
[ -f .env ] || stop ".env introuvable dans $PWD (il se crée à la main, jamais dans Git)"
# Les droits « group » et « other » de .env doivent être vides (chmod 600).
[ "$(ls -l .env | cut -c5-10)" = "------" ] || stop ".env lisible par d'autres utilisateurs : chmod 600 .env"
docker compose config --quiet || stop "configuration Compose invalide (variable manquante dans .env ?)"

ACTUEL="$(cat .deployed_tag 2>/dev/null || true)"
etape "$COMPOSE_FILE : ${ACTUEL:-rien} -> $TAG"

# --- Mémoriser la version qui tourne : c'est la cible d'un rollback ----------
# Seulement si elle change : redéployer la même version ne doit pas écraser
# le vrai « précédent ».
if [ -n "$ACTUEL" ] && [ "$ACTUEL" != "$TAG" ]; then
  echo "$ACTUEL" > .previous_tag
fi

etape "Téléchargement des images"
docker compose pull --quiet

# --wait : rend la main quand tous les healthchecks sont verts, échoue si l'un
# reste unhealthy (sinon « up -d » réussit dès que les conteneurs sont CRÉÉS).
# Seuls les services dont l'image ou la config a changé sont recréés.
etape "Mise à jour des services"
docker compose up -d --remove-orphans --wait --wait-timeout 120

# Le proxy (prod) a résolu l'IP du front à son démarrage. Le front vient peut-être
# d'être recréé avec une autre IP : on recharge Nginx, sans couper les connexions.
if docker compose config --services | grep -qx proxy; then
  etape "Rechargement du proxy"
  docker compose exec -T proxy nginx -t -q
  docker compose exec -T proxy nginx -s reload
fi

echo "$TAG" > .deployed_tag
# Historique horodaté des déploiements : utile pour mesurer la fréquence (DORA).
printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$COMPOSE_FILE" "$TAG" >> .deploy_history

docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}'

# On ne supprime que les images sans tag : les versions précédentes restent en
# cache, ce qui rend le rollback quasi instantané (pas de téléchargement).
docker image prune -f >/dev/null

etape "Déployé : $TAG (précédent : $(cat .previous_tag 2>/dev/null || echo aucun))"

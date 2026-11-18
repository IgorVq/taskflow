#!/usr/bin/env bash
# ============================================================================
# smoke-test.sh : la version déployée répond-elle VRAIMENT ?
#
#     ./smoke-test.sh <url-de-/health> [version-attendue]
#
# Vert seulement si, dans le délai imparti, /health répond :
#   1. code HTTP 200 ;
#   2. "status": "ok" ET "db": "up" (l'API ET sa base fonctionnent) ;
#   3. "version" = la version attendue, si elle est donnée.
# Le point 3 évite le faux vert : pendant un déploiement, l'ANCIENNE version peut
# encore répondre « ok ». Sans vérifier la version, on validerait la mauvaise.
#
# Variables : SMOKE_RETRIES (20), SMOKE_DELAY (3 s), SMOKE_CURL_OPTS (options curl
# en plus, ex. "--cacert certs/taskflow.crt" pour VÉRIFIER le certificat, jamais -k).
# ============================================================================
set -euo pipefail

URL="${1:?usage : ./smoke-test.sh <url-de-/health> [version-attendue]}"
ATTENDUE="${2:-}"
ESSAIS="${SMOKE_RETRIES:-20}"
PAUSE="${SMOKE_DELAY:-3}"
# shellcheck disable=SC2206  # découpage volontaire des options sur les espaces
OPTS=(${SMOKE_CURL_OPTS:-})

command -v jq >/dev/null || { echo "jq est requis" >&2; exit 2; }

for i in $(seq 1 "$ESSAIS"); do
  # -w ajoute le code HTTP sur la dernière ligne ; -s sans -f : on veut le corps
  # même en 503 (il dit souvent pourquoi : "db": "down").
  # ${OPTS[@]+...} : un tableau vide ne fait pas planter « set -u » sous bash 3.2.
  reponse="$(curl -sS --max-time 5 -w '\n%{http_code}' ${OPTS[@]+"${OPTS[@]}"} "$URL" 2>&1 || true)"
  code="${reponse##*$'\n'}"
  corps="${reponse%$'\n'*}"

  if [ "$code" = "200" ] && jq -e --arg v "$ATTENDUE" \
       '.status == "ok" and .db == "up" and ($v == "" or .version == $v)' \
       <<<"$corps" >/dev/null 2>&1; then
    echo "Smoke test OK (essai $i/$ESSAIS) : $corps"
    exit 0
  fi
  echo "Essai $i/$ESSAIS : HTTP ${code:-?} -> ${corps:0:160}"
  sleep "$PAUSE"
done

echo "Smoke test ÉCHOUÉ sur $URL (version attendue : ${ATTENDUE:-indifférente})" >&2
exit 1

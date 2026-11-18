#!/usr/bin/env bash
# Usage : ./smoke-test.sh <url-de-/health> [version-attendue]
# Vert si HTTP 200, status=ok, db=up et la bonne version.
# Options : SMOKE_RETRIES, SMOKE_DELAY, SMOKE_CURL_OPTS (ex. "--cacert certs/taskflow.crt").
set -euo pipefail

URL="${1:?usage : ./smoke-test.sh <url-de-/health> [version-attendue]}"
ATTENDUE="${2:-}"
ESSAIS="${SMOKE_RETRIES:-20}"
PAUSE="${SMOKE_DELAY:-3}"
# shellcheck disable=SC2206
OPTS=(${SMOKE_CURL_OPTS:-})

command -v jq >/dev/null || { echo "jq est requis" >&2; exit 2; }

for i in $(seq 1 "$ESSAIS"); do
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

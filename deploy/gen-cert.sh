#!/usr/bin/env bash
# Certificat auto-signé du lab : certs/taskflow.crt et certs/taskflow.key (FORCE=1 pour régénérer).
set -euo pipefail

cd "$(dirname "$0")"
DOSSIER="${CERT_DIR:-certs}"
DOMAINE="${DOMAIN:-taskflow.localhost}"
JOURS="${DAYS:-365}"
# host.docker.internal : le smoke test du runner vérifie le certificat (--cacert).
SAN="subjectAltName=DNS:$DOMAINE,DNS:localhost,DNS:host.docker.internal,IP:127.0.0.1"

mkdir -p "$DOSSIER"
if [ -f "$DOSSIER/taskflow.crt" ] && [ -f "$DOSSIER/taskflow.key" ] && [ "${FORCE:-0}" != 1 ]; then
  echo "Certificat déjà présent dans $DOSSIER/ (FORCE=1 ./gen-cert.sh pour le régénérer)"
  exit 0
fi

umask 077
if command -v openssl >/dev/null 2>&1; then
  openssl req -x509 -nodes -days "$JOURS" \
    -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$DOSSIER/taskflow.key" -out "$DOSSIER/taskflow.crt" \
    -subj "/CN=$DOMAINE" -addext "$SAN" 2>/dev/null
else
  docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/$DOSSIER:/out" docker.io/library/alpine:3.22 sh -c "
    apk add --no-cache openssl >/dev/null 2>&1 &&
    openssl req -x509 -nodes -days '$JOURS' -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -keyout /out/taskflow.key -out /out/taskflow.crt -subj '/CN=$DOMAINE' -addext '$SAN' 2>/dev/null"
fi

chmod 600 "$DOSSIER/taskflow.key"
chmod 644 "$DOSSIER/taskflow.crt"
echo "Certificat créé dans $DOSSIER/ pour $DOMAINE (valable $JOURS jours)"

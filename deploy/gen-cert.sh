#!/usr/bin/env bash
# ============================================================================
# gen-cert.sh : certificat HTTPS AUTO-SIGNÉ pour la prod du lab.
#
# Le chiffrement est réel ; seule l'identité n'est garantie par aucune autorité,
# d'où l'avertissement du navigateur. Sur un vrai serveur : Let's Encrypt.
#
#     ./gen-cert.sh            # crée certs/taskflow.crt (public) et certs/taskflow.key (privée)
#     FORCE=1 ./gen-cert.sh    # régénère
#
# Le certificat couvre taskflow.localhost, localhost, 127.0.0.1 ET host.docker.internal :
# le smoke test lancé depuis le runner (un conteneur) peut ainsi le VÉRIFIER avec
# `curl --cacert certs/taskflow.crt` au lieu de l'ignorer avec `curl -k`.
# Clé ECDSA P-256 : plus courte et plus rapide qu'une RSA 2048, même niveau de sécurité.
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")"
DOSSIER="${CERT_DIR:-certs}"
DOMAINE="${DOMAIN:-taskflow.localhost}"
JOURS="${DAYS:-365}"
SAN="subjectAltName=DNS:$DOMAINE,DNS:localhost,DNS:host.docker.internal,IP:127.0.0.1"

mkdir -p "$DOSSIER"
if [ -f "$DOSSIER/taskflow.crt" ] && [ -f "$DOSSIER/taskflow.key" ] && [ "${FORCE:-0}" != 1 ]; then
  echo "Certificat déjà présent dans $DOSSIER/ (FORCE=1 ./gen-cert.sh pour le régénérer)"
  exit 0
fi

# La clé privée est créée directement en 600 (umask), pas « chmod après coup ».
umask 077
if command -v openssl >/dev/null 2>&1; then
  openssl req -x509 -nodes -days "$JOURS" \
    -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$DOSSIER/taskflow.key" -out "$DOSSIER/taskflow.crt" \
    -subj "/CN=$DOMAINE" -addext "$SAN" 2>/dev/null
else
  # Pas d'openssl sur la machine : on l'emprunte à un conteneur Alpine.
  docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/$DOSSIER:/out" docker.io/library/alpine:3.22 sh -c "
    apk add --no-cache openssl >/dev/null 2>&1 &&
    openssl req -x509 -nodes -days '$JOURS' -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -keyout /out/taskflow.key -out /out/taskflow.crt -subj '/CN=$DOMAINE' -addext '$SAN' 2>/dev/null"
fi

chmod 600 "$DOSSIER/taskflow.key"
chmod 644 "$DOSSIER/taskflow.crt"
echo "Certificat créé dans $DOSSIER/ pour $DOMAINE (valable $JOURS jours)"
openssl x509 -in "$DOSSIER/taskflow.crt" -noout -enddate -ext subjectAltName 2>/dev/null || true

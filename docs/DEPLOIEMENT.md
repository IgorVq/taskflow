# Déploiement de TaskFlow

## Les environnements

Dans le lab, les trois environnements tournent sur la même machine. Chaque dossier joue le rôle d'un serveur.

| Environnement | Dossier | Fichier Compose | Projet Compose | URL |
|---|---|---|---|---|
| dev | le clone du dépôt | `compose.yaml` (build local) | `taskflow` | `http://localhost:8080` |
| staging | `~/taskflow-staging` (`STAGING_DIR`) | `compose.staging.yaml` | `taskflow-staging` | `http://localhost:8081` |
| production | `~/taskflow-prod` (`PROD_DIR`) | `compose.prod.yaml` | `taskflow-prod` | `https://taskflow.localhost` |

Le staging et la production lancent **les mêmes images**, repérées par le SHA court du commit (`IMAGE_TAG`). Seule la
configuration change : elle vient du `.env` du dossier.

**Un fichier Compose par environnement** plutôt qu'un fichier paramétré : la prod et le staging n'ont pas la même
**structure** (proxy HTTPS en prod, front publié directement en staging). Deux fichiers courts se relisent mieux en PR
qu'un seul rempli de conditions. Ce qui ne diffère que par une valeur (mot de passe, ports, `APP_ENV`) est dans le
`.env`. `deploy.sh` est le même pour les deux : il prend le fichier indiqué par `COMPOSE_FILE`.

## Code, configuration, données

| Catégorie | Éléments du dossier | Origine | Le pipeline peut l'écraser ? |
|---|---|---|---|
| **Code** | `compose.*.yaml`, `nginx/taskflow.conf`, `*.sh` (et les images) | dépôt Git | **oui**, à chaque déploiement |
| **Configuration** | `.env` (600), `certs/` (clé en 600) | créés à la main sur le serveur | non |
| **Données** | volume `pgdata`, `backups/`, `.deployed_tag`, `.previous_tag`, `.deploy_history` | produits par l'exploitation | non |

## Première installation de la production

```bash
REPO=~/taskflow
mkdir -p ~/taskflow-prod/nginx && cd ~/taskflow-prod
cp $REPO/compose.prod.yaml $REPO/deploy/*.sh . && cp $REPO/deploy/nginx/taskflow.conf nginx/
cp $REPO/.env.example .env && chmod 600 .env
PASS=$(openssl rand -hex 24) && sed -i '' "s/changez-moi/$PASS/" .env && unset PASS   # Linux : sed -i "..."
vi .env                       # GHCR_OWNER en minuscules ; 8082/8443 si 80/443 sont pris
./gen-cert.sh
docker compose -f compose.prod.yaml config --quiet && echo "configuration valide"
```

## Déployer, vérifier, revenir en arrière

```bash
cd ~/taskflow-prod
./deploy.sh <sha>                                                       # pull, up --wait, reload du proxy
SMOKE_CURL_OPTS="--cacert certs/taskflow.crt" ./smoke-test.sh https://localhost/health <sha>
./deploy.sh "$(cat .previous_tag)"                                      # rollback
```

En staging : `COMPOSE_FILE=compose.staging.yaml ./deploy.sh <sha>`, puis
`./smoke-test.sh http://localhost:8081/health <sha>`.

Un rollback relance une image déjà construite et déjà testée : il ne reconstruit rien. Il n'est possible que si la
version précédente comprend encore le schéma de la base (règle *expand / contract*).

## Sauvegarde et restauration

```bash
./backup.sh                                     # backups/taskflow-AAAAMMJJ-HHMMSS.sql.gz, 7 jours gardés
gunzip -c backups/taskflow-XXXX.sql.gz | docker compose -f compose.prod.yaml exec -T db psql -q -U taskflow -d taskflow
```

Testez la restauration régulièrement : une sauvegarde qu'on n'a jamais restaurée ne prouve rien.

## Dépannage

| Symptôme | Cause probable | Correctif |
|---|---|---|
| `api is unhealthy` et `password authentication failed` dans `logs api` | le volume a été créé avec un autre mot de passe (Postgres ne lit `POSTGRES_PASSWORD` qu'à la création du volume) | remettre l'ancien mot de passe ; en lab seulement : `down -v` |
| `bind: address already in use` sur 80/443 | port déjà pris | `HTTP_PORT=8082`, `HTTPS_PORT=8443` dans `.env` |
| `proxy` redémarre en boucle | `certs/` vide | `./gen-cert.sh` |
| 502 après un déploiement | le proxy garde l'ancienne IP du front | `docker compose exec proxy nginx -s reload` (fait par `deploy.sh`) |
| `.env lisible par d'autres utilisateurs` | droits trop ouverts | `chmod 600 .env` |

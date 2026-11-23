# Gestion des incidents

Quand quelque chose casse en production, on **répare d'abord**, puis on **comprend** et on **écrit** ce qu'on a appris.
Un post-mortem n'a pas pour but de trouver un coupable mais d'éviter que l'incident se reproduise. Il est **sans
blâme** : on parle de processus et de systèmes, pas de personnes. Chaque post-mortem se termine par au moins une
**issue** qui améliore le code, le pipeline ou la supervision.

```
alerte ─▶ incident (diagnostic, correction) ─▶ post-mortem sans blâme ─▶ issue ─▶ amélioration ─▶ (moins d'incidents, détectés plus tôt)
```

## Supervision en place

| Outil | Adresse | Sert à |
|---|---|---|
| Mailpit | http://localhost:8025 | recevoir les notifications d'Alertmanager |
| Alertmanager | http://localhost:9093 | alertes actives, inhibées ; poser un **silence** pendant une intervention |
| Prometheus | http://localhost:9090 | *Alerts*, *Targets*, requêtes PromQL |
| Grafana | http://localhost:3001 | dashboard *TaskFlow : RED et disponibilité* |

| Alerte | Signification | Premier réflexe |
|---|---|---|
| `TaskFlowApiDown` (critical) | `/health` ne répond pas `ok` à travers le front depuis 1 min | méthode ci-dessous, dès l'étape 1 |
| `TaskFlowMetricsDown` (warning) | Prometheus ne lit plus `api:3000/metrics` | `ps` : l'API tourne-t-elle ? |
| `TaskFlowHighErrorRate` (warning) | plus de 5 % de 5xx pendant 5 min | logs `level=error` de l'API, état de la base |
| `TaskFlowHighLatency` (warning) | p95 > 300 ms pendant 5 min | panneau Duration par route ; base, ressources du poste |

## Méthode de diagnostic

Du plus visible au plus profond (dans `~/taskflow-prod`) :

1. **Alerte** : laquelle, depuis quand (`activeAt`), quelle cible ? Notez l'heure : c'est le début de la chronologie.
2. **Dashboard** : depuis quand la disponibilité est-elle tombée ? La version a-t-elle changé (*Version en ligne*,
   annotations de déploiement) ? Les courbes RED montent-elles (erreurs) ou **s'arrêtent**-elles (API morte) ?
3. **Symptôme** : `curl -sk https://taskflow.localhost/health` ; que voit l'utilisateur ?
4. **Conteneurs** : `docker compose -f compose.prod.yaml ps` (qui est `unhealthy`, `Restarting` ?)
5. **Logs** du service suspect, filtrés :
   `docker compose -f compose.prod.yaml logs --no-log-prefix --since 15m api | jq -c 'select(.level != "info")'`
6. **Cause racine** : configuration, code, base, ressources ? **Prouvez-la** (`docker inspect`, fichier, requête).
7. **Correction**, puis **vérification** : `ps`, `/health`, une action utilisateur, sonde verte, mail `[RESOLVED]`.

Pendant une intervention longue : un **silence** dans Alertmanager (avec un commentaire et une durée) évite de
recevoir la même alerte en boucle, sans la supprimer.

## Modèle de post-mortem

Copiez ce modèle pour chaque incident, du plus récent au plus ancien.

```markdown
## Incident n° N - Titre court

**Gravité** : faible / moyenne / élevée
**Détection** : alerte <nom> / utilisateur / autre - délai entre le début et la détection : X min
**Durée** : début hh:mm - fin hh:mm (durée totale = temps de rétablissement)
**Rédaction** : ...

### Résumé
Deux ou trois phrases : ce qui s'est passé et l'impact pour les utilisateurs.

### Chronologie (heure, UTC ou locale : préciser)
- hh:mm - Changement à l'origine de l'incident
- hh:mm - Premier signal (alerte, message d'un utilisateur...)
- hh:mm - Diagnostic : ce qu'on a regardé, ce qu'on a trouvé
- hh:mm - Correction appliquée
- hh:mm - Retour à la normale confirmé (sonde verte, [RESOLVED])

### Cause racine (5 pourquoi)
1. Pourquoi ... ?
...

### Ce qui a bien fonctionné
### Ce qui a moins bien fonctionné

### Actions
| Action | Type | Issue | Statut |
| --- | --- | --- | --- |
| ... | prévention / détection / processus | #N | à faire |
```

---

## Incident n° 1 - L'API redémarre en boucle après une modification du `.env`

**Contexte** : incident provoqué dans le cadre de l'exercice de l'étape 4, sur la production du lab.
**Gravité** : élevée (aucune tâche consultable ni modifiable)
**Détection** : alerte `TaskFlowApiDown`, reçue 1 min 13 s après le début de la panne
**Durée** : 11:37:53 - 11:41:12, heure de Paris, le 23/11/2026 (3 min 19 s)
**Rédaction** : équipe TaskFlow

### Résumé

Pendant 3 min 19 s, l'API de production était indisponible et `/health` comme `/api/tasks` renvoyaient une erreur 502.
La variable `DATABASE_URL` avait été renommée en `DATABASE_UR` dans le `.env` : l'API retombait sur l'adresse de base par
défaut (`localhost`), absente de son conteneur, et redémarrait en boucle. Aucune donnée n'a été perdue : la base est
restée saine et les 2 tâches sont intactes.

### Chronologie (heure de Paris)

- 11:37:53 - Le `.env` est modifié (`DATABASE_URL` devient `DATABASE_UR`), puis le conteneur `api` est recréé.
- 11:37:55 - Premier log `fatal` de l'API : `Démarrage impossible : ECONNREFUSED`.
- 11:37:57 - Première sonde `probe_success` à 0.
- 11:38:56 - `TaskFlowApiDown` passe à *firing* après son délai `for: 1m`.
- 11:39:06 - Mail `[FIRING:1] TaskFlowApiDown prod` reçu.
- 11:39:11 - `TaskFlowMetricsDown` s'active et reste inhibée par l'alerte critique.
- 11:40:47 - Diagnostic : sonde en 502, `up{job="taskflow-api"}` à 0, `api` en `Restarting (1)` avec 11 redémarrages, base
  *healthy*, version inchangée (`f948377`), logs `fatal` qui orientent vers `DATABASE_URL`.
- 11:41:00 environ - Preuve : `docker inspect` montre `DATABASE_UR` dans le conteneur, et la comparaison avec la copie
  du `.env` montre une seule ligne modifiée, sur le nom de la variable et non sur sa valeur.
- 11:41:08 - Nom de la variable restauré et conteneur `api` recréé.
- 11:41:12 - Sonde de nouveau à 1.
- 11:41:15 - `api` *healthy*, `/health` à `ok`. Création puis suppression d'une tâche de contrôle réussies.
- 11:41:21 - Mail `[FIRING:1] TaskFlowMetricsDown prod` reçu, alors que le service est déjà rétabli.
- 11:43:06 - Mail `[RESOLVED] TaskFlowApiDown prod`.
- 11:43:21 - Mail `[RESOLVED] TaskFlowMetricsDown prod`. Seul le `Watchdog` reste actif.

### Indicateurs

| Indicateur | Valeur |
| --- | --- |
| Temps de détection (début → mail d'alerte) | 1 min 13 s |
| Temps de correction (mail d'alerte → correction appliquée) | 2 min 02 s |
| Temps de rétablissement, MTTR (début → sonde verte) | 3 min 19 s |

### Cause racine (5 pourquoi)

1. Pourquoi le site renvoyait-il 502 ? Le front ne joignait plus l'API.
2. Pourquoi ? L'API redémarrait en boucle et n'était jamais prête.
3. Pourquoi ? Elle tentait de joindre PostgreSQL sur `localhost:5432`, où il n'y a pas de base dans son conteneur.
4. Pourquoi ? `DATABASE_URL` était absente et `readConfig` retombe silencieusement sur une valeur par défaut de
   développement, y compris en production.
5. Pourquoi l'erreur a-t-elle atteint la production ? Le `.env` de production se modifie à la main, sans relecture ni
   contrôle automatique de sa complétude.

### Ce qui a bien fonctionné

- L'alerte est arrivée 1 min 13 s après le début de la panne, sans signalement extérieur.
- Le statut des conteneurs a écarté la base, et la version inchangée a écarté l'image : un rollback n'aurait rien réparé.
- Les logs JSON filtrés avec `jq` ont orienté vers `DATABASE_URL` en une commande.
- L'inhibition a évité une seconde notification pendant la panne.

### Ce qui a moins bien fonctionné

- Rien n'empêche l'API de démarrer en production avec une configuration incomplète.
- Le `.env` de production peut être modifié sans comparaison avec `.env.example`.
- `TaskFlowMetricsDown` a été notifiée à 11:41:21, après le rétablissement : l'inhibition s'est levée avec la fin de
  l'alerte critique alors que l'alerte secondaire n'était pas encore résolue.
- Le mail `[RESOLVED]` est arrivé près de 2 minutes après le retour à la normale.

### Actions

| Action | Type | Issue | Statut |
| --- | --- | --- | --- |
| En production (`APP_ENV=production`), l'API refuse de démarrer si `DATABASE_URL` est absente, avec un message explicite ; test dans `tests/config.test.js` | prévention | #32 | à faire |
| `deploy.sh` compare les noms de variables de `.env` et de `.env.example`, et s'arrête s'il en manque | prévention | à créer | à faire |
| Éviter la notification d'une alerte secondaire après la fin de l'alerte critique (réglage de `group_wait` ou du `for` de `TaskFlowMetricsDown`), vérifié par un nouvel exercice | détection | à créer | à faire |

<!-- Ajoutez vos post-mortems au-dessus de celui-ci, du plus récent au plus ancien. -->

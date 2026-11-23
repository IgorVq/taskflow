# Sécurité de TaskFlow

> Ce document décrit les contrôles de sécurité du projet, les corrections appliquées et le **registre des
> exceptions**. Il est mis à jour à chaque fois qu'une alerte est traitée.

## 1. Les contrôles et leur place dans le pipeline

| Contrôle | Outil | Étape | Déclencheur | Ce qu'il protège |
| --- | --- | --- | --- | --- |
| Secrets (pré-commit) | **gitleaks** | poste de développement | `git commit` | un secret qui part dans un commit |
| Secrets (historique) | **gitleaks** | `security.yml` | PR, push `main`, hebdo | un secret déjà présent dans l'historique |
| Dépendances (SCA) | **npm audit** `--audit-level=high` | `security.yml` | PR, push `main`, hebdo | dépendances avec une CVE connue |
| Dépendances (veille) | **Dependabot** | dépôt | planifié | dépendances qui vieillissent |
| Code (SAST) | **Semgrep** (`p/javascript`, `p/nodejsscan`) | `security.yml` | PR, push `main`, hebdo | injection, XSS, `eval` |
| Image (SCA) | **Trivy** | `release.yml` | push `main` | CVE dans l'image publiée |
| Application (DAST) | **OWASP ZAP baseline** | `security.yml` | PR, push `main`, hebdo | en-têtes, cookies, fuites d'information |
| Durcissement HTTP | en-têtes **Nginx** | exécution | chaque requête | XSS, clickjacking, fuite d'information |
| Moindre privilège | `permissions:`, actions **épinglées par SHA** | workflows | toujours | jeton détourné, action modifiée |

Le `schedule` hebdomadaire de `security.yml` rattrape les CVE publiées **après** un merge.

## 2. Durcissement HTTP

Les en-têtes sont posés dans [`front/nginx.conf`](../front/nginx.conf), sur **toutes** les réponses (`always`) :

| En-tête | Valeur | Rôle |
| --- | --- | --- |
| `Content-Security-Policy` | `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'` | n'autorise que nos propres ressources |
| `X-Content-Type-Options` | `nosniff` | empêche le navigateur de deviner un type de fichier |
| `X-Frame-Options` | `DENY` | anti-clickjacking pour les navigateurs anciens |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | ne transmet pas l'URL complète aux tiers |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=(), payment=(), usb=()` | coupe les API matérielles inutilisées |
| `Cross-Origin-Opener-Policy` / `-Resource-Policy` / `-Embedder-Policy` | `same-origin` / `same-origin` / `require-corp` | isolation d'origine |

Également : `server_tokens off` (version de Nginx masquée) et `proxy_hide_header X-Powered-By`.

- **Pas de `'unsafe-inline'`** : le build Vite ne produit ni script ni style inline. Création, bascule et suppression
  d'une tâche ont été testées dans un navigateur, sans violation CSP en console.
- **`add_header` n'est pas hérité** par une `location` qui a son propre `add_header`. Le `Cache-Control` des assets est
  donc posé par un `map`. Les en-têtes ont été vérifiés sur `/`, `/health`, un fichier `/assets/` et une réponse 404.
- **Proxy de production** : il pose déjà `X-Content-Type-Options`, `X-Frame-Options` et `Referrer-Policy`. Il masque
  ceux du front (`proxy_hide_header`) pour ne pas les envoyer en double.
- **HSTS non activé** : sur `localhost`, il s'appliquerait aussi au port de développement.

## 3. Triage du 23/11/2026

| Alerte | Outil | Sévérité | Vrai ou faux positif | Décision |
| --- | --- | --- | --- | --- |
| `body-parser` < 1.20.9 (déni de service) | npm audit | high | **vrai**, en production via `express` | corrigé en 1.20.9 |
| `vitest`, `@vitest/coverage-v8`, `tinypool`, `vite` | npm audit | critical / high | **vrai**, outils de développement et CI | corrigé : `vitest` 4, `vite` 7 |
| CSP absente | ZAP | medium | **vrai** | corrigé |
| Anti-clickjacking absent | ZAP | medium | **vrai** | corrigé |
| `X-Content-Type-Options`, `Permissions-Policy` absents | ZAP | low | **vrai** | corrigé |
| Version de Nginx dans `Server` | ZAP | low | **vrai** | corrigé |
| COOP / COEP / CORP absents | ZAP | low | **vrai**, impact faible | corrigé, surveillé en WARN |
| Nginx avec vulnérabilités connues (1.29.8) | ZAP | à vérifier | **non confirmé** : Trivy ne trouve aucune CVE dans l'image | surveillé par Trivy |
| Storable and Cacheable Content | ZAP | info | **faux positif** : cache voulu | exception |
| Modern Web Application | ZAP | info | **faux positif** : signale une SPA | exception |

L'alerte Nginx ne remonte plus depuis `server_tokens off`, car ZAP ne voit plus la version : ce masquage **n'est pas une
correction**. Le contrôle fiable reste le scan Trivy de l'image.

`vitest` 5 n'est pas retenu : il exige Node 22 ou plus, alors que la CI et les images utilisent encore Node 20. Après
correction, `npm audit` ne signale plus aucune vulnérabilité dans `api` ni dans `front`, et les tests passent sur
Node 20.

## 4. Registre des exceptions

> Chaque exception est **étroite** et **justifiée**. Un vrai secret ne s'ajoute jamais ici : on le **révoque**.

### ZAP : [`.zap/rules.tsv`](../.zap/rules.tsv)

| Règle | Action | Justification | Responsable | Date | Revue |
| --- | --- | --- | --- | --- | --- |
| 10049 Storable and Cacheable Content | IGNORE | les assets Vite, avec un hash dans leur nom, sont volontairement cachés 1 an | équipe TaskFlow | 23/11/2026 | 23/02/2027 |
| 10109 Modern Web Application | IGNORE | information seulement : l'application est une SPA | équipe TaskFlow | 23/11/2026 | 23/02/2027 |

Les règles 10038, 10020, 10021, 10063, 10036 et 10037 sont en **FAIL** : toute régression bloque la PR.

### gitleaks et Semgrep

Aucune exception à ce jour. Pour un faux positif Semgrep, utiliser `// nosemgrep: <id-de-règle>` sur la ligne concernée,
jamais un `nosemgrep` nu, et ajouter une entrée datée ici.

## 5. Limites connues

- La **baseline** ZAP est **passive** : elle ne teste ni l'authentification, ni les injections, ni le contrôle d'accès.
  Elle ne remplace ni un scan actif sur le staging, ni un pentest, ni la revue de code.
- Semgrep peut rater une injection si la requête est construite dans une autre fonction que l'appel.
- TaskFlow n'a volontairement **ni authentification ni multi-utilisateurs**.
- Avec `env_file`, l'API de production reçoit tout le `.env`, y compris des variables dont elle n'a pas besoin.

## 6. En cas de secret exposé

1. **Révoquer** immédiatement le secret auprès de son fournisseur.
2. Le remplacer par une nouvelle valeur, stockée en secret GitHub ou dans un `.env` hors de Git.
3. Purger l'historique si nécessaire (`git filter-repo`) et prévenir l'équipe.
4. Ouvrir un post-mortem, comme pour un incident (voir [`INCIDENTS.md`](INCIDENTS.md)).

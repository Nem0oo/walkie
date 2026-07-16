# Walkie

Talkie-walkie personnel auto-hébergé. Une app iOS tourne en arrière-plan sur ton téléphone et joue instantanément les messages vocaux reçus. Tes proches (sans l'app) t'envoient des messages vocaux via une simple page web accessible par un lien partagé — pas de compte, pas d'authentification forte : le "secret" est un code de canal non devinable dans le lien.

```
backend/   API REST + WebSocket (Node.js/TypeScript)
web/       Page d'enregistrement pour les contacts (HTML/JS vanilla)
ios/       App iOS qui reçoit et joue les messages (SwiftUI)
```

Un seul conteneur Docker sert à la fois l'API et la page web (le Dockerfile copie `web/` dans les fichiers statiques du backend).

## Comment ça marche

1. Au premier lancement, l'app iOS crée un canal (`POST /channels`) et affiche un code + un lien `https://walkie.gcourtot.fr/send/{code}` + un QR code.
2. Tu partages ce lien à un proche par SMS/mail.
3. Le proche ouvre le lien dans son navigateur, enregistre un message (max 2 minutes), l'envoie.
4. Le backend retranscode systématiquement l'audio en AAC/`.m4a` — les navigateurs enregistrent en général en webm/opus, qu'iOS ne lit pas de façon fiable ; ce passage garantit que l'app iOS reçoit toujours un format lisible quel que soit le navigateur d'origine.
5. Le message est diffusé en direct via WebSocket à l'app iOS, qui le télécharge et le joue automatiquement, même en arrière-plan.
6. Si l'app était hors ligne, elle rattrape les messages manqués via un appel REST au retour au premier plan.

## Backend + web — build et déploiement

### Développement local

```bash
cd backend
cp .env.example .env   # DATA_DIR=./data-dev par défaut, pratique en local
npm install
npm run build
npm start               # ou `npm run dev` pour le rechargement à chaud
```

Le serveur sert aussi `web/` en statique une fois buildé dans une image Docker (voir plus bas) ; en dev pur backend sans Docker, copie `web/` dans `backend/dist/static/` si tu veux tester la page d'envoi en local :

```bash
mkdir -p backend/dist/static && cp -r web/* backend/dist/static/
```

### Image Docker

L'image est construite et publiée automatiquement par la CI (voir [CI/CD](#cicd) plus bas). Pour un build manuel :

```bash
cd VoiceMessage
docker build -t nem0oo/walkie:latest .
docker push nem0oo/walkie:latest
```

Le `Dockerfile` utilise `node:20-bookworm-slim` (pas Alpine) pour les deux étapes du build : `ffmpeg-static`/`ffprobe-static` fournissent des binaires liés à glibc, cassés sous musl (Alpine).

### Déploiement dans `homelab-services`

```bash
mkdir -p /home/nem0oo/homelab-services/walkie
cp docker-compose.yml /home/nem0oo/homelab-services/walkie/
cp .env.example /home/nem0oo/homelab-services/walkie/.env
mkdir -p /home/nem0oo/homelab-services/walkie/data

cd /home/nem0oo/homelab-services/walkie
docker compose pull
docker compose up -d
```

Vérifier : `curl https://walkie.gcourtot.fr/health` → `{"status":"ok"}`.

### Variables d'environnement

| Variable | Défaut | Description |
|---|---|---|
| `PORT` | `3000` | Port d'écoute HTTP interne |
| `DATA_DIR` | `/data` | Racine du stockage persistant (DB SQLite + blobs audio) |
| `MAX_UPLOAD_BYTES` | `8388608` (8 Mio) | Garde-fou serveur — la vraie limite est côté web (voir ci-dessous) |
| `CHANNEL_CODE_LENGTH` | `10` | Longueur des codes de canal générés |
| `PUBLIC_BASE_URL` | `http://localhost:3000` | Base des URLs de blobs renvoyées dans les réponses JSON/WS — mettre `https://walkie.gcourtot.fr` en prod |

Aucun secret dans `.env` : pas d'authentification forte en v1, cohérent avec le modèle "lien de partage classique".

### Contrainte importante : proxy nginx-proxy existant

`/home/nem0oo/srv/nginx` (le nginx-proxy + acme-companion existant, non modifié par ce projet) n'a **aucun override** de `client_max_body_size` (défaut nginx = 1 Mio) ni de `proxy_read_timeout` (défaut = 60s). Le design tient compte de ça sans toucher à cette config :
- La page web plafonne les enregistrements à **120s** et force un débit de **24 kbps mono**, soit ~360 Ko max par message — largement sous la limite d'1 Mio.
- Le hub WebSocket ping les clients toutes les 25s côté serveur, l'app iOS ping le serveur toutes les 20s côté client — les deux gardent la connexion sous le seuil d'inactivité de 60s du proxy.

Si un jour tu veux des messages plus longs, la vraie limite à changer est `CLIENT_MAX_BODY_SIZE` sur le conteneur `nginx-proxy` (dans l'autre repo), pas `MAX_UPLOAD_BYTES` ici.

## App iOS — build avec Theos (pas de Mac requis)

Contrairement à un projet Xcode classique, `ios/` est un projet **Theos** — il se compile entièrement en ligne de commande, sur Linux, sans Xcode ni Mac. C'est ce que fait la CI (voir [CI/CD](#cicd)) et c'est reproductible en local :

```bash
cd VoiceMessage/ios
docker run --rm -v "$PWD/..":/home/builder/code -w /home/builder/code/ios \
  docker.io/nem0oo/theos \
  make package PACKAGE_FORMAT=ipa FINALPACKAGE=1
```

Le `.ipa` non signé apparaît dans `ios/packages/`.

### Structure du projet Theos

| Fichier | Rôle |
|---|---|
| `ios/Makefile` | Cible `iphone:clang:latest:16.0`, liste des fichiers Swift, frameworks (`UIKit`, `AVFoundation`, `CoreImage`), dossiers de ressources |
| `ios/control` | Métadonnées du paquet (bundle id `fr.gcourtot.walkie`, version) — le champ `Version` est écrasé par la CI à partir du tag git sur une release |
| `ios/Resources/Info.plist` | Info.plist réel utilisé par le build (c'est ici, pas dans un projet Xcode, que vit la clé `UIBackgroundModes: audio` qui autorise la lecture en arrière-plan) |
| `ios/Resources/AppIcon.png` | Icône placeholder 1024×1024 — à remplacer si besoin |
| `ios/Resources/DontTouchMe.plist` | Marqueur de SDK requis par la chaîne de build Theos, ne pas modifier |
| `ios/Walkie/` | Code source Swift (Models/Services/ViewModels), y compris `Walkie/Resources/keepalive.caf` (boucle audio quasi-silencieuse pour le maintien en arrière-plan) |

Pas d'entitlements ni d'App Group nécessaires (pas d'extension/widget dans cette v1).

### Installer le `.ipa` sur le téléphone : AltStore / SideStore

Le `.ipa` produit n'est pas signé — c'est voulu. Installe-le via **AltStore** ou **SideStore**, qui gèrent la signature avec ton Apple ID gratuit **et se re-signent automatiquement en arrière-plan avant l'expiration du profil de 7 jours** (AltStore via AltServer sur le même réseau, SideStore via son propre refresh en arrière-plan). C'est ce qui élimine le besoin de rebrancher le téléphone à un Mac chaque semaine.

### Limites connues du mécanisme d'arrière-plan (à connaître, pas à corriger)

- La boucle audio silencieuse ne relance pas l'app après un force-quit depuis l'app switcher ni après un redémarrage du téléphone — il n'y a pas de notification push (APNs indisponible avec un compte Apple gratuit). Il faut rouvrir l'app manuellement une fois après ces cas.
- La catégorie `.playback` ignore le bouton silence physique du téléphone — les messages jouent même téléphone en mode silencieux. C'est le comportement voulu pour un talkie-walkie.
- Le profil de signature reste lié à un compte Apple gratuit : même avec AltStore/SideStore, une réinstallation complète (pas juste un refresh) reste nécessaire de temps en temps si le refresh échoue (téléphone éteint plus de 7 jours, AltServer injoignable, etc.).

## CI/CD

Deux workflows GitHub Actions indépendants, déclenchés séparément via `paths:` pour ne pas se relancer inutilement l'un l'autre :

### `.github/workflows/docker-build.yml` — image backend

- Sur chaque push/PR touchant `backend/`, `web/`, `Dockerfile` (tout sauf `ios/**` et les `.md`) : build de l'image (`docker/build-push-action`).
- Push vers Docker Hub (`nem0oo/walkie`) uniquement sur `push` (jamais sur PR) : tag `latest` sur `main`, tags sémantiques (`1.2.3`, `1.2`) sur un tag git `v*`.
- Secrets requis dans les paramètres du repo GitHub (`Settings → Secrets and variables → Actions`) : `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` (un [access token](https://hub.docker.com/settings/security) Docker Hub, pas ton mot de passe).
- Déclencher une release versionnée : `git tag v1.0.0 && git push origin v1.0.0`.
- Après le push de l'image, un dernier job (`trigger_watchtower`) appelle le webhook n8n (`N8N_WEBHOOK_ID`, même mécanisme que `killer_search/.github/workflows/build.yml`) pour forcer une vérification immédiate de watchtower — sinon watchtower ne repasserait qu'à son prochain passage planifié (`WATCHTOWER_SCHEDULE`, une fois par jour sur ce serveur), et le conteneur `walkie` ne redémarrerait pas tout de suite après un `push`/tag.

### `.github/workflows/ios-build.yml` — app iOS

- Sur chaque push/PR touchant `ios/` : build du `.ipa` via l'image Docker `docker.io/nem0oo/theos` (même image que le projet `Tides_app`), upload en artifact de build.
- Sur un tag `ios-v*` : en plus, publie une [GitHub Release](../../releases) avec le `.ipa` en pièce jointe (`gh release create`), et aligne le champ `Version` de `ios/control` sur le tag.
- Aucun secret requis — le `.ipa` publié n'est pas signé (voir la section AltStore/SideStore ci-dessus).
- Déclencher une release : `git tag ios-v1.0.0 && git push origin ios-v1.0.0`.

Préfixes de tag distincts (`v*` pour le backend, `ios-v*` pour l'app) car ce repo publie deux artefacts indépendants avec des cycles de version différents — contrairement à `Tides_app` qui n'a qu'un seul artefact et utilise `v*` directement.

## Hors scope v1 (assumé)

- Pas de purge/rétention des blobs et lignes SQLite — `/data` croît sans limite. Acceptable vu le volume attendu (quelques utilisateurs, ~360 Ko/message max).
- Pas d'historique des messages écoutés dans l'UI iOS.

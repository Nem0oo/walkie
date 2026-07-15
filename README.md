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

Construction et publication (pas de CI configurée — commandes manuelles) :

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

## App iOS — installation Xcode

Le dossier `ios/Walkie/` contient tout le code source Swift, mais **pas de fichier `.xcodeproj`** — Xcode doit générer le projet lui-même. Étapes :

1. **Xcode → File → New → Project → iOS → App.** Nom du produit : `Walkie`. Interface : SwiftUI. Langage : Swift. Storage : None. Tu peux décocher "Include Tests".
2. Une fois le projet créé, **supprime** les fichiers `WalkieApp.swift`, `ContentView.swift`, `Info.plist` et le dossier `Assets.xcassets` générés par défaut par Xcode à l'emplacement du nouveau projet (garde `Assets.xcassets`, tu en as besoin), puis **glisse-dépose tout le contenu de `ios/Walkie/`** (les vrais fichiers de ce repo) dans le navigateur de projet Xcode, en cochant "Copy items if needed" et la cible `Walkie`.
3. **Signing & Capabilities** :
   - Team : ton **Personal Team** (Apple ID gratuit).
   - Bundle Identifier : par exemple `fr.gcourtot.walkie` (doit juste être unique sur ton compte).
   - Signing Certificate : Automatic.
4. **General → Minimum Deployments** : iOS **16.0**.
5. **+ Capability → Background Modes** → coche **"Audio, AirPlay, and Picture in Picture."** C'est ce qui écrit `UIBackgroundModes: audio` dans l'Info.plist réel du projet — ne modifie jamais cette clé à la main, laisse Xcode la garder synchronisée avec la case cochée ici. Le fichier `ios/Walkie/Info.plist` fourni dans ce repo est une référence documentant la clé attendue, pas le fichier que Xcode utilisera réellement.
6. Vérifie que `Resources/keepalive.caf` (déjà généré dans ce repo, prêt à l'emploi) a bien la cible `Walkie` cochée dans son "Target Membership" après le glisser-déposer de l'étape 2.
7. Ajoute une icône (même un simple carré de couleur) dans `Assets.xcassets → AppIcon` — pas strictement bloquant pour lancer sur un appareil de dev, mais recommandé.
8. Branche ton iPhone, sélectionne-le comme destination de build, **Product → Run**. Au premier lancement, il faudra faire confiance au certificat développeur sur le téléphone : **Réglages → Général → VPN et gestion de l'appareil**.

### ⚠️ Rappel important : compte gratuit = resign tous les 7 jours

Avec un Personal Team (Apple ID gratuit, sans abonnement Apple Developer à 99$/an), le profil de provisioning généré expire **au bout de 7 jours**. Passé ce délai, l'app cesse de se lancer sur le téléphone (icône présente mais qui ne s'ouvre plus). **Il faut rebrancher le téléphone et relancer l'app depuis Xcode (Product → Run) au moins une fois par semaine** pour la re-signer. Aucune action côté backend n'est nécessaire — seule l'app iOS est concernée.

### Limites connues du mécanisme d'arrière-plan (à connaître, pas à corriger)

- La boucle audio silencieuse ne relance pas l'app après un force-quit depuis l'app switcher ni après un redémarrage du téléphone — il n'y a pas de notification push (APNs indisponible avec un compte Personal Team gratuit). Il faut rouvrir l'app manuellement une fois après ces cas.
- La catégorie `.playback` ignore le bouton silence physique du téléphone — les messages jouent même téléphone en mode silencieux. C'est le comportement voulu pour un talkie-walkie.

## Hors scope v1 (assumé)

- Pas de purge/rétention des blobs et lignes SQLite — `/data` croît sans limite. Acceptable vu le volume attendu (quelques utilisateurs, ~360 Ko/message max).
- Pas d'historique des messages écoutés dans l'UI iOS.
- Pas de CI/CD — build et push Docker sont des commandes manuelles.

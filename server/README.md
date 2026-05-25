# Notifier server — Déploiement rapide (Vercel / Render / Heroku)

Ce petit serveur fournit un endpoint sécurisé `/sendNotification` que l'application cliente appelle pour demander l'envoi de push (OneSignal ou FCM). Il est conçu pour tourner sur Vercel, Render ou Heroku (free tier possible).

## Variables d'environnement requises
- `SERVICE_ACCOUNT_JSON` : (optionnel pour fallback FCM) contenu JSON du service account Firebase (stringifié). Si absent, seul OneSignal sera utilisé.
- `ONE_SIGNAL_APP_ID` : votre OneSignal App ID (ex: `ac19fdcc-16e7-4775-8806-8cde03d1fadb`).
- `ONE_SIGNAL_REST_KEY` : votre OneSignal REST API Key (pour envoyer via OneSignal).
- `PORT` : (optionnel) port d'écoute (par défaut 3000).

## Agent de contenu
Le serveur peut publier automatiquement dans Firestore avec un compte systeme identifiable (`Agent Konnect`).
Il a besoin de Firebase Admin (`SERVICE_ACCOUNT_JSON`, sauf environnement avec credentials Firebase par defaut).

Variables utiles :
- `CONTENT_AGENT_ENABLED=1` : active le scheduler interne du serveur.
- `CONTENT_AGENT_SECRET` : secret requis pour appeler `/content-agent/run` et `/content-agent/status`.
- `GEMINI_API_KEY` : cle Gemini utilisee par l'agent pour generer ses publications et ses messages automatiques.
- `CONTENT_AGENT_GEMINI_ENABLED=1` : active Gemini pour les posts (`0` pour revenir au fallback local).
- `CONTENT_AGENT_GEMINI_MODEL=gemini-2.5-flash` : modele Gemini utilise pour generer les posts.
- `CONTENT_AGENT_MIN_HOURS=4` : delai minimum entre deux publications.
- `CONTENT_AGENT_INTERVAL_MINUTES=60` : frequence de verification du scheduler.
- `CONTENT_AGENT_CREATE_STORY=1` : publie aussi une story texte de 24h (`0` pour desactiver).
- `CONTENT_AGENT_AUTHOR_ID`, `CONTENT_AGENT_AUTHOR_NAME`, `CONTENT_AGENT_AUTHOR_AVATAR` : personnalisation du compte.
- `CONTENT_AGENT_PUBLIC_BASE_URL=https://lualaba-konnect.onrender.com` : URL publique du serveur, utilisee pour servir le logo comme avatar de l'agent.
- `CONTENT_AGENT_AVATAR_PATH=/content-agent/avatar.png` : chemin public du logo expose par le serveur.
- `CONTENT_AGENT_MEDIA_JSON` : liste JSON de medias a associer aux publications automatiques, ex. `[{"type":"image","url":"https://..."}]`.
- `CONTENT_AGENT_REQUIRE_MEDIA=1` : garantit qu'une publication automatique a au moins une image/video (`0` pour autoriser les posts texte seuls).
- `CONTENT_AGENT_FACEBOOK_ENABLED=1`, `FACEBOOK_PAGE_ID`, `FACEBOOK_PAGE_ACCESS_TOKEN` : active l'import officiel via Meta Graph API.
- `FACEBOOK_GRAPH_VERSION=v21.0` et `CONTENT_AGENT_FACEBOOK_LIMIT=8` : version Graph API et nombre de posts Facebook inspectes.
- `CONTENT_AGENT_MESSAGE_BATCH_SIZE=3` : nombre d'utilisateurs contactes par vague.
- `CONTENT_AGENT_MESSAGE_INTERVAL_SECONDS=120` : delai entre deux vagues de messages.
- `CONTENT_AGENT_MESSAGE_MAX_RECIPIENTS=500` : plafond de destinataires pour un envoi global.
- `CONTENT_AGENT_MESSAGE_TEMPLATES_JSON` : liste JSON optionnelle de messages de secours si aucun `text` n'est fourni et que Gemini ne repond pas.

Sur Render/Heroku, `CONTENT_AGENT_ENABLED=1` suffit pour lancer le scheduler. Sur Vercel/serverless, utilisez plutot un cron externe qui appelle `/content-agent/run`, car les timers ne restent pas actifs entre deux requetes.

Ordre de publication automatique : contenu manuel envoye a `/content-agent/run`, puis import Facebook si configure, puis generation Gemini si `GEMINI_API_KEY` est present. Les textes locaux ne servent que de secours si Gemini/Facebook ne donnent rien. Les posts automatiques sont publies en mode `media_card` avec une image/video par defaut si aucun media n'est fourni. Le profil de l'agent utilise par defaut le logo de l'app via `/content-agent/avatar.png`. Pour les messages sans `text`, l'agent essaye aussi Gemini avant les templates.

Publier un post manuel avec image :
```bash
curl -X POST 'https://my-notifier.vercel.app/content-agent/run?force=1' \
  -H 'content-type: application/json' \
  -H 'x-agent-secret: <CONTENT_AGENT_SECRET>' \
  -d '{"text":"Info du jour","category":"Communauté","media":[{"type":"image","url":"https://..."}]}'
```

Envoyer un message chat depuis l'agent :
```bash
curl -X POST 'https://my-notifier.vercel.app/content-agent/message' \
  -H 'content-type: application/json' \
  -H 'x-agent-secret: <CONTENT_AGENT_SECRET>' \
  -d '{"recipients":["UID_UTILISATEUR"],"text":"Bonjour, voici une info utile."}'
```

Envoyer a tout le monde sans tout envoyer au meme moment :
```bash
curl -X POST 'https://my-notifier.vercel.app/content-agent/message' \
  -H 'content-type: application/json' \
  -H 'x-agent-secret: <CONTENT_AGENT_SECRET>' \
  -d '{"allUsers":true,"batchSize":3,"intervalSeconds":120}'
```
Si `text` est absent, l'agent choisit lui-meme un message depuis ses templates.

## Déployer sur Vercel
1. Créez un nouveau projet sur Vercel en pointant vers le répertoire `server/` (ou importez le repo entier et sélectionnez le dossier `server`).
2. Définissez les variables d'environnement dans le dashboard Vercel (Settings → Environment Variables) :
   - `ONE_SIGNAL_APP_ID` = votre App ID
   - `ONE_SIGNAL_REST_KEY` = votre REST API Key
   - `SERVICE_ACCOUNT_JSON` = collez le JSON complet (value) du service account (si vous voulez fallback vers FCM)
3. Build & Deploy (Vercel détecte automatiquement et déploie Node.js).

Alternativement, via Vercel CLI :
```bash
cd server
npm install
vercel login
vercel --prod
# puis add env vars via UI ou `vercel env add` commands`
```

## Tester l'endpoint
Après déploiement vous aurez une URL, par ex `https://my-notifier.vercel.app/sendNotification`.
Pour appeler l'endpoint vous devez fournir un Firebase ID token (Authorization: Bearer <idToken>). Exemple (curl) :

```bash
curl -X POST 'https://my-notifier.vercel.app/sendNotification' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <FIREBASE_ID_TOKEN>' \
  -d '{"recipients":["uid_dest"],"title":"Test","body":"Hello","data":{"chatId":"abc"}}'
```

Pour obtenir un `FIREBASE_ID_TOKEN` en développement vous pouvez utiliser `FirebaseAuth.instance.currentUser.getIdToken()` côté client et l'afficher temporairement.

## Intégration côté Flutter
- Définissez l'URL du notifier dans la build Flutter :
```bash
flutter run --dart-define=NOTIFIER_URL=https://my-notifier.vercel.app/sendNotification \
            --dart-define=ONESIGNAL_APP_ID=ac19fdcc-16e7-4775-8806-8cde03d1fadb
```
- Le client appelle automatiquement le endpoint lorsque vous envoyez un message (modification faite dans `lib/features/chat/presentation/pages/chat_detail_page.dart`).

## Notes de sécurité
- L'endpoint vérifie le Firebase ID token pour s'assurer que la requête vient d'un utilisateur authentifié.
- Ne publiez jamais `SERVICE_ACCOUNT_JSON` en clair dans un repo public. Utilisez les variables d'environnement du provider.

## Fallback
- Si OneSignal n'est pas configuré, le serveur utilisera Firebase Admin (si `SERVICE_ACCOUNT_JSON` est présent) pour envoyer des notifications via FCM.

---
Si vous voulez, je peux préparer les commandes exactes pour Vercel (ou déployer pour vous si vos credentials sont disponibles). 

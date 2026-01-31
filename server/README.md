# Notifier server — Déploiement rapide (Vercel / Render / Heroku)

Ce petit serveur fournit un endpoint sécurisé `/sendNotification` que l'application cliente appelle pour demander l'envoi de push (OneSignal ou FCM). Il est conçu pour tourner sur Vercel, Render ou Heroku (free tier possible).

## Variables d'environnement requises
- `SERVICE_ACCOUNT_JSON` : (optionnel pour fallback FCM) contenu JSON du service account Firebase (stringifié). Si absent, seul OneSignal sera utilisé.
- `ONE_SIGNAL_APP_ID` : votre OneSignal App ID (ex: `ac19fdcc-16e7-4775-8806-8cde03d1fadb`).
- `ONE_SIGNAL_REST_KEY` : votre OneSignal REST API Key (pour envoyer via OneSignal).
- `PORT` : (optionnel) port d'écoute (par défaut 3000).

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

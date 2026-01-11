# Fonctions Cloud (FCM)

Ce dossier contient des Cloud Functions Firebase qui envoient des notifications FCM lors de la création :
- d'un message dans `chats/{chatId}/messages/{messageId}`
- d'un document d'appel dans `calls/{callId}`

Prérequis
- Firebase CLI installé (`npm install -g firebase-tools`) et connecté (`firebase login`).
- Accès au projet Firebase avec les droits de déploiement.

Installation
```bash
cd functions
npm install
```

Déploiement (local)
```bash
# depuis la racine du repo
firebase deploy --only functions --project YOUR_FIREBASE_PROJECT_ID
```

Déploiement CI (GitHub Actions)
- Le workflow `.github/workflows/deploy_functions.yml` utilise le secret `FIREBASE_TOKEN`.
- Pour générer le token en local :
```bash
firebase login:ci
# copier le token et l'ajouter au secret `FIREBASE_TOKEN` dans GitHub
```

Remarques d'intégration
- Les fonctions lisent `fcmToken` dans `classic_users/{uid}` pour envoyer les notifications. Assurez-vous que le client Flutter stocke le token FCM (`FirebaseMessaging.instance.getToken()`) dans ce champ.
- Pour gérer plusieurs appareils par utilisateur, stockez un tableau `fcmTokens` et utilisez `admin.messaging().sendMulticast()`.

Test local (émulateur)
```bash
firebase emulators:start --only functions
```

Améliorations recommandées
- Nettoyage des tokens invalides après l'envoi (retours `result.results`).
- Utiliser `sendMulticast` pour envoyer à plusieurs tokens en une seule requête.
- Ajouter logs structurés et gestion d'erreurs détaillée.

Nettoyage programmé (implémentation)
- Ce repo inclut une Cloud Function planifiée `cleanFcmTokens` qui :
	- migre `fcmToken` (champ unique) vers `fcmTokens` (tableau),
	- supprime les entrées vides et déduplique les tokens,
	- s'exécute toutes les 24h (Cloud Scheduler via `functions.pubsub.schedule`).

Support multi-collections
- Les fonctions `onMessageCreate` et `onCallCreate` cherchent désormais les utilisateurs
	dans les collections `classic_users`, `pro_users`, `enterprise_users` et utilisent
	la map `chat.userTypes` si présente pour déterminer la collection préférée.

Si vous voulez que j'ajoute un script de test, un linter ou que j'adapte les fonctions aux collections d'utilisateurs (`pro_users`, `enterprise_users`), je peux le faire.

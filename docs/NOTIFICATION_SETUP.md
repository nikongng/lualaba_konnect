Guide rapide pour sonnerie personnalisée et notifications

Android (native):
- Placez votre fichier MP3/OGG dans `android/app/src/main/res/raw/` (créez le dossier `raw` si nécessaire).
- Dans `android/app/src/main/AndroidManifest.xml`, la configuration du canal de notification peut référencer le son. Avec `flutter_local_notifications` vous pouvez définir le son dans `AndroidNotificationDetails` via `sound: RawResourceAndroidNotificationSound('your_ringtone')`.

iOS:
- Ajoutez la sonnerie au runner (Xcode) et cochez la cible. Configurez `UNNotificationSound` avec le nom du fichier si vous utilisez des notifications locales.

Flutter:
- `flutter_local_notifications` permet de définir un son personnalisé au moment d'afficher la notification. Exemple :

final androidDetails = AndroidNotificationDetails('channelId', 'Channel', sound: RawResourceAndroidNotificationSound('your_ringtone'));

- Nous utilisons actuellement le son natif via `flutter_ringtone_player`. Pour utiliser un asset, remplacez `playRingtone()` pour jouer un asset via `flutter_local_notifications` ou `flutter_ringtone_player` si supporté.

Cloud Functions:
- La Cloud Function fournie (`functions/index.js`) envoie un FCM au callee. Pour que le téléphone réagisse (sonnerie + écran d'appel), la logique côté app doit traiter le message `data.type == 'call'` et afficher l'UI.

Remarques:
- Assurez-vous que les tokens FCM des utilisateurs sont stockés (ex: `classic_users/{uid}.fcmToken`).
- Sur Android 13+, vérifiez les permissions runtime pour notifications.

Ajout d'une sonnerie personnalisée

1) Placez votre fichier audio (MP3/OGG) à :
   `android/app/src/main/res/raw/my_ringtone.mp3` (Android)
   et/ou
   `ios/Runner/my_ringtone.caf` (iOS) via Xcode.

2) Ou placez l'asset Flutter dans : `assets/sounds/ringtone.mp3` (déclaré dans `pubspec.yaml`).

3) Android : pour utiliser le son raw, modifiez le canal dans le code si besoin. Exemple (déjà supporté) :
   - `NotificationService.playRingtone()` essaie d'abord `assets/sounds/ringtone.mp3`.
   - Si vous préférez le raw Android, copiez `my_ringtone.mp3` dans `android/app/src/main/res/raw/` et utilisez son nom dans les `AndroidNotificationDetails` :
     `sound: RawResourceAndroidNotificationSound('my_ringtone')`.

4) iOS : ajoutez le fichier dans Runner via Xcode et assurez-vous que "Target Membership" est coché. Pour les notifications locales, utilisez `DarwinNotificationDetails(sound: 'my_ringtone.caf')`.

5) Test :
   - Lancez l'app sur Android/iOS, provoquez un appel entrant (ou envoyez une notification FCM de type `call`) ; la sonnerie personnalisée sera jouée si présente.

Notes:
- Pour avoir une boucle fiable côté Android, la solution la plus robuste est d'utiliser le son système ou `flutter_ringtone_player` avec l'asset. Sur iOS, la lecture d'un son long en boucle peut être restreinte par le système; utilisez plutôt un son court et répétez si nécessaire côté application.

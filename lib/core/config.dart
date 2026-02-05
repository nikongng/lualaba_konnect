// Configuration centralisée pour constantes d'environnement
const String kNotifierUrl = String.fromEnvironment(
  'NOTIFIER_URL',
  defaultValue: 'https://lualaba-konnect.onrender.com/sendNotification',
);

// Uri d'aide pour l'envoi de requêtes (utilisez `Uri.parse(kNotifierUrl)` si vous préférez parser localement)
final Uri notifierUri = Uri.parse(kNotifierUrl);

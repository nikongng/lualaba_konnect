// Configuration centralisée pour constantes d'environnement
const String kNotifierUrl = String.fromEnvironment(
  'NOTIFIER_URL',
  defaultValue: 'https://lualaba-konnect.onrender.com/sendNotification',
);

// Uri d'aide pour l'envoi de requêtes (utilisez `Uri.parse(kNotifierUrl)` si vous préférez parser localement)
final Uri notifierUri = Uri.parse(kNotifierUrl);

// Cloud Functions (Express API)
const String kFunctionsApiUrl = String.fromEnvironment(
  'FUNCTIONS_API_URL',
  defaultValue: 'https://us-central1-lualaba-konnect.cloudfunctions.net/api',
);

final Uri functionsApiUri = Uri.parse(kFunctionsApiUrl);

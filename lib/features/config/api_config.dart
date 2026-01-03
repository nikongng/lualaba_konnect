import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  // Récupère la clé OpenWeather
  static String get openWeatherKey => dotenv.env['OPENWEATHER_API_KEY'] ?? "";

  // Récupère la clé Gemini pour le chat avec Masta
  static String get geminiKey => dotenv.env['GEMINI_API_KEY'] ?? "";
}
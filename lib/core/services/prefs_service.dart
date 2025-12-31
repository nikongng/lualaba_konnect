import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static const String _keyIsRegistered = "is_registered";

  // Appeler ceci quand l'inscription est réussie
  static Future<void> markAsRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsRegistered, true);
  }

  // Vérifier si l'utilisateur est déjà inscrit
  static Future<bool> isUserRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsRegistered) ?? false;
  }
}
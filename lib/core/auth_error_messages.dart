import 'package:firebase_auth/firebase_auth.dart';

class AuthErrorMessages {
  static String fromFirebaseAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return "Adresse email invalide.";
      case 'user-not-found':
        return "Aucun compte trouvé avec cet email.";
      case 'wrong-password':
        return "Mot de passe incorrect.";
      case 'invalid-credential':
        return "Email ou mot de passe incorrect.";
      case 'user-disabled':
        return "Ce compte a été désactivé. Contacte le support.";
      case 'too-many-requests':
        return "Trop de tentatives. Réessaie plus tard.";
      case 'network-request-failed':
        return "Problème de connexion internet. Vérifie ta connexion puis réessaie.";

      case 'email-already-in-use':
        return "Cet email est déjà utilisé. Connecte-toi ou utilise un autre email.";
      case 'weak-password':
        return "Mot de passe trop faible (minimum 6 caractères).";
      case 'operation-not-allowed':
        return "Cette méthode de connexion n'est pas activée.";
      case 'requires-recent-login':
        return "Pour des raisons de sécurité, reconnecte-toi puis réessaie.";

      case 'account-exists-with-different-credential':
        return "Ce compte existe déjà avec une autre méthode de connexion.";
      case 'credential-already-in-use':
        return "Ces identifiants sont déjà utilisés par un autre compte.";
    }

    final msg = (e.message ?? '').trim();
    if (msg.isNotEmpty) return msg;
    return "Une erreur est survenue. Réessaie.";
  }
}


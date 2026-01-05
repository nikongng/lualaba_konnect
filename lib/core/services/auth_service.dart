import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore ajouté

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Créer le compte complet
  Future<User?> registerUser({
    required String email,
    required String password,
    required Map<String, dynamic> userData,
  }) async {
    try {
      // 1. Création de l'utilisateur dans Firebase Auth
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = result.user;

      if (user != null) {
        // 2. Sauvegarde des infos complémentaires dans Firestore
        // C'est ici qu'on génère l'ID LK-XXXX vu sur ton profil
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'idKonnect': "LK-${user.uid.substring(0, 5).toUpperCase()}",
          ...userData,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return user;
    } catch (e) {
      print("Erreur d'inscription: $e");
      rethrow;
    }
  }
}
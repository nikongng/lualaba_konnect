import 'package:cloud_firestore/cloud_firestore.dart';

class HealthUserContext {
  final String userId;
  final String userCollection;

  const HealthUserContext({
    required this.userId,
    required this.userCollection,
  });

  DocumentReference<Map<String, dynamic>> get userRef =>
      FirebaseFirestore.instance.collection(userCollection).doc(userId);

  CollectionReference<Map<String, dynamic>> subCollection(String name) {
    return userRef.collection(name);
  }
}

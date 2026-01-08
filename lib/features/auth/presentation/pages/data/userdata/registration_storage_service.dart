import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import 'package:firebase_storage/firebase_storage.dart';

class RegistrationStorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// 📄 Upload du document PDF (pièce d'identité)
  static Future<String> uploadIdentityPdf({
    required String uid,
    required File? file,
    Uint8List? webBytes,
  }) async {
    try {
      final ref = _storage
          .ref()
          .child('users')
          .child(uid)
          .child('documents')
          .child('identity.pdf');

      UploadTask uploadTask;

      if (kIsWeb) {
        if (webBytes == null) {
          throw Exception("PDF bytes manquants (web)");
        }
        uploadTask = ref.putData(
          webBytes,
          SettableMetadata(contentType: 'application/pdf'),
        );
      } else {
        if (file == null) {
          throw Exception("Fichier PDF manquant (mobile)");
        }
        uploadTask = ref.putFile(
          file,
          SettableMetadata(contentType: 'application/pdf'),
        );
      }

      // Log progress events (utile pour debug web) et sécuriser l'upload avec un timeout
      try {
        uploadTask.snapshotEvents.listen((TaskSnapshot s) {
          debugPrint('uploadIdentityPdf: state=${s.state} transferred=${s.bytesTransferred} total=${s.totalBytes}');
        }, onError: (err) {
          debugPrint('uploadIdentityPdf: snapshotEvents error: $err');
        });

        final snapshot = await uploadTask.timeout(const Duration(seconds: 60), onTimeout: () {
          try {
            uploadTask.cancel();
          } catch (_) {}
          throw TimeoutException('Upload du PDF expiré. Possible cause: CORS blocked or network issue. Vérifiez la configuration CORS du bucket et vos règles Firebase Storage.');
        });
        final url = await snapshot.ref.getDownloadURL();
        return url;
      } catch (e) {
        debugPrint('uploadIdentityPdf error: $e');
        rethrow;
      }
    } catch (e) {
      throw Exception("Erreur upload PDF : $e");
    }
  }

  /// 🤳 Upload du selfie utilisateur
  static Future<String> uploadSelfie({
    required String uid,
    required File? file,
    Uint8List? webBytes,
  }) async {
    try {
      final ref = _storage
          .ref()
          .child('users')
          .child(uid)
          .child('documents')
          .child('selfie.jpg');

      UploadTask uploadTask;

      if (kIsWeb) {
        if (webBytes == null) {
          throw Exception("Image selfie manquante (web)");
        }
        uploadTask = ref.putData(
          webBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
      } else {
        if (file == null) {
          throw Exception("Fichier selfie manquant (mobile)");
        }
        uploadTask = ref.putFile(
          file,
          SettableMetadata(contentType: 'image/jpeg'),
        );
      }

      // Log progress events (utile pour debug web) et sécuriser l'upload avec un timeout
      try {
        uploadTask.snapshotEvents.listen((TaskSnapshot s) {
          debugPrint('uploadSelfie: state=${s.state} transferred=${s.bytesTransferred} total=${s.totalBytes}');
        }, onError: (err) {
          debugPrint('uploadSelfie: snapshotEvents error: $err');
        });

        final snapshot = await uploadTask.timeout(const Duration(seconds: 60), onTimeout: () {
          try {
            uploadTask.cancel();
          } catch (_) {}
          throw TimeoutException('Upload du selfie expiré. Possible cause: CORS blocked or network issue.');
        });
        final url = await snapshot.ref.getDownloadURL();
        return url;
      } catch (e) {
        debugPrint('uploadSelfie error: $e');
        rethrow;
      }
    } catch (e) {
      throw Exception("Erreur upload selfie : $e");
    }
  }
}

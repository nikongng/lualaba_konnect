import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

// Firebase Storage removed: uploads for registration use Supabase only
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:lualaba_konnect/core/supabase_service.dart';

class RegistrationStorageService {
  static const int _maxRetries = 3;

  static Future<void> _ensureOnline() async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) {
      throw Exception('Pas de connexion réseau. Vérifiez votre connexion internet.');
    }
  }

  static Future<Uint8List> _maybeCompressImage(File file) async {
    try {
      final originalSize = await file.length();
      // If small (<100KB), skip compression
      if (originalSize < 100 * 1024) return file.readAsBytes();

      // targetQuality depends on size
      int quality = 80;
      if (originalSize > 1024 * 1024) quality = 60; // >1MB
      return await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        quality: quality,
        rotate: 0,
      ).then((v) => v ?? file.readAsBytes());
    } catch (e) {
      debugPrint('Compression failed, using original file: $e');
      return file.readAsBytes();
    }
  }

  /// 📄 Upload du document PDF (pièce d'identité)
  static Future<String> uploadIdentityPdf({
    required String uid,
    required File? file,
    Uint8List? webBytes,
  }) async {
    try {
      await _ensureOnline();

      // Prefer Supabase when available (mobile or web). Use 'IDENTITY' bucket.
      if (!SupabaseService.isInitialized) {
        throw Exception('Supabase non initialisé — upload des documents d\'identité requis sur Supabase (bucket IDENTITY).');
      }

      // Prefer Supabase when available
      if (kIsWeb) {
        if (webBytes == null) throw Exception('PDF bytes manquants (web)');
        final fileName = 'identity_${DateTime.now().millisecondsSinceEpoch}.pdf';
        try {
          return await SupabaseService.uploadBytes(webBytes, fileName, 'identity');
        } catch (e) {
          debugPrint('Supabase upload failed (web) for identity: $e');
          throw Exception('Supabase upload failed: $e');
        }
      } else {
        if (file == null) throw Exception('Fichier PDF manquante (mobile)');
        final tmp = File('${Directory.systemTemp.path}/identity_${DateTime.now().millisecondsSinceEpoch}.pdf');
        final bytes = await file.readAsBytes();
        await tmp.writeAsBytes(bytes);
        try {
          final publicUrl = await SupabaseService.uploadFile(tmp, 'identity');
          try { await tmp.delete(); } catch (_) {}
          return publicUrl;
        } catch (e) {
          try { await tmp.delete(); } catch (_) {}
          debugPrint('Supabase identity upload failed (mobile): $e');
          throw Exception('Supabase upload failed: $e');
        }
      }

      // handled above using Supabase; no Firebase fallback
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
      await _ensureOnline();

      // Require Supabase for selfie uploads to bucket 'IDENTITY'
      if (!SupabaseService.isInitialized) {
        throw Exception('Supabase non initialisé — upload du selfie requis sur Supabase (bucket IDENTITY).');
      }

      // prepare bytes (compress if mobile)
      if (kIsWeb) {
        if (webBytes == null) throw Exception('Image selfie manquante (web)');
        final fileName = 'selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';
        try {
          return await SupabaseService.uploadBytes(webBytes, fileName, 'identity');
        } catch (e) {
          debugPrint('Supabase upload failed (web) for selfie: $e');
          throw Exception('Supabase upload failed: $e');
        }
      } else {
        if (file == null) throw Exception('Fichier selfie manquant (mobile)');
        final bytes = await _maybeCompressImage(file);
        final tmp = File('${Directory.systemTemp.path}/selfie_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tmp.writeAsBytes(bytes);
        int attempt = 0;
        while (true) {
          attempt++;
          try {
            final publicUrl = await SupabaseService.uploadFile(tmp, 'identity');
            try { await tmp.delete(); } catch (_) {}
            return publicUrl;
          } catch (e) {
            debugPrint('Supabase selfie upload attempt $attempt failed: $e');
            if (attempt >= _maxRetries) {
              try { await tmp.delete(); } catch (_) {}
              debugPrint('Supabase selfie final failure');
              throw Exception('Supabase upload failed: $e');
            }
            await Future.delayed(Duration(milliseconds: 500 * math.pow(2, attempt).toInt()));
          }
        }
      }


      // handled above using Supabase; no Firebase fallback
    } catch (e) {
      throw Exception("Erreur upload selfie : $e");
    }
  }
}
  // No fallback: rely only on Supabase. Errors are rethrown as Supabase upload failures.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static bool _initialized = false;

  // Public getter to check whether Supabase was initialized
  static bool get isInitialized => _initialized;

  static Future<void> init({required String url, required String anonKey}) async {
    if (_initialized) return;
    debugPrint('SupabaseService.init: url=$url anonKey=${anonKey.substring(0,8)}...');
    await Supabase.initialize(url: url, anonKey: anonKey);
    _initialized = true;
    debugPrint('SupabaseService: initialized');
  }

  static SupabaseClient get client => Supabase.instance.client;

  /// Ensure the storage bucket exists. Tries to create it if missing.
  /// Note: creating buckets may require elevated (service_role) privileges.
  static Future<void> ensureBucketExists(String bucket) async {
    try {
      debugPrint('SupabaseService.ensureBucketExists: checking/creating bucket "$bucket"');
      // attempt to create the bucket; if the method is not permitted or already exists,
      // Supabase will return an error which we catch and log.
      await client.storage.createBucket(bucket);
      debugPrint('SupabaseService.ensureBucketExists: createBucket returned (ok) for $bucket');
    } catch (e) {
      debugPrint('SupabaseService.ensureBucketExists: createBucket error (may already exist or insufficient permissions): $e');
    }
  }

  /// Upload a file to the given bucket (folder). Returns public URL or throws.
  static Future<String> uploadFile(File file, String bucket) async {
    if (!_initialized) throw Exception('Supabase not initialized');
    final bytes = await file.readAsBytes();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.uri.pathSegments.last}';
    try {
      // Ensure bucket exists (best-effort). If creation requires service role it will fail silently.
      await ensureBucketExists(bucket);
      debugPrint('SupabaseService.uploadFile: uploading to bucket="$bucket", file="$fileName", size=${bytes.length}');
      await client.storage.from(bucket).uploadBinary(fileName, bytes);
      debugPrint('SupabaseService.uploadFile: upload succeeded for $fileName');
    } catch (e) {
      debugPrint('SupabaseService.uploadFile: upload error (${e.runtimeType}): $e');
      // If the error indicates bucket not found, attempt to create then retry once.
      final msg = e.toString();
      if (msg.toLowerCase().contains('bucket not found') || msg.toLowerCase().contains('404')) {
        try {
          debugPrint('SupabaseService.uploadFile: bucket missing, attempting create+retry for $bucket');
          await ensureBucketExists(bucket);
          await client.storage.from(bucket).uploadBinary(fileName, bytes);
          final public = client.storage.from(bucket).getPublicUrl(fileName);
          debugPrint('SupabaseService.uploadFile: retry succeeded for $fileName');
          return public.toString();
        } catch (e2) {
          debugPrint('SupabaseService.uploadFile: retry failed: $e2');
          throw Exception('Supabase upload failed: $e2');
        }
      }
      throw Exception('Supabase upload failed: $e');
    }

    // getPublicUrl may return a String (depending on package version).
    final public = client.storage.from(bucket).getPublicUrl(fileName);
    debugPrint('SupabaseService.uploadFile: publicUrl=$public');
    return public.toString();
  }

  /// Upload raw bytes to Supabase storage. Returns public URL or throws.
  static Future<String> uploadBytes(Uint8List bytes, String filename, String bucket) async {
    if (!_initialized) throw Exception('Supabase not initialized');
    try {
      // Ensure bucket exists (best-effort)
      await ensureBucketExists(bucket);
      debugPrint('SupabaseService.uploadBytes: uploading to bucket="$bucket", file="$filename", size=${bytes.length}');
      await client.storage.from(bucket).uploadBinary(filename, bytes);
      debugPrint('SupabaseService.uploadBytes: upload succeeded for $filename');
    } catch (e) {
      debugPrint('SupabaseService.uploadBytes: upload error (${e.runtimeType}): $e');
      final msg = e.toString();
      if (msg.toLowerCase().contains('bucket not found') || msg.toLowerCase().contains('404')) {
        try {
          debugPrint('SupabaseService.uploadBytes: bucket missing, attempting create+retry for $bucket');
          await ensureBucketExists(bucket);
          await client.storage.from(bucket).uploadBinary(filename, bytes);
          final public = client.storage.from(bucket).getPublicUrl(filename);
          debugPrint('SupabaseService.uploadBytes: retry succeeded for $filename');
          return public.toString();
        } catch (e2) {
          debugPrint('SupabaseService.uploadBytes: retry failed: $e2');
          throw Exception('Supabase upload failed: $e2');
        }
      }
      throw Exception('Supabase upload failed: $e');
    }
    final public = client.storage.from(bucket).getPublicUrl(filename);
    debugPrint('SupabaseService.uploadBytes: publicUrl=$public');
    return public.toString();
  }
}

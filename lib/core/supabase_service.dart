import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static bool _initialized = false;
  static String? _url;
  static String? _anonKey;
  static bool _bucketCreateWarningShown = false;

  // Public getter to check whether Supabase was initialized
  static bool get isInitialized => _initialized;

  static Future<void> init({required String url, required String anonKey}) async {
    if (_initialized) return;
    debugPrint('SupabaseService.init: url=$url anonKey=${anonKey.substring(0,8)}...');
    await Supabase.initialize(url: url, anonKey: anonKey);
    _url = url;
    _anonKey = anonKey;
    _initialized = true;
    debugPrint('SupabaseService: initialized');
  }

  static SupabaseClient get client => Supabase.instance.client;

  static String get supabaseUrl {
    final u = _url;
    if (u == null || u.isEmpty) throw Exception('Supabase url is missing');
    return u;
  }

  static String get anonKey {
    final k = _anonKey;
    if (k == null || k.isEmpty) throw Exception('Supabase anon key is missing');
    return k;
  }

  static Map<String, String> _storageHeaders({String? contentType}) {
    final token = client.auth.currentSession?.accessToken;
    return <String, String>{
      'apikey': anonKey,
      'Authorization': 'Bearer ${token ?? anonKey}',
      if (contentType != null && contentType.trim().isNotEmpty) 'Content-Type': contentType.trim(),
      'x-upsert': 'true',
    };
  }

  /// Ensure the storage bucket exists. Tries to create it if missing.
  /// Note: creating buckets may require elevated (service_role) privileges.
  static Future<void> ensureBucketExists(String bucket) async {
    // Buckets should be provisioned in Supabase dashboard (or server-side).
    // Client-side bucket creation requires elevated privileges and is expected to fail.
    if (!_bucketCreateWarningShown) {
      _bucketCreateWarningShown = true;
      debugPrint(
        'SupabaseService.ensureBucketExists: skipped on client. '
        'Create bucket "$bucket" in Supabase dashboard.',
      );
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

  /// Upload a file to the given bucket with a provided object path (filename).
  /// Can report progress (best-effort) on mobile/desktop. On Web, progress is not available.
  static Future<String> uploadFileNamed(
    File file,
    String objectPath,
    String bucket, {
    void Function(int sentBytes, int totalBytes)? onProgress,
    String? contentType,
  }) async {
    if (!_initialized) throw Exception('Supabase not initialized');
    if (objectPath.trim().isEmpty) throw Exception('objectPath is empty');

    await ensureBucketExists(bucket);

    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      await client.storage.from(bucket).uploadBinary(objectPath, bytes);
      return client.storage.from(bucket).getPublicUrl(objectPath).toString();
    }

    final totalBytes = await file.length();
    onProgress?.call(0, totalBytes);

    final uri = Uri.parse('$supabaseUrl/storage/v1/object/$bucket/$objectPath');
    final req = http.StreamedRequest('POST', uri);
    req.contentLength = totalBytes;
    req.headers.addAll(_storageHeaders(contentType: contentType));

    int sent = 0;
    int lastTick = DateTime.now().millisecondsSinceEpoch;
    await for (final chunk in file.openRead()) {
      req.sink.add(chunk);
      sent += chunk.length;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastTick > 90 || sent >= totalBytes) {
        lastTick = now;
        onProgress?.call(sent, totalBytes);
      }
    }
    await req.sink.close();

    final resp = await req.send();
    final ok = resp.statusCode >= 200 && resp.statusCode < 300;
    if (!ok) {
      final body = await resp.stream.bytesToString();
      throw Exception('Supabase upload failed (${resp.statusCode}): $body');
    }

    onProgress?.call(totalBytes, totalBytes);
    return client.storage.from(bucket).getPublicUrl(objectPath).toString();
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

  /// Upload raw bytes to Supabase storage with provided object path and optional progress.
  /// Note: On most platforms, this reports only coarse progress unless the bytes are chunked.
  static Future<String> uploadBytesNamed(
    Uint8List bytes,
    String objectPath,
    String bucket, {
    void Function(int sentBytes, int totalBytes)? onProgress,
    String? contentType,
  }) async {
    if (!_initialized) throw Exception('Supabase not initialized');
    if (objectPath.trim().isEmpty) throw Exception('objectPath is empty');

    await ensureBucketExists(bucket);

    if (kIsWeb) {
      await client.storage.from(bucket).uploadBinary(objectPath, bytes);
      onProgress?.call(bytes.length, bytes.length);
      return client.storage.from(bucket).getPublicUrl(objectPath).toString();
    }

    final totalBytes = bytes.length;
    onProgress?.call(0, totalBytes);

    final uri = Uri.parse('$supabaseUrl/storage/v1/object/$bucket/$objectPath');
    final req = http.StreamedRequest('POST', uri);
    req.contentLength = totalBytes;
    req.headers.addAll(_storageHeaders(contentType: contentType));

    // Chunk to provide progress updates.
    const chunkSize = 64 * 1024;
    int sent = 0;
    int lastTick = DateTime.now().millisecondsSinceEpoch;
    while (sent < totalBytes) {
      final end = (sent + chunkSize) > totalBytes ? totalBytes : (sent + chunkSize);
      req.sink.add(bytes.sublist(sent, end));
      sent = end;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastTick > 90 || sent >= totalBytes) {
        lastTick = now;
        onProgress?.call(sent, totalBytes);
      }
    }
    await req.sink.close();

    final resp = await req.send();
    final ok = resp.statusCode >= 200 && resp.statusCode < 300;
    if (!ok) {
      final body = await resp.stream.bytesToString();
      throw Exception('Supabase upload failed (${resp.statusCode}): $body');
    }

    onProgress?.call(totalBytes, totalBytes);
    return client.storage.from(bucket).getPublicUrl(objectPath).toString();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MediaTransferService {
  MediaTransferService._();

  static final MediaTransferService instance = MediaTransferService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Set<String> _downloading = <String>{};
  final Map<String, int> _receivedBytes = <String, int>{};
  final Map<String, int?> _totalBytes = <String, int?>{};
  final Map<String, Future<File?>> _tasks = <String, Future<File?>>{};

  bool isDownloading(String key) => _downloading.contains(key);
  int receivedBytes(String key) => _receivedBytes[key] ?? 0;
  int? totalBytes(String key) => _totalBytes[key];

  void _bump() => revision.value = (revision.value + 1) & 0x7fffffff;

  Future<File?> downloadToFile({
    required String url,
    required File dest,
    int? expectedBytes,
  }) {
    if (_tasks.containsKey(url)) return _tasks[url]!;
    final fut = _downloadToFileImpl(url: url, dest: dest, expectedBytes: expectedBytes);
    _tasks[url] = fut;
    return fut;
  }

  Future<File?> _downloadToFileImpl({
    required String url,
    required File dest,
    int? expectedBytes,
  }) async {
    http.Client? client;
    IOSink? sink;
    try {
      if (url.isEmpty) return null;
      if (kIsWeb) return null;

      // If already downloaded, return it immediately.
      if (dest.existsSync()) return dest;

      _downloading.add(url);
      _receivedBytes[url] = 0;
      _totalBytes[url] = expectedBytes;
      _bump();

      if (!dest.parent.existsSync()) {
        dest.parent.createSync(recursive: true);
      }

      client = http.Client();
      final resp = await client.send(http.Request('GET', Uri.parse(url)));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }

      final total = (resp.contentLength != null && resp.contentLength! > 0) ? resp.contentLength : expectedBytes;
      _totalBytes[url] = total;
      _bump();

      sink = dest.openWrite();
      int received = 0;
      int lastTick = DateTime.now().millisecondsSinceEpoch;

      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastTick > 90 || (total != null && received >= total)) {
          lastTick = now;
          _receivedBytes[url] = received;
          _bump();
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      _receivedBytes[url] = received;
      _bump();

      return dest;
    } catch (_) {
      return null;
    } finally {
      try {
        await sink?.flush();
        await sink?.close();
      } catch (_) {}
      try {
        client?.close();
      } catch (_) {}

      _downloading.remove(url);
      _receivedBytes.remove(url);
      _totalBytes.remove(url);
      _tasks.remove(url);
      _bump();
    }
  }
}


import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart' as fs;
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_manager/photo_manager.dart';
import 'attachment_menu.dart';
import 'call_webrtc_page.dart';
import 'group_call_webrtc_page.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:lualaba_konnect/screnns/camera_screen.dart';
import 'package:lualaba_konnect/screnns/media_preview_screen.dart';
import 'package:lualaba_konnect/core/supabase_service.dart';
import 'package:lualaba_konnect/widgets/animated_chat_background.dart';
import 'package:lottie/lottie.dart';
import 'user_utils.dart';
import 'group_chat_detail_page.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lualaba_konnect/core/config.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:lualaba_konnect/core/media_transfer_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:lualaba_konnect/shared/widgets/account_badge.dart';

const Color tgBg = Color(0xFF0B1418);
const Color tgAccent = Color(0xFF00CBA9);
// Outgoing bubble (dark blue, WhatsApp-ish vibe).
const Color tgMyBubble = Color(0xFF0B3A6D);
const Color tgOtherBubble = Color(0xFF2E2F4F);
const Color tgBar = Color(0xFF071011);

class ChatDetailPage extends StatefulWidget {
  final String chatId;
  final String chatName;

  const ChatDetailPage({
    super.key,
    required this.chatId,
    required this.chatName,
  });

  @override
  State<ChatDetailPage> createState() => _ChatState();
}

class _ChatState extends State<ChatDetailPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _msgController = TextEditingController();
  final currentUser = FirebaseAuth.instance.currentUser;
  String? _cachedSenderUid;
  String? _cachedSenderName;
  String? _cachedSenderPhoto;
  fs.FlutterSoundRecorder? _recorder;
  bool _recorderInitialized = false;
  late final VoidCallback _msgListener;
  bool _showEmoji = false;

  bool _isLoading = false;
  String? _uploadLabel;
  int? _uploadTotalBytes;
  int _uploadSentBytes = 0;
  bool _uploadVisualSuccess = false;
  double _uploadVisualProgress = 0.0;
  Timer? _uploadProgressPulseTimer;
  String? _uploadPreviewType;
  String? _uploadPreviewPath;
  Uint8List? _uploadPreviewBytes;
  bool _isRecording = false;
  bool _recordLocked = false;
  bool _recordCanceled = false;
  bool _hasText = false;
  double? _recordStartDx;
  double? _recordStartDy;
  late final AnimationController _lockHintCtrl;
  Timer? _recordTimer;
  final ValueNotifier<int> _recordSecondsNotifier = ValueNotifier<int>(0);
  Timer? _bgTimer;
  int _bgIndex = 0;
  // sound effects
  final _sfxPlayer = AudioPlayer();
  bool _messageStreamInitialized = false;
  bool _markingReceipts = false;

  Future<Map<String, String>> _resolveSenderMeta(User user) async {
    // Cache to avoid hitting Firestore on every message/call.
    if (_cachedSenderUid == user.uid &&
        _cachedSenderName != null &&
        _cachedSenderName!.trim().isNotEmpty &&
        _cachedSenderPhoto != null &&
        _cachedSenderPhoto!.trim().isNotEmpty) {
      return {
        'name': _cachedSenderName!.trim(),
        'photo': _cachedSenderPhoto!.trim(),
      };
    }

    String name = (user.displayName ?? '').trim();
    String photo = (user.photoURL ?? '').trim();

    // Fallback to Firestore profile (works for web too).
    try {
      final cols = ['classic_users', 'pro_users', 'enterprise_users'];
      for (final col in cols) {
        final snap = await FirebaseFirestore.instance
            .collection(col)
            .doc(user.uid)
            .get();
        if (!snap.exists) continue;
        final d = snap.data() ?? <String, dynamic>{};

        String pickString(List<String> keys) {
          for (final k in keys) {
            final v = d[k];
            if (v == null) continue;
            final s = v.toString().trim();
            if (s.isNotEmpty) return s;
          }
          return '';
        }

        name = name.isNotEmpty
            ? name
            : (pickString(['displayName', 'name', 'username']).isNotEmpty
                  ? pickString(['displayName', 'name', 'username'])
                  : '${pickString(['firstName'])} ${pickString(['lastName'])}'
                        .trim());

        if (photo.isEmpty) {
          photo = pickString([
            'photoUrl',
            'avatarUrl',
            'profileImageUrl',
            'imageUrl',
          ]);
        }
        break;
      }
    } catch (_) {
      // Best-effort only.
    }

    if (name.isEmpty) name = 'Un utilisateur';
    if (photo.isEmpty)
      photo = 'https://cdn-icons-png.flaticon.com/512/149/149071.png';

    _cachedSenderUid = user.uid;
    _cachedSenderName = name;
    _cachedSenderPhoto = photo;
    return {'name': name, 'photo': photo};
  }

  // tracked for potential use by other logic; keep but silence unused warning
  // ignore: unused_field
  String? _lastMessageId;
  StreamSubscription<QuerySnapshot>? _messagesSub;
  final Map<String, bool> _deliveredMap = {};
  final List<List<Color>> _bgGradients = [
    [Color(0xFF0B2B3A), Color(0xFF063447)],
    [Color(0xFF063447), Color(0xFF0B3A2F)],
    [Color(0xFF13294A), Color(0xFF1A3A5A)],
  ];
  Timer? _typingTimer;
  // --- MULTI-SELECT STATE ---
  final Set<String> _selectedMessageIds = {};
  bool _selectionMode = false;
  bool _isGroupChat = false;
  final ScrollController _listController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  String? _pendingJumpMessageId;
  String? _highlightMessageId;
  final MediaTransferService _mediaTransfers = MediaTransferService.instance;
  late final VoidCallback _mediaTransferListener;

  // --- REPLY (WhatsApp-style swipe-to-reply) ---
  Map<String, dynamic>? _replyTo; // persisted into Firestore as `replyTo`

  bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  Color _modalBg(BuildContext context) =>
      _isDark(context) ? tgBar : Colors.white;
  Color _modalText(BuildContext context) =>
      _isDark(context) ? Colors.white : Colors.black87;
  Color _modalSub(BuildContext context) =>
      _isDark(context) ? Colors.white70 : Colors.black54;
  Color _modalMuted(BuildContext context) =>
      _isDark(context) ? Colors.white54 : Colors.black45;
  Color _modalTileBg(BuildContext context) =>
      _isDark(context) ? Colors.white10 : Colors.black12;

  String _safeExtFromName(String? name) {
    if (name == null) return '';
    final i = name.lastIndexOf('.');
    if (i == -1 || i == name.length - 1) return '';
    final ext = name.substring(i).toLowerCase();
    if (ext.length > 10) return '';
    final ok = RegExp(r'^\.[a-z0-9]+$').hasMatch(ext);
    return ok ? ext : '';
  }

  bool _looksLikeVideo(String? nameOrExt) {
    if (nameOrExt == null || nameOrExt.trim().isEmpty) return false;
    final s = nameOrExt.toLowerCase();
    final ext = s.startsWith('.')
        ? s.substring(1)
        : (s.contains('.') ? s.split('.').last : s);
    const vids = {'mp4', 'mov', 'm4v', '3gp', 'webm', 'mkv', 'avi'};
    return vids.contains(ext);
  }

  Map<String, dynamic> _extractUploadPreview(dynamic fileSource, String type) {
    String? previewPath;
    Uint8List? previewBytes;
    if (type == 'image') {
      if (fileSource is XFile) {
        final p = fileSource.path;
        if (!kIsWeb && p.isNotEmpty) previewPath = p;
      } else if (fileSource is PlatformFile) {
        if (!kIsWeb) {
          final p = fileSource.path;
          if (p != null && p.isNotEmpty) {
            previewPath = p;
          }
        }
        if (previewPath == null &&
            fileSource.bytes != null &&
            fileSource.bytes!.isNotEmpty &&
            fileSource.bytes!.lengthInBytes <= (2 * 1024 * 1024)) {
          previewBytes = fileSource.bytes;
        }
      } else if (fileSource is File) {
        if (!kIsWeb) previewPath = fileSource.path;
      } else if (fileSource is Uint8List) {
        if (fileSource.isNotEmpty &&
            fileSource.lengthInBytes <= (2 * 1024 * 1024)) {
          previewBytes = fileSource;
        }
      }
    }
    return <String, dynamic>{
      'type': type,
      'path': previewPath,
      'bytes': previewBytes,
    };
  }

  void _startUploadVisualProgressPulse() {
    _uploadProgressPulseTimer?.cancel();
    _uploadProgressPulseTimer = Timer.periodic(
      const Duration(milliseconds: 140),
      (_) {
        if (!mounted || !_isLoading || _uploadVisualSuccess) return;
        final int total = (_uploadTotalBytes != null && _uploadTotalBytes! > 0)
            ? _uploadTotalBytes!
            : 0;
        final double rawProgress = total > 0
            ? (_uploadSentBytes / total).clamp(0.0, 1.0)
            : 0.0;
        final double cap = rawProgress > 0 ? 0.98 : 0.96;
        final double current = max(_uploadVisualProgress, rawProgress);
        if (current >= cap) return;
        final double step = current < 0.35
            ? 0.030
            : (current < 0.72 ? 0.018 : 0.010);
        final double next = (current + step).clamp(0.0, cap);
        setState(() {
          _uploadVisualProgress = next;
        });
      },
    );
  }

  void _stopUploadVisualProgressPulse() {
    _uploadProgressPulseTimer?.cancel();
    _uploadProgressPulseTimer = null;
  }

  Future<void> _pickAndSendMultipleMedia() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: true,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;

      setState(() {
        _isLoading = true;
        _uploadVisualSuccess = false;
        _uploadVisualProgress = 0.03;
        _uploadPreviewType = null;
        _uploadPreviewPath = null;
        _uploadPreviewBytes = null;
      });
      _startUploadVisualProgressPulse();
      for (var i = 0; i < res.files.length; i++) {
        final pf = res.files[i];
        final name = pf.name;
        final isVideo = _looksLikeVideo(pf.extension ?? name);
        final msgType = isVideo ? 'video' : 'image';
        final msgText = isVideo ? '🎬 Vidéo' : '📸 Photo';

        if (mounted) {
          setState(() {
            _uploadLabel =
                'Envoi ${i + 1}/${res.files.length} • ${isVideo ? "vidéo" : "photo"}';
            _uploadTotalBytes = pf.size > 0 ? pf.size : null;
            _uploadSentBytes = 0;
            _uploadVisualProgress = max(_uploadVisualProgress, 0.03);
          });
        }

        dynamic source = pf;

        await _uploadAndSend(
          source,
          msgType,
          'chat_media',
          msgText,
          manageLoading: false,
          originalName: name,
        );
      }
    } catch (e) {
      debugPrint('pick multiple media error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadVisualSuccess = false;
          _uploadVisualProgress = 0.0;
          _uploadLabel = null;
          _uploadTotalBytes = null;
          _uploadSentBytes = 0;
          _uploadPreviewType = null;
          _uploadPreviewPath = null;
          _uploadPreviewBytes = null;
        });
        _stopUploadVisualProgressPulse();
      }
    }
  }

  // --- UPLOAD & SAVE HELPERS ---
  Future<void> _uploadAndSend(
    dynamic fileSource,
    String type,
    String folder,
    String text, {
    Map<String, dynamic>? extraData,
    bool manageLoading = true,
    String? originalName,
  }) async {
    final preview = _extractUploadPreview(fileSource, type);
    if (manageLoading) {
      setState(() {
        _isLoading = true;
        _uploadVisualSuccess = false;
        _uploadVisualProgress = 0.03;
        _uploadLabel =
            'Envoi ${type == "video" ? "vidéo" : (type == "image" ? "photo" : "média")}';
        _uploadTotalBytes = null;
        _uploadSentBytes = 0;
        _uploadPreviewType = preview['type'] as String?;
        _uploadPreviewPath = preview['path'] as String?;
        _uploadPreviewBytes = preview['bytes'] as Uint8List?;
      });
      _startUploadVisualProgressPulse();
    } else if (mounted) {
      setState(() {
        if (_uploadVisualSuccess) _uploadVisualSuccess = false;
        _uploadVisualProgress = max(_uploadVisualProgress, 0.03);
        _uploadPreviewType = preview['type'] as String?;
        _uploadPreviewPath = preview['path'] as String?;
        _uploadPreviewBytes = preview['bytes'] as Uint8List?;
      });
      _startUploadVisualProgressPulse();
    }
    try {
      // On Web, JS bit ops can turn `1 << 32` into 0, which breaks nextInt().
      // Use a safe max that works everywhere.
      final nonce = Random()
          .nextInt(0x7fffffff)
          .toRadixString(16)
          .padLeft(8, '0');
      String fileName = '${DateTime.now().microsecondsSinceEpoch}_$nonce';
      // Support XFile/PlatformFile/File/bytes across web and mobile
      Uint8List? bytes;
      File? file;
      String? localName;
      if (fileSource is XFile) {
        localName = fileSource.name;
        try {
          if (kIsWeb) {
            bytes = await fileSource.readAsBytes();
          } else {
            final p = fileSource.path;
            if (p.isNotEmpty) {
              file = File(p);
              if (!(await file.exists())) {
                file = null;
                bytes = await fileSource.readAsBytes();
              }
            } else {
              bytes = await fileSource.readAsBytes();
            }
          }
        } catch (_) {}
      } else if (fileSource is PlatformFile) {
        localName = fileSource.name;
        bytes = fileSource.bytes;
        if (bytes == null) {
          if (!kIsWeb) {
            final path = fileSource.path;
            if (path != null && path.isNotEmpty) {
              file = File(path);
              try {
                if (!(await file.exists())) file = null;
              } catch (_) {}
            }
          }
          if (file == null && fileSource.readStream != null) {
            bytes = await _readStreamToBytes(fileSource.readStream!);
          }
        }
      } else if (fileSource is Uint8List) {
        bytes = fileSource;
      } else {
        file = fileSource as File;
        try {
          localName = file.path.split(Platform.pathSeparator).last;
        } catch (_) {}
      }

      final ext = _safeExtFromName(originalName) != ''
          ? _safeExtFromName(originalName)
          : (_safeExtFromName(localName) != ''
                ? _safeExtFromName(localName)
                : _safeExtFromName(file?.path));
      if (ext.isNotEmpty) fileName = '$fileName$ext';

      int? sizeBytes;
      try {
        if (bytes != null) {
          sizeBytes = bytes.length;
        } else if (file != null) {
          sizeBytes = await file.length();
        }
      } catch (_) {}
      if (sizeBytes != null && manageLoading && mounted) {
        setState(() {
          _uploadTotalBytes = sizeBytes;
          _uploadVisualProgress = max(_uploadVisualProgress, 0.03);
        });
      }

      String url;
      try {
        // Ensure Supabase is initialized (try to init from --dart-define if missing)
        if (!SupabaseService.isInitialized) {
          try {
            final su = const String.fromEnvironment('SUPABASE_URL');
            final sk = const String.fromEnvironment('SUPABASE_ANON_KEY');
            if (su.isNotEmpty && sk.isNotEmpty) {
              await SupabaseService.init(url: su, anonKey: sk);
              debugPrint('SupabaseService init attempted in uploadAndSend.');
            } else {
              debugPrint(
                'Supabase keys not provided at runtime (upload will fallback to Firebase).',
              );
            }
          } catch (ie) {
            debugPrint('Error trying to init SupabaseService on demand: $ie');
          }
        }

        // try Supabase - use provided folder as bucket (chat media -> 'chat_media', stories -> 'stories')
        final supabaseBucket = folder;
        debugPrint(
          'SupabaseService.isInitialized = ${SupabaseService.isInitialized}',
        );
        if (SupabaseService.isInitialized) {
          int lastTick = 0;
          void onProgress(int sent, int total) {
            if (!manageLoading || !mounted) return;
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - lastTick < 90 && sent < total) return;
            lastTick = now;
            setState(() {
              _uploadSentBytes = sent;
              _uploadTotalBytes = total > 0 ? total : _uploadTotalBytes;
              final int t =
                  (_uploadTotalBytes != null && _uploadTotalBytes! > 0)
                  ? _uploadTotalBytes!
                  : total;
              if (t > 0) {
                final double rp = (sent / t).clamp(0.0, 1.0);
                _uploadVisualProgress = max(
                  _uploadVisualProgress,
                  rp.clamp(0.0, 0.97),
                );
              }
            });
          }

          final String extLower = ext.toLowerCase();
          String? contentType;
          if (type == 'image') {
            if (extLower == '.png')
              contentType = 'image/png';
            else if (extLower == '.webp')
              contentType = 'image/webp';
            else if (extLower == '.gif')
              contentType = 'image/gif';
            else if (extLower == '.heic' || extLower == '.heif')
              contentType = 'image/heic';
            else
              contentType = 'image/jpeg';
          } else if (type == 'video') {
            if (extLower == '.mov')
              contentType = 'video/quicktime';
            else if (extLower == '.webm')
              contentType = 'video/webm';
            else
              contentType = 'video/mp4';
          } else if (type == 'audio' || type == 'voice') {
            if (extLower == '.wav')
              contentType = 'audio/wav';
            else if (extLower == '.m4a')
              contentType = 'audio/mp4';
            else if (extLower == '.ogg' || extLower == '.oga')
              contentType = 'audio/ogg';
            else
              contentType = 'audio/mpeg';
          } else {
            contentType = 'application/octet-stream';
          }

          if (bytes != null) {
            url = await SupabaseService.uploadBytesNamed(
              bytes,
              fileName,
              supabaseBucket,
              onProgress: onProgress,
              contentType: contentType,
            ).timeout(const Duration(seconds: 120));
          } else if (file != null) {
            url = await SupabaseService.uploadFileNamed(
              file,
              fileName,
              supabaseBucket,
              onProgress: onProgress,
              contentType: contentType,
            ).timeout(const Duration(seconds: 120));
          } else {
            throw Exception('No file data to upload');
          }
          debugPrint('Uploaded to Supabase: $url');
        } else {
          throw Exception('Supabase not initialized');
        }
      } catch (e) {
        debugPrint(
          'Supabase upload failed or unavailable: $e — falling back to Firebase Storage',
        );
        Reference ref = FirebaseStorage.instance
            .ref()
            .child(folder)
            .child(fileName);
        final UploadTask task = bytes != null
            ? ref.putData(bytes)
            : ref.putFile(file!);
        final sub = task.snapshotEvents.listen((snap) {
          if (!mounted) return;
          setState(() {
            _uploadSentBytes = snap.bytesTransferred;
            _uploadTotalBytes = snap.totalBytes > 0
                ? snap.totalBytes
                : _uploadTotalBytes;
            if (_uploadTotalBytes != null && _uploadTotalBytes! > 0) {
              final double rp = (_uploadSentBytes / _uploadTotalBytes!).clamp(
                0.0,
                1.0,
              );
              _uploadVisualProgress = max(
                _uploadVisualProgress,
                rp.clamp(0.0, 0.97),
              );
            }
          });
        });
        await task.timeout(const Duration(seconds: 180));
        await sub.cancel();
        url = await ref.getDownloadURL();
      }

      await _saveToFirestore({
        'type': type,
        'url': url,
        'text': text,
        if (sizeBytes != null) 'size': sizeBytes,
        if ((originalName ?? localName)?.trim().isNotEmpty == true)
          'fileName': (originalName ?? localName)!.trim(),
        if (extraData != null) ...extraData,
      });
      await _markUploadUiSuccess(
        fallbackTotal: sizeBytes,
        hold: manageLoading
            ? const Duration(milliseconds: 1300)
            : const Duration(milliseconds: 900),
      );
      // play send sfx
      try {
        await _playSfx('sounds/pop.mp3');
      } catch (_) {}
    } catch (e) {
      debugPrint("Erreur upload: $e");
      _stopUploadVisualProgressPulse();
    }
    if (manageLoading && mounted) {
      setState(() {
        _isLoading = false;
        _uploadVisualSuccess = false;
        _uploadVisualProgress = 0.0;
        _uploadLabel = null;
        _uploadTotalBytes = null;
        _uploadSentBytes = 0;
        _uploadPreviewType = null;
        _uploadPreviewPath = null;
        _uploadPreviewBytes = null;
      });
      _stopUploadVisualProgressPulse();
    }
  }

  Future<void> _markUploadUiSuccess({
    int? fallbackTotal,
    Duration hold = const Duration(milliseconds: 220),
  }) async {
    if (!mounted) return;
    final int resolvedTotal =
        (_uploadTotalBytes != null && _uploadTotalBytes! > 0)
        ? _uploadTotalBytes!
        : ((fallbackTotal != null && fallbackTotal > 0) ? fallbackTotal : 100);
    setState(() {
      _uploadTotalBytes = resolvedTotal;
      _uploadSentBytes = resolvedTotal;
      _uploadVisualProgress = 1.0;
      _uploadLabel = 'Envoi réussi';
      _uploadVisualSuccess = true;
    });
    _stopUploadVisualProgressPulse();
    await Future.delayed(hold);
  }

  Future<Uint8List> _readStreamToBytes(Stream<List<int>> stream) async {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      buffer.add(chunk);
    }
    return buffer.toBytes();
  }

  Future<void> _onMessageOpen(QueryDocumentSnapshot doc, Map m) async {
    try {
      // If this is an alert message, remove pending alert entry for this message
      if (currentUser == null) return;
      if ((m['type'] ?? '') == 'alert') {
        try {
          final pendingRef = FirebaseFirestore.instance
              .collection('user_alerts')
              .doc(currentUser!.uid)
              .collection('pending')
              .doc(doc.id);
          final snap = await pendingRef.get();
          if (snap.exists) await pendingRef.delete();
        } catch (_) {}
      }
      // mark message read (avoid per-message decrement that can become inconsistent)
      try {
        final senderId = (m['senderId'] ?? '').toString();
        if (senderId.isNotEmpty &&
            senderId != currentUser!.uid &&
            (m['isRead'] != true)) {
          await _markMessagesAsDeliveredAndRead([doc]);
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('onMessageOpen error: $e');
    }
  }

  Future<void> _onMenuSelected(String v) async {
    try {
      final chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId);
      final chatSnap = await chatRef.get();
      if (!chatSnap.exists) return;
      final data = chatSnap.data() ?? {};
      final isGroup = data['isGroup'] == true;

      if (isGroup) {
        final groupName =
            (data['groupName'] ?? data['name'] ?? widget.chatName ?? 'Groupe')
                .toString();
        final groupPhoto = (data['groupPhoto'] ?? '').toString();
        final description = (data['description'] ?? '').toString();
        final creatorId =
            (data['creatorId'] ?? data['createdBy'] ?? data['ownerId'] ?? '')
                .toString();
        final groupParticipants = (data['participants'] is List)
            ? (data['participants'] as List).map((e) => e.toString()).toList()
            : <String>[];

        if (v == 'group_info') {
          _showGroupInfoSheet(
            groupName: groupName,
            groupPhotoUrl: groupPhoto,
            participantIds: groupParticipants,
            creatorId: creatorId,
            description: description,
          );
          return;
        }
        if (v == 'group_media') {
          _showGroupMediaGridSheet();
          return;
        }
        if (v == 'search') {
          _showGroupSearchSheet();
          return;
        }
        if (v == 'mute') {
          await _toggleMuteChat(widget.chatId);
          return;
        }
        if (v == 'ephemeral') {
          await _toggleEphemeralMode(widget.chatId);
          return;
        }
        if (v == 'theme') {
          await _showChatThemeMenu();
          return;
        }
        if (v == 'clear') {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              backgroundColor: _modalBg(c),
              title: Text(
                'Effacer le contenu ?',
                style: TextStyle(color: _modalText(c)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: Text('Annuler', style: TextStyle(color: _modalSub(c))),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(
                    'Effacer',
                    style: TextStyle(color: _modalText(c)),
                  ),
                ),
              ],
            ),
          );
          if (ok == true && mounted) {
            await _clearChatMessages();
          }
          return;
        }
      }

      List participants = (data['participants'] is List)
          ? List.from(data['participants'])
          : [];
      String otherId = participants.firstWhere(
        (id) => id != FirebaseAuth.instance.currentUser?.uid,
        orElse: () => "",
      );
      if (otherId == "") return;

      if (v == 'delete') {
        _confirmAndDeleteConversation();
        return;
      }

      if (v == 'info') {
        _showContactInfo(otherId);
        return;
      }

      if (v == 'audio' || v == 'video') {
        await _startCall(otherId, v == 'video');
        return;
      }
    } catch (e) {
      debugPrint('Menu action error: $e');
    }
  }

  Future<void> _toggleMuteChat(String chatId) async {
    if (currentUser == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('chats').doc(chatId);
      final snap = await ref.get();
      final data = snap.exists ? (snap.data() ?? {}) : {};
      Map<String, dynamic> muted = (data['muted'] is Map)
          ? Map<String, dynamic>.from(data['muted'])
          : {};
      final cur = muted[currentUser!.uid] == true;
      muted[currentUser!.uid] = !cur;
      await ref.set({'muted': muted}, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !cur
                  ? 'Discussion mise en silencieux'
                  : 'Mode silencieux desactive',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _toggleEphemeralMode(String chatId) async {
    if (currentUser == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('chats').doc(chatId);
      final snap = await ref.get();
      final data = snap.exists ? (snap.data() ?? {}) : {};
      Map<String, dynamic> eph = (data['ephemeral'] is Map)
          ? Map<String, dynamic>.from(data['ephemeral'])
          : {};
      final cur = eph[currentUser!.uid] == true;
      eph[currentUser!.uid] = !cur;
      await ref.set({'ephemeral': eph}, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !cur
                  ? 'Messages ephemeres actives'
                  : 'Messages ephemeres desactives',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _showChatThemeMenu() async {
    final prefs = await SharedPreferences.getInstance();
    String theme = prefs.getString('chat_theme') ?? 'system';
    await showModalBottomSheet(
      context: context,
      backgroundColor: _modalBg(context),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (mCtx, setStateModal) {
            return Container(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                children: [
                  ListTile(
                    title: Text(
                      'Theme discussion',
                      style: TextStyle(
                        color: _modalText(ctx),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'system',
                    groupValue: theme,
                    onChanged: (v) async {
                      if (v != null) {
                        setStateModal(() => theme = v);
                        await prefs.setString('chat_theme', v);
                      }
                    },
                    title: Text(
                      'Systeme',
                      style: TextStyle(color: _modalText(ctx)),
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'light',
                    groupValue: theme,
                    onChanged: (v) async {
                      if (v != null) {
                        setStateModal(() => theme = v);
                        await prefs.setString('chat_theme', v);
                      }
                    },
                    title: Text(
                      'Clair',
                      style: TextStyle(color: _modalText(ctx)),
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'dark',
                    groupValue: theme,
                    onChanged: (v) async {
                      if (v != null) {
                        setStateModal(() => theme = v);
                        await prefs.setString('chat_theme', v);
                      }
                    },
                    title: Text(
                      'Sombre',
                      style: TextStyle(color: _modalText(ctx)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---- Multi-select helpers ----
  void _toggleSelection(String id) {
    setState(() {
      if (_selectedMessageIds.contains(id)) {
        _selectedMessageIds.remove(id);
      } else {
        _selectedMessageIds.add(id);
      }
      _selectionMode = _selectedMessageIds.isNotEmpty;
    });
  }

  Future<void> _onMessageLongPress(QueryDocumentSnapshot doc, Map m) async {
    bool isAdmin = false;
    try {
      final chatSnap = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();
      if (chatSnap.exists) {
        final data = chatSnap.data() ?? {};
        final admins =
            (data['admins'] as List?)?.map((e) => e.toString()).toList() ??
            <String>[];
        isAdmin = admins.contains(currentUser?.uid ?? '');
      }
    } catch (_) {}
    // Show options modal: allow saving, selecting, deleting
    showModalBottomSheet(
      context: context,
      backgroundColor: _modalBg(context),
      builder: (c) {
        final isMe = m['senderId'] == currentUser?.uid;
        return SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['👍', '❤️', '😂', '😮', '😢', '🙏'].map((e) {
                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(c);
                        await _toggleReaction(doc.reference, e);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _modalTileBg(c),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              ListTile(
                leading: Icon(Icons.bookmark, color: _modalText(c)),
                title: Text(
                  'Enregistrer',
                  style: TextStyle(color: _modalText(c)),
                ),
                onTap: () async {
                  Navigator.pop(c);
                  await _saveMessageForUser(m, chatId: widget.chatId);
                },
              ),
              ListTile(
                leading: Icon(Icons.check_box, color: _modalText(c)),
                title: Text(
                  'Sélectionner',
                  style: TextStyle(color: _modalText(c)),
                ),
                onTap: () {
                  Navigator.pop(c);
                  setState(() {
                    _selectionMode = true;
                    _selectedMessageIds.add(doc.id);
                  });
                },
              ),
              if (isMe || isAdmin)
                ListTile(
                  leading: Icon(Icons.delete, color: _modalText(c)),
                  title: Text(
                    'Supprimer pour tout le monde',
                    style: TextStyle(color: _modalText(c)),
                  ),
                  onTap: () async {
                    Navigator.pop(c);
                    await _deleteMessageForAll(doc.id);
                  },
                ),
              ListTile(
                leading: Icon(Icons.close, color: _modalMuted(c)),
                title: Text('Annuler', style: TextStyle(color: _modalMuted(c))),
                onTap: () => Navigator.pop(c),
              ),
            ],
          ),
        );
      },
    );
  }

  String _messagePreviewText(Map<String, dynamic> m) {
    final raw = (m['text'] ?? '').toString();
    if (raw.trim().isNotEmpty) return raw;
    final type = (m['type'] ?? 'text').toString();
    switch (type) {
      case 'image':
        return '📸 Photo';
      case 'video':
        return '🎬 Vidéo';
      case 'audio':
      case 'voice':
        return '🎤 Audio';
      case 'file':
        return '📄 Fichier';
      case 'location':
        return '📍 Position';
      case 'contact':
        return '👤 Contact';
      case 'poll':
        return '📊 Sondage';
      default:
        return 'Nouveau message';
    }
  }

  Future<void> _deleteMessageForAll(String messageId) async {
    try {
      final chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId);
      await chatRef.collection('messages').doc(messageId).delete();

      // Recompute lastMessage/lastMessageTime after deletion
      final lastSnap = await chatRef
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (lastSnap.docs.isNotEmpty) {
        final last = lastSnap.docs.first.data();
        final preview = _messagePreviewText(last);
        await chatRef.update({
          'lastMessage': preview,
          'lastMessageTime': last['timestamp'] ?? FieldValue.serverTimestamp(),
        });
      } else {
        await chatRef.update({
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
        });
      }

      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message supprimé')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _toggleReaction(DocumentReference msgRef, String emoji) async {
    if (currentUser == null) return;
    final uid = currentUser!.uid;
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(msgRef);
        if (!snap.exists) return;
        final data = snap.data() as Map<String, dynamic>? ?? {};
        final raw = (data['reactions'] is Map)
            ? Map<String, dynamic>.from(data['reactions'])
            : <String, dynamic>{};
        final List<dynamic> list = (raw[emoji] is List)
            ? List<dynamic>.from(raw[emoji])
            : <dynamic>[];
        if (list.contains(uid)) {
          list.remove(uid);
        } else {
          list.add(uid);
        }
        if (list.isEmpty) {
          raw.remove(emoji);
        } else {
          raw[emoji] = list;
        }
        tx.update(msgRef, {'reactions': raw});
      });
    } catch (e) {
      debugPrint('toggle reaction err: $e');
    }
  }

  Widget _buildReactions(Map<String, dynamic> m, DocumentReference? msgRef) {
    final raw = (m['reactions'] is Map)
        ? Map<String, dynamic>.from(m['reactions'])
        : <String, dynamic>{};
    final uid = currentUser?.uid ?? '';
    if (raw.isEmpty && msgRef == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        ...raw.entries.map((e) {
          final emoji = e.key;
          final users = (e.value is List)
              ? List<dynamic>.from(e.value)
              : <dynamic>[];
          final count = users.length;
          final mine = uid.isNotEmpty && users.contains(uid);
          return GestureDetector(
            onTap: () => _showReactionUsers(emoji, users),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: mine ? tgAccent.withOpacity(0.25) : Colors.white10,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: mine ? tgAccent : Colors.white12),
              ),
              child: Text(
                '$emoji $count',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          );
        }),
        if (msgRef != null)
          GestureDetector(
            onTap: () => _showReactionPicker(msgRef),
            // Requested: the "+" should not look like a chip/circle inside the bubble.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '+',
                style: TextStyle(
                  color: tgAccent.withOpacity(0.95),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showReactionPicker(DocumentReference msgRef) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          height: 320,
          decoration: BoxDecoration(
            color: _modalBg(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'Réagir',
                    style: TextStyle(
                      color: _modalText(ctx),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: _modalSub(ctx)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Expanded(
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) async {
                    Navigator.pop(ctx);
                    await _toggleReaction(msgRef, emoji.emoji);
                  },
                  config: Config(
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: _modalBg(ctx),
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: _modalBg(ctx),
                      indicatorColor: tgAccent,
                      iconColorSelected: tgAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showReactionUsers(String emoji, List<dynamic> users) async {
    if (users.isEmpty) return;
    final ids = users.map((e) => e.toString()).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: _modalBg(ctx),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Réactions $emoji',
                        style: TextStyle(
                          color: _modalText(ctx),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: _modalSub(ctx)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: ids.length,
                      itemBuilder: (c, i) {
                        final uid = ids[i];
                        return FutureBuilder<DocumentSnapshot?>(
                          future: _getUserDoc(uid),
                          builder: (ctx2, snap) {
                            String name = uid;
                            String photo = '';
                            if (snap.hasData &&
                                snap.data != null &&
                                snap.data!.exists) {
                              final raw = snap.data!.data();
                              final ud = raw is Map
                                  ? Map<String, dynamic>.from(
                                      raw as Map<String, dynamic>,
                                    )
                                  : <String, dynamic>{};
                              name = UserUtils.formatName(ud);
                              photo =
                                  (ud['photoUrl'] ??
                                          ud['photo'] ??
                                          ud['avatar'] ??
                                          '')
                                      as String;
                            }
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.white10,
                                backgroundImage: photo.isNotEmpty
                                    ? CachedNetworkImageProvider(photo)
                                          as ImageProvider
                                    : null,
                                child: photo.isEmpty
                                    ? Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                name.isNotEmpty ? name : 'Utilisateur',
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: uid == currentUser?.uid
                                  ? const Text(
                                      'Vous',
                                      style: TextStyle(color: Colors.white54),
                                    )
                                  : null,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<Directory?> _mediaCacheDir() async {
    if (kIsWeb) return null;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}media_cache');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  // Stable, short cache key for a media URL.
  // Note: We intentionally avoid truncating encoded URLs because that can collide and show the wrong media.
  String _mediaCacheKey(String url) {
    // FNV-1a 64-bit (fast, stable, no extra deps).
    // On Web, large `int` literals (> 2^53) can't be represented exactly in JS,
    // so we use BigInt to keep it deterministic across platforms.
    final fnvPrime = BigInt.parse('100000001b3', radix: 16);
    final mask64 = BigInt.parse('ffffffffffffffff', radix: 16);
    BigInt hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final bytes = utf8.encode(url);
    for (final b in bytes) {
      hash = (hash ^ BigInt.from(b)) & mask64;
      hash = (hash * fnvPrime) & mask64;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  String _mediaExtFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final p = uri.path;
      final idx = p.lastIndexOf('.');
      if (idx != -1 && idx < p.length - 1) {
        final ext = p.substring(idx);
        if (ext.length <= 6) return ext;
      }
    } catch (_) {}
    return '';
  }

  Future<bool> _isLocalMediaFileHealthy(File file, {int? expectedBytes}) async {
    try {
      if (!await file.exists()) return false;
      final int length = await file.length();
      if (length <= 0) return false;
      if (expectedBytes != null && expectedBytes > 0) {
        final int minExpected = max(256, (expectedBytes * 0.60).round());
        if (length < minExpected) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<File?> _getCachedMediaFile(String url, {int? expectedBytes}) async {
    if (url.isEmpty) return null;
    final dir = await _mediaCacheDir();
    if (dir == null) return null;
    final ext = _mediaExtFromUrl(url);
    final name = 'v2_${_mediaCacheKey(url)}';
    final file = File('${dir.path}${Platform.pathSeparator}$name$ext');
    if (file.existsSync()) {
      final bool healthy = await _isLocalMediaFileHealthy(
        file,
        expectedBytes: expectedBytes,
      );
      if (healthy) return file;
      try {
        file.deleteSync();
      } catch (_) {}
    }
    return null;
  }

  Future<File?> _downloadMediaToCache(String url, {int? expectedBytes}) async {
    try {
      if (url.isEmpty) return null;
      if (kIsWeb) return null;

      final dir = await _mediaCacheDir();
      if (dir == null) return null;
      final ext = _mediaExtFromUrl(url);
      final name = 'v2_${_mediaCacheKey(url)}';
      final file = File('${dir.path}${Platform.pathSeparator}$name$ext');
      if (file.existsSync()) {
        final bool healthy = await _isLocalMediaFileHealthy(
          file,
          expectedBytes: expectedBytes,
        );
        if (healthy) return file;
        try {
          file.deleteSync();
        } catch (_) {}
      }

      Future<File?> attemptDownload() async {
        final downloaded = await _mediaTransfers.downloadToFile(
          url: url,
          dest: file,
          expectedBytes: expectedBytes,
        );
        if (downloaded == null) return null;
        final bool healthy = await _isLocalMediaFileHealthy(
          downloaded,
          expectedBytes: expectedBytes,
        );
        if (healthy) return downloaded;
        try {
          downloaded.deleteSync();
        } catch (_) {}
        return null;
      }

      final firstTry = await attemptDownload();
      if (firstTry != null) return firstTry;

      // Réseau mobile instable: on relance automatiquement une fois.
      await Future.delayed(const Duration(milliseconds: 420));
      final secondTry = await attemptDownload();
      if (secondTry != null) return secondTry;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Échec du téléchargement. Vérifiez la connexion puis réessayez.',
            ),
          ),
        );
      }
      return null;
    } catch (e) {
      debugPrint('download media err: $e');
    }
    return null;
  }

  Future<bool> _askDownloadMedia() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('media_download_pref') ?? 'ask';
    final wifiOnly = prefs.getBool('media_download_wifi_only') ?? false;
    if (wifiOnly) {
      try {
        final conn = await Connectivity().checkConnectivity();
        final isWifi = conn == ConnectivityResult.wifi;
        if (!isWifi) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Téléchargement autorisé uniquement en Wi‑Fi'),
              ),
            );
          }
          return false;
        }
      } catch (_) {}
    }
    if (stored == 'always') return true;
    if (stored == 'never') return false;
    final res = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _modalBg(c),
        title: Text(
          'Télécharger ce média ?',
          style: TextStyle(color: _modalText(c)),
        ),
        content: Text(
          'Pour éviter de recharger ce média à chaque ouverture, veux-tu le sauvegarder sur ce téléphone ?',
          style: TextStyle(color: _modalSub(c)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'no'),
            child: Text('Non', style: TextStyle(color: _modalSub(c))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'always'),
            child: Text(
              'Oui, toujours',
              style: TextStyle(color: _modalText(c)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'yes'),
            child: Text('Oui', style: TextStyle(color: _modalText(c))),
          ),
        ],
      ),
    );
    if (res == 'always') {
      await prefs.setString('media_download_pref', 'always');
      return true;
    }
    if (res == 'no') {
      return false;
    }
    if (res == 'yes') return true;
    return false;
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes o';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} Ko';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} Mo';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} Go';
  }

  Future<int> _mediaCacheSizeBytes() async {
    final dir = await _mediaCacheDir();
    if (dir == null || !dir.existsSync()) return 0;
    int total = 0;
    for (final e in dir.listSync(recursive: true)) {
      if (e is File) {
        try {
          total += e.lengthSync();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<void> _clearMediaCache() async {
    final dir = await _mediaCacheDir();
    if (dir == null || !dir.existsSync()) return;
    for (final e in dir.listSync(recursive: true)) {
      if (e is File) {
        try {
          e.deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<void> _showCacheManagerSheet() async {
    int size = await _mediaCacheSizeBytes();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (mCtx, setModal) {
            return Container(
              decoration: BoxDecoration(
                color: _modalBg(ctx),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        'Cache médias',
                        style: TextStyle(
                          color: _modalText(ctx),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: _modalSub(ctx)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: Icon(Icons.storage, color: _modalSub(ctx)),
                    title: Text(
                      'Taille du cache',
                      style: TextStyle(color: _modalText(ctx)),
                    ),
                    trailing: Text(
                      _fmtBytes(size),
                      style: TextStyle(color: _modalSub(ctx)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await _clearMediaCache();
                            size = await _mediaCacheSizeBytes();
                            setModal(() {});
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Cache vidé')),
                              );
                            }
                          },
                          child: Text(
                            'Vider le cache',
                            style: TextStyle(color: _modalText(ctx)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveMessageForUser(Map msg, {String? chatId}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final Map<String, dynamic> data = msg is Map<String, dynamic>
        ? msg
        : Map<String, dynamic>.from(msg);
    final msgId = data['id'] ?? data['messageId'] ?? '';
    try {
      // avoid duplicates
      final existing = await FirebaseFirestore.instance
          .collection('saved_messages')
          .where('userId', isEqualTo: user.uid)
          .where('messageId', isEqualTo: msgId)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Déjà enregistré')));
        return;
      }
      final doc = {
        'userId': user.uid,
        'chatId': chatId ?? data['chatId'] ?? '',
        'messageId': msgId,
        'type': data['type'] ?? 'text',
        'text': data['text'] ?? '',
        'url': data['url'] ?? data['fileUrl'] ?? '',
        'senderId': data['senderId'] ?? '',
        'senderName': data['senderName'] ?? data['senderDisplayName'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('saved_messages').add(doc);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message enregistré')));
    } catch (e) {
      debugPrint('Save msg err: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedMessageIds.clear();
      _selectionMode = false;
    });
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selectedMessageIds.isEmpty) return;
    final cnt = _selectedMessageIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _modalBg(ctx),
        title: Text(
          'Supprimer $cnt message(s) ?',
          style: TextStyle(color: _modalText(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: TextStyle(color: _modalSub(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteSelectedMessages();
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessageIds.isEmpty) return;
    final count = _selectedMessageIds.length;
    final batch = FirebaseFirestore.instance.batch();
    for (var id in _selectedMessageIds) {
      final ref = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(id);
      batch.delete(ref);
    }
    try {
      await batch.commit();
      if (mounted) {
        _clearSelection();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count message(s) supprimé(s)')),
        );
      }
    } catch (e) {
      debugPrint('Delete selected error: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression')),
        );
    }
  }

  Future<void> _showContactInfo(String otherId) async {
    try {
      final collections = ['classic_users', 'pro_users', 'enterprise_users'];
      DocumentSnapshot? snap;
      for (var c in collections) {
        try {
          final s = await FirebaseFirestore.instance
              .collection(c)
              .doc(otherId)
              .get();
          if (s.exists) {
            snap = s;
            break;
          }
        } catch (_) {}
      }
      if (snap == null) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Profil introuvable')));
        return;
      }

      final raw = snap.data();
      final data = raw is Map
          ? Map<String, dynamic>.from((raw as Map<String, dynamic>?) ?? {})
          : <String, dynamic>{};
      final displayName = UserUtils.formatName(data);
      final photo =
          (data['photoUrl'] ?? data['avatar'] ?? data['photo'] ?? '') as String;
      final lastSeen = data['lastSeen'] is Timestamp
          ? (data['lastSeen'] as Timestamp).toDate()
          : (data['lastSeen'] is int
                ? DateTime.fromMillisecondsSinceEpoch(data['lastSeen'])
                : null);
      final phone =
          (data['phone'] ?? data['telephone'] ?? data['phoneNumber'] ?? '')
              as String;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          return DraggableScrollableSheet(
            initialChildSize: 0.44,
            minChildSize: 0.28,
            maxChildSize: 0.9,
            builder: (_, controller) {
              return Container(
                decoration: BoxDecoration(
                  color: _modalBg(ctx),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: ListView(
                  controller: controller,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                tgAccent.withOpacity(0.2),
                                tgAccent.withOpacity(0.06),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.45),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 34,
                            backgroundImage: photo.isNotEmpty
                                ? CachedNetworkImageProvider(photo)
                                      as ImageProvider
                                : null,
                            backgroundColor: Colors.transparent,
                            child: photo.isEmpty
                                ? Text(
                                    displayName.isNotEmpty
                                        ? displayName[0]
                                        : '?',
                                    style: TextStyle(
                                      color: _modalText(ctx),
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: TextStyle(
                                  color: _modalText(ctx),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                lastSeen != null
                                    ? 'Dernière connexion • ${DateFormat.yMd().add_Hm().format(lastSeen)}'
                                    : 'Dernière connexion • N/A',
                                style: TextStyle(
                                  color: _modalSub(ctx),
                                  fontSize: 13,
                                ),
                              ),
                              if (phone.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Text(
                                    '📞 $phone',
                                    style: TextStyle(
                                      color: _modalSub(ctx),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: _modalSub(ctx)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // action grid
                    Wrap(
                      spacing: 10,
                      runSpacing: 12,
                      children: [
                        _actionTile(
                          icon: Icons.message,
                          label: 'Message',
                          color: Colors.blueAccent,
                          onTap: () async {
                            Navigator.pop(ctx);
                            try {
                              final doc = await FirebaseFirestore.instance
                                  .collection('chats')
                                  .doc(widget.chatId)
                                  .get();
                              final isGroup =
                                  doc.exists &&
                                  ((doc.data())?['isGroup'] == true);
                              if (mounted) {
                                if (isGroup) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => GroupChatDetailPage(
                                        chatId: widget.chatId,
                                        chatName: displayName,
                                      ),
                                    ),
                                  );
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatDetailPage(
                                        chatId: widget.chatId,
                                        chatName: displayName,
                                      ),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              debugPrint('Error opening conversation: $e');
                            }
                          },
                        ),
                        _actionTile(
                          icon: Icons.share,
                          label: 'Partager',
                          color: Colors.teal,
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: 'Name: $displayName\nPhone: $phone',
                              ),
                            );
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Contact copié')),
                            );
                          },
                        ),
                        _actionTile(
                          icon: Icons.phone,
                          label: 'Appeler',
                          color: Colors.green,
                          onTap: () async {
                            Navigator.pop(ctx);
                            // start audio call
                            try {
                              final callRef = await FirebaseFirestore.instance
                                  .collection('calls')
                                  .add({
                                    'caller':
                                        FirebaseAuth.instance.currentUser?.uid,
                                    'callerName':
                                        FirebaseAuth
                                            .instance
                                            .currentUser
                                            ?.displayName ??
                                        '',
                                    'callee': otherId,
                                    'status': 'ringing',
                                    'type': 'audio',
                                    'createdAt': FieldValue.serverTimestamp(),
                                  });

                              await _sendIncomingCallPush(
                                calleeId: otherId,
                                callId: callRef.id,
                                isVideo: false,
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CallWebRTCPage(
                                    callId: callRef.id,
                                    otherId: otherId,
                                    isCaller: true,
                                    name: displayName,
                                    avatarLetter: displayName.isNotEmpty
                                        ? displayName[0].toUpperCase()
                                        : '?',
                                  ),
                                ),
                              );
                            } catch (e) {
                              debugPrint('Start call error: $e');
                            }
                          },
                        ),
                        _actionTile(
                          icon: Icons.edit,
                          label: 'Modifier',
                          color: Colors.amber,
                          onTap: () {
                            Navigator.pop(ctx);
                            _editContactLocal(otherId);
                          },
                        ),
                        _actionTile(
                          icon: Icons.block,
                          label: 'Bloquer',
                          color: Colors.redAccent,
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _confirmBlock(otherId);
                          },
                        ),
                        _actionTile(
                          icon: Icons.delete,
                          label: 'Supprimer',
                          color: Colors.red,
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _confirmDeleteContact(otherId);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(color: _modalTileBg(ctx)),
                    const SizedBox(height: 8),
                    Text(
                      'Plus d’informations',
                      style: TextStyle(
                        color: _modalText(ctx),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ce panneau permet de bloquer ou supprimer un contact. Les actions modifient uniquement vos données dans l’application.',
                      style: TextStyle(color: _modalSub(ctx), fontSize: 13),
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      debugPrint('Show contact info error: $e');
    }
  }

  Future<void> _showGroupParticipantsSheet(List<String> participantIds) async {
    if (participantIds.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: _modalBg(ctx),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Participants',
                        style: TextStyle(
                          color: _modalText(ctx),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: _modalSub(ctx)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: participantIds.length,
                      itemBuilder: (c, i) {
                        final uid = participantIds[i];
                        return FutureBuilder<DocumentSnapshot?>(
                          future: _getUserDoc(uid),
                          builder: (ctx2, snap) {
                            String name = uid;
                            String photo = '';
                            if (snap.hasData &&
                                snap.data != null &&
                                snap.data!.exists) {
                              final raw = snap.data!.data();
                              final ud = raw is Map
                                  ? Map<String, dynamic>.from(
                                      raw as Map<String, dynamic>,
                                    )
                                  : <String, dynamic>{};
                              name = UserUtils.formatName(ud);
                              photo =
                                  (ud['photoUrl'] ??
                                          ud['photo'] ??
                                          ud['avatar'] ??
                                          '')
                                      as String;
                            }
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _modalTileBg(ctx),
                                backgroundImage: photo.isNotEmpty
                                    ? CachedNetworkImageProvider(photo)
                                          as ImageProvider
                                    : null,
                                child: photo.isEmpty
                                    ? Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          color: _modalText(ctx),
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                name.isNotEmpty ? name : 'Utilisateur',
                                style: TextStyle(color: _modalText(ctx)),
                              ),
                              subtitle: uid == currentUser?.uid
                                  ? Text(
                                      'Vous',
                                      style: TextStyle(color: _modalMuted(ctx)),
                                    )
                                  : null,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showGroupInfoSheet({
    required String groupName,
    required String groupPhotoUrl,
    required List<String> participantIds,
    required String creatorId,
    required String description,
  }) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (_, controller) {
            final total = participantIds.length;
            return Container(
              decoration: BoxDecoration(
                color: _modalBg(ctx),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: ListView(
                controller: controller,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _modalTileBg(ctx),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          try {
                            final snap = await FirebaseFirestore.instance
                                .collection('chats')
                                .doc(widget.chatId)
                                .get();
                            if (!snap.exists) return;
                            final data = snap.data() ?? {};
                            final admins =
                                (data['admins'] as List?)
                                    ?.map((e) => e.toString())
                                    .toList() ??
                                <String>[];
                            final perms = (data['permissions'] is Map)
                                ? Map<String, dynamic>.from(data['permissions'])
                                : <String, dynamic>{};
                            final canChange =
                                (perms['canChangeInfo'] ?? 'admins').toString();
                            if (canChange == 'admins' &&
                                !admins.contains(currentUser?.uid ?? '')) {
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Seuls les admins peuvent modifier la photo',
                                    ),
                                  ),
                                );
                              return;
                            }
                            final picker = ImagePicker();
                            final img = await picker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 1200,
                              imageQuality: 85,
                            );
                            if (img == null) return;
                            final url = await _uploadGroupPhoto(img);
                            if (url != null && url.isNotEmpty) {
                              await FirebaseFirestore.instance
                                  .collection('chats')
                                  .doc(widget.chatId)
                                  .update({'groupPhoto': url});
                            }
                          } catch (_) {}
                        },
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Colors.white10, Colors.white12],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.45),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.transparent,
                            backgroundImage: groupPhotoUrl.isNotEmpty
                                ? CachedNetworkImageProvider(groupPhotoUrl)
                                      as ImageProvider
                                : null,
                            child: groupPhotoUrl.isEmpty
                                ? Icon(
                                    Icons.group,
                                    color: _modalSub(ctx),
                                    size: 34,
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              groupName.isNotEmpty ? groupName : 'Groupe',
                              style: TextStyle(
                                color: _modalText(ctx),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$total membres',
                              style: TextStyle(
                                color: _modalSub(ctx),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (description.isNotEmpty)
                              Text(
                                description,
                                style: TextStyle(
                                  color: _modalSub(ctx),
                                  fontSize: 12,
                                ),
                              ),
                            if (description.isNotEmpty)
                              const SizedBox(height: 6),
                            if (creatorId.isNotEmpty)
                              FutureBuilder<DocumentSnapshot?>(
                                future: _getUserDoc(creatorId),
                                builder: (ctx2, snap) {
                                  String creatorName = creatorId;
                                  if (snap.hasData &&
                                      snap.data != null &&
                                      snap.data!.exists) {
                                    final raw = snap.data!.data();
                                    final ud = raw is Map
                                        ? Map<String, dynamic>.from(
                                            raw as Map<String, dynamic>,
                                          )
                                        : <String, dynamic>{};
                                    creatorName = UserUtils.formatName(ud);
                                  }
                                  return Text(
                                    'Créé par $creatorName',
                                    style: TextStyle(
                                      color: _modalMuted(ctx),
                                      fontSize: 12,
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: _modalSub(ctx)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showAddMembersSheet(participantIds);
                          },
                          icon: Icon(Icons.person_add, color: _modalText(ctx)),
                          label: Text(
                            'Ajouter',
                            style: TextStyle(color: _modalText(ctx)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showGroupSearchSheet();
                          },
                          icon: Icon(Icons.search, color: _modalText(ctx)),
                          label: Text(
                            'Rechercher',
                            style: TextStyle(color: _modalText(ctx)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Médias du groupe',
                        style: TextStyle(
                          color: _modalText(ctx),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _showGroupMediaGridSheet(),
                        child: Text(
                          'Voir tout',
                          style: TextStyle(color: _modalText(ctx)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 92,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('chats')
                          .doc(widget.chatId)
                          .collection('messages')
                          .where('type', whereIn: ['image', 'video'])
                          .orderBy('timestamp', descending: true)
                          .limit(12)
                          .snapshots(),
                      builder: (context, mediaSnap) {
                        if (!mediaSnap.hasData ||
                            mediaSnap.data!.docs.isEmpty) {
                          return Center(
                            child: Text(
                              'Aucun média',
                              style: TextStyle(color: _modalMuted(ctx)),
                            ),
                          );
                        }
                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: mediaSnap.data!.docs.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (c, i) {
                            final m =
                                mediaSnap.data!.docs[i].data()
                                    as Map<String, dynamic>;
                            final url = (m['url'] ?? '') as String? ?? '';
                            final type = (m['type'] ?? 'image').toString();
                            final msgId = mediaSnap.data!.docs[i].id;
                            final senderId = (m['senderId'] ?? '').toString();
                            return Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                color: _modalTileBg(ctx),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: url.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () => _openMediaViewer(
                                        url,
                                        type,
                                        messageId: msgId,
                                        senderId: senderId,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            CachedNetworkImage(
                                              imageUrl: url,
                                              fit: BoxFit.cover,
                                            ),
                                            if (type == 'video')
                                              Container(
                                                color: Colors.black26,
                                                child: Icon(
                                                  Icons.play_circle_filled,
                                                  color: _modalSub(ctx),
                                                  size: 32,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : Icon(Icons.image, color: _modalMuted(ctx)),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Membres',
                    style: TextStyle(
                      color: _modalText(ctx),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .doc(widget.chatId)
                        .snapshots(),
                    builder: (ctx3, chatSnap) {
                      final data = chatSnap.hasData && chatSnap.data!.exists
                          ? (chatSnap.data!.data() as Map<String, dynamic>?) ??
                                {}
                          : <String, dynamic>{};
                      final admins =
                          (data['admins'] as List?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          <String>[];
                      final participants =
                          (data['participants'] as List?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          participantIds;
                      final isAdmin = admins.contains(currentUser?.uid ?? '');
                      return Column(
                        children: participants.map((uid) {
                          return FutureBuilder<DocumentSnapshot?>(
                            future: _getUserDoc(uid),
                            builder: (ctx2, snap) {
                              String name = uid;
                              String photo = '';
                              if (snap.hasData &&
                                  snap.data != null &&
                                  snap.data!.exists) {
                                final raw = snap.data!.data();
                                final ud = raw is Map
                                    ? Map<String, dynamic>.from(
                                        raw as Map<String, dynamic>,
                                      )
                                    : <String, dynamic>{};
                                name = UserUtils.formatName(ud);
                                photo =
                                    (ud['photoUrl'] ??
                                            ud['photo'] ??
                                            ud['avatar'] ??
                                            '')
                                        as String;
                              }
                              final bool isMemberAdmin = admins.contains(uid);
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: _modalTileBg(ctx),
                                  backgroundImage: photo.isNotEmpty
                                      ? CachedNetworkImageProvider(photo)
                                            as ImageProvider
                                      : null,
                                  child: photo.isEmpty
                                      ? Text(
                                          name.isNotEmpty
                                              ? name[0].toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            color: _modalText(ctx),
                                          ),
                                        )
                                      : null,
                                ),
                                title: Text(
                                  name.isNotEmpty ? name : 'Utilisateur',
                                  style: TextStyle(color: _modalText(ctx)),
                                ),
                                subtitle: Row(
                                  children: [
                                    if (uid == currentUser?.uid)
                                      Text(
                                        'Vous',
                                        style: TextStyle(
                                          color: _modalMuted(ctx),
                                        ),
                                      ),
                                    if (uid == currentUser?.uid &&
                                        isMemberAdmin)
                                      Text(
                                        ' • ',
                                        style: TextStyle(
                                          color: _modalTileBg(ctx),
                                        ),
                                      ),
                                    if (isMemberAdmin)
                                      Text(
                                        'Admin',
                                        style: TextStyle(
                                          color: _modalMuted(ctx),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: isAdmin && uid != currentUser?.uid
                                    ? PopupMenuButton<String>(
                                        onSelected: (v) async {
                                          if (v == 'promote') {
                                            await _setAdmin(uid, true);
                                          } else if (v == 'demote') {
                                            await _setAdmin(uid, false);
                                          } else if (v == 'remove') {
                                            await _removeGroupMember(uid);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          if (!isMemberAdmin)
                                            const PopupMenuItem(
                                              value: 'promote',
                                              child: Text('Promouvoir admin'),
                                            ),
                                          if (isMemberAdmin)
                                            const PopupMenuItem(
                                              value: 'demote',
                                              child: Text('Retirer admin'),
                                            ),
                                          const PopupMenuItem(
                                            value: 'remove',
                                            child: Text('Retirer du groupe'),
                                          ),
                                        ],
                                      )
                                    : null,
                                onTap: () => _showContactInfo(uid),
                              );
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Divider(color: _modalTileBg(ctx)),
                  ListTile(
                    leading: const Icon(
                      Icons.exit_to_app,
                      color: Colors.orangeAccent,
                    ),
                    title: const Text(
                      'Quitter le groupe',
                      style: TextStyle(color: Colors.orangeAccent),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: _modalBg(c),
                          title: Text(
                            'Quitter le groupe ?',
                            style: TextStyle(color: _modalText(c)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: Text(
                                'Annuler',
                                style: TextStyle(color: _modalSub(c)),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text(
                                'Quitter',
                                style: TextStyle(color: Colors.orangeAccent),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && mounted) {
                        await _leaveGroup();
                      }
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.settings, color: _modalSub(ctx)),
                    title: Text(
                      'Paramètres du groupe',
                      style: TextStyle(color: _modalText(ctx)),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      () async {
                        try {
                          final snap = await FirebaseFirestore.instance
                              .collection('chats')
                              .doc(widget.chatId)
                              .get();
                          if (!snap.exists) return;
                          final data = snap.data() ?? {};
                          final admins =
                              (data['admins'] as List?)
                                  ?.map((e) => e.toString())
                                  .toList() ??
                              <String>[];
                          final perms = (data['permissions'] is Map)
                              ? Map<String, dynamic>.from(data['permissions'])
                              : <String, dynamic>{};
                          final canChange = (perms['canChangeInfo'] ?? 'admins')
                              .toString();
                          if (canChange == 'admins' &&
                              !admins.contains(currentUser?.uid ?? '')) {
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Seuls les admins peuvent modifier les infos',
                                  ),
                                ),
                              );
                            return;
                          }
                          await _showGroupSettingsSheet(
                            currentName: groupName,
                            currentDescription: description,
                          );
                        } catch (e) {
                          debugPrint('settings permission err: $e');
                        }
                      }();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.redAccent),
                    title: const Text(
                      'Supprimer le groupe',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: _modalBg(c),
                          title: Text(
                            'Supprimer le groupe ?',
                            style: TextStyle(color: _modalText(c)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: Text(
                                'Annuler',
                                style: TextStyle(color: _modalSub(c)),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text(
                                'Supprimer',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && mounted) {
                        await _deleteGroupAndMessages();
                      }
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.cleaning_services,
                      color: _modalSub(ctx),
                    ),
                    title: Text(
                      'Effacer la discussion',
                      style: TextStyle(color: _modalText(ctx)),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: _modalBg(c),
                          title: Text(
                            'Effacer la discussion ?',
                            style: TextStyle(color: _modalText(c)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: Text(
                                'Annuler',
                                style: TextStyle(color: _modalSub(c)),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: Text(
                                'Effacer',
                                style: TextStyle(color: _modalText(c)),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && mounted) {
                        await _clearChatMessages();
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _lookupUserByEmailOrUid(String input) async {
    final q = input.trim();
    if (q.isEmpty) return null;
    final cols = ['classic_users', 'pro_users', 'enterprise_users'];

    Future<Map<String, dynamic>?> byEmail() async {
      for (final col in cols) {
        try {
          final res = await FirebaseFirestore.instance
              .collection(col)
              .where('email', isEqualTo: q)
              .limit(1)
              .get();
          if (res.docs.isNotEmpty) {
            final d = res.docs.first;
            final data = d.data();
            return {
              'uid': d.id,
              'name': UserUtils.formatName(data),
              'email': data['email'] ?? '',
              'photo':
                  data['photoUrl'] ?? data['photo'] ?? data['avatar'] ?? '',
            };
          }
        } catch (_) {}
      }
      return null;
    }

    Future<Map<String, dynamic>?> byUid() async {
      for (final col in cols) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection(col)
              .doc(q)
              .get();
          if (snap.exists) {
            final data = snap.data() ?? {};
            return {
              'uid': snap.id,
              'name': UserUtils.formatName(data),
              'email': data['email'] ?? '',
              'photo':
                  data['photoUrl'] ?? data['photo'] ?? data['avatar'] ?? '',
            };
          }
        } catch (_) {}
      }
      return null;
    }

    if (q.contains('@')) return byEmail();
    final byId = await byUid();
    if (byId != null) return byId;
    return byEmail();
  }

  Future<List<Map<String, dynamic>>> _loadOwnedContacts() async {
    final user = currentUser;
    if (user == null) return [];
    final List<Map<String, dynamic>> out = [];
    try {
      final q = await FirebaseFirestore.instance
          .collection('contacts')
          .where('owner', isEqualTo: user.uid)
          .limit(300)
          .get();
      for (final d in q.docs) {
        final data = d.data();
        final email = (data['email'] ?? '').toString();
        final name = (data['name'] ?? data['email'] ?? '').toString();
        String uid = (data['uid'] ?? '').toString();
        if (uid.isEmpty && email.isNotEmpty) {
          try {
            final resolved = await _lookupUserByEmailOrUid(email);
            if (resolved != null) uid = (resolved['uid'] ?? '').toString();
          } catch (_) {}
        }
        if (uid.isEmpty) {
          // skip contacts not linked to an app user
          continue;
        }
        out.add({
          'uid': uid,
          'name': name.isNotEmpty ? name : uid,
          'email': email,
          'photo': data['photoUrl'] ?? data['photo'] ?? data['avatar'] ?? '',
        });
      }
    } catch (e) {
      debugPrint('load contacts err: $e');
    }
    return out;
  }

  Future<void> _showAddMembersSheet(List<String> existingIds) async {
    final current = currentUser;
    if (current == null) return;
    final searchCtrl = TextEditingController();
    final addCtrl = TextEditingController();
    final Set<String> selectedUids = {};
    final List<Map<String, dynamic>> manualUsers = [];
    final contacts = await _loadOwnedContacts();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (mCtx, setModal) {
            final allUsers = <Map<String, dynamic>>[
              ...manualUsers,
              ...contacts,
            ];
            final q = searchCtrl.text.trim().toLowerCase();
            final visible = q.isEmpty
                ? allUsers
                : allUsers.where((u) {
                    final name = (u['name'] ?? '').toString().toLowerCase();
                    final email = (u['email'] ?? '').toString().toLowerCase();
                    return name.contains(q) || email.contains(q);
                  }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.78,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (_, controller) {
                return Container(
                  decoration: BoxDecoration(
                    color: _modalBg(ctx),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            'Ajouter des membres',
                            style: TextStyle(
                              color: _modalText(ctx),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.close, color: _modalSub(ctx)),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: searchCtrl,
                        style: TextStyle(color: _modalText(ctx)),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.search, color: _modalSub(ctx)),
                          hintText: 'Rechercher un contact',
                          hintStyle: TextStyle(color: _modalMuted(ctx)),
                          filled: true,
                          fillColor: _modalTileBg(ctx),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (_) => setModal(() {}),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: addCtrl,
                              style: TextStyle(color: _modalText(ctx)),
                              decoration: InputDecoration(
                                hintText: 'Ajouter via email ou UID',
                                hintStyle: TextStyle(color: _modalMuted(ctx)),
                                filled: true,
                                fillColor: _modalTileBg(ctx),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _modalTileBg(ctx),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () async {
                                final query = addCtrl.text.trim();
                                if (query.isEmpty) return;
                                final user = await _lookupUserByEmailOrUid(
                                  query,
                                );
                                if (user == null) {
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Aucun utilisateur trouvé',
                                        ),
                                      ),
                                    );
                                  return;
                                }
                                final uid = user['uid'] as String;
                                if (existingIds.contains(uid)) {
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Utilisateur déjà membre',
                                        ),
                                      ),
                                    );
                                  return;
                                }
                                final exists =
                                    manualUsers.any((u) => u['uid'] == uid) ||
                                    contacts.any((u) => u['uid'] == uid);
                                if (!exists) {
                                  setModal(() {
                                    manualUsers.insert(0, user);
                                    selectedUids.add(uid);
                                  });
                                }
                                addCtrl.clear();
                              },
                              child: Icon(Icons.add, color: _modalText(ctx)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: visible.isEmpty
                            ? Center(
                                child: Text(
                                  'Aucun contact',
                                  style: TextStyle(color: _modalMuted(ctx)),
                                ),
                              )
                            : ListView.builder(
                                controller: controller,
                                itemCount: visible.length,
                                itemBuilder: (c, i) {
                                  final u = visible[i];
                                  final uid = (u['uid'] ?? '').toString();
                                  final name = (u['name'] ?? '').toString();
                                  final email = (u['email'] ?? '').toString();
                                  final photo = (u['photo'] ?? '').toString();
                                  final isMember =
                                      uid.isNotEmpty &&
                                      existingIds.contains(uid);
                                  final selected =
                                      uid.isNotEmpty &&
                                      selectedUids.contains(uid);
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _modalTileBg(ctx),
                                      backgroundImage: photo.isNotEmpty
                                          ? CachedNetworkImageProvider(photo)
                                                as ImageProvider
                                          : null,
                                      child: photo.isEmpty
                                          ? Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                color: _modalText(ctx),
                                              ),
                                            )
                                          : null,
                                    ),
                                    title: Text(
                                      name.isNotEmpty ? name : email,
                                      style: TextStyle(color: _modalText(ctx)),
                                    ),
                                    subtitle: email.isNotEmpty
                                        ? Text(
                                            email,
                                            style: TextStyle(
                                              color: _modalSub(ctx),
                                            ),
                                          )
                                        : null,
                                    trailing: isMember
                                        ? Text(
                                            'Membre',
                                            style: TextStyle(
                                              color: _modalMuted(ctx),
                                            ),
                                          )
                                        : Checkbox(
                                            value: selected,
                                            onChanged: uid.isEmpty
                                                ? null
                                                : (v) => setModal(() {
                                                    if (v == true) {
                                                      selectedUids.add(uid);
                                                    } else {
                                                      selectedUids.remove(uid);
                                                    }
                                                  }),
                                          ),
                                    onTap: uid.isEmpty || isMember
                                        ? null
                                        : () => setModal(() {
                                            if (selected) {
                                              selectedUids.remove(uid);
                                            } else {
                                              selectedUids.add(uid);
                                            }
                                          }),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                'Annuler',
                                style: TextStyle(color: _modalSub(ctx)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () async {
                              if (selectedUids.isEmpty) return;
                              try {
                                final chatRef = FirebaseFirestore.instance
                                    .collection('chats')
                                    .doc(widget.chatId);
                                final chatSnap = await chatRef.get();
                                if (!chatSnap.exists) return;
                                final data = chatSnap.data() ?? {};
                                final perms = (data['permissions'] is Map)
                                    ? Map<String, dynamic>.from(
                                        data['permissions'],
                                      )
                                    : <String, dynamic>{};
                                final canAdd = (perms['canAddMembers'] ?? 'all')
                                    .toString();
                                final admins =
                                    (data['admins'] as List?)
                                        ?.map((e) => e.toString())
                                        .toList() ??
                                    [];
                                if (canAdd == 'admins' &&
                                    !admins.contains(current.uid)) {
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Seuls les admins peuvent ajouter des membres',
                                        ),
                                      ),
                                    );
                                  return;
                                }

                                final existing =
                                    (data['participants'] as List?)
                                        ?.map((e) => e.toString())
                                        .toSet() ??
                                    <String>{};
                                final toAdd = selectedUids
                                    .where((u) => !existing.contains(u))
                                    .toList();
                                if (toAdd.isEmpty) {
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Aucun nouveau membre'),
                                      ),
                                    );
                                  return;
                                }

                                await chatRef.update({
                                  'participants': FieldValue.arrayUnion(toAdd),
                                });

                                final updates = <String, dynamic>{};
                                for (final uid in toAdd) {
                                  updates['unreadCounts.$uid'] = 0;
                                  updates['typing.$uid'] = false;
                                  updates['present.$uid'] = false;
                                }
                                if (updates.isNotEmpty) {
                                  await chatRef.update(updates);
                                }

                                final creatorName =
                                    current.displayName ?? 'Un utilisateur';
                                final text =
                                    '$creatorName a ajouté ${toAdd.length} membre(s)';
                                await chatRef.collection('messages').add({
                                  'type': 'system',
                                  'text': text,
                                  'senderId': current.uid,
                                  'timestamp': FieldValue.serverTimestamp(),
                                  'isRead': false,
                                  'delivered': false,
                                });

                                final allParticipants = {...existing, ...toAdd};
                                final metaUpdates = <String, dynamic>{
                                  'lastMessage': text,
                                  'lastMessageTime':
                                      FieldValue.serverTimestamp(),
                                };
                                for (var p in allParticipants) {
                                  if (p != current.uid)
                                    metaUpdates['unreadCounts.$p'] =
                                        FieldValue.increment(1);
                                }
                                await chatRef.update(metaUpdates);

                                if (mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Membres ajoutés'),
                                    ),
                                  );
                                }
                              } catch (e) {
                                debugPrint('add members err: $e');
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Erreur lors de l’ajout'),
                                    ),
                                  );
                              }
                            },
                            child: const Text('Ajouter'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showGroupSearchSheet() async {
    final queryCtrl = TextEditingController();
    List<QueryDocumentSnapshot> cached = [];

    Future<void> load() async {
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(300)
          .get();
      cached = snap.docs;
    }

    await load();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (mCtx, setModal) {
            List<QueryDocumentSnapshot> filtered = cached;
            final q = queryCtrl.text.trim().toLowerCase();
            if (q.isNotEmpty) {
              filtered = cached.where((d) {
                final m = d.data() as Map<String, dynamic>;
                final text = (m['text'] ?? '').toString().toLowerCase();
                return text.contains(q);
              }).toList();
            }
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              builder: (_, controller) {
                return Container(
                  decoration: BoxDecoration(
                    color: _modalBg(ctx),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            'Rechercher',
                            style: TextStyle(
                              color: _modalText(ctx),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.close, color: _modalSub(ctx)),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: queryCtrl,
                        style: TextStyle(color: _modalText(ctx)),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.search, color: _modalSub(ctx)),
                          hintText: 'Rechercher dans le groupe',
                          hintStyle: TextStyle(color: _modalMuted(ctx)),
                          filled: true,
                          fillColor: _modalTileBg(ctx),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (_) => setModal(() {}),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'Aucun résultat',
                                  style: TextStyle(color: _modalMuted(ctx)),
                                ),
                              )
                            : ListView.builder(
                                controller: controller,
                                itemCount: filtered.length,
                                itemBuilder: (c, i) {
                                  final m =
                                      filtered[i].data()
                                          as Map<String, dynamic>;
                                  final text = (m['text'] ?? '').toString();
                                  final sender =
                                      (m['senderName'] ?? '') as String? ?? '';
                                  final ts = m['timestamp'] is Timestamp
                                      ? (m['timestamp'] as Timestamp).toDate()
                                      : null;
                                  final time = ts != null
                                      ? DateFormat('dd/MM HH:mm').format(ts)
                                      : '';
                                  return ListTile(
                                    title: Text(
                                      text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: _modalText(ctx)),
                                    ),
                                    subtitle: Text(
                                      [
                                        sender,
                                        time,
                                      ].where((e) => e.isNotEmpty).join(' • '),
                                      style: TextStyle(color: _modalMuted(ctx)),
                                    ),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      setState(
                                        () => _pendingJumpMessageId =
                                            filtered[i].id,
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showGroupMediaGridSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: _modalBg(ctx),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Médias du groupe',
                        style: TextStyle(
                          color: _modalText(ctx),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: _modalSub(ctx)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('chats')
                          .doc(widget.chatId)
                          .collection('messages')
                          .where('type', whereIn: ['image', 'video'])
                          .orderBy('timestamp', descending: true)
                          .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData || snap.data!.docs.isEmpty) {
                          return Center(
                            child: Text(
                              'Aucun média',
                              style: TextStyle(color: _modalMuted(ctx)),
                            ),
                          );
                        }
                        return GridView.builder(
                          controller: controller,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                              ),
                          itemCount: snap.data!.docs.length,
                          itemBuilder: (c, i) {
                            final m =
                                snap.data!.docs[i].data()
                                    as Map<String, dynamic>;
                            final url = (m['url'] ?? '').toString();
                            final type = (m['type'] ?? 'image').toString();
                            final msgId = snap.data!.docs[i].id;
                            final senderId = (m['senderId'] ?? '').toString();
                            return GestureDetector(
                              onTap: () => _openMediaViewer(
                                url,
                                type,
                                messageId: msgId,
                                senderId: senderId,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CachedNetworkImage(
                                      imageUrl: url,
                                      fit: BoxFit.cover,
                                    ),
                                    if (type == 'video')
                                      Container(
                                        color: Colors.black26,
                                        child: Icon(
                                          Icons.play_circle_filled,
                                          color: _modalSub(ctx),
                                          size: 32,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openMediaViewer(
    String url,
    String type, {
    String? messageId,
    String? senderId,
    int? sizeBytes,
  }) async {
    if (url.isEmpty) return;
    File? local;
    if (!kIsWeb) {
      local = await _getCachedMediaFile(url, expectedBytes: sizeBytes);
      if (local == null) {
        final ok = await _askDownloadMedia();
        if (ok) {
          local = await _downloadMediaToCache(url, expectedBytes: sizeBytes);
        }
      }
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MediaViewerPage(
          url: url,
          type: type,
          chatId: widget.chatId,
          messageId: messageId,
          senderId: senderId,
          localPath: local?.path,
        ),
      ),
    );
  }

  Future<void> _setAdmin(String uid, bool makeAdmin) async {
    try {
      final chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId);
      await chatRef.update({
        'admins': makeAdmin
            ? FieldValue.arrayUnion([uid])
            : FieldValue.arrayRemove([uid]),
      });
    } catch (e) {
      debugPrint('set admin err: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Erreur admin')));
    }
  }

  Future<String> _resolveUserName(String uid) async {
    try {
      final snap = await _getUserDoc(uid);
      if (snap != null && snap.exists) {
        final raw = snap.data();
        final ud = raw is Map
            ? Map<String, dynamic>.from(raw as Map<String, dynamic>)
            : <String, dynamic>{};
        final name = UserUtils.formatName(ud);
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return uid;
  }

  Future<void> _removeGroupMember(String uid, {bool isSelf = false}) async {
    try {
      final chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId);
      final chatSnap = await chatRef.get();
      if (!chatSnap.exists) return;
      final data = chatSnap.data() ?? {};
      final participants =
          (data['participants'] as List?)?.map((e) => e.toString()).toList() ??
          <String>[];
      if (!participants.contains(uid)) return;
      final admins =
          (data['admins'] as List?)?.map((e) => e.toString()).toList() ??
          <String>[];
      final remaining = participants.where((p) => p != uid).toList();

      if (remaining.isEmpty) {
        await _deleteGroupAndMessages();
        return;
      }

      final updates = <String, dynamic>{
        'participants': remaining,
        'unreadCounts.$uid': FieldValue.delete(),
        'typing.$uid': FieldValue.delete(),
        'present.$uid': FieldValue.delete(),
        'userActions.$uid': FieldValue.delete(),
      };
      if (admins.contains(uid)) {
        updates['admins'] = FieldValue.arrayRemove([uid]);
      }
      await chatRef.update(updates);

      final name = await _resolveUserName(uid);
      final text = isSelf
          ? '$name a quitté le groupe'
          : '$name a été retiré du groupe';
      await chatRef.collection('messages').add({
        'type': 'system',
        'text': text,
        'senderId': currentUser?.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'delivered': false,
      });

      final metaUpdates = <String, dynamic>{
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
      };
      for (var p in remaining) {
        if (p != currentUser?.uid)
          metaUpdates['unreadCounts.$p'] = FieldValue.increment(1);
      }
      await chatRef.update(metaUpdates);

      if (isSelf && mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('remove member err: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur suppression membre')),
        );
    }
  }

  Future<void> _leaveGroup() async {
    if (currentUser == null) return;
    await _removeGroupMember(currentUser!.uid, isSelf: true);
  }

  Future<void> _showGroupSettingsSheet({
    required String currentName,
    required String currentDescription,
  }) async {
    final nameCtrl = TextEditingController(text: currentName);
    final descCtrl = TextEditingController(text: currentDescription);
    String groupPhoto = '';
    String canAddMembers = 'all';
    String canChangeInfo = 'admins';
    bool sendDisabled = false;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();
      if (snap.exists) {
        final data = snap.data() ?? {};
        groupPhoto = (data['groupPhoto'] ?? '').toString();
        if (data['permissions'] is Map) {
          final perms = Map<String, dynamic>.from(data['permissions']);
          canAddMembers = (perms['canAddMembers'] ?? canAddMembers).toString();
          canChangeInfo = (perms['canChangeInfo'] ?? canChangeInfo).toString();
          sendDisabled = (perms['sendDisabled'] ?? false) == true;
        }
      }
    } catch (_) {}
    XFile? newPhoto;

    bool opening = false;
    bool closing = false;
    bool initialized = false;
    void closeSheet(BuildContext ctx, void Function(void Function()) setModal) {
      if (closing) return;
      closing = true;
      opening = false;
      setModal(() {});
      Future.delayed(const Duration(milliseconds: 180), () {
        if (Navigator.canPop(ctx)) Navigator.pop(ctx);
      });
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (mCtx, setModal) {
            if (!initialized) {
              initialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                opening = true;
                setModal(() {});
              });
            }
            final ImageProvider? avatar = newPhoto != null
                ? FileImage(File(newPhoto!.path))
                : (groupPhoto.isNotEmpty
                      ? CachedNetworkImageProvider(groupPhoto) as ImageProvider
                      : null);
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => closeSheet(ctx, setModal),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(color: Colors.black.withOpacity(0.35)),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(ctx).viewInsets.bottom,
                    ),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: (opening && !closing) ? 1.0 : 0.0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        transform: Matrix4.translationValues(
                          0,
                          (opening && !closing) ? 0 : 24,
                          0,
                        ),
                        decoration: BoxDecoration(
                          color: _modalBg(ctx),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 24,
                              offset: const Offset(0, -6),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        tgAccent.withOpacity(0.7),
                                        tgAccent.withOpacity(0.2),
                                      ],
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.settings,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Paramètres du groupe',
                                  style: TextStyle(
                                    color: _modalText(ctx),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    color: _modalSub(ctx),
                                  ),
                                  onPressed: () => closeSheet(ctx, setModal),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    final picker = ImagePicker();
                                    final img = await picker.pickImage(
                                      source: ImageSource.gallery,
                                      maxWidth: 1200,
                                      imageQuality: 85,
                                    );
                                    if (img != null) {
                                      setModal(() => newPhoto = img);
                                    }
                                  },
                                  child: CircleAvatar(
                                    radius: 34,
                                    backgroundColor: _modalTileBg(ctx),
                                    backgroundImage: avatar,
                                    child:
                                        (newPhoto == null && groupPhoto.isEmpty)
                                        ? Icon(
                                            Icons.camera_alt,
                                            color: _modalSub(ctx),
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: nameCtrl,
                                    style: TextStyle(color: _modalText(ctx)),
                                    decoration: InputDecoration(
                                      hintText: 'Nom du groupe',
                                      hintStyle: TextStyle(
                                        color: _modalMuted(ctx),
                                      ),
                                      filled: true,
                                      fillColor: _modalTileBg(ctx),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: descCtrl,
                              style: TextStyle(color: _modalText(ctx)),
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText: 'Description',
                                hintStyle: TextStyle(color: _modalMuted(ctx)),
                                filled: true,
                                fillColor: _modalTileBg(ctx),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _modalTileBg(ctx),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _modalTileBg(ctx)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.block,
                                    color: Colors.orangeAccent,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Désactiver l’envoi des messages',
                                      style: TextStyle(color: _modalText(ctx)),
                                    ),
                                  ),
                                  Switch(
                                    value: sendDisabled,
                                    onChanged: (v) =>
                                        setModal(() => sendDisabled = v),
                                    activeThumbColor: Colors.orangeAccent,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Permissions',
                              style: TextStyle(
                                color: _modalSub(ctx),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Ajouter membres',
                                        style: TextStyle(
                                          color: _modalMuted(ctx),
                                          fontSize: 12,
                                        ),
                                      ),
                                      DropdownButton<String>(
                                        value: canAddMembers,
                                        isExpanded: true,
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'admins',
                                            child: Text('Admins seulement'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'all',
                                            child: Text('Tous les membres'),
                                          ),
                                        ],
                                        onChanged: (v) => setModal(
                                          () => canAddMembers = v ?? 'all',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Changer infos',
                                        style: TextStyle(
                                          color: _modalMuted(ctx),
                                          fontSize: 12,
                                        ),
                                      ),
                                      DropdownButton<String>(
                                        value: canChangeInfo,
                                        isExpanded: true,
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'admins',
                                            child: Text('Admins seulement'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'all',
                                            child: Text('Tous les membres'),
                                          ),
                                        ],
                                        onChanged: (v) => setModal(
                                          () => canChangeInfo = v ?? 'admins',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => closeSheet(ctx, setModal),
                                    child: Text(
                                      'Annuler',
                                      style: TextStyle(color: _modalSub(ctx)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: () async {
                                    try {
                                      final updates = <String, dynamic>{
                                        'groupName': nameCtrl.text.trim(),
                                        'description': descCtrl.text.trim(),
                                        'permissions': {
                                          'canAddMembers': canAddMembers,
                                          'canChangeInfo': canChangeInfo,
                                          'sendDisabled': sendDisabled,
                                        },
                                      };
                                      if (newPhoto != null) {
                                        final url = await _uploadGroupPhoto(
                                          newPhoto!,
                                        );
                                        if (url != null && url.isNotEmpty)
                                          updates['groupPhoto'] = url;
                                      }
                                      await FirebaseFirestore.instance
                                          .collection('chats')
                                          .doc(widget.chatId)
                                          .update(updates);
                                      if (mounted) {
                                        closeSheet(ctx, setModal);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Paramètres mis à jour',
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      debugPrint('group settings err: $e');
                                      if (mounted)
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Erreur de mise à jour',
                                            ),
                                          ),
                                        );
                                    }
                                  },
                                  child: const Text('Enregistrer'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Divider(color: _modalTileBg(ctx)),
                            const SizedBox(height: 6),
                            ListTile(
                              leading: Icon(
                                Icons.cloud_download,
                                color: _modalSub(ctx),
                              ),
                              title: Text(
                                'Téléchargement médias',
                                style: TextStyle(color: _modalText(ctx)),
                              ),
                              subtitle: Text(
                                'Gérer le cache et le Wi‑Fi',
                                style: TextStyle(
                                  color: _modalMuted(ctx),
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () async {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                bool wifiOnlyLocal =
                                    prefs.getBool('media_download_wifi_only') ??
                                    false;
                                showModalBottomSheet(
                                  context: context,
                                  backgroundColor: Colors.transparent,
                                  builder: (c) {
                                    return StatefulBuilder(
                                      builder: (cc, setPref) {
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: _modalBg(c),
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(18),
                                                ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    'Téléchargements',
                                                    style: TextStyle(
                                                      color: _modalText(c),
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.close,
                                                      color: _modalSub(c),
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.pop(c),
                                                  ),
                                                ],
                                              ),
                                              SwitchListTile(
                                                value: wifiOnlyLocal,
                                                onChanged: (v) async {
                                                  await prefs.setBool(
                                                    'media_download_wifi_only',
                                                    v,
                                                  );
                                                  setPref(
                                                    () => wifiOnlyLocal = v,
                                                  );
                                                },
                                                title: Text(
                                                  'Télécharger uniquement en Wi‑Fi',
                                                  style: TextStyle(
                                                    color: _modalText(c),
                                                  ),
                                                ),
                                              ),
                                              ListTile(
                                                leading: Icon(
                                                  Icons.storage,
                                                  color: _modalSub(c),
                                                ),
                                                title: Text(
                                                  'Gérer le cache',
                                                  style: TextStyle(
                                                    color: _modalText(c),
                                                  ),
                                                ),
                                                onTap: () {
                                                  Navigator.pop(c);
                                                  _showCacheManagerSheet();
                                                },
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteAllMessages() async {
    final messagesRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages');
    while (true) {
      final snap = await messagesRef.limit(300).get();
      if (snap.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _clearChatMessages() async {
    try {
      await _deleteAllMessages();
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
            'lastMessage': '',
            'lastMessageTime': FieldValue.serverTimestamp(),
            if (currentUser != null) 'unreadCounts.${currentUser!.uid}': 0,
          });
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Discussion effacée')));
    } catch (e) {
      debugPrint('clear chat err: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l’effacement')),
        );
    }
  }

  Future<void> _deleteGroupAndMessages() async {
    try {
      await _deleteAllMessages();
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .delete();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Groupe supprimé')));
      }
    } catch (e) {
      debugPrint('delete group err: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression')),
        );
    }
  }

  Future<String?> _uploadGroupPhoto(XFile file) async {
    try {
      final fileName = '${widget.chatId}/group_photo.jpg';
      if (SupabaseService.isInitialized) {
        final bytes = await file.readAsBytes();
        return await SupabaseService.uploadBytes(bytes, fileName, 'chat_media');
      }
      final ref = FirebaseStorage.instance.ref().child('chats/$fileName');
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        await ref.putData(bytes);
      } else {
        await ref.putFile(File(file.path));
      }
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('upload group photo err: $e');
      return null;
    }
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 100,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white10,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withOpacity(0.18),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmBlock(String otherId) async {
    if (currentUser == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          backgroundColor: _modalBg(c),
          title: Text(
            'Bloquer ce contact?',
            style: TextStyle(color: _modalText(c)),
          ),
          content: Text(
            'Vous ne recevrez plus de messages de ce contact. Vous pouvez débloquer plus tard depuis vos paramètres.',
            style: TextStyle(color: _modalSub(c)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('Annuler', style: TextStyle(color: _modalSub(c))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Bloquer', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
    if (ok == true) await _blockContact(otherId);
  }

  Future<void> _blockContact(String otherId) async {
    if (currentUser == null) return;

    final collections = ['classic_users', 'enterprise_users', 'pro_users'];

    try {
      // Mettre à jour le doc de l'utilisateur courant (me) dans la collection appropriée
      for (final col in collections) {
        final meRef = FirebaseFirestore.instance
            .collection(col)
            .doc(currentUser!.uid);
        try {
          await meRef.update({
            'blocked': FieldValue.arrayUnion([otherId]),
          });
          break; // stop dès qu'on a trouvé la collection
        } catch (_) {}
      }

      // Mettre à jour le doc de l'autre utilisateur
      for (final col in collections) {
        final otherRef = FirebaseFirestore.instance
            .collection(col)
            .doc(otherId);
        try {
          await otherRef.update({
            'blockedBy': FieldValue.arrayUnion([currentUser!.uid]),
          });
          break;
        } catch (_) {}
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Utilisateur bloqué')));
    } catch (e) {
      debugPrint('Block contact error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de bloquer ce contact')),
      );
    }
  }

  Future<void> _confirmDeleteContact(String otherId) async {
    if (currentUser == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          backgroundColor: _modalBg(c),
          title: Text(
            'Supprimer le contact?',
            style: TextStyle(color: _modalText(c)),
          ),
          content: Text(
            'Cette action supprimera le contact de votre liste. Les messages historiques restent inchangés.',
            style: TextStyle(color: _modalSub(c)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('Annuler', style: TextStyle(color: _modalSub(c))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text(
                'Supprimer',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
    if (ok == true) await _deleteContact(otherId);
  }

  Future<void> _deleteContact(String otherId) async {
    if (currentUser == null) return;

    final collections = ['classic_users', 'enterprise_users', 'pro_users'];

    try {
      for (final col in collections) {
        final meRef = FirebaseFirestore.instance
            .collection(col)
            .doc(currentUser!.uid);
        try {
          await meRef.update({
            'contacts': FieldValue.arrayRemove([otherId]),
          });
          break; // stop dès qu'on trouve la bonne collection
        } catch (_) {}
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Contact supprimé')));
    } catch (e) {
      debugPrint('Delete contact error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de supprimer ce contact')),
      );
    }
  }

  String _replyPreviewText(Map<String, dynamic> m) {
    final type = (m['type'] ?? 'text').toString();
    final rawText = (m['text'] ?? '').toString().trim();
    switch (type) {
      case 'text':
        return rawText.isNotEmpty ? rawText : 'Message';
      case 'image':
        return 'Photo';
      case 'video':
        return 'Vidéo';
      case 'audio':
      case 'voice':
        return 'Message vocal';
      case 'file':
        return 'Fichier';
      case 'alert':
        return rawText.isNotEmpty ? rawText : 'Alerte';
      default:
        return rawText.isNotEmpty ? rawText : 'Message';
    }
  }

  void _setReplyTarget(String messageId, Map<String, dynamic> m) {
    if (_selectionMode) return;
    final senderId = (m['senderId'] ?? '').toString();
    final isMe = senderId == (currentUser?.uid ?? '');
    final senderNameRaw = (m['senderName'] ?? m['senderDisplayName'] ?? '')
        .toString()
        .trim();
    final senderLabel = isMe
        ? 'Vous'
        : (senderNameRaw.isNotEmpty ? senderNameRaw : 'Utilisateur');
    final type = (m['type'] ?? 'text').toString();
    final mediaUrl = (m['url'] ?? m['imageUrl'] ?? m['fileUrl'] ?? '')
        .toString();

    final preview = _replyPreviewText(m);
    final clipped = preview.length > 120
        ? '${preview.substring(0, 117)}...'
        : preview;

    setState(() {
      _replyTo = {
        'messageId': messageId,
        'senderId': senderId,
        'senderName': senderLabel,
        'type': type,
        'text': clipped,
        if (mediaUrl.isNotEmpty) 'mediaUrl': mediaUrl,
      };
    });
  }

  Widget _buildReplyComposerBar(BuildContext context) {
    final r = _replyTo;
    if (r == null) return const SizedBox.shrink();
    final isDark = _isDark(context);
    final bg = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);
    final border = isDark ? Colors.white12 : Colors.black12;
    final title = (r['senderName'] ?? 'Utilisateur').toString();
    final txt = (r['text'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(
              color: tgAccent,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Répondre à $title',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  txt,
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            splashRadius: 18,
            icon: Icon(
              Icons.close,
              size: 18,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            onPressed: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyInBubble(
    BuildContext context,
    Map<String, dynamic> m, {
    required bool isMe,
  }) {
    final raw = m['replyTo'];
    if (raw is! Map) return const SizedBox.shrink();
    final r = Map<String, dynamic>.from(raw);
    final isDark = _isDark(context);
    final barColor = isMe ? Colors.white70 : tgAccent;
    final titleColor = isDark ? Colors.white70 : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black54;
    final senderName = (r['senderName'] ?? 'Utilisateur').toString();
    final txt = (r['text'] ?? '').toString();
    final replyId = (r['messageId'] ?? '').toString();

    return InkWell(
      onTap: replyId.isEmpty
          ? null
          : () {
              setState(() => _pendingJumpMessageId = replyId);
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withOpacity(0.15)
              : Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 36,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    senderName,
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    txt,
                    style: TextStyle(color: subColor, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (replyId.isNotEmpty)
              Icon(
                Icons.chevron_right,
                size: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToFirestore(Map<String, dynamic> data) async {
    final payload = <String, dynamic>{...data};
    if (_replyTo != null) {
      payload['replyTo'] = _replyTo;
    }

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .add({
          'senderId': currentUser?.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'delivered': false,
          'deliveredAt': null,
          ...payload,
        });

    if (_replyTo != null && mounted) {
      setState(() => _replyTo = null);
    }

    // Keep UI responsive: run chat metadata + push notification in background.
    unawaited(_updateChatMetaAndNotify(payload));

    // play local send sfx (best-effort, non blocking)
    try {
      if (currentUser != null) {
        unawaited(_playSfx('sounds/pop.mp3'));
      }
    } catch (_) {}
  }

  Future<void> _updateChatMetaAndNotify(Map<String, dynamic> payload) async {
    final chatRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId);
    List<dynamic> participants = const [];
    try {
      final chatSnap = await chatRef.get().timeout(const Duration(seconds: 10));
      final chatData = chatSnap.data() ?? const <String, dynamic>{};
      participants = (chatData['participants'] is List)
          ? List.from(chatData['participants'])
          : const [];

      final updateData = <String, dynamic>{
        'lastMessage': payload['text'] ?? "",
        'lastMessageTime': FieldValue.serverTimestamp(),
      };

      if (currentUser != null && participants.isNotEmpty) {
        for (final p in participants) {
          updateData['hiddenFor.$p'] = FieldValue.delete();
          if (p != currentUser!.uid) {
            updateData['unreadCounts.$p'] = FieldValue.increment(1);
          }
        }
      }

      await chatRef
          .set(updateData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Erreur update chat meta: $e');
    }

    unawaited(_sendChatMessageNotifier(payload, participants: participants));
  }

  Future<void> _sendChatMessageNotifier(
    Map<String, dynamic> payload, {
    required List<dynamic> participants,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final recipients = participants
          .map((p) => p.toString())
          .where((p) => p.isNotEmpty && p != user.uid)
          .toList();
      if (recipients.isEmpty) return;

      final idToken = await user.getIdToken().timeout(
        const Duration(seconds: 8),
      );
      final url = Uri.parse(kNotifierUrl);

      final meta = await _resolveSenderMeta(
        user,
      ).timeout(const Duration(seconds: 8));
      final String senderName = meta['name'] ?? 'Un utilisateur';
      final String senderPhoto =
          meta['photo'] ??
          'https://cdn-icons-png.flaticon.com/512/149/149071.png';

      final String msgType = (payload['type'] ?? 'text').toString();
      final String rawText = (payload['text'] ?? '').toString().trim();
      String preview;
      switch (msgType) {
        case 'text':
          preview = rawText.isNotEmpty ? rawText : 'Nouveau message';
          break;
        case 'image':
          preview = rawText.isNotEmpty ? rawText : 'Photo';
          break;
        case 'video':
          preview = rawText.isNotEmpty ? rawText : 'Video';
          break;
        case 'voice':
        case 'audio':
          preview = rawText.isNotEmpty ? rawText : 'Message vocal';
          break;
        case 'file':
          preview = rawText.isNotEmpty ? rawText : 'Fichier';
          break;
        default:
          preview = rawText.isNotEmpty ? rawText : 'Nouveau message';
          break;
      }
      if (preview.length > 120) preview = '${preview.substring(0, 117)}...';

      final String mediaUrl =
          (payload['url'] ?? payload['imageUrl'] ?? payload['fileUrl'] ?? '')
              .toString();
      final String imageUrl = (msgType == 'image' || msgType == 'video')
          ? mediaUrl
          : '';

      final resp = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'recipients': recipients,
              'title': senderName,
              'body': preview,
              'senderAvatarUrl': senderPhoto,
              'imageUrl': imageUrl,
              'existing_android_channel_id': 'lualaba_channel_v2',
              'android_sound': 'lualaba_pop',
              'data': {
                'chatId': widget.chatId,
                'chatName': widget.chatName,
                'senderId': user.uid,
                'type': 'chat_message',
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint(
        '[Notifier][chat_message] status=${resp.statusCode} body=${resp.body}',
      );
    } catch (e) {
      debugPrint('Notifier call error: $e');
    }
  }

  Future<void> _markMessagesAsDeliveredAndRead(
    List<QueryDocumentSnapshot> docs,
  ) async {
    if (currentUser == null) return;
    if (_markingReceipts) return;
    _markingReceipts = true;

    final String uid = currentUser!.uid;
    bool shouldClearUnread = false;
    int pendingOps = 0;
    WriteBatch batch = FirebaseFirestore.instance.batch();

    Future<void> commitBatch() async {
      if (pendingOps == 0) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      pendingOps = 0;
    }

    try {
      for (final d in docs) {
        Map<String, dynamic> m;
        try {
          m = Map<String, dynamic>.from(d.data() as Map);
        } catch (_) {
          continue;
        }

        final senderId = (m['senderId'] ?? '').toString();
        if (senderId.isEmpty || senderId == uid) continue;

        final Map<String, dynamic> update = {};
        if (m['delivered'] != true) {
          update['delivered'] = true;
          update['deliveredAt'] = FieldValue.serverTimestamp();
        }
        if (m['isRead'] != true) {
          update['isRead'] = true;
          update['readAt'] = FieldValue.serverTimestamp();
          shouldClearUnread = true;
        }
        if (update.isEmpty) continue;

        batch.update(d.reference, update);
        pendingOps++;

        // Firestore batch limit is 500 operations. Commit earlier to stay safe.
        if (pendingOps >= 450) {
          await commitBatch();
        }
      }

      await commitBatch();

      if (shouldClearUnread) {
        final chatRef = FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId);
        try {
          await chatRef.update({
            'unreadCounts.$uid': 0,
            'lastReadAt.$uid': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          // fallback merge if the doc shape is different/missing
          try {
            await chatRef.set({
              'unreadCounts': {uid: 0},
              'lastReadAt': {uid: FieldValue.serverTimestamp()},
            }, SetOptions(merge: true));
          } catch (_) {}
        }

        // Best effort: clear notifications so "push" doesn't stay visible after opening/reading.
        try {
          await NotificationService.clearNotificationsForChat(
            widget.chatId,
            clearPush: true,
          );
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Erreur maj accusés: $e');
    } finally {
      _markingReceipts = false;
    }
  }

  Future<void> _setTyping(bool value) async {
    if (currentUser == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'typing.${currentUser!.uid}': value});
    } catch (e) {
      debugPrint('Set typing error: $e');
    }
  }

  Future<void> _setUserAction(String action) async {
    if (currentUser == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'userActions.${currentUser!.uid}': action});
    } catch (e) {
      debugPrint('Set userAction error: $e');
    }
  }

  Future<void> _setPresence(bool present) async {
    if (currentUser == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'present.${currentUser!.uid}': present});
    } catch (e) {
      debugPrint('Set presence error: $e');
    }
  }

  // --- DIALOGUE DE SONDAGE RAPIDE ---
  void _showPollDialog() {
    String question = "";
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _modalBg(context),
        title: Text(
          "Nouveau sondage",
          style: TextStyle(color: _modalText(context)),
        ),
        content: TextField(
          autofocus: true,
          style: TextStyle(color: _modalText(context)),
          decoration: InputDecoration(
            hintText: "Posez votre question...",
            hintStyle: TextStyle(color: _modalMuted(context)),
          ),
          onChanged: (v) => question = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Annuler", style: TextStyle(color: _modalSub(context))),
          ),
          TextButton(
            onPressed: () {
              if (question.trim().isNotEmpty) {
                _saveToFirestore({
                  'type': 'poll',
                  'question': question,
                  'text': '📊 Sondage: $question',
                });
                Navigator.pop(context);
              }
            },
            child: const Text("Envoyer", style: TextStyle(color: tgAccent)),
          ),
        ],
      ),
    );
  }

  // --- ACTIONS DU MENU D'ATTACHEMENT MISES À JOUR ---
  void _showAttachmentMenu() {
    final parentContext = context;

    showModalBottomSheet(
      context: parentContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => TelegramAttachmentSheet(
        onImageSelected: (asset) async {
          Navigator.pop(parentContext);
          File? f = await asset.file;
          if (f != null)
            _uploadAndSend(XFile(f.path), 'image', 'chat_media', '📸 Photo');
        },
        onCameraTap: () async {
          Navigator.pop(parentContext);
          final XFile? media = await Navigator.push(
            parentContext,
            MaterialPageRoute(builder: (c) => const CameraScreen()),
          );
          if (media != null) {
            final result = await Navigator.push(
              parentContext,
              MaterialPageRoute(
                builder: (c) => MediaPreviewScreen(
                  mediaFile: media,
                  type: media.path.endsWith('.mp4') ? 'video' : 'image',
                ),
              ),
            );
            if (result != null) {
              _uploadAndSend(
                result['file'],
                media.path.endsWith('.mp4') ? 'video' : 'image',
                'chat_media',
                result['caption'],
              );
            }
          }
        },
        onGalleryTap: () async {
          Navigator.pop(parentContext);
          await _pickAndSendMultipleMedia();
        },
        onFileTap: () async {
          Navigator.pop(parentContext);
          FilePickerResult? res = await FilePicker.platform.pickFiles(
            withData: true,
          );
          if (res != null) {
            _uploadAndSend(
              res.files.single,
              'file',
              'chat_media',
              '📄 Fichier',
              extraData: {'fileName': res.files.single.name},
              originalName: res.files.single.name,
            );
          }
        },
        onLocationTap: () async {
          Navigator.pop(context);
          LocationPermission p = await Geolocator.requestPermission();
          if (p != LocationPermission.denied) {
            Position pos = await Geolocator.getCurrentPosition();
            _saveToFirestore({
              'type': 'location',
              'lat': pos.latitude,
              'lng': pos.longitude,
              'text': '📍 Position',
            });
          }
        },
        onMusicTap: () async {
          Navigator.pop(context);
          FilePickerResult? res = await FilePicker.platform.pickFiles(
            type: FileType.audio,
            withData: true,
          );
          if (res != null) {
            _uploadAndSend(
              res.files.single,
              'audio',
              'chat_media',
              '🎵 Musique',
              extraData: {'fileName': res.files.single.name},
              originalName: res.files.single.name,
            );
          }
        },
        onContactTap: () async {
          Navigator.pop(context);
          if (await FlutterContacts.requestPermission()) {
            final contact = await FlutterContacts.openExternalPick();
            if (contact != null) {
              _saveToFirestore({
                'type': 'contact',
                'contactName': contact.displayName,
                'phone': contact.phones.isNotEmpty
                    ? contact.phones.first.number
                    : "Pas de numéro",
                'text': '👤 Contact: ${contact.displayName}',
              });
            }
          }
        },
        onPollTap: () {
          Navigator.pop(context);
          _showPollDialog();
        },
      ),
    );
  }

  Future<void> _editContactLocal(String otherId) async {
    if (currentUser == null) return;

    String name = '';
    String phone = '';

    // Fonction interne pour chercher le contact dans une collection spécifique
    Future<Map<String, dynamic>?> getContactFromCollection(
      String collection,
    ) async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(collection)
            .doc(currentUser!.uid)
            .collection('contacts')
            .doc(otherId)
            .get();
        if (doc.exists) return Map<String, dynamic>.from(doc.data() ?? {});
      } catch (_) {}
      return null;
    }

    // Chercher dans toutes les collections jusqu'à trouver
    final collections = ['classic_users', 'enterprise_users', 'pro_users'];
    Map<String, dynamic>? contact;
    for (final col in collections) {
      contact = await getContactFromCollection(col);
      if (contact != null) break;
    }

    if (contact != null) {
      name = contact['displayName'] ?? '';
      phone = contact['phone'] ?? '';
    }

    final nCtrl = TextEditingController(text: name);
    final pCtrl = TextEditingController(text: phone);

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        return AlertDialog(
          backgroundColor: _modalBg(c),
          title: Text(
            'Modifier contact',
            style: TextStyle(color: _modalText(c)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nCtrl,
                style: TextStyle(color: _modalText(c)),
                decoration: InputDecoration(
                  hintText: 'Nom',
                  hintStyle: TextStyle(color: _modalMuted(c)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pCtrl,
                style: TextStyle(color: _modalText(c)),
                decoration: InputDecoration(
                  hintText: 'Téléphone',
                  hintStyle: TextStyle(color: _modalMuted(c)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('Annuler', style: TextStyle(color: _modalSub(c))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(
                'Enregistrer',
                style: TextStyle(color: _modalText(c)),
              ),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      try {
        // Mettre à jour dans la collection où le contact a été trouvé
        final ref = FirebaseFirestore.instance
            .collection(
              contact != null && collections.contains('classic_users')
                  ? 'classic_users'
                  : contact != null && collections.contains('enterprise_users')
                  ? 'enterprise_users'
                  : 'pro_users',
            )
            .doc(currentUser!.uid)
            .collection('contacts')
            .doc(otherId);

        await ref.set({
          'displayName': nCtrl.text.trim(),
          'phone': pCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Mettre à jour les localNames dans le chat pour affichage instantané
        try {
          final chatRef = FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId);
          await chatRef.set({
            'localNames': {currentUser!.uid: nCtrl.text.trim()},
          }, SetOptions(merge: true));
        } catch (_) {}

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Contact mis à jour')));
      } catch (e) {
        debugPrint('Edit contact error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la mise à jour')),
        );
      }
    }
  }

  void _showCallOptions() async {
    // resolve other participant id from chat doc
    try {
      final chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId);
      final chatSnap = await chatRef.get();
      if (!chatSnap.exists) return;
      final data = chatSnap.data() ?? {};
      List participants = (data['participants'] is List)
          ? List.from(data['participants'])
          : [];
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final bool isGroup = data['isGroup'] == true || participants.length > 2;

      // Group call: invite everyone in the group except me.
      if (isGroup) {
        final ids = participants
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toSet()
            .toList();
        final others = ids.where((e) => e != uid).toList();
        if (others.isEmpty) return;
        final groupName = (data['groupName'] ?? data['name'] ?? widget.chatName)
            .toString();
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (ctx) {
            final isDark = _isDark(ctx);
            return Container(
              decoration: BoxDecoration(
                color: _modalBg(ctx),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white12 : Colors.black12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Appel de groupe',
                    style: TextStyle(
                      color: _modalText(ctx),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (groupName.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _modalSub(ctx), fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionTile(
                        icon: Icons.call,
                        label: 'Audio',
                        color: Colors.green,
                        onTap: () {
                          Navigator.pop(ctx);
                          _startGroupCall(others, false, title: groupName);
                        },
                      ),
                      _actionTile(
                        icon: Icons.videocam,
                        label: 'Vidéo',
                        color: Colors.purple,
                        onTap: () {
                          Navigator.pop(ctx);
                          _startGroupCall(others, true, title: groupName);
                        },
                      ),
                      _actionTile(
                        icon: Icons.schedule,
                        label: 'Planifier',
                        color: Colors.orange,
                        onTap: () {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Planifier un appel — bientôt'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
        return;
      }

      String otherId = participants.firstWhere(
        (id) => id != uid,
        orElse: () => "",
      );
      if (otherId == "") return;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final isDark = _isDark(ctx);
          return Container(
            decoration: BoxDecoration(
              color: _modalBg(ctx),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : Colors.black12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Options d\'appel',
                  style: TextStyle(
                    color: _modalText(ctx),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _actionTile(
                      icon: Icons.call,
                      label: 'Audio',
                      color: Colors.green,
                      onTap: () {
                        Navigator.pop(ctx);
                        _startCall(otherId, false);
                      },
                    ),
                    _actionTile(
                      icon: Icons.videocam,
                      label: 'Vidéo',
                      color: Colors.purple,
                      onTap: () {
                        Navigator.pop(ctx);
                        _startCall(otherId, true);
                      },
                    ),
                    _actionTile(
                      icon: Icons.schedule,
                      label: 'Planifier',
                      color: Colors.orange,
                      onTap: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Planifier un appel — bientôt'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Show call options error: $e');
    }
  }

  Future<void> _startGroupCall(
    List<String> otherIds,
    bool video, {
    String? title,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final ids = otherIds
          .where((e) => e.trim().isNotEmpty && e != user.uid)
          .toSet()
          .toList();
      if (ids.isEmpty) return;

      final participants = <String>[user.uid, ...ids];
      final callRef = await FirebaseFirestore.instance.collection('calls').add({
        'isGroup': true,
        'chatId': widget.chatId,
        'chatName': title ?? widget.chatName,
        'groupName': title ?? widget.chatName,
        'caller': user.uid,
        'callerName': user.displayName ?? '',
        'participants': participants,
        'invited': ids,
        'status': 'ringing',
        'type': video ? 'video' : 'audio',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _sendIncomingGroupCallPush(
        calleeIds: ids,
        callId: callRef.id,
        isVideo: video,
        title: title ?? widget.chatName,
      );

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupCallWebRTCPage(
            callId: callRef.id,
            name: (title ?? widget.chatName).toString(),
            isVideo: video,
            isCaller: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Start group call error: $e');
    }
  }

  Future<void> _startCall(String otherId, bool video) async {
    try {
      final callRef = await FirebaseFirestore.instance.collection('calls').add({
        'caller': FirebaseAuth.instance.currentUser?.uid,
        'callerName': FirebaseAuth.instance.currentUser?.displayName ?? '',
        'callee': otherId,
        'status': 'ringing',
        'type': video ? 'video' : 'audio',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Push "incoming call" so the callee gets notified even if the app is closed.
      await _sendIncomingCallPush(
        calleeId: otherId,
        callId: callRef.id,
        isVideo: video,
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallWebRTCPage(
            callId: callRef.id,
            otherId: otherId,
            isCaller: true,
            name: widget.chatName,
            avatarLetter: widget.chatName.isNotEmpty
                ? widget.chatName[0].toUpperCase()
                : '?',
            isVideo: video,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Start call error: $e');
    }
  }

  Future<void> _sendIncomingGroupCallPush({
    required List<String> calleeIds,
    required String callId,
    required bool isVideo,
    required String title,
  }) async {
    try {
      final ids = calleeIds.where((e) => e.trim().isNotEmpty).toSet().toList();
      if (ids.isEmpty) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();
      final url = Uri.parse(kNotifierUrl);

      final meta = await _resolveSenderMeta(user);
      final String senderPhoto =
          (user.photoURL != null && user.photoURL!.trim().isNotEmpty)
          ? user.photoURL!.trim()
          : (meta['photo'] ??
                'https://cdn-icons-png.flaticon.com/512/149/149071.png');

      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'recipients': ids,
          'title': title,
          'body': isVideo ? 'Appel vidéo de groupe' : 'Appel audio de groupe',
          'senderAvatarUrl': senderPhoto,
          'existing_android_channel_id': 'lualaba_channel_v2',
          'android_sound': 'lualaba_pop',
          'data': {
            'type': 'incoming_call',
            'isGroup': true,
            'callId': callId,
            'isVideo': isVideo,
            'chatId': widget.chatId,
            'chatName': widget.chatName,
          },
        }),
      );
      debugPrint(
        '[Notifier][incoming_group_call] status=${resp.statusCode} body=${resp.body}',
      );
    } catch (e) {
      debugPrint('Send incoming group call push error: $e');
    }
  }

  Future<void> _sendIncomingCallPush({
    required String calleeId,
    required String callId,
    required bool isVideo,
  }) async {
    try {
      if (calleeId.trim().isEmpty) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();
      final url = Uri.parse(kNotifierUrl);

      final String callerName =
          (user.displayName != null && user.displayName!.trim().isNotEmpty)
          ? user.displayName!.trim()
          : '';

      final String callerPhoto =
          (user.photoURL != null && user.photoURL!.trim().isNotEmpty)
          ? user.photoURL!.trim()
          : '';

      final meta = await _resolveSenderMeta(user);
      final String resolvedCallerName = callerName.isNotEmpty
          ? callerName
          : (meta['name'] ?? 'Appel entrant');
      final String resolvedCallerPhoto = callerPhoto.isNotEmpty
          ? callerPhoto
          : (meta['photo'] ??
                'https://cdn-icons-png.flaticon.com/512/149/149071.png');

      final resp = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'recipients': [calleeId],
          'title': resolvedCallerName,
          'body': isVideo ? 'Appel vidéo entrant' : 'Appel audio entrant',
          'senderAvatarUrl': resolvedCallerPhoto,
          'existing_android_channel_id': 'lualaba_channel_v2',
          'android_sound': 'lualaba_pop',
          'data': {
            'type': 'incoming_call',
            'callId': callId,
            'isVideo': isVideo,
            // Useful for navigation/UX
            'chatId': widget.chatId,
            'chatName': widget.chatName,
          },
        }),
      );
      debugPrint(
        '[Notifier][incoming_call] status=${resp.statusCode} body=${resp.body}',
      );
    } catch (e) {
      debugPrint('Send incoming call push error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? tgBg : const Color(0xFFF5F6F8);
    // Light mode requested: an "orange noiratre" top bar (burnt orange / near-black).
    final bool warmBar = !isDark;
    final Color bar = isDark ? tgBar : const Color(0xFF2B140B);
    final Gradient? barGradient = warmBar
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF241006), Color(0xFF6E2A0C)],
          )
        : null;
    final Color text = isDark ? Colors.white : Colors.black87;
    final Color sub = isDark ? Colors.white70 : Colors.black54;
    final Color icon = isDark ? Colors.white : Colors.black87;
    final Color appBarFg = Colors.white;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bar,
        flexibleSpace: barGradient == null
            ? null
            : Container(decoration: BoxDecoration(gradient: barGradient)),
        elevation: 1,
        iconTheme: IconThemeData(color: warmBar ? appBarFg : icon),
        leading: _selectionMode
            ? IconButton(
                icon: Icon(Icons.close, color: warmBar ? appBarFg : icon),
                onPressed: () => _clearSelection(),
              )
            : null,
        title: _selectionMode
            ? Text(
                '${_selectedMessageIds.length} sélectionné(s)',
                style: TextStyle(color: warmBar ? appBarFg : text),
              )
            : StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .doc(widget.chatId)
                    .snapshots(),
                builder: (context, snap) {
                  String status = "";
                  bool isGroup = false;
                  String groupPhoto = "";
                  List<String> groupParticipants = const [];
                  String groupCreatorId = "";
                  String groupDescription = "";
                  // Determine a resilient display name: prefer chat doc 'name', then widget.chatName,
                  // then current user's displayName, finally fallback to 'Utilisateur'.
                  String displayName = widget.chatName.trim();
                  if (displayName.isEmpty)
                    displayName = currentUser?.displayName ?? "";
                  if (snap.hasData && snap.data!.exists) {
                    final rawChat = snap.data!.data();
                    var data = rawChat is Map
                        ? Map<String, dynamic>.from(
                            (rawChat as Map<String, dynamic>?) ?? {},
                          )
                        : <String, dynamic>{};
                    isGroup = data['isGroup'] == true;
                    if (_isGroupChat != isGroup) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isGroupChat = isGroup);
                      });
                    }
                    if (isGroup) {
                      groupPhoto = (data['groupPhoto'] as String?) ?? '';
                      if (data['groupName'] is String &&
                          (data['groupName'] as String).trim().isNotEmpty) {
                        displayName = (data['groupName'] as String).trim();
                      }
                      if (data['description'] is String &&
                          (data['description'] as String).trim().isNotEmpty) {
                        groupDescription = (data['description'] as String)
                            .trim();
                      }
                      groupCreatorId =
                          (data['creatorId'] ??
                                  data['createdBy'] ??
                                  data['ownerId'] ??
                                  '')
                              as String? ??
                          '';
                    }
                    // prefer explicit chat name from document
                    // support local per-user override: data['localNames'] is a map of uid->name
                    if (data['localNames'] is Map && currentUser != null) {
                      try {
                        final ln = Map<String, dynamic>.from(
                          (data['localNames'] as Map<String, dynamic>?) ?? {},
                        );
                        if (ln.containsKey(currentUser!.uid) &&
                            (ln[currentUser!.uid] as String)
                                .trim()
                                .isNotEmpty) {
                          displayName = (ln[currentUser!.uid] as String).trim();
                        }
                      } catch (_) {}
                    }
                    if (displayName.isEmpty &&
                        data['name'] is String &&
                        (data['name'] as String).trim().isNotEmpty) {
                      displayName = (data['name'] as String).trim();
                    }
                    Map typing = (data['typing'] is Map) ? data['typing'] : {};
                    Map actions = (data['userActions'] is Map)
                        ? data['userActions']
                        : {};
                    Map present = (data['present'] is Map)
                        ? data['present']
                        : {};
                    List others = (data['participants'] is List)
                        ? List.from(data['participants'])
                        : [];
                    if (isGroup) {
                      groupParticipants = others
                          .map((e) => e.toString())
                          .toList();
                    }
                    others.removeWhere((id) => id == currentUser?.uid);
                    // priority: actions (recording) > typing > present
                    List<String> recording = [];
                    List<String> typingUsers = [];
                    int presentCount = 0;
                    for (var o in others) {
                      if (actions[o] == 'recording') {
                        recording.add(o as String);
                      } else if (typing[o] == true)
                        typingUsers.add(o as String);
                      if (present[o] == true) presentCount++;
                    }
                    if (!isGroup) {
                      if (recording.isNotEmpty) {
                        status = recording.length == 1
                            ? "enregistrement audio..."
                            : "plusieurs enregistrement(s)...";
                      } else if (typingUsers.isNotEmpty)
                        status = typingUsers.length == 1
                            ? "en train d'écrire..."
                            : "plusieurs en train d'écrire...";
                      else if (presentCount > 0)
                        status = presentCount == 1
                            ? "1 personne présente"
                            : "$presentCount personnes présentes";
                    }
                  }
                  // sanitize accidental greeting strings like "bonjour utilisateur"
                  final lower = displayName.toLowerCase();
                  if (lower.contains('bonjour') ||
                      lower.contains('utilisateur')) {
                    displayName = '';
                  }

                  // try to detect other participant uid from chat doc so we can lookup their user profile
                  String otherId = "";
                  if (snap.hasData && snap.data!.exists) {
                    final rawChat2 = snap.data!.data();
                    var data = rawChat2 is Map
                        ? Map<String, dynamic>.from(
                            (rawChat2 as Map<String, dynamic>?) ?? {},
                          )
                        : <String, dynamic>{};
                    List parts = (data['participants'] is List)
                        ? List.from(data['participants'])
                        : [];
                    parts.removeWhere((id) => id == currentUser?.uid);
                    if (parts.isNotEmpty) otherId = parts.first as String;
                  }

                  Widget buildRow(String name, {String? otherId}) {
                    String displayNameLocal = name;
                    final avatarLetter = displayNameLocal.isNotEmpty
                        ? displayNameLocal[0].toUpperCase()
                        : '?';

                    Widget nameAndBadge(bool isCert, String? accountType) {
                      return Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name.isNotEmpty ? name : 'Utilisateur',
                                    style: TextStyle(
                                      color: warmBar ? appBarFg : text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isCert ||
                                    (accountType != null &&
                                        accountType.isNotEmpty)) ...[
                                  const SizedBox(width: 6),
                                  AccountBadges(
                                    isCertified: isCert,
                                    accountType: accountType,
                                    fontSize: 10,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            if (status.isNotEmpty)
                              Text(
                                status,
                                style: TextStyle(
                                  color: warmBar ? Colors.white70 : sub,
                                  fontSize: 12,
                                  height: 1.1,
                                ),
                              ),
                          ],
                        ),
                      );
                    }

                    if (otherId != null && otherId.isNotEmpty) {
                      return FutureBuilder<Map<String, dynamic>?>(
                        future: _getUserProfile(otherId),
                        builder: (ctx, userSnap) {
                          String photo = '';
                          bool isCert = false;
                          String? accountType;
                          if (userSnap.hasData && userSnap.data != null) {
                            final ud =
                                userSnap.data!['data']
                                    as Map<String, dynamic>? ??
                                <String, dynamic>{};
                            accountType =
                                userSnap.data!['collection'] as String?;
                            photo =
                                (ud['photoUrl'] ??
                                        ud['photo'] ??
                                        ud['avatar'] ??
                                        '')
                                    as String;
                            if (ud['displayName'] is String &&
                                (ud['displayName'] as String)
                                    .trim()
                                    .isNotEmpty) {
                              displayNameLocal = (ud['displayName'] as String)
                                  .trim();
                            } else if (ud['name'] is String &&
                                (ud['name'] as String).trim().isNotEmpty) {
                              displayNameLocal = (ud['name'] as String).trim();
                            }
                            isCert = ud['isCertified'] == true;
                          }

                          final avatar = GestureDetector(
                            onTap: () => _showAvatarActions(
                              otherId,
                              canEdit: otherId == currentUser?.uid,
                              photoUrl: photo,
                            ),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [Colors.white10, Colors.white12],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.4),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.transparent,
                                backgroundImage: photo.isNotEmpty
                                    ? CachedNetworkImageProvider(photo)
                                          as ImageProvider
                                    : null,
                                child: photo.isEmpty
                                    ? Text(
                                        avatarLetter,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          );

                          return Row(
                            children: [
                              avatar,
                              const SizedBox(width: 12),
                              // use resolvedNameTemp for display if available
                              Builder(
                                builder: (_) {
                                  return nameAndBadge(isCert, accountType);
                                },
                              ),
                            ],
                          );
                        },
                      );
                    }

                    return Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Colors.white10, Colors.white12],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.transparent,
                            child: Text(
                              avatarLetter,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        nameAndBadge(false, null),
                      ],
                    );
                  }

                  Widget buildGroupRow(
                    String name,
                    String photoUrl,
                    List<String> participants,
                    String creatorId,
                    String description,
                  ) {
                    final ids = participants
                        .where((p) => p != currentUser?.uid)
                        .toList();
                    final lastTwo = ids.length <= 2
                        ? ids
                        : ids.sublist(ids.length - 2);
                    return GestureDetector(
                      onTap: () {
                        _showGroupInfoSheet(
                          groupName: name,
                          groupPhotoUrl: photoUrl,
                          participantIds: participants,
                          creatorId: creatorId,
                          description: description,
                        );
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Colors.white10, Colors.white12],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.transparent,
                              backgroundImage: photoUrl.isNotEmpty
                                  ? CachedNetworkImageProvider(photoUrl)
                                        as ImageProvider
                                  : null,
                              child: photoUrl.isEmpty
                                  ? const Icon(
                                      Icons.group,
                                      color: Colors.white70,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name.isNotEmpty ? name : 'Groupe',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                if (lastTwo.isEmpty)
                                  const Text(
                                    'Aucun membre récent',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      height: 1.1,
                                    ),
                                  )
                                else
                                  FutureBuilder<List<String>>(
                                    future: _resolveNames(lastTwo),
                                    builder: (ctx, snap) {
                                      final names = snap.data ?? lastTwo;
                                      final label = names.join(', ');
                                      return Text(
                                        label,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          height: 1.1,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (isGroup) {
                    final groupName = displayName.isNotEmpty
                        ? displayName
                        : (widget.chatName.isNotEmpty
                              ? widget.chatName
                              : 'Groupe');
                    return buildGroupRow(
                      groupName,
                      groupPhoto,
                      groupParticipants,
                      groupCreatorId,
                      groupDescription,
                    );
                  }

                  // If we have an other participant id, try to resolve displayName from users collection
                  final needsLookup =
                      otherId.isNotEmpty &&
                      (displayName.isEmpty ||
                          displayName.contains('@') ||
                          displayName.toLowerCase().contains('utilisateur'));
                  if (needsLookup) {
                    return FutureBuilder<DocumentSnapshot?>(
                      future: _getUserDoc(otherId),
                      builder: (ctx, userSnap) {
                        String resolved = displayName;
                        if (userSnap.hasData &&
                            userSnap.data != null &&
                            userSnap.data!.exists) {
                          final rawUd = userSnap.data!.data();
                          final ud = rawUd is Map
                              ? Map<String, dynamic>.from(
                                  rawUd as Map<String, dynamic>,
                                )
                              : <String, dynamic>{};
                          if (ud['displayName'] is String &&
                              (ud['displayName'] as String).trim().isNotEmpty) {
                            resolved = (ud['displayName'] as String).trim();
                          } else if (ud['name'] is String &&
                              (ud['name'] as String).trim().isNotEmpty) {
                            resolved = (ud['name'] as String).trim();
                          }
                        }
                        if (resolved.isEmpty)
                          resolved = currentUser?.displayName ?? 'Utilisateur';
                        return buildRow(resolved, otherId: otherId);
                      },
                    );
                  }

                  // default
                  if (displayName.isEmpty)
                    displayName = currentUser?.displayName ?? 'Utilisateur';
                  return buildRow(displayName, otherId: otherId);
                },
              ),
        actions: [
          _selectionMode
              ? IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => _confirmDeleteSelected(),
                )
              : const SizedBox.shrink(),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('chats')
                .doc(widget.chatId)
                .snapshots(),
            builder: (context, snap) {
              bool isGroup = false;
              if (snap.hasData && snap.data!.exists) {
                final rawChat = snap.data!.data();
                final data = rawChat is Map
                    ? Map<String, dynamic>.from(
                        (rawChat as Map<String, dynamic>?) ?? {},
                      )
                    : <String, dynamic>{};
                isGroup = data['isGroup'] == true;
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_selectionMode && !isGroup)
                    IconButton(
                      icon: Icon(Icons.call, color: warmBar ? appBarFg : icon),
                      onPressed: () => _showCallOptions(),
                    ),
                  if (!_selectionMode)
                    PopupMenuButton<String>(
                      onSelected: (v) => _onMenuSelected(v),
                      itemBuilder: (ctx) => isGroup
                          ? [
                              const PopupMenuItem(
                                value: 'group_info',
                                child: Text('Info du groupe'),
                              ),
                              const PopupMenuItem(
                                value: 'group_media',
                                child: Text('Media du groupe'),
                              ),
                              const PopupMenuItem(
                                value: 'search',
                                child: Text('Rechercher'),
                              ),
                              const PopupMenuItem(
                                value: 'mute',
                                child: Text('Mode silencieux'),
                              ),
                              const PopupMenuItem(
                                value: 'ephemeral',
                                child: Text('Message ephemere'),
                              ),
                              const PopupMenuItem(
                                value: 'theme',
                                child: Text('Theme de la discussion'),
                              ),
                              const PopupMenuItem(
                                value: 'clear',
                                child: Text('Effacer le contenu'),
                              ),
                            ]
                          : [
                              const PopupMenuItem(
                                value: 'audio',
                                child: Text('Appel audio'),
                              ),
                              const PopupMenuItem(
                                value: 'video',
                                child: Text('Appel vidéo'),
                              ),
                              const PopupMenuItem(
                                value: 'info',
                                child: Text('Info contact'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Supprimer la conversation'),
                              ),
                            ],
                    )
                  else
                    const SizedBox.shrink(),
                ],
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // animated chat background (placed below content)
          const Positioned.fill(child: AnimatedChatBackground()),
          // animated gradient background (subtle cycling)
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(seconds: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _bgGradients[_bgIndex]
                      .map((c) => c.withOpacity(0.18))
                      .toList(),
                ),
              ),
            ),
          ),
          // glass blur
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
              child: Container(color: Colors.black.withOpacity(0.03)),
            ),
          ),
          // gradient overlay + content
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    isDark
                        ? tgBg.withOpacity(0.25)
                        : Colors.white.withOpacity(0.9),
                    isDark
                        ? const Color(0xFF071011).withOpacity(0.35)
                        : const Color(0xFFE8ECF1).withOpacity(0.9),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(child: _buildMessageList()),
                      if (_isLoading)
                        _buildUploadingMediaBubble(isDark: isDark),
                      _buildInputArea(),
                    ],
                  ),
                  // motifs overlay removed per request
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadingMediaBubble({required bool isDark}) {
    final bool done = _uploadVisualSuccess;
    final int total = (_uploadTotalBytes != null && _uploadTotalBytes! > 0)
        ? _uploadTotalBytes!
        : (done ? 100 : 0);
    final int sent = done ? total : _uploadSentBytes;
    final double progressValue = done
        ? 1.0
        : _uploadVisualProgress.clamp(0.0, 0.98);
    final int displayedSent = total > 0
        ? max(sent, (total * progressValue).round().clamp(0, total))
        : sent;
    final String percent = done
        ? '100%'
        : '${(progressValue * 100).clamp(0, 100).toStringAsFixed(0)}%';
    final String mediaType = _uploadPreviewType ?? 'media';
    final bool isImage = mediaType == 'image';
    final bool isVideo = mediaType == 'video';
    final double mediaWidth = MediaQuery.of(context).size.width * 0.56;
    final double mediaHeight = isVideo
        ? (mediaWidth * 0.62)
        : (mediaWidth * 0.92);
    final bool hasPreviewBytes =
        _uploadPreviewBytes != null && _uploadPreviewBytes!.isNotEmpty;
    bool hasPreviewPath = false;
    if (!kIsWeb && (_uploadPreviewPath?.isNotEmpty == true)) {
      try {
        hasPreviewPath = File(_uploadPreviewPath!).existsSync();
      } catch (_) {
        hasPreviewPath = false;
      }
    }

    Widget preview;
    if (isImage && hasPreviewPath) {
      preview = Image.file(
        File(_uploadPreviewPath!),
        width: mediaWidth,
        height: mediaHeight,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: mediaWidth,
          height: mediaHeight,
          color: Colors.black26,
          alignment: Alignment.center,
          child: const Icon(
            Icons.image_not_supported_rounded,
            color: Colors.white54,
            size: 34,
          ),
        ),
      );
    } else if (isImage && hasPreviewBytes) {
      preview = Image.memory(
        _uploadPreviewBytes!,
        width: mediaWidth,
        height: mediaHeight,
        fit: BoxFit.cover,
      );
    } else {
      final IconData icon = isVideo
          ? Icons.play_circle_fill_rounded
          : (isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded);
      preview = Container(
        width: mediaWidth,
        height: mediaHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0C2340),
              isVideo ? const Color(0xFF1D3557) : const Color(0xFF22324E),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white70, size: 52),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E3F75), Color(0xFF0A2B4F)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: done
                  ? const Color(0xFF2ECC71).withOpacity(0.85)
                  : Colors.white.withOpacity(0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.34 : 0.12),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.file_upload_rounded,
                      color: done ? const Color(0xFF2ECC71) : Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        done
                            ? 'Envoi terminé'
                            : (_uploadLabel ??
                                  (isVideo
                                      ? 'Envoi vidéo'
                                      : (isImage
                                            ? 'Envoi photo'
                                            : 'Envoi média'))),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (percent.isNotEmpty)
                      Text(
                        percent,
                        style: TextStyle(
                          color: done
                              ? const Color(0xFF2ECC71)
                              : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      preview,
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.06),
                                  Colors.black.withOpacity(0.24),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (done)
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.done_rounded,
                            color: Color(0xFF2ECC71),
                            size: 22,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: progressValue),
                    duration: Duration(milliseconds: done ? 280 : 210),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      color: done ? const Color(0xFF2ECC71) : tgAccent,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
                if (total > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_fmtBytes(displayedSent)}/${_fmtBytes(total)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark
        ? Colors.white10
        : Colors.black.withOpacity(0.05);
    final Color text = isDark ? Colors.white : Colors.black87;
    final Color sub = isDark ? Colors.white70 : Colors.black54;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        if (snapshot.hasData && snapshot.data!.docs.isEmpty) {
          return Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.86,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Aucun message ici pour l'instant...",
                    style: TextStyle(
                      color: text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Envoyez un message ou touchez la salutation ci‑dessous.",
                    style: TextStyle(color: sub),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 150,
                    child: GestureDetector(
                      onTap: () async {
                        // send a quick greeting message
                        if (currentUser == null) return;
                        await _saveToFirestore({
                          'type': 'text',
                          'text': 'salut',
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Salut envoyé')),
                        );
                      },
                      child: Lottie.network(
                        'https://assets10.lottiefiles.com/packages/lf20_touohxv0.json',
                        fit: BoxFit.contain,
                        repeat: true,
                        errorBuilder: (context, error, stackTrace) =>
                            Lottie.asset(
                              'assets/lottie/animated_orangutan.json',
                              fit: BoxFit.contain,
                              repeat: true,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        // Marquer messages comme delivered / read quand le destinataire ouvre la conversation
        try {
          _markMessagesAsDeliveredAndRead(snapshot.data!.docs);
        } catch (e) {
          debugPrint('Mark error: $e');
        }

        if (_pendingJumpMessageId != null) {
          final jumpId = _pendingJumpMessageId!;
          final key = _messageKeys[jumpId];
          if (key != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = key.currentContext;
              if (ctx != null) {
                Scrollable.ensureVisible(
                  ctx,
                  duration: const Duration(milliseconds: 350),
                  alignment: 0.3,
                );
                setState(() => _highlightMessageId = jumpId);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted && _highlightMessageId == jumpId) {
                    setState(() => _highlightMessageId = null);
                  }
                });
              }
            });
            _pendingJumpMessageId = null;
          }
        }

        return ListView.builder(
          controller: _listController,
          reverse: true,
          padding: const EdgeInsets.only(bottom: 10, top: 10),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            // `reverse: true` means index 0 renders at the bottom (newest).
            // For Telegram-like bubble grouping we need the neighbors in the visual stack.
            final QueryDocumentSnapshot? newerDoc = index > 0
                ? snapshot.data!.docs[index - 1]
                : null; // below
            final QueryDocumentSnapshot? olderDoc =
                (index + 1) < snapshot.data!.docs.length
                ? snapshot.data!.docs[index + 1]
                : null; // above
            final key = _messageKeys.putIfAbsent(doc.id, () => GlobalKey());
            return KeyedSubtree(
              key: key,
              child: _buildBubble(doc, olderDoc: olderDoc, newerDoc: newerDoc),
            );
          },
        );
      },
    );
  }

  Widget _buildBubble(
    QueryDocumentSnapshot doc, {
    QueryDocumentSnapshot? olderDoc,
    QueryDocumentSnapshot? newerDoc,
  }) {
    final m = doc.data() as Map<String, dynamic>;
    bool isMe = m['senderId'] == currentUser?.uid;
    String type = m['type'] ?? 'text';
    String time = m['timestamp'] != null
        ? DateFormat('HH:mm').format((m['timestamp'] as Timestamp).toDate())
        : "";
    final bool isHighlighted = _highlightMessageId == doc.id;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color pendingColor = isDark ? Colors.white30 : Colors.black38;
    final Color systemTimeColor = isDark ? Colors.white38 : Colors.black38;
    final Color systemBg = isDark
        ? Colors.white10
        : Colors.black.withOpacity(0.06);
    Widget statusIcon = const SizedBox.shrink();
    if (isMe) {
      if ((m['isRead'] ?? false)) {
        statusIcon = Icon(Icons.done_all, size: 14, color: tgAccent);
      } else if ((m['delivered'] ?? false))
        statusIcon = Icon(Icons.done_all, size: 14, color: pendingColor);
      else
        statusIcon = Icon(Icons.done, size: 14, color: pendingColor);
    }

    // Render system messages as centered labels (WhatsApp-style)
    if (type == 'system') {
      final text = (m['text'] ?? '').toString();
      final lower = text.toLowerCase();
      Color labelColor = isDark ? Colors.white70 : Colors.black54;
      Color borderColor = isDark ? Colors.white12 : Colors.black12;
      IconData? icon;
      if (lower.contains('ajout')) {
        labelColor = Colors.greenAccent;
        borderColor = Colors.greenAccent.withOpacity(0.35);
        icon = Icons.person_add_alt_1;
      } else if (lower.contains('quitt') || lower.contains('retir')) {
        labelColor = Colors.orangeAccent;
        borderColor = Colors.orangeAccent.withOpacity(0.35);
        icon = Icons.exit_to_app;
      } else if (lower.contains('supprim') || lower.contains('effac')) {
        labelColor = Colors.redAccent;
        borderColor = Colors.redAccent.withOpacity(0.35);
        icon = Icons.delete_forever;
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: systemBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 14, color: labelColor),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        text,
                        style: TextStyle(color: labelColor, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  time,
                  style: TextStyle(color: systemTimeColor, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final bool isMedia = type == 'image' || type == 'video' || type == 'file';
    final bool isAudio = type == 'audio' || type == 'voice';
    final double meBlend = isMedia ? 0.35 : (isAudio ? 0.28 : 0.25);
    final double otherBlend = isMedia ? 0.18 : (isAudio ? 0.14 : 0.06);
    final bool onDarkBubble = isDark || isMe || (!isDark && !isMe);
    // Requested: my bubble should be a darker color (not bright blue).
    final Color myBase = tgMyBubble;
    // Light mode (requested): other bubble should be black (not white).
    final Color otherBase = isDark ? tgOtherBubble : const Color(0xFF101114);
    final Color borderColor = onDarkBubble
        ? Colors.white.withOpacity(isMe ? 0.18 : 0.12)
        : Colors.black.withOpacity(isMe ? 0.08 : 0.06);
    final Color shadowBase = isDark
        ? Colors.black.withOpacity(0.35)
        : Colors.black.withOpacity(0.08);
    final Color accentShadowBase = (isMe ? tgAccent : otherBase).withOpacity(
      isDark ? 0.18 : 0.12,
    );
    final Color timeColor = onDarkBubble ? Colors.white70 : Colors.black54;
    final Color statusBg = onDarkBubble ? Colors.white10 : Colors.black12;
    final meColors = [
      // Dark blue gradient (WhatsApp/Telegram-ish). Keep it blue, not teal.
      Color.lerp(myBase, const Color(0xFF0F4C8A), isMedia ? 0.22 : 0.18)!,
      Color.lerp(myBase, Colors.black, isMedia ? 0.06 : 0.10)!,
    ];
    final otherColors = isDark
        ? [
            Color.lerp(otherBase, Colors.black, isMedia ? 0.04 : 0.08)!,
            Color.lerp(otherBase, tgAccent, otherBlend)!,
          ]
        : [
            const Color(0xFF16171B),
            isMedia ? const Color(0xFF0E0F12) : const Color(0xFF121318),
          ];

    // --- Telegram-like grouping (dynamic bubble shape) ---
    DateTime? dtFrom(Map<String, dynamic> x) {
      try {
        final ts = x['timestamp'];
        if (ts is Timestamp) return ts.toDate();
      } catch (_) {}
      return null;
    }

    bool sameSender(QueryDocumentSnapshot? d) {
      if (d == null) return false;
      try {
        final md = d.data() as Map<String, dynamic>;
        final String sid = (m['senderId'] ?? '').toString();
        if (sid.isEmpty) return false;
        if ((md['senderId'] ?? '').toString() != sid) return false;
        final String t = (md['type'] ?? 'text').toString();
        if (t == 'system') return false;
        // Group only if close in time (keeps grouping natural like Telegram).
        final a = dtFrom(m);
        final b = dtFrom(md);
        if (a == null || b == null) return true;
        return a.difference(b).abs().inMinutes <= 5;
      } catch (_) {
        return false;
      }
    }

    final bool canGroup = type != 'system';
    final bool sameAbove = canGroup && sameSender(olderDoc);
    final bool sameBelow = canGroup && sameSender(newerDoc);
    final bool showTail =
        canGroup && !sameBelow; // only on last bubble of a run (bottom-most)

    BorderRadius bubbleRadius() {
      // Slightly tighter radii => more compact Telegram/WhatsApp feel.
      const double r = 16;
      const double join = 9;
      const double tail = 5;

      if (isMe) {
        return BorderRadius.only(
          topLeft: const Radius.circular(r),
          topRight: Radius.circular(sameAbove ? join : r),
          bottomLeft: const Radius.circular(r),
          bottomRight: Radius.circular(
            showTail ? tail : (sameBelow ? join : r),
          ),
        );
      }
      return BorderRadius.only(
        topLeft: Radius.circular(sameAbove ? join : r),
        topRight: const Radius.circular(r),
        bottomLeft: Radius.circular(showTail ? tail : (sameBelow ? join : r)),
        bottomRight: const Radius.circular(r),
      );
    }

    final EdgeInsets bubbleMargin = EdgeInsets.only(
      top: sameAbove ? 1 : 4,
      bottom: sameBelow ? 1 : 4,
      left: 10,
      right: 10,
    );

    BoxDecoration bubbleDecoration = BoxDecoration(
      gradient: LinearGradient(
        colors: isMe ? meColors : otherColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: bubbleRadius(),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: shadowBase,
          blurRadius: isDark ? 14 : 8,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: accentShadowBase,
          blurRadius: isDark ? 22 : 14,
          offset: const Offset(0, 10),
        ),
      ],
    );

    // Special styling for alert messages to make them stand out
    if (type == 'alert') {
      bubbleDecoration = BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF7043), Color(0xFFFFB74D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: Colors.redAccent, width: 6)),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      );
    }

    // Create the bubble widget (animation + content)
    Widget bubbleWidget = TweenAnimationBuilder<double>(
      key: ValueKey(doc.id),
      tween: Tween(begin: 18.0, end: 0.0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) {
        final opacity = (1 - (val / 18)).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, val),
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          margin: bubbleMargin,
          constraints: BoxConstraints(
            // Slightly narrower bubbles (less "big blocks")
            maxWidth:
                MediaQuery.of(context).size.width * (isMedia ? 0.78 : 0.72),
          ),
          // highlight when selected
          decoration: _selectedMessageIds.contains(doc.id) || isHighlighted
              ? BoxDecoration(
                  gradient: bubbleDecoration.gradient,
                  borderRadius: bubbleDecoration.borderRadius as BorderRadius?,
                  boxShadow: bubbleDecoration.boxShadow,
                  border: Border.all(
                    color: isHighlighted ? Colors.amber : tgAccent,
                    width: 2,
                  ),
                )
              : bubbleDecoration,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              clipBehavior:
                  Clip.none, // tail can extend outside the bubble bounds
              children: [
                if (showTail)
                  Positioned(
                    bottom: 6,
                    left: isMe ? null : -18,
                    right: isMe ? -18 : null,
                    child: IgnorePointer(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) {
                          final scale = 0.90 + (0.10 * t);
                          final dx = (isMe ? 2.0 : -2.0) * (1 - t);
                          final dy = 1.5 * (1 - t);
                          return Opacity(
                            opacity: (0.10 + 0.90 * t).clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(dx, dy),
                              child: Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: Transform.rotate(
                          angle: isMe ? 0.26 : -0.26,
                          child: CustomPaint(
                            painter: _BubbleTailPainter(
                              color: (isMe ? meColors.first : otherColors.first)
                                  .withOpacity(0.94),
                              pointRight: isMe,
                            ),
                            size: const Size(20, 14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ClipRRect(
                  borderRadius: bubbleDecoration.borderRadius as BorderRadius,
                  child: InkWell(
                    onLongPress: () => _onMessageLongPress(doc, m),
                    onDoubleTap: () => _toggleReaction(doc.reference, '❤️'),
                    onTap: () {
                      if (_selectionMode) {
                        _toggleSelection(doc.id);
                      } else {
                        _onMessageOpen(doc, m);
                      }
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 0.35,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.18),
                                      Colors.transparent,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            isMedia ? 5 : 10,
                            isMedia ? 5 : 8,
                            isMedia ? 5 : 10,
                            8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isGroupChat && !isMe) ...[
                                Builder(
                                  builder: (ctx) {
                                    final bool isDark =
                                        Theme.of(ctx).brightness ==
                                        Brightness.dark;
                                    final Color nameColor = (isDark || isMe)
                                        ? Colors.white70
                                        : Colors.black54;
                                    final senderId = (m['senderId'] ?? '')
                                        .toString();
                                    final fallbackName =
                                        (m['senderName'] ?? 'Utilisateur')
                                            .toString();
                                    return FutureBuilder<Map<String, dynamic>?>(
                                      future: senderId.isNotEmpty
                                          ? _getUserProfile(senderId)
                                          : Future.value(null),
                                      builder: (c, snap) {
                                        final data =
                                            snap.data?['data']
                                                as Map<String, dynamic>? ??
                                            <String, dynamic>{};
                                        final accountType =
                                            snap.data?['collection'] as String?;
                                        final name = UserUtils.formatName(data);
                                        final displayName = name.isNotEmpty
                                            ? name
                                            : fallbackName;
                                        final isCert =
                                            data['isCertified'] == true;
                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                displayName,
                                                style: TextStyle(
                                                  color: nameColor,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isCert ||
                                                (accountType != null &&
                                                    accountType
                                                        .isNotEmpty)) ...[
                                              const SizedBox(width: 6),
                                              AccountBadges(
                                                isCertified: isCert,
                                                accountType: accountType,
                                                fontSize: 9,
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    );
                                  },
                                ),
                                const SizedBox(height: 4),
                              ],
                              _buildReplyInBubble(context, m, isMe: isMe),
                              _buildContent(m, type, isMe: isMe),
                              const SizedBox(height: 4),
                              _buildReactions(m, doc.reference),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Spacer(),
                                  Text(
                                    time,
                                    style: TextStyle(
                                      color: timeColor,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (isMe) const SizedBox(width: 8),
                                  if (isMe)
                                    // Requested: read receipts should not be inside circles.
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      transitionBuilder: (child, anim) =>
                                          ScaleTransition(
                                            scale: anim,
                                            child: child,
                                          ),
                                      child: IconTheme(
                                        key: ValueKey(
                                          '${m['isRead']}_${m['delivered']}',
                                        ),
                                        data: const IconThemeData(size: 14),
                                        child: statusIcon,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Swipe to reply (WhatsApp style): swipe right on any message bubble.
    // We never dismiss; we just set the reply target and let it snap back.
    if (!_selectionMode && type != 'system') {
      bubbleWidget = Dismissible(
        key: ValueKey('reply_${doc.id}'),
        direction: DismissDirection.startToEnd,
        dismissThresholds: const {DismissDirection.startToEnd: 0.22},
        confirmDismiss: (direction) async {
          _setReplyTarget(doc.id, m);
          return false;
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 22),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tgAccent.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: tgAccent.withOpacity(0.35)),
            ),
            child: const Icon(Icons.reply, color: tgAccent, size: 18),
          ),
        ),
        child: bubbleWidget,
      );
    }

    // If the message is from the current user, show the bubble on the right as before
    if (isMe) return bubbleWidget;

    // For incoming messages, show avatar at left (load from user doc)
    final senderId = (m['senderId'] ?? '') as String;
    return FutureBuilder<DocumentSnapshot?>(
      future: senderId.isNotEmpty ? _getUserDoc(senderId) : Future.value(null),
      builder: (ctx, snap) {
        String photo = '';
        String avatarLetterLocal = '';
        if (snap.hasData && snap.data != null && snap.data!.exists) {
          final raw = snap.data!.data();
          final ud = raw is Map
              ? Map<String, dynamic>.from(raw as Map<String, dynamic>)
              : <String, dynamic>{};
          photo =
              (ud['photoUrl'] ?? ud['photo'] ?? ud['avatar'] ?? '') as String;
          final nm = ud['displayName'] ?? ud['name'] ?? '';
          if (nm is String && nm.isNotEmpty)
            avatarLetterLocal = nm[0].toUpperCase();
        } else {
          // fallback to message senderName
          final maybeName = (m['senderName'] ?? '') as String? ?? '';
          if (maybeName.isNotEmpty)
            avatarLetterLocal = maybeName[0].toUpperCase();
        }

        final avatarWidget = GestureDetector(
          onTap: () => _showAvatarActions(
            senderId,
            canEdit: senderId == currentUser?.uid,
            photoUrl: photo,
          ),
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 8, left: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6),
              ],
            ),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.transparent,
              backgroundImage: photo.isNotEmpty
                  ? CachedNetworkImageProvider(photo) as ImageProvider
                  : null,
              child: photo.isEmpty
                  ? (avatarLetterLocal.isNotEmpty
                        ? Text(
                            avatarLetterLocal,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            color: Colors.white70,
                            size: 18,
                          ))
                  : null,
            ),
          ),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            avatarWidget,
            Expanded(child: bubbleWidget),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _getUserProfile(String userId) async {
    final firestore = FirebaseFirestore.instance;
    for (final col in ['classic_users', 'enterprise_users', 'pro_users']) {
      final snap = await firestore.collection(col).doc(userId).get();
      if (snap.exists) {
        final raw = snap.data();
        final data = raw is Map
            ? Map<String, dynamic>.from(raw as Map<String, dynamic>)
            : <String, dynamic>{};
        return {'data': data, 'collection': col};
      }
    }
    return null;
  }

  Future<DocumentSnapshot?> _getUserDoc(String userId) async {
    final firestore = FirebaseFirestore.instance;

    // Essayer dans classic_users
    var snap = await firestore.collection('classic_users').doc(userId).get();
    if (snap.exists) return snap;

    // Essayer dans enterprise_users
    snap = await firestore.collection('enterprise_users').doc(userId).get();
    if (snap.exists) return snap;

    // Essayer dans pro_users
    snap = await firestore.collection('pro_users').doc(userId).get();
    if (snap.exists) return snap;

    // Aucun document trouvé
    return null;
  }

  Future<List<String>> _resolveNames(List<String> ids) async {
    final out = <String>[];
    for (final id in ids) {
      try {
        final snap = await _getUserDoc(id);
        if (snap != null && snap.exists) {
          final raw = snap.data();
          final ud = raw is Map
              ? Map<String, dynamic>.from(raw as Map<String, dynamic>)
              : <String, dynamic>{};
          final name = UserUtils.formatName(ud);
          out.add(name.isNotEmpty ? name : id);
        } else {
          out.add(id);
        }
      } catch (_) {
        out.add(id);
      }
    }
    return out;
  }

  Future<void> _showAvatarActions(
    String uid, {
    required bool canEdit,
    String? photoUrl,
  }) async {
    final photo = photoUrl ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: _modalBg(ctx),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Wrap(
              children: [
                // =======================
                // VOIR LA PHOTO
                // =======================
                if (photo.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.visibility, color: _modalSub(ctx)),
                    title: Text(
                      'Voir la photo',
                      style: TextStyle(color: _modalText(ctx)),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          child: InteractiveViewer(child: Image.network(photo)),
                        ),
                      );
                    },
                  ),

                // =======================
                // CHANGER LA PHOTO
                // =======================
                if (canEdit)
                  ListTile(
                    leading: Icon(Icons.photo_camera, color: _modalSub(ctx)),
                    title: Text(
                      'Changer la photo',
                      style: TextStyle(color: _modalText(ctx)),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);

                      final picker = ImagePicker();
                      final img = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 1000,
                      );
                      if (img == null) return;

                      try {
                        String url = '';

                        // 🔹 SUPABASE / FIREBASE (support web bytes)
                        Uint8List bytes;
                        if (kIsWeb) {
                          bytes = await img.readAsBytes();
                        } else {
                          bytes = await File(img.path).readAsBytes();
                        }

                        if (SupabaseService.isInitialized) {
                          url = await SupabaseService.uploadBytes(
                            bytes,
                            'users/$uid/profile.jpg',
                            'IDENTITY',
                          );
                        }
                        // 🔹 FIREBASE
                        else {
                          final ref = FirebaseStorage.instance.ref().child(
                            'users/$uid/profile.jpg',
                          );

                          if (kIsWeb) {
                            await ref.putData(bytes);
                          } else {
                            await ref.putFile(File(img.path));
                          }
                          url = await ref.getDownloadURL();
                        }

                        // Mise à jour du profil Firebase Auth
                        if (uid == currentUser?.uid) {
                          try {
                            await FirebaseAuth.instance.currentUser
                                ?.updatePhotoURL(url);
                          } catch (_) {}
                        }

                        // Mise à jour Firestore
                        for (var c in [
                          'classic_users',
                          'pro_users',
                          'enterprise_users',
                        ]) {
                          final doc = FirebaseFirestore.instance
                              .collection(c)
                              .doc(uid);
                          final snap = await doc.get();
                          if (snap.exists) {
                            await doc.update({'photoUrl': url, 'photo': url});
                            break;
                          }
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Photo mise à jour')),
                          );
                        }
                      } catch (e) {
                        debugPrint('update avatar err: $e');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Erreur lors de l\'upload'),
                            ),
                          );
                        }
                      }
                    },
                  ),

                // =======================
                // SUPPRIMER LA PHOTO
                // =======================
                if (canEdit && photo.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.delete, color: _modalSub(ctx)),
                    title: Text(
                      'Supprimer la photo',
                      style: TextStyle(color: _modalText(ctx)),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);

                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          backgroundColor: _modalBg(d),
                          title: Text(
                            'Confirmer',
                            style: TextStyle(color: _modalText(d)),
                          ),
                          content: Text(
                            'Supprimer la photo de profil ?',
                            style: TextStyle(color: _modalSub(d)),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: Text(
                                'Annuler',
                                style: TextStyle(color: _modalSub(d)),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: Text(
                                'Supprimer',
                                style: TextStyle(color: _modalText(d)),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (ok != true) return;

                      // 🔹 Suppression STORAGE
                      try {
                        if (SupabaseService.isInitialized) {
                          await Supabase.instance.client.storage
                              .from('IDENTITY')
                              .remove(['users/$uid/profile.jpg']);
                        } else {
                          final ref = FirebaseStorage.instance.ref().child(
                            'users/$uid/profile.jpg',
                          );
                          await ref.delete();
                        }
                      } catch (_) {}

                      // 🔹 Suppression Firestore + Auth
                      try {
                        for (var c in [
                          'classic_users',
                          'pro_users',
                          'enterprise_users',
                        ]) {
                          final doc = FirebaseFirestore.instance
                              .collection(c)
                              .doc(uid);
                          final snap = await doc.get();
                          if (snap.exists) {
                            await doc.update({
                              'photoUrl': FieldValue.delete(),
                              'photo': FieldValue.delete(),
                            });
                            break;
                          }
                        }

                        if (uid == currentUser?.uid) {
                          try {
                            await FirebaseAuth.instance.currentUser
                                ?.updatePhotoURL('');
                          } catch (_) {}
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Photo supprimée')),
                          );
                        }
                      } catch (e) {
                        debugPrint('delete avatar err: $e');
                      }
                    },
                  ),

                // =======================
                // ANNULER
                // =======================
                ListTile(
                  leading: const Icon(Icons.close, color: Colors.white54),
                  title: const Text(
                    'Annuler',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(Map m, String type, {required bool isMe}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // Bubble palette rules:
    // - My bubble is always "dark" (blue) even in light mode.
    // - Other bubble in light mode is also dark (user request: black).
    final bool onDarkBubble = isDark || isMe || (!isDark && !isMe);
    final Color textColor = onDarkBubble ? Colors.white : Colors.black87;
    final Color subText = onDarkBubble ? Colors.white70 : Colors.black54;
    final Color mutedText = onDarkBubble ? Colors.white54 : Colors.black45;
    final Color iconMuted = onDarkBubble ? Colors.white24 : Colors.black26;
    final Color iconColor = onDarkBubble ? Colors.white : Colors.black87;
    final double mediaWidth = MediaQuery.of(context).size.width * 0.66;
    Widget telegramMediaShell({
      required Widget child,
      String? badge,
      EdgeInsetsGeometry? badgePadding,
    }) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: onDarkBubble
                ? Colors.white.withOpacity(0.16)
                : Colors.black.withOpacity(0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.30 : 0.10),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              child,
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.05),
                          Colors.black.withOpacity(0.20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (badge != null)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        badgePadding ??
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.50),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Afficher message supprimé pour l'utilisateur courant
    try {
      if (currentUser != null && m['deletedFor'] is Map) {
        final df = Map<String, dynamic>.from(
          (m['deletedFor'] as Map<String, dynamic>?) ?? {},
        );
        if (df[currentUser!.uid] == true) {
          return Text(
            'Message supprimé',
            style: TextStyle(color: mutedText, fontStyle: FontStyle.italic),
          );
        }
      }
    } catch (_) {}
    switch (type) {
      case 'image':
        return m['url'] != null
            ? FutureBuilder<File?>(
                future: _getCachedMediaFile(
                  m['url'].toString(),
                  expectedBytes: (m['size'] is int) ? (m['size'] as int) : null,
                ),
                builder: (c, snap) {
                  final int? expected = (m['size'] is int)
                      ? (m['size'] as int)
                      : null;
                  final local = snap.data;
                  if (local != null && local.existsSync()) {
                    return GestureDetector(
                      onTap: () => _openMediaViewer(
                        m['url'].toString(),
                        'image',
                        sizeBytes: expected,
                      ),
                      child: telegramMediaShell(
                        badge: 'Photo',
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: mediaWidth * 1.35,
                          ),
                          child: Image.file(
                            local,
                            width: mediaWidth,
                            fit: BoxFit.fitWidth,
                            filterQuality: FilterQuality.high,
                            isAntiAlias: true,
                          ),
                        ),
                      ),
                    );
                  }
                  final url = m['url'].toString();
                  final downloading = _mediaTransfers.isDownloading(url);
                  final int received = _mediaTransfers.receivedBytes(url);
                  final int? total =
                      _mediaTransfers.totalBytes(url) ?? expected;
                  final double? progress = (total != null && total > 0)
                      ? (received / total).clamp(0.0, 1.0)
                      : null;
                  return GestureDetector(
                    onTap: () =>
                        _openMediaViewer(url, 'image', sizeBytes: expected),
                    child: telegramMediaShell(
                      badge: 'Photo',
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CachedNetworkImage(
                            imageUrl: url,
                            imageBuilder: (context, provider) => Image(
                              image: provider,
                              width: mediaWidth,
                              fit: BoxFit.fitWidth,
                              filterQuality: FilterQuality.high,
                              isAntiAlias: true,
                            ),
                            placeholder: (c, s) => SizedBox(
                              width: mediaWidth,
                              height: mediaWidth * 0.72,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Theme.of(c).colorScheme.primary,
                                ),
                              ),
                            ),
                            errorWidget: (c, s, e) => SizedBox(
                              width: mediaWidth,
                              height: mediaWidth * 0.72,
                              child: Icon(
                                Icons.broken_image,
                                color: iconMuted,
                                size: 50,
                              ),
                            ),
                          ),
                          if (!kIsWeb)
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: GestureDetector(
                                onTap: downloading
                                    ? null
                                    : () async {
                                        final ok = await _askDownloadMedia();
                                        if (ok)
                                          await _downloadMediaToCache(
                                            url,
                                            expectedBytes: expected,
                                          );
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: downloading
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: iconColor,
                                                value: progress,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              progress != null
                                                  ? '${(progress * 100).toStringAsFixed(0)}%'
                                                  : _fmtBytes(received),
                                              style: TextStyle(
                                                color: iconColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            if (total != null) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '${_fmtBytes(received)}/${_fmtBytes(total)}',
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ],
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.download,
                                              size: 14,
                                              color: iconColor,
                                            ),
                                            if (expected != null) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                _fmtBytes(expected),
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              )
            : Icon(Icons.image, color: iconMuted, size: 50);

      case 'video':
        return m['url'] != null
            ? FutureBuilder<File?>(
                future: _getCachedMediaFile(
                  m['url'].toString(),
                  expectedBytes: (m['size'] is int) ? (m['size'] as int) : null,
                ),
                builder: (c, snap) {
                  final local = snap.data;
                  final url = m['url'].toString();
                  final downloading = _mediaTransfers.isDownloading(url);
                  final int? expected = (m['size'] is int)
                      ? (m['size'] as int)
                      : null;
                  final int received = _mediaTransfers.receivedBytes(url);
                  final int? total =
                      _mediaTransfers.totalBytes(url) ?? expected;
                  final double? progress = (total != null && total > 0)
                      ? (received / total).clamp(0.0, 1.0)
                      : null;
                  return GestureDetector(
                    onTap: () =>
                        _openMediaViewer(url, 'video', sizeBytes: expected),
                    child: telegramMediaShell(
                      badge: 'Vidéo',
                      child: SizedBox(
                        width: mediaWidth,
                        height: mediaWidth * 0.62,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            DecoratedBox(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF121A2A),
                                    Color(0xFF0B101C),
                                  ],
                                ),
                              ),
                              child: SizedBox(
                                width: mediaWidth,
                                height: mediaWidth * 0.62,
                              ),
                            ),
                            if (local != null && local.existsSync())
                              Icon(
                                Icons.play_circle_fill_rounded,
                                color: subText,
                                size: 54,
                              )
                            else
                              Icon(
                                Icons.play_circle_fill_rounded,
                                color: mutedText,
                                size: 54,
                              ),
                            if (!kIsWeb &&
                                (local == null || !local.existsSync()))
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: GestureDetector(
                                  onTap: downloading
                                      ? null
                                      : () async {
                                          final ok = await _askDownloadMedia();
                                          if (ok)
                                            await _downloadMediaToCache(
                                              url,
                                              expectedBytes: expected,
                                            );
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: downloading
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: iconColor,
                                                      value: progress,
                                                    ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                progress != null
                                                    ? '${(progress * 100).toStringAsFixed(0)}%'
                                                    : _fmtBytes(received),
                                                style: TextStyle(
                                                  color: iconColor,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              if (total != null) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  '${_fmtBytes(received)}/${_fmtBytes(total)}',
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.download,
                                                size: 14,
                                                color: iconColor,
                                              ),
                                              if (expected != null) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  _fmtBytes(expected),
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              )
            : Icon(Icons.videocam, color: iconMuted, size: 50);

      case 'file':
        return FutureBuilder<File?>(
          future: _getCachedMediaFile(
            m['url'] ?? '',
            expectedBytes: (m['size'] is int) ? (m['size'] as int) : null,
          ),
          builder: (c, snap) {
            final url = (m['url'] ?? '').toString();
            final local = snap.data;
            final downloading = _mediaTransfers.isDownloading(url);
            final int? expected = (m['size'] is int)
                ? (m['size'] as int)
                : null;
            final int received = _mediaTransfers.receivedBytes(url);
            final int? total = _mediaTransfers.totalBytes(url) ?? expected;
            final double? progress = (total != null && total > 0)
                ? (received / total).clamp(0.0, 1.0)
                : null;
            return GestureDetector(
              onTap: () async {
                if (url.isEmpty) return;
                if (local != null && local.existsSync()) {
                  // open local file by system
                  final uri = Uri.file(local.path);
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                  return;
                }
                if (!kIsWeb) {
                  final ok = await _askDownloadMedia();
                  if (ok) {
                    await _downloadMediaToCache(url, expectedBytes: expected);
                  }
                } else {
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    try {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (_) {}
                  }
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insert_drive_file, color: iconColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      m['fileName'] ?? "Fichier",
                      style: TextStyle(color: textColor),
                    ),
                  ),
                  if (expected != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      _fmtBytes(expected),
                      style: TextStyle(
                        color: subText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  if (!kIsWeb)
                    downloading
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: iconColor,
                                  value: progress,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                progress != null
                                    ? '${(progress * 100).toStringAsFixed(0)}%'
                                    : _fmtBytes(received),
                                style: TextStyle(
                                  color: subText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (total != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '${_fmtBytes(received)}/${_fmtBytes(total)}',
                                  style: TextStyle(
                                    color: subText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          )
                        : Icon(Icons.download, color: subText, size: 16),
                ],
              ),
            );
          },
        );

      case 'audio':
        return FutureBuilder<File?>(
          future: _getCachedMediaFile(
            m['url'] ?? '',
            expectedBytes: (m['size'] is int) ? (m['size'] as int) : null,
          ),
          builder: (c, snap) {
            final url = (m['url'] ?? '').toString();
            final local = snap.data;
            final downloading = _mediaTransfers.isDownloading(url);
            final int? expected = (m['size'] is int)
                ? (m['size'] as int)
                : null;
            final int received = _mediaTransfers.receivedBytes(url);
            final int? total = _mediaTransfers.totalBytes(url) ?? expected;
            final double? progress = (total != null && total > 0)
                ? (received / total).clamp(0.0, 1.0)
                : null;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: AudioMessagePlayer(
                    url: (local != null && local.existsSync())
                        ? 'file://${local.path}'
                        : url,
                    fileName: m['fileName'] ?? 'Audio',
                    onDarkBubble: onDarkBubble,
                  ),
                ),
                if (!kIsWeb &&
                    url.isNotEmpty &&
                    (local == null || !local.existsSync()))
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: downloading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: iconColor,
                                  value: progress,
                                ),
                              )
                            : Icon(Icons.download, color: subText, size: 18),
                        onPressed: downloading
                            ? null
                            : () async {
                                final ok = await _askDownloadMedia();
                                if (ok)
                                  await _downloadMediaToCache(
                                    url,
                                    expectedBytes: expected,
                                  );
                              },
                      ),
                      if (downloading)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            progress != null
                                ? '${(progress * 100).toStringAsFixed(0)}%'
                                : _fmtBytes(received),
                            style: TextStyle(
                              color: subText,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else if (expected != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            _fmtBytes(expected),
                            style: TextStyle(
                              color: subText,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (downloading && total != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${_fmtBytes(received)}/${_fmtBytes(total)}',
                            style: TextStyle(
                              color: subText,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        );

      case 'contact':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(radius: 18, child: Icon(Icons.person)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m['contactName'] ?? "Contact",
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  m['phone'] ?? "",
                  style: TextStyle(color: subText, fontSize: 12),
                ),
              ],
            ),
          ],
        );

      case 'poll':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "📊 SONDAGE",
              style: TextStyle(
                color: Color(0xFF64B5F6),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              m['question'] ?? "",
              style: TextStyle(color: textColor, fontSize: 16),
            ),
          ],
        );

      case 'location':
        return Column(
          children: [
            const Icon(Icons.map, color: Color(0xFF64B5F6), size: 40),
            Text("Position partagée", style: TextStyle(color: textColor)),
          ],
        );

      case 'alert':
        try {
          final loc = m['location'];
          final hasLoc =
              loc != null && loc['lat'] != null && loc['lng'] != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFFFE082),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      m['text'] ?? 'Je me sens en insécurité.',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasLoc) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final uri = Uri.tryParse(
                      'https://www.google.com/maps?q=${loc['lat']},${loc['lng']}',
                    );
                    if (uri == null) return;
                    try {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (e) {
                      try {
                        await launchUrl(uri);
                      } catch (_) {}
                    }
                  },
                  child: Text(
                    'Voir la position',
                    style: TextStyle(
                      color: subText,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ],
          );
        } catch (_) {
          return Text(
            m['text'] ?? 'Je me sens en insécurité.',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          );
        }

      default:
        return Text(
          m['text'] ?? "",
          style: TextStyle(color: textColor, fontSize: 16),
        );
    }
  }

  void _confirmAndDeleteConversation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _modalBg(c),
        title: Text(
          'Supprimer la conversation',
          style: TextStyle(color: _modalText(c)),
        ),
        content: Text(
          'Voulez-vous supprimer cette conversation pour vous uniquement ?',
          style: TextStyle(color: _modalSub(c)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Annuler', style: TextStyle(color: _modalSub(c))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Supprimer', style: TextStyle(color: tgAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _deleteConversation();
  }

  Future<void> _deleteConversation() async {
    try {
      if (currentUser == null) return;
      final chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId);
      await chatRef.set({
        'hiddenFor.${currentUser!.uid}': true,
        'unreadCounts.${currentUser!.uid}': 0,
      }, SetOptions(merge: true));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversation supprimée pour vous')),
        );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Delete conversation error: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression')),
        );
    }
  }

  Widget _buildInputArea() {
    final double kb = MediaQuery.of(context).viewInsets.bottom;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bar = isDark ? tgBar : Colors.white;
    final Color text = isDark ? Colors.white : Colors.black87;
    final Color hint = isDark ? Colors.white24 : Colors.black45;
    final Color icon = isDark ? Colors.white38 : Colors.black54;
    final Color sub = isDark ? Colors.white70 : Colors.black54;
    final Color muted = isDark ? Colors.white38 : Colors.black45;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .snapshots(),
      builder: (context, snap) {
        bool sendDisabled = false;
        bool isAdmin = false;
        if (snap.hasData && snap.data!.exists) {
          final data = (snap.data!.data() as Map<String, dynamic>?) ?? {};
          final perms = (data['permissions'] is Map)
              ? Map<String, dynamic>.from(data['permissions'])
              : <String, dynamic>{};
          sendDisabled = perms['sendDisabled'] == true;
          final admins =
              (data['admins'] as List?)?.map((e) => e.toString()).toList() ??
              <String>[];
          isAdmin = admins.contains(currentUser?.uid ?? '');
        }
        final blocked = sendDisabled && !isAdmin;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.only(
            bottom: kb + MediaQuery.of(context).padding.bottom + 8,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (blocked)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.orangeAccent.withOpacity(0.35),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.block, color: Colors.orangeAccent, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'L’envoi des messages est désactivé par les admins',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildReplyComposerBar(context),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  color: Colors.transparent,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Opacity(
                          opacity: blocked ? 0.6 : 1.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: bar,
                              borderRadius: BorderRadius.circular(26),
                              border: isDark
                                  ? null
                                  : Border.all(color: Colors.black12),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(
                                    _showEmoji
                                        ? Icons.keyboard
                                        : Icons.sentiment_satisfied_alt,
                                    color: icon,
                                    size: 28,
                                  ),
                                  onPressed: blocked
                                      ? null
                                      : () {
                                          setState(() {
                                            _showEmoji = !_showEmoji;
                                            if (_showEmoji)
                                              FocusScope.of(context).unfocus();
                                          });
                                        },
                                ),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextField(
                                        controller: _msgController,
                                        enabled: !blocked,
                                        onTap: () =>
                                            setState(() => _showEmoji = false),
                                        style: TextStyle(
                                          color: text,
                                          fontSize: 16,
                                        ),
                                        maxLines: 5,
                                        minLines: 1,
                                        decoration: InputDecoration(
                                          hintText: "Message",
                                          hintStyle: TextStyle(color: hint),
                                          border: InputBorder.none,
                                        ),
                                      ),
                                      if (_isRecording)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6.0,
                                            bottom: 2.0,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ValueListenableBuilder<int>(
                                                valueListenable:
                                                    _recordSecondsNotifier,
                                                builder: (context, secs, _) {
                                                  final mm = (secs ~/ 60)
                                                      .toString()
                                                      .padLeft(2, '0');
                                                  final ss = (secs % 60)
                                                      .toString()
                                                      .padLeft(2, '0');
                                                  return Text(
                                                    '$mm:$ss',
                                                    style: TextStyle(
                                                      color: sub,
                                                      fontSize: 12,
                                                    ),
                                                  );
                                                },
                                              ),
                                              const Spacer(),
                                              if (!_recordLocked)
                                                Text(
                                                  'Glisser pour annuler',
                                                  style: TextStyle(
                                                    color: muted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              if (_recordLocked)
                                                Text(
                                                  'Verrouillé',
                                                  style: TextStyle(
                                                    color: muted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.attach_file,
                                    color: icon,
                                    size: 26,
                                  ),
                                  onPressed: blocked
                                      ? null
                                      : _showAttachmentMenu,
                                ),
                                const SizedBox(width: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: blocked
                            ? null
                            : () async {
                                if (_hasText) {
                                  _saveToFirestore({
                                    'text': _msgController.text.trim(),
                                    'type': 'text',
                                  });
                                  _msgController.clear();
                                  setState(() => _hasText = false);
                                  _setTyping(false);
                                  _setUserAction('sent');
                                  return;
                                }
                                if (_recordLocked) {
                                  await _stopRecording();
                                }
                              },
                        onLongPressStart: blocked
                            ? null
                            : (details) async {
                                if (_hasText || _isRecording) return;
                                _recordStartDx = details.globalPosition.dx;
                                _recordStartDy = details.globalPosition.dy;
                                await _startRecording();
                              },
                        onLongPressMoveUpdate: blocked
                            ? null
                            : (details) async {
                                if (!_isRecording || _recordLocked) return;
                                final dx = _recordStartDx != null
                                    ? (details.globalPosition.dx -
                                          _recordStartDx!)
                                    : details.offsetFromOrigin.dx;
                                final dy = _recordStartDy != null
                                    ? (details.globalPosition.dy -
                                          _recordStartDy!)
                                    : details.offsetFromOrigin.dy;
                                if (dx < -80 && !_recordCanceled) {
                                  setState(() => _recordCanceled = true);
                                  await _cancelRecording();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Enregistrement annulé'),
                                      ),
                                    );
                                  }
                                }
                                if (dy < -70 &&
                                    !_recordLocked &&
                                    !_recordCanceled) {
                                  setState(() => _recordLocked = true);
                                }
                              },
                        onLongPressEnd: blocked
                            ? null
                            : (_) async {
                                if (!_isRecording) return;
                                if (_recordCanceled) return;
                                if (_recordLocked) return;
                                _recordStartDx = null;
                                _recordStartDy = null;
                                await _stopRecording();
                              },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedScale(
                              scale: _hasText ? 1.06 : 1.0,
                              duration: const Duration(milliseconds: 160),
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      _isRecording
                                          ? Colors.redAccent
                                          : tgAccent.withOpacity(0.95),
                                      tgAccent,
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.35),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    transitionBuilder: (child, anim) =>
                                        ScaleTransition(
                                          scale: anim,
                                          child: child,
                                        ),
                                    child: _recordLocked
                                        ? const Icon(
                                            Icons.send,
                                            key: ValueKey('send_locked'),
                                            color: Colors.white,
                                            size: 24,
                                          )
                                        : (_isRecording
                                              ? const Icon(
                                                  Icons.mic,
                                                  key: ValueKey('mic_rec'),
                                                  color: Colors.white,
                                                  size: 24,
                                                )
                                              : (_hasText
                                                    ? const Icon(
                                                        Icons.send,
                                                        key: ValueKey('send'),
                                                        color: Colors.white,
                                                        size: 24,
                                                      )
                                                    : const Icon(
                                                        Icons.mic,
                                                        key: ValueKey('mic'),
                                                        color: Colors.white,
                                                        size: 24,
                                                      ))),
                                  ),
                                ),
                              ),
                            ),
                            if (_isRecording && !_recordLocked)
                              Positioned(
                                top: -52,
                                left: 2,
                                child: AnimatedBuilder(
                                  animation: _lockHintCtrl,
                                  builder: (context, child) {
                                    final v = _lockHintCtrl.value;
                                    final pulse =
                                        1.0 +
                                        (0.06 * (0.5 - (v - 0.5).abs()) * 2);
                                    final floatY =
                                        -4.0 + (8.0 * (v <= 0.5 ? v : 1 - v));
                                    return Transform.translate(
                                      offset: Offset(0, floatY),
                                      child: Transform.scale(
                                        scale: pulse,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 160),
                                    opacity: _isRecording ? 1.0 : 0.0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white12,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.lock,
                                            color: Colors.white70,
                                            size: 14,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            '↑ Verrouiller',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showEmoji)
                  SizedBox(
                    height: 250,
                    child: EmojiPicker(
                      onEmojiSelected: (category, emoji) {
                        _msgController.text = _msgController.text + emoji.emoji;
                      },
                      config: Config(
                        emojiViewConfig: EmojiViewConfig(backgroundColor: bar),
                        categoryViewConfig: CategoryViewConfig(
                          backgroundColor: bar,
                          indicatorColor: tgAccent,
                          iconColorSelected: tgAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startRecording() async {
    try {
      var status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission micro requise')),
          );
        return;
      }
      if (mounted) {
        setState(() {
          _recordCanceled = false;
          _recordLocked = false;
        });
      }
      if (!_recorderInitialized) {
        _recorder ??= fs.FlutterSoundRecorder();
        await _recorder!.openRecorder();
        _recorderInitialized = true;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}${Platform.pathSeparator}record_${DateTime.now().millisecondsSinceEpoch}.m4a';
      // signaler action "recording" dans le document chat
      await _setUserAction('recording');
      try {
        await _recorder!.startRecorder(toFile: path, codec: fs.Codec.aacADTS);
      } catch (e) {
        debugPrint(
          'Start record error: $e — attempting fallback codec pcm16WAV',
        );
        try {
          final wavPath = path.replaceAll('.m4a', '.wav');
          await _recorder!.startRecorder(
            toFile: wavPath,
            codec: fs.Codec.pcm16WAV,
          );
        } catch (e2) {
          debugPrint('Fallback record error: $e2');
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Impossible de démarrer l\'enregistrement audio sur cet appareil',
                ),
              ),
            );
          return;
        }
      }
      if (mounted) setState(() => _isRecording = true);
      // start visible recorder timer
      _recordSecondsNotifier.value = 0;
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted)
          _recordSecondsNotifier.value = _recordSecondsNotifier.value + 1;
      });
    } catch (e) {
      debugPrint('Start record error: $e');
    }
  }

  Future<void> _stopRecording({bool send = true}) async {
    try {
      final path = await _recorder?.stopRecorder();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordLocked = false;
          _recordCanceled = false;
        });
      }
      _recordTimer?.cancel();
      _recordTimer = null;
      _recordSecondsNotifier.value = 0;
      await _setUserAction('idle');
      if (path != null && path.isNotEmpty) {
        if (!send) {
          try {
            if (!kIsWeb) File(path).deleteSync();
          } catch (_) {}
          return;
        }
        await _uploadAndSend(
          File(path),
          'audio',
          'chat_media',
          '🎤 Audio',
          extraData: {'fileName': path.split(Platform.pathSeparator).last},
        );
      }
    } catch (e) {
      debugPrint('Stop record error: $e');
    }
  }

  Future<void> _cancelRecording() async {
    try {
      await _stopRecording(send: false);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _lockHintCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _msgListener = () => _onUserTyped(_msgController.text);
    _msgController.addListener(_msgListener);
    // mark presence when opening the chat
    _setPresence(true);
    // clear any pending alerts for this chat (stop header blinking)
    _clearPendingAlertsForChat();
    // clear local notifications for this chat (foreground banners)
    try {
      NotificationService.clearNotificationsForChat(widget.chatId);
    } catch (_) {}
    // lazy init recorder to avoid constructor side-effects during widget construction
    _recorder ??= fs.FlutterSoundRecorder();
    // animated background cycling
    _bgTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted)
        setState(() => _bgIndex = (_bgIndex + 1) % _bgGradients.length);
    });

    _mediaTransferListener = () {
      if (!mounted) return;
      setState(() {});
    };
    _mediaTransfers.revision.addListener(_mediaTransferListener);

    // listen for incoming messages to play sfx and detect delivered-state transitions
    _messagesSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          if (!_messageStreamInitialized) {
            _messageStreamInitialized = true;
            _deliveredMap.clear();
            if (snap.docs.isNotEmpty) _lastMessageId = snap.docs.first.id;
            for (var d in snap.docs) {
              try {
                final data = d.data();
                _deliveredMap[d.id] = (data['delivered'] == true);
              } catch (_) {
                _deliveredMap[d.id] = false;
              }
            }
            return;
          }

          // handle docChanges for precise transitions
          for (var change in snap.docChanges) {
            final id = change.doc.id;
            final data = Map<String, dynamic>.from(change.doc.data() ?? {});
            final bool delivered = data['delivered'] == true;

            // incoming new message: play incoming ringtone if not from current user
            if (change.type == DocumentChangeType.added) {
              if (data['senderId'] != currentUser?.uid) {
                try {
                  _playSfx('sounds/ringtone.mp3');
                } catch (_) {}
              }
            }

            // modified: check delivered transition for messages sent by current user
            if (change.type == DocumentChangeType.modified) {
              final wasDelivered = _deliveredMap[id] == true;
              if (data['senderId'] == currentUser?.uid &&
                  delivered &&
                  !wasDelivered) {
                try {
                  _playTick();
                } catch (_) {}
              }
            }

            // update local map
            _deliveredMap[id] = delivered;
          }

          // keep track of latest id for other logic
          if (snap.docs.isNotEmpty) _lastMessageId = snap.docs.first.id;
        });
  }

  Future<void> _clearPendingAlertsForChat() async {
    if (currentUser == null) return;
    try {
      final col = FirebaseFirestore.instance
          .collection('user_alerts')
          .doc(currentUser!.uid)
          .collection('pending');
      final snap = await col.where('chatId', isEqualTo: widget.chatId).get();
      for (var d in snap.docs) {
        try {
          await d.reference.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('clear pending alerts error: $e');
    }
  }

  void _onUserTyped(String v) {
    final has = v.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    if (currentUser == null) return;
    // set typing true and debounce to false
    if (has) {
      _setTyping(true);
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _setTyping(false);
      });
    } else {
      _typingTimer?.cancel();
      _setTyping(false);
    }
  }

  @override
  void dispose() {
    _msgController.removeListener(_msgListener);
    _msgController.dispose();
    _lockHintCtrl.dispose();
    try {
      _mediaTransfers.revision.removeListener(_mediaTransferListener);
    } catch (_) {}
    if (_recorderInitialized) {
      try {
        _recorder?.closeRecorder();
      } catch (e) {
        debugPrint('Error closing recorder: $e');
      }
    }
    _bgTimer?.cancel();
    _recordTimer?.cancel();
    _stopUploadVisualProgressPulse();
    // clear typing and presence when leaving
    _typingTimer?.cancel();
    _setTyping(false);
    _setUserAction('idle');
    _setPresence(false);
    _messagesSub?.cancel();
    _listController.dispose();
    try {
      _sfxPlayer.dispose();
    } catch (_) {}
    try {
      _recordSecondsNotifier.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _playSfx(String assetPath) async {
    try {
      final path = assetPath.replaceFirst(RegExp(r'^assets\/'), '');
      await _sfxPlayer.play(AssetSource(path));
    } catch (e) {
      debugPrint('SFX play error: $e');
    }
  }

  Future<void> _playTick([String variant = 'metallic']) async {
    try {
      // synthesize a short click/tick WAV in memory (mono, 44100 Hz, 16-bit)
      const int sampleRate = 44100;
      double duration = 0.06; // default 60 ms
      final rnd = Random();

      // parameterize by variant
      double decayRate;
      double noiseLevel;
      List<double> partials;
      switch (variant) {
        case 'bright':
          duration = 0.045;
          decayRate = 90.0;
          noiseLevel = 0.6;
          partials = [3500.0, 5200.0];
          break;
        case 'warm':
          duration = 0.08;
          decayRate = 28.0;
          noiseLevel = 0.25;
          partials = [700.0, 1500.0];
          break;
        case 'metallic':
        default:
          duration = 0.06;
          decayRate = 70.0;
          noiseLevel = 0.8;
          partials = [1400.0, 3000.0, 4300.0];
          break;
      }

      final int samples = max(220, (sampleRate * duration).toInt());
      final Int16List pcm = Int16List(samples);
      for (int i = 0; i < samples; i++) {
        final double t = i / sampleRate;
        final double env = exp(-t * decayRate);

        // noise component
        double noise = (rnd.nextDouble() * 2.0 - 1.0) * noiseLevel;

        // partials (sine components) with inharmonic ratios for metallic feel
        double tone = 0.0;
        for (int p = 0; p < partials.length; p++) {
          final freq = partials[p] * (1.0 + (p * 0.02));
          final double a = 1.0 / (p + 1);
          tone += a * sin(2 * pi * freq * t);
        }

        // subtle click transient envelope shaping
        final double attack = min(1.0, t * (1.0 / 0.001));
        final double v = (noise + 0.6 * tone) * env * attack * 0.7;
        int s = (v * 32767).clamp(-32767, 32767).toInt();
        pcm[i] = s;
      }

      // build WAV header + data
      final int byteRate = sampleRate * 2; // 16-bit mono
      final int dataSize = pcm.lengthInBytes;
      final int fileSize = 36 + dataSize;

      final builder = BytesBuilder();
      builder.add(ascii.encode('RIFF'));
      builder.add(_u32(fileSize));
      builder.add(ascii.encode('WAVE'));
      builder.add(ascii.encode('fmt '));
      builder.add(_u32(16)); // PCM header size
      builder.add(_u16(1)); // PCM format
      builder.add(_u16(1)); // channels
      builder.add(_u32(sampleRate));
      builder.add(_u32(byteRate));
      builder.add(_u16(2)); // block align
      builder.add(_u16(16)); // bits per sample
      builder.add(ascii.encode('data'));
      builder.add(_u32(dataSize));
      // append PCM little-endian
      final pcmBytes = ByteData.view(pcm.buffer);
      builder.add(pcmBytes.buffer.asUint8List());

      final bytes = builder.toBytes();
      await _sfxPlayer.play(BytesSource(Uint8List.fromList(bytes)));
    } catch (e) {
      debugPrint('Tick synth error: $e');
    }
  }

  List<int> _u16(int v) {
    final b = ByteData(2);
    b.setUint16(0, v, Endian.little);
    return b.buffer.asUint8List();
  }

  List<int> _u32(int v) {
    final b = ByteData(4);
    b.setUint32(0, v, Endian.little);
    return b.buffer.asUint8List();
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;
  // `true` => tail points to the right, `false` => to the left.
  final bool pointRight;
  _BubbleTailPainter({required this.color, required this.pointRight});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // Softer, Telegram-like tail (not a sharp triangle).
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h)
      ..quadraticBezierTo(w * 0.18, h * 0.72, w * 0.55, h * 0.62)
      ..quadraticBezierTo(w * 0.82, h * 0.54, w, h * 0.5)
      ..quadraticBezierTo(w * 0.82, h * 0.46, w * 0.55, h * 0.38)
      ..quadraticBezierTo(w * 0.18, h * 0.28, 0, 0)
      ..quadraticBezierTo(w * 0.10, h * 0.5, 0, h)
      ..close();
    if (pointRight) {
      canvas.drawPath(path, paint);
    } else {
      // Mirror horizontally so incoming bubbles point left.
      canvas.save();
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pointRight != pointRight;
}

class AudioMessagePlayer extends StatefulWidget {
  final String url;
  final String fileName;
  final bool onDarkBubble;
  const AudioMessagePlayer({
    super.key,
    required this.url,
    required this.fileName,
    required this.onDarkBubble,
  });

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((d) {
      setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool onDark = isDark || widget.onDarkBubble;
    final Color fg = onDark ? Colors.white : Colors.black87;
    final Color sub = onDark ? Colors.white70 : Colors.black54;
    final Color muted = onDark ? Colors.white24 : Colors.black26;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow, color: fg),
          onPressed: () async {
            if (_playing) {
              await _player.pause();
              setState(() => _playing = false);
            } else {
              try {
                setState(() => _playing = true);
                if (widget.url.startsWith('file://')) {
                  final path = widget.url.replaceFirst('file://', '');
                  await _player.play(DeviceFileSource(path));
                } else {
                  await _player.play(UrlSource(widget.url));
                }
              } catch (e) {
                debugPrint('Audio play error: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Impossible de lire l\'audio')),
                );
                setState(() => _playing = false);
              }
            }
          },
        ),
        SizedBox(
          width: 160,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Slider(
                value: _duration.inMilliseconds > 0
                    ? _position.inMilliseconds / _duration.inMilliseconds
                    : 0.0,
                onChanged: (v) async {
                  if (_duration.inMilliseconds > 0) {
                    final pos = Duration(
                      milliseconds: (v * _duration.inMilliseconds).round(),
                    );
                    await _player.seek(pos);
                  }
                },
                activeColor: fg,
                inactiveColor: muted,
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: TextStyle(color: fg, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fmt(_position),
                    style: TextStyle(color: sub, fontSize: 11),
                  ),
                  const SizedBox(width: 6),
                  Text('/', style: TextStyle(color: muted, fontSize: 11)),
                  const SizedBox(width: 6),
                  Text(
                    _fmt(_duration),
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MediaViewerPage extends StatefulWidget {
  final String url;
  final String type;
  final String chatId;
  final String? messageId;
  final String? senderId;
  final String? localPath;
  const _MediaViewerPage({
    required this.url,
    required this.type,
    required this.chatId,
    this.messageId,
    this.senderId,
    this.localPath,
  });

  @override
  State<_MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<_MediaViewerPage> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') {
      _videoController =
          (widget.localPath != null && widget.localPath!.isNotEmpty)
                ? VideoPlayerController.file(File(widget.localPath!))
                : VideoPlayerController.networkUrl(Uri.parse(widget.url))
            ..initialize().then((_) {
              if (mounted) setState(() {});
              _videoController?.play();
              _videoController?.setLooping(true);
            });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  String _inferMediaExtension() {
    final lower = widget.url.toLowerCase();
    if (widget.type == 'video') {
      if (lower.contains('.mov')) return '.mov';
      if (lower.contains('.webm')) return '.webm';
      return '.mp4';
    }
    if (lower.contains('.png')) return '.png';
    if (lower.contains('.webp')) return '.webp';
    if (lower.contains('.gif')) return '.gif';
    if (lower.contains('.heic') || lower.contains('.heif')) return '.heic';
    return '.jpg';
  }

  Future<File> _ensureLocalMediaFile() async {
    if (widget.localPath != null && widget.localPath!.isNotEmpty) {
      final local = File(widget.localPath!);
      if (await local.exists()) return local;
    }
    final uri = Uri.parse(widget.url);
    final resp = await http.get(uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Téléchargement échoué (${resp.statusCode})');
    }
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = _inferMediaExtension();
    final file = File('${dir.path}${Platform.pathSeparator}lk_media_$ts$ext');
    await file.writeAsBytes(resp.bodyBytes, flush: true);
    return file;
  }

  Future<void> _saveMediaToGallery() async {
    if (kIsWeb) {
      try {
        final uri = Uri.parse(widget.url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          Clipboard.setData(ClipboardData(text: widget.url));
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Lien copié')));
          }
        }
      } catch (_) {}
      return;
    }

    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.hasAccess) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Autorisez l\'accès Photos/Galerie pour enregistrer le média',
            ),
          ),
        );
        await PhotoManager.openSetting();
        return;
      }

      final localFile = await _ensureLocalMediaFile();
      if (widget.type == 'video') {
        await PhotoManager.editor.saveVideo(
          localFile,
          title: 'LK_video_${DateTime.now().millisecondsSinceEpoch}',
        );
      } else {
        await PhotoManager.editor.saveImageWithPath(
          localFile.path,
          title: 'LK_photo_${DateTime.now().millisecondsSinceEpoch}',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Média enregistré dans la galerie')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Impossible d\'enregistrer: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: _saveMediaToGallery,
          ),
          if (widget.messageId != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) async {
                if (value != 'delete') return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: Theme.of(c).brightness == Brightness.dark
                        ? tgBar
                        : Colors.white,
                    title: Text(
                      'Supprimer ce média ?',
                      style: TextStyle(
                        color: Theme.of(c).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: Text(
                          'Annuler',
                          style: TextStyle(
                            color: Theme.of(c).brightness == Brightness.dark
                                ? Colors.white70
                                : Colors.black54,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text(
                          'Supprimer',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;
                  bool canDelete = widget.senderId == user.uid;
                  if (!canDelete) {
                    final chatSnap = await FirebaseFirestore.instance
                        .collection('chats')
                        .doc(widget.chatId)
                        .get();
                    if (chatSnap.exists) {
                      final data = chatSnap.data() ?? {};
                      final admins =
                          (data['admins'] as List?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          <String>[];
                      canDelete = admins.contains(user.uid);
                    }
                  }
                  if (!canDelete) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Permission refusée')),
                      );
                    }
                    return;
                  }
                  await FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId)
                      .collection('messages')
                      .doc(widget.messageId)
                      .delete();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Média supprimé')),
                    );
                  }
                } catch (_) {}
              },
              itemBuilder: (c) => const [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.redAccent, size: 18),
                      SizedBox(width: 8),
                      Text('Supprimer'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Center(
        child: widget.type == 'video'
            ? (_videoController != null && _videoController!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    )
                  : const CircularProgressIndicator(color: Colors.white54))
            : InteractiveViewer(
                child: widget.localPath != null && widget.localPath!.isNotEmpty
                    ? Image.file(
                        File(widget.localPath!),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        isAntiAlias: true,
                      )
                    : CachedNetworkImage(
                        imageUrl: widget.url,
                        imageBuilder: (context, provider) => Image(
                          image: provider,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          isAntiAlias: true,
                        ),
                      ),
              ),
      ),
    );
  }
}

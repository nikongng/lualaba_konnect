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
import 'attachment_menu.dart';
import 'call_webrtc_page.dart';
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
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';


const Color tgBg = Color(0xFF0B1418);
const Color tgAccent = Color(0xFF00CBA9);
const Color tgMyBubble = Color(0xFF5B8DEF);
const Color tgOtherBubble = Color(0xFF2E2F4F);
const Color tgBar = Color(0xFF071011);
class ChatDetailPage extends StatefulWidget {
  final String chatId;
  final String chatName;

  const ChatDetailPage({super.key, required this.chatId, required this.chatName});

  @override
  State<ChatDetailPage> createState() => _ChatState();
}

class _ChatState extends State<ChatDetailPage> {
  final TextEditingController _msgController = TextEditingController();
  final currentUser = FirebaseAuth.instance.currentUser;
  fs.FlutterSoundRecorder? _recorder;
  bool _recorderInitialized = false;
  late final VoidCallback _msgListener;
  bool _showEmoji = false;

  bool _isLoading = false;
  bool _isRecording = false;
  bool _recordLocked = false;
  bool _recordCanceled = false;
  bool _hasText = false;
  Timer? _recordTimer;
  final ValueNotifier<int> _recordSecondsNotifier = ValueNotifier<int>(0);
  Timer? _bgTimer;
  int _bgIndex = 0;
  // sound effects
  final _sfxPlayer = AudioPlayer();
  bool _messageStreamInitialized = false;
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
  final ScrollController _listController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  String? _pendingJumpMessageId;
  String? _highlightMessageId;
  final Set<String> _downloadingMedia = {};
  
  // --- UPLOAD & SAVE HELPERS ---
  Future<void> _uploadAndSend(dynamic fileSource, String type, String folder, String text, {Map<String, dynamic>? extraData}) async {
    setState(() => _isLoading = true);
    try {
      String fileName = '${DateTime.now().millisecondsSinceEpoch}';
      // Support XFile (camera/gallery) on web and mobile: use bytes on web, File on mobile
      Uint8List? bytes;
      File? file;
      if (fileSource is XFile) {
        if (kIsWeb) {
          bytes = await fileSource.readAsBytes();
        } else {
          file = File(fileSource.path);
        }
      } else {
        file = fileSource as File;
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
              debugPrint('Supabase keys not provided at runtime (upload will fallback to Firebase).');
            }
          } catch (ie) {
            debugPrint('Error trying to init SupabaseService on demand: $ie');
          }
        }

        // try Supabase - use provided folder as bucket (chat media -> 'chat_media', stories -> 'stories')
        final supabaseBucket = folder;
        debugPrint('SupabaseService.isInitialized = ${SupabaseService.isInitialized}');
        if (SupabaseService.isInitialized) {
          if (bytes != null) {
            url = await SupabaseService.uploadBytes(bytes, fileName, supabaseBucket);
          } else if (file != null) {
            url = await SupabaseService.uploadFile(file, supabaseBucket);
          } else {
            throw Exception('No file data to upload');
          }
          debugPrint('Uploaded to Supabase: $url');
        } else {
          throw Exception('Supabase not initialized');
        }
      } catch (e) {
        debugPrint('Supabase upload failed or unavailable: $e — falling back to Firebase Storage');
        Reference ref = FirebaseStorage.instance.ref().child(folder).child(fileName);
        if (bytes != null) {
          await ref.putData(bytes);
        } else {
          await ref.putFile(file!);
        }
        url = await ref.getDownloadURL();
      }

      await _saveToFirestore({
        'type': type,
        'url': url,
        'text': text,
        if (extraData != null) ...extraData,
      });
      // play send sfx
      try { await _playSfx('sounds/pop.mp3'); } catch (_) {}
    } catch (e) {
      debugPrint("Erreur upload: $e");
    }
    setState(() => _isLoading = false);
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
      // mark message read and decrement unread count for this user
      try {
        final alreadyRead = (m['isRead'] == true);
        if (!alreadyRead) {
          await doc.reference.update({'isRead': true});
          try {
            await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
              'unreadCounts.${currentUser!.uid}': FieldValue.increment(-1),
            });
          } catch (e) {
            // fallback: try setting to 0 if decrement failed
            try { await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({'unreadCounts.${currentUser!.uid}': 0}); } catch (_) {}
          }
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('onMessageOpen error: $e');
    }
  }

  Future<void> _onMenuSelected(String v) async {
    try {
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      final chatSnap = await chatRef.get();
      if (!chatSnap.exists) return;
      final data = chatSnap.data() ?? {};
      List participants = (data['participants'] is List) ? List.from(data['participants']) : [];
      String otherId = participants.firstWhere((id) => id != FirebaseAuth.instance.currentUser?.uid, orElse: () => "");
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
        final callRef = await FirebaseFirestore.instance.collection('calls').add({
          'caller': FirebaseAuth.instance.currentUser?.uid,
          'callerName': FirebaseAuth.instance.currentUser?.displayName ?? '',
          'callee': otherId,
          'status': 'ringing',
          'type': v == 'video' ? 'video' : 'audio',
          'createdAt': FieldValue.serverTimestamp(),
        });
        Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => CallWebRTCPage(
      callId: callRef.id,
      otherId: otherId,
      isCaller: true,
      name: widget.chatName,
      avatarLetter: widget.chatName.isNotEmpty ? widget.chatName[0].toUpperCase() : '?',
    ),
  ),
);

        return;
      }
    } catch (e) {
      debugPrint('Menu action error: $e');
    }
  }

  // ---- Multi-select helpers ----
  void _toggleSelection(String id) {
    setState(() {
      if (_selectedMessageIds.contains(id)) _selectedMessageIds.remove(id);
      else _selectedMessageIds.add(id);
      _selectionMode = _selectedMessageIds.isNotEmpty;
    });
  }

  void _onMessageLongPress(QueryDocumentSnapshot doc, Map m) {
    // Show options modal: allow saving, selecting, deleting
    showModalBottomSheet(
      context: context,
      backgroundColor: tgBar,
      builder: (c) {
        final isMe = m['senderId'] == currentUser?.uid;
        return SafeArea(
          child: Wrap(children: [
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
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                }).toList(),
              ),
            ),
            ListTile(leading: const Icon(Icons.bookmark, color: Colors.white), title: const Text('Enregistrer', style: TextStyle(color: Colors.white)), onTap: () async { Navigator.pop(c); await _saveMessageForUser(m, chatId: widget.chatId); }),
            ListTile(leading: const Icon(Icons.check_box, color: Colors.white), title: const Text('Sélectionner', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(c); setState(() { _selectionMode = true; _selectedMessageIds.add(doc.id); }); }),
            if (isMe) ListTile(leading: const Icon(Icons.delete, color: Colors.white), title: const Text('Supprimer pour tout le monde', style: TextStyle(color: Colors.white)), onTap: () async { Navigator.pop(c); try { await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(doc.id).delete(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message supprimé'))); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'))); } }),
            ListTile(leading: const Icon(Icons.close, color: Colors.white54), title: const Text('Annuler', style: TextStyle(color: Colors.white54)), onTap: () => Navigator.pop(c)),
          ]),
        );
      }
    );
  }

  Future<void> _toggleReaction(DocumentReference msgRef, String emoji) async {
    if (currentUser == null) return;
    final uid = currentUser!.uid;
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(msgRef);
        if (!snap.exists) return;
        final data = snap.data() as Map<String, dynamic>? ?? {};
        final raw = (data['reactions'] is Map) ? Map<String, dynamic>.from(data['reactions']) : <String, dynamic>{};
        final List<dynamic> list = (raw[emoji] is List) ? List<dynamic>.from(raw[emoji]) : <dynamic>[];
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
    final raw = (m['reactions'] is Map) ? Map<String, dynamic>.from(m['reactions']) : <String, dynamic>{};
    final uid = currentUser?.uid ?? '';
    if (raw.isEmpty && msgRef == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        ...raw.entries.map((e) {
          final emoji = e.key;
          final users = (e.value is List) ? List<dynamic>.from(e.value) : <dynamic>[];
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
              child: Text('$emoji $count', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          );
        }).toList(),
        if (msgRef != null)
          GestureDetector(
            onTap: () => _showReactionPicker(msgRef),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Text('+', style: TextStyle(color: Colors.white, fontSize: 12)),
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
            color: tgBar,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  const Text('Réagir', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              Expanded(
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) async {
                    Navigator.pop(ctx);
                    await _toggleReaction(msgRef, emoji.emoji);
                  },
                  config: Config(
                    emojiViewConfig: EmojiViewConfig(backgroundColor: tgBar),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: tgBar,
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
                color: tgBar,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Réactions $emoji', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
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
                            if (snap.hasData && snap.data != null && snap.data!.exists) {
                              final raw = snap.data!.data();
                              final ud = raw is Map ? Map<String, dynamic>.from(raw as Map<String, dynamic>) : <String, dynamic>{};
                              name = UserUtils.formatName(ud);
                              photo = (ud['photoUrl'] ?? ud['photo'] ?? ud['avatar'] ?? '') as String;
                            }
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.white10,
                                backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null,
                                child: photo.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)) : null,
                              ),
                              title: Text(name.isNotEmpty ? name : 'Utilisateur', style: const TextStyle(color: Colors.white)),
                              subtitle: uid == currentUser?.uid ? const Text('Vous', style: TextStyle(color: Colors.white54)) : null,
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

  Future<File?> _getCachedMediaFile(String url) async {
    if (url.isEmpty) return null;
    final dir = await _mediaCacheDir();
    if (dir == null) return null;
    final ext = _mediaExtFromUrl(url);
    var name = base64UrlEncode(utf8.encode(url));
    if (name.length > 80) name = name.substring(0, 80);
    final file = File('${dir.path}${Platform.pathSeparator}$name$ext');
    if (file.existsSync()) return file;
    return null;
  }

  Future<File?> _downloadMediaToCache(String url) async {
    try {
      if (url.isEmpty) return null;
      if (mounted) setState(() => _downloadingMedia.add(url));
      final dir = await _mediaCacheDir();
      if (dir == null) return null;
      final ext = _mediaExtFromUrl(url);
      var name = base64UrlEncode(utf8.encode(url));
      if (name.length > 80) name = name.substring(0, 80);
      final file = File('${dir.path}${Platform.pathSeparator}$name$ext');
      final res = await http.get(Uri.parse(url));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await file.writeAsBytes(res.bodyBytes, flush: true);
        return file;
      }
    } catch (e) {
      debugPrint('download media err: $e');
    } finally {
      if (mounted) setState(() => _downloadingMedia.remove(url));
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
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Téléchargement autorisé uniquement en Wi‑Fi')));
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
        backgroundColor: tgBar,
        title: const Text('Télécharger ce média ?', style: TextStyle(color: Colors.white)),
        content: const Text('Pour éviter de recharger ce média à chaque ouverture, veux-tu le sauvegarder sur ce téléphone ?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'no'), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(c, 'always'), child: const Text('Oui, toujours')),
          TextButton(onPressed: () => Navigator.pop(c, 'yes'), child: const Text('Oui')),
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
        try { total += e.lengthSync(); } catch (_) {}
      }
    }
    return total;
  }

  Future<void> _clearMediaCache() async {
    final dir = await _mediaCacheDir();
    if (dir == null || !dir.existsSync()) return;
    for (final e in dir.listSync(recursive: true)) {
      if (e is File) {
        try { e.deleteSync(); } catch (_) {}
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
                color: tgBar,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('Cache médias', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.storage, color: Colors.white70),
                    title: const Text('Taille du cache', style: TextStyle(color: Colors.white)),
                    trailing: Text(_fmtBytes(size), style: const TextStyle(color: Colors.white70)),
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
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache vidé')));
                            }
                          },
                          child: const Text('Vider le cache', style: TextStyle(color: Colors.white)),
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
    final Map<String, dynamic> data = msg is Map<String, dynamic> ? msg : Map<String, dynamic>.from(msg as Map);
    final msgId = data['id'] ?? data['messageId'] ?? '';
    try {
      // avoid duplicates
      final existing = await FirebaseFirestore.instance.collection('saved_messages').where('userId', isEqualTo: user.uid).where('messageId', isEqualTo: msgId).limit(1).get();
      if (existing.docs.isNotEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Déjà enregistré')));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message enregistré')));
    } catch (e) {
      debugPrint('Save msg err: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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
        title: Text('Supprimer $cnt message(s) ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
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
      final ref = FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(id);
      batch.delete(ref);
    }
    try {
      await batch.commit();
      if (mounted) {
        _clearSelection();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count message(s) supprimé(s)')));
      }
    } catch (e) {
      debugPrint('Delete selected error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de la suppression')));
    }
  }

  Future<void> _showContactInfo(String otherId) async {
    try {
      final collections = ['classic_users', 'pro_users', 'enterprise_users'];
      DocumentSnapshot? snap;
      for (var c in collections) {
        try {
          final s = await FirebaseFirestore.instance.collection(c).doc(otherId).get();
          if (s.exists) { snap = s; break; }
        } catch (_) {}
      }
      if (snap == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil introuvable')));
        return;
      }

      final raw = snap.data();
      final data = raw is Map ? Map<String, dynamic>.from((raw as Map<String, dynamic>?) ?? {}) : <String, dynamic>{};
      final displayName = UserUtils.formatName(data);
      final photo = (data['photoUrl'] ?? data['avatar'] ?? data['photo'] ?? '') as String;
      final lastSeen = data['lastSeen'] is Timestamp ? (data['lastSeen'] as Timestamp).toDate() : (data['lastSeen'] is int ? DateTime.fromMillisecondsSinceEpoch(data['lastSeen']) : null);
      final phone = (data['phone'] ?? data['telephone'] ?? data['phoneNumber'] ?? '') as String;

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
                  color: tgBar,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: ListView(controller: controller, children: [
                  Row(children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [tgAccent.withOpacity(0.2), tgAccent.withOpacity(0.06)]),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 12, offset: const Offset(0, 6))],
                      ),
                      child: CircleAvatar(
                        radius: 34,
                        backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null,
                        backgroundColor: Colors.transparent,
                        child: photo.isEmpty ? Text(displayName.isNotEmpty ? displayName[0] : '?', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)) : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(lastSeen != null ? 'Dernière connexion • ${DateFormat.yMd().add_Hm().format(lastSeen)}' : 'Dernière connexion • N/A', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        if (phone.isNotEmpty) Padding(padding: const EdgeInsets.only(top:6.0), child: Text('📞 $phone', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                      ]),
                    ),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                  ]),
                  const SizedBox(height: 16),

                  // action grid
                  Wrap(spacing: 10, runSpacing: 12, children: [
                    _actionTile(icon: Icons.message, label: 'Message', color: Colors.blueAccent, onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        final doc = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
                        final isGroup = doc.exists && ((doc.data() as Map<String, dynamic>?)?['isGroup'] == true);
                        if (mounted) {
                          if (isGroup) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatDetailPage(chatId: widget.chatId, chatName: displayName)));
                          } else {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => ChatDetailPage(chatId: widget.chatId, chatName: displayName)));
                          }
                        }
                      } catch (e) {
                        debugPrint('Error opening conversation: $e');
                      }
                    }),
                    _actionTile(icon: Icons.share, label: 'Partager', color: Colors.teal, onTap: () { Clipboard.setData(ClipboardData(text: 'Name: $displayName\nPhone: $phone')); Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact copié'))); }),
                    _actionTile(icon: Icons.phone, label: 'Appeler', color: Colors.green, onTap: () async {
                      Navigator.pop(ctx);
                      // start audio call
                      try {
                        final callRef = await FirebaseFirestore.instance.collection('calls').add({
                          'caller': FirebaseAuth.instance.currentUser?.uid,
                          'callerName': FirebaseAuth.instance.currentUser?.displayName ?? '',
                          'callee': otherId,
                          'status': 'ringing',
                          'type': 'audio',
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                       Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => CallWebRTCPage(
      callId: callRef.id,
      otherId: otherId,
      isCaller: true,
      name: displayName,
      avatarLetter: displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
    ),
  ),
);

                      } catch (e) { debugPrint('Start call error: $e'); }
                    }),
                    _actionTile(icon: Icons.edit, label: 'Modifier', color: Colors.amber, onTap: () { Navigator.pop(ctx); _editContactLocal(otherId); }),
                    _actionTile(icon: Icons.block, label: 'Bloquer', color: Colors.redAccent, onTap: () async { Navigator.pop(ctx); await _confirmBlock(otherId); }),
                    _actionTile(icon: Icons.delete, label: 'Supprimer', color: Colors.red, onTap: () async { Navigator.pop(ctx); await _confirmDeleteContact(otherId); }),
                  ]),
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 8),
                  Text('Plus d’informations', style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Ce panneau permet de bloquer ou supprimer un contact. Les actions modifient uniquement vos données dans l’application.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 18),
                ]),
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
                color: tgBar,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Participants', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
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
                            if (snap.hasData && snap.data != null && snap.data!.exists) {
                              final raw = snap.data!.data();
                              final ud = raw is Map ? Map<String, dynamic>.from(raw as Map<String, dynamic>) : <String, dynamic>{};
                              name = UserUtils.formatName(ud);
                              photo = (ud['photoUrl'] ?? ud['photo'] ?? ud['avatar'] ?? '') as String;
                            }
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.white10,
                                backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null,
                                child: photo.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)) : null,
                              ),
                              title: Text(name.isNotEmpty ? name : 'Utilisateur', style: const TextStyle(color: Colors.white)),
                              subtitle: uid == currentUser?.uid ? const Text('Vous', style: TextStyle(color: Colors.white54)) : null,
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
                color: tgBar,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: ListView(
                controller: controller,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6))),
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
                            final snap = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
                            if (!snap.exists) return;
                            final data = snap.data() ?? {};
                            final admins = (data['admins'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
                            final perms = (data['permissions'] is Map) ? Map<String, dynamic>.from(data['permissions']) : <String, dynamic>{};
                            final canChange = (perms['canChangeInfo'] ?? 'admins').toString();
                            if (canChange == 'admins' && !admins.contains(currentUser?.uid ?? '')) {
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seuls les admins peuvent modifier la photo')));
                              return;
                            }
                            final picker = ImagePicker();
                            final img = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
                            if (img == null) return;
                            final url = await _uploadGroupPhoto(img);
                            if (url != null && url.isNotEmpty) {
                              await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({'groupPhoto': url});
                            }
                          } catch (_) {}
                        },
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [Colors.white10, Colors.white12]),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 12, offset: const Offset(0, 6))],
                          ),
                          child: CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.transparent,
                            backgroundImage: groupPhotoUrl.isNotEmpty ? CachedNetworkImageProvider(groupPhotoUrl) as ImageProvider : null,
                            child: groupPhotoUrl.isEmpty ? const Icon(Icons.group, color: Colors.white70, size: 34) : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(groupName.isNotEmpty ? groupName : 'Groupe', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Text('$total membres', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 6),
                            if (description.isNotEmpty)
                              Text(description, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                            if (description.isNotEmpty) const SizedBox(height: 6),
                            if (creatorId.isNotEmpty)
                              FutureBuilder<DocumentSnapshot?>(
                                future: _getUserDoc(creatorId),
                                builder: (ctx2, snap) {
                                  String creatorName = creatorId;
                                  if (snap.hasData && snap.data != null && snap.data!.exists) {
                                    final raw = snap.data!.data();
                                    final ud = raw is Map ? Map<String, dynamic>.from(raw as Map<String, dynamic>) : <String, dynamic>{};
                                    creatorName = UserUtils.formatName(ud);
                                  }
                                  return Text('Créé par $creatorName', style: const TextStyle(color: Colors.white54, fontSize: 12));
                                },
                              ),
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
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
                          icon: const Icon(Icons.person_add, color: Colors.white),
                          label: const Text('Ajouter', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showGroupSearchSheet();
                          },
                          icon: const Icon(Icons.search, color: Colors.white),
                          label: const Text('Rechercher', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Médias du groupe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _showGroupMediaGridSheet(),
                        child: const Text('Voir tout'),
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
                        if (!mediaSnap.hasData || mediaSnap.data!.docs.isEmpty) {
                          return const Center(child: Text('Aucun média', style: TextStyle(color: Colors.white54)));
                        }
                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: mediaSnap.data!.docs.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (c, i) {
                            final m = mediaSnap.data!.docs[i].data() as Map<String, dynamic>;
                            final url = (m['url'] ?? '') as String? ?? '';
                            final type = (m['type'] ?? 'image').toString();
                            final msgId = mediaSnap.data!.docs[i].id;
                            final senderId = (m['senderId'] ?? '').toString();
                            return Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                              child: url.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () => _openMediaViewer(url, type, messageId: msgId, senderId: senderId),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
                                            if (type == 'video')
                                              Container(
                                                color: Colors.black26,
                                                child: const Icon(Icons.play_circle_filled, color: Colors.white70, size: 32),
                                              ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : const Icon(Icons.image, color: Colors.white54),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Membres', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
                    builder: (ctx3, chatSnap) {
                      final data = chatSnap.hasData && chatSnap.data!.exists ? (chatSnap.data!.data() as Map<String, dynamic>?) ?? {} : <String, dynamic>{};
                      final admins = (data['admins'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
                      final participants = (data['participants'] as List?)?.map((e) => e.toString()).toList() ?? participantIds;
                      final isAdmin = admins.contains(currentUser?.uid ?? '');
                      return Column(
                        children: participants.map((uid) {
                          return FutureBuilder<DocumentSnapshot?>(
                            future: _getUserDoc(uid),
                            builder: (ctx2, snap) {
                              String name = uid;
                              String photo = '';
                              if (snap.hasData && snap.data != null && snap.data!.exists) {
                                final raw = snap.data!.data();
                                final ud = raw is Map ? Map<String, dynamic>.from(raw as Map<String, dynamic>) : <String, dynamic>{};
                                name = UserUtils.formatName(ud);
                                photo = (ud['photoUrl'] ?? ud['photo'] ?? ud['avatar'] ?? '') as String;
                              }
                              final bool isMemberAdmin = admins.contains(uid);
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.white10,
                                  backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null,
                                  child: photo.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)) : null,
                                ),
                                title: Text(name.isNotEmpty ? name : 'Utilisateur', style: const TextStyle(color: Colors.white)),
                                subtitle: Row(
                                  children: [
                                    if (uid == currentUser?.uid) const Text('Vous', style: TextStyle(color: Colors.white54)),
                                    if (uid == currentUser?.uid && isMemberAdmin) const Text(' • ', style: TextStyle(color: Colors.white24)),
                                    if (isMemberAdmin) const Text('Admin', style: TextStyle(color: Colors.white54)),
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
                                          if (!isMemberAdmin) const PopupMenuItem(value: 'promote', child: Text('Promouvoir admin')),
                                          if (isMemberAdmin) const PopupMenuItem(value: 'demote', child: Text('Retirer admin')),
                                          const PopupMenuItem(value: 'remove', child: Text('Retirer du groupe')),
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
                  const Divider(color: Colors.white12),
                  ListTile(
                    leading: const Icon(Icons.exit_to_app, color: Colors.orangeAccent),
                    title: const Text('Quitter le groupe', style: TextStyle(color: Colors.orangeAccent)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: tgBar,
                          title: const Text('Quitter le groupe ?', style: TextStyle(color: Colors.white)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quitter', style: TextStyle(color: Colors.orangeAccent))),
                          ],
                        ),
                      );
                      if (ok == true && mounted) {
                        await _leaveGroup();
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings, color: Colors.white70),
                    title: const Text('Paramètres du groupe', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      () async {
                        try {
                          final snap = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
                          if (!snap.exists) return;
                          final data = snap.data() ?? {};
                          final admins = (data['admins'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
                          final perms = (data['permissions'] is Map) ? Map<String, dynamic>.from(data['permissions']) : <String, dynamic>{};
                          final canChange = (perms['canChangeInfo'] ?? 'admins').toString();
                          if (canChange == 'admins' && !admins.contains(currentUser?.uid ?? '')) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seuls les admins peuvent modifier les infos')));
                            return;
                          }
                          await _showGroupSettingsSheet(currentName: groupName, currentDescription: description);
                        } catch (e) {
                          debugPrint('settings permission err: $e');
                        }
                      }();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.redAccent),
                    title: const Text('Supprimer le groupe', style: TextStyle(color: Colors.redAccent)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: tgBar,
                          title: const Text('Supprimer le groupe ?', style: TextStyle(color: Colors.white)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent))),
                          ],
                        ),
                      );
                      if (ok == true && mounted) {
                        await _deleteGroupAndMessages();
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.cleaning_services, color: Colors.white70),
                    title: const Text('Effacer la discussion', style: TextStyle(color: Colors.white)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          backgroundColor: tgBar,
                          title: const Text('Effacer la discussion ?', style: TextStyle(color: Colors.white)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Effacer')),
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
          final res = await FirebaseFirestore.instance.collection(col).where('email', isEqualTo: q).limit(1).get();
          if (res.docs.isNotEmpty) {
            final d = res.docs.first;
            final data = d.data();
            return {
              'uid': d.id,
              'name': UserUtils.formatName(data),
              'email': data['email'] ?? '',
              'photo': data['photoUrl'] ?? data['photo'] ?? data['avatar'] ?? '',
            };
          }
        } catch (_) {}
      }
      return null;
    }

    Future<Map<String, dynamic>?> byUid() async {
      for (final col in cols) {
        try {
          final snap = await FirebaseFirestore.instance.collection(col).doc(q).get();
          if (snap.exists) {
            final data = snap.data() ?? {};
            return {
              'uid': snap.id,
              'name': UserUtils.formatName(data),
              'email': data['email'] ?? '',
              'photo': data['photoUrl'] ?? data['photo'] ?? data['avatar'] ?? '',
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
      final q = await FirebaseFirestore.instance.collection('contacts').where('owner', isEqualTo: user.uid).limit(300).get();
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
            final allUsers = <Map<String, dynamic>>[...manualUsers, ...contacts];
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
                    color: tgBar,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('Ajouter des membres', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          const Spacer(),
                          IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: searchCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, color: Colors.white54),
                          hintText: 'Rechercher un contact',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white10,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onChanged: (_) => setModal(() {}),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: addCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Ajouter via email ou UID',
                                hintStyle: const TextStyle(color: Colors.white38),
                                filled: true,
                                fillColor: Colors.white10,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, padding: EdgeInsets.zero),
                              onPressed: () async {
                                final query = addCtrl.text.trim();
                                if (query.isEmpty) return;
                                final user = await _lookupUserByEmailOrUid(query);
                                if (user == null) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun utilisateur trouvé')));
                                  return;
                                }
                                final uid = user['uid'] as String;
                                if (existingIds.contains(uid)) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Utilisateur déjà membre')));
                                  return;
                                }
                                final exists = manualUsers.any((u) => u['uid'] == uid) || contacts.any((u) => u['uid'] == uid);
                                if (!exists) {
                                  setModal(() {
                                    manualUsers.insert(0, user);
                                    selectedUids.add(uid);
                                  });
                                }
                                addCtrl.clear();
                              },
                              child: const Icon(Icons.add, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: visible.isEmpty
                            ? const Center(child: Text('Aucun contact', style: TextStyle(color: Colors.white38)))
                            : ListView.builder(
                                controller: controller,
                                itemCount: visible.length,
                                itemBuilder: (c, i) {
                                  final u = visible[i];
                                  final uid = (u['uid'] ?? '').toString();
                                  final name = (u['name'] ?? '').toString();
                                  final email = (u['email'] ?? '').toString();
                                  final photo = (u['photo'] ?? '').toString();
                                  final isMember = uid.isNotEmpty && existingIds.contains(uid);
                                  final selected = uid.isNotEmpty && selectedUids.contains(uid);
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.white10,
                                      backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null,
                                      child: photo.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)) : null,
                                    ),
                                    title: Text(name.isNotEmpty ? name : email, style: const TextStyle(color: Colors.white)),
                                    subtitle: email.isNotEmpty ? Text(email, style: const TextStyle(color: Colors.white60)) : null,
                                    trailing: isMember
                                        ? const Text('Membre', style: TextStyle(color: Colors.white54))
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
                              child: const Text('Annuler', style: TextStyle(color: Colors.white70)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () async {
                              if (selectedUids.isEmpty) return;
                              try {
                                final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
                                final chatSnap = await chatRef.get();
                                if (!chatSnap.exists) return;
                                final data = chatSnap.data() ?? {};
                                final perms = (data['permissions'] is Map) ? Map<String, dynamic>.from(data['permissions']) : <String, dynamic>{};
                                final canAdd = (perms['canAddMembers'] ?? 'all').toString();
                                final admins = (data['admins'] as List?)?.map((e) => e.toString()).toList() ?? [];
                                if (canAdd == 'admins' && !admins.contains(current.uid)) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seuls les admins peuvent ajouter des membres')));
                                  return;
                                }

                                final existing = (data['participants'] as List?)?.map((e) => e.toString()).toSet() ?? <String>{};
                                final toAdd = selectedUids.where((u) => !existing.contains(u)).toList();
                                if (toAdd.isEmpty) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun nouveau membre')));
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

                                final creatorName = current.displayName ?? 'Un utilisateur';
                                final text = '$creatorName a ajouté ${toAdd.length} membre(s)';
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
                                  'lastMessageTime': FieldValue.serverTimestamp(),
                                };
                                for (var p in allParticipants) {
                                  if (p != current.uid) metaUpdates['unreadCounts.$p'] = FieldValue.increment(1);
                                }
                                await chatRef.update(metaUpdates);

                                if (mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Membres ajoutés')));
                                }
                              } catch (e) {
                                debugPrint('add members err: $e');
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de l’ajout')));
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
                    color: tgBar,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('Rechercher', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          const Spacer(),
                          IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: queryCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, color: Colors.white54),
                          hintText: 'Rechercher dans le groupe',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white10,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onChanged: (_) => setModal(() {}),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('Aucun résultat', style: TextStyle(color: Colors.white38)))
                            : ListView.builder(
                                controller: controller,
                                itemCount: filtered.length,
                                itemBuilder: (c, i) {
                                  final m = filtered[i].data() as Map<String, dynamic>;
                                  final text = (m['text'] ?? '').toString();
                                  final sender = (m['senderName'] ?? '') as String? ?? '';
                                  final ts = m['timestamp'] is Timestamp ? (m['timestamp'] as Timestamp).toDate() : null;
                                  final time = ts != null ? DateFormat('dd/MM HH:mm').format(ts) : '';
                                  return ListTile(
                                    title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                                    subtitle: Text([sender, time].where((e) => e.isNotEmpty).join(' • '), style: const TextStyle(color: Colors.white54)),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      setState(() => _pendingJumpMessageId = filtered[i].id);
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
                color: tgBar,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text('Médias du groupe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
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
                          return const Center(child: Text('Aucun média', style: TextStyle(color: Colors.white54)));
                        }
                        return GridView.builder(
                          controller: controller,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6,
                          ),
                          itemCount: snap.data!.docs.length,
                          itemBuilder: (c, i) {
                            final m = snap.data!.docs[i].data() as Map<String, dynamic>;
                            final url = (m['url'] ?? '').toString();
                            final type = (m['type'] ?? 'image').toString();
                            final msgId = snap.data!.docs[i].id;
                            final senderId = (m['senderId'] ?? '').toString();
                            return GestureDetector(
                              onTap: () => _openMediaViewer(url, type, messageId: msgId, senderId: senderId),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
                                    if (type == 'video')
                                      Container(
                                        color: Colors.black26,
                                        child: const Icon(Icons.play_circle_filled, color: Colors.white70, size: 32),
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

  Future<void> _openMediaViewer(String url, String type, {String? messageId, String? senderId}) async {
    if (url.isEmpty) return;
    File? local;
    if (!kIsWeb) {
      local = await _getCachedMediaFile(url);
      if (local == null) {
        final ok = await _askDownloadMedia();
        if (ok) {
          local = await _downloadMediaToCache(url);
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
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      await chatRef.update({
        'admins': makeAdmin ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
      });
    } catch (e) {
      debugPrint('set admin err: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur admin')));
    }
  }

  Future<String> _resolveUserName(String uid) async {
    try {
      final snap = await _getUserDoc(uid);
      if (snap != null && snap.exists) {
        final raw = snap.data();
        final ud = raw is Map ? Map<String, dynamic>.from(raw as Map<String, dynamic>) : <String, dynamic>{};
        final name = UserUtils.formatName(ud);
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return uid;
  }

  Future<void> _removeGroupMember(String uid, {bool isSelf = false}) async {
    try {
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      final chatSnap = await chatRef.get();
      if (!chatSnap.exists) return;
      final data = chatSnap.data() ?? {};
      final participants = (data['participants'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
      if (!participants.contains(uid)) return;
      final admins = (data['admins'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
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
      final text = isSelf ? '$name a quitté le groupe' : '$name a été retiré du groupe';
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
        if (p != currentUser?.uid) metaUpdates['unreadCounts.$p'] = FieldValue.increment(1);
      }
      await chatRef.update(metaUpdates);

      if (isSelf && mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('remove member err: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur suppression membre')));
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
      final snap = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
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
                : (groupPhoto.isNotEmpty ? CachedNetworkImageProvider(groupPhoto) as ImageProvider : null);
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
                    padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: (opening && !closing) ? 1.0 : 0.0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        transform: Matrix4.translationValues(0, (opening && !closing) ? 0 : 24, 0),
                        decoration: BoxDecoration(
                          color: tgBar,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, -6))],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                            gradient: LinearGradient(colors: [tgAccent.withOpacity(0.7), tgAccent.withOpacity(0.2)]),
                          ),
                          child: const Icon(Icons.settings, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Text('Paramètres du groupe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => closeSheet(ctx, setModal)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final picker = ImagePicker();
                            final img = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
                            if (img != null) {
                              setModal(() => newPhoto = img);
                            }
                          },
                          child: CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.white10,
                            backgroundImage: avatar,
                            child: (newPhoto == null && groupPhoto.isEmpty) ? const Icon(Icons.camera_alt, color: Colors.white70) : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: nameCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Nom du groupe',
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: Colors.white10,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descCtrl,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Description',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.block, color: Colors.orangeAccent),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Désactiver l’envoi des messages', style: TextStyle(color: Colors.white)),
                          ),
                          Switch(
                            value: sendDisabled,
                            onChanged: (v) => setModal(() => sendDisabled = v),
                            activeColor: Colors.orangeAccent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Permissions', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Ajouter membres', style: TextStyle(color: Colors.white54, fontSize: 12)),
                              DropdownButton<String>(
                                value: canAddMembers,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(value: 'admins', child: Text('Admins seulement')),
                                  DropdownMenuItem(value: 'all', child: Text('Tous les membres')),
                                ],
                                onChanged: (v) => setModal(() => canAddMembers = v ?? 'all'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Changer infos', style: TextStyle(color: Colors.white54, fontSize: 12)),
                              DropdownButton<String>(
                                value: canChangeInfo,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(value: 'admins', child: Text('Admins seulement')),
                                  DropdownMenuItem(value: 'all', child: Text('Tous les membres')),
                                ],
                                onChanged: (v) => setModal(() => canChangeInfo = v ?? 'admins'),
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
                            child: const Text('Annuler', style: TextStyle(color: Colors.white70)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () async {
                            try {
                              final updates = <String, dynamic>{
                                'groupName': nameCtrl.text.trim(),
                                'description': descCtrl.text.trim(),
                                'permissions': {'canAddMembers': canAddMembers, 'canChangeInfo': canChangeInfo, 'sendDisabled': sendDisabled},
                              };
                              if (newPhoto != null) {
                                final url = await _uploadGroupPhoto(newPhoto!);
                                if (url != null && url.isNotEmpty) updates['groupPhoto'] = url;
                              }
                              await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update(updates);
                              if (mounted) {
                                closeSheet(ctx, setModal);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paramètres mis à jour')));
                              }
                            } catch (e) {
                              debugPrint('group settings err: $e');
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur de mise à jour')));
                            }
                          },
                          child: const Text('Enregistrer'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 6),
                    ListTile(
                      leading: const Icon(Icons.cloud_download, color: Colors.white70),
                      title: const Text('Téléchargement médias', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Gérer le cache et le Wi‑Fi', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        bool wifiOnlyLocal = prefs.getBool('media_download_wifi_only') ?? false;
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          builder: (c) {
                            return StatefulBuilder(
                              builder: (cc, setPref) {
                                return Container(
                                  decoration: BoxDecoration(
                                    color: tgBar,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          const Text('Téléchargements', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          const Spacer(),
                                          IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(c)),
                                        ],
                                      ),
                                      SwitchListTile(
                                        value: wifiOnlyLocal,
                                        onChanged: (v) async {
                                          await prefs.setBool('media_download_wifi_only', v);
                                          setPref(() => wifiOnlyLocal = v);
                                        },
                                        title: const Text('Télécharger uniquement en Wi‑Fi', style: TextStyle(color: Colors.white)),
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.storage, color: Colors.white70),
                                        title: const Text('Gérer le cache', style: TextStyle(color: Colors.white)),
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
    final messagesRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages');
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
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        if (currentUser != null) 'unreadCounts.${currentUser!.uid}': 0,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Discussion effacée')));
    } catch (e) {
      debugPrint('clear chat err: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de l’effacement')));
    }
  }

  Future<void> _deleteGroupAndMessages() async {
    try {
      await _deleteAllMessages();
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).delete();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Groupe supprimé')));
      }
    } catch (e) {
      debugPrint('delete group err: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de la suppression')));
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

  Widget _actionTile({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return SizedBox(
      width: 100,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white10,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 18, backgroundColor: color.withOpacity(0.18), child: Icon(icon, color: color, size: 18)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      ),
    );
  }

  Future<void> _confirmBlock(String otherId) async {
    if (currentUser == null) return;
    final ok = await showDialog<bool>(context: context, builder: (c) {
      return AlertDialog(
        backgroundColor: tgBar,
        title: const Text('Bloquer ce contact?', style: TextStyle(color: Colors.white)),
        content: const Text('Vous ne recevrez plus de messages de ce contact. Vous pouvez débloquer plus tard depuis vos paramètres.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Bloquer', style: TextStyle(color: Colors.red))),
        ],
      );
    });
    if (ok == true) await _blockContact(otherId);
  }

Future<void> _blockContact(String otherId) async {
  if (currentUser == null) return;

  final collections = ['classic_users', 'enterprise_users', 'pro_users'];

  try {
    // Mettre à jour le doc de l'utilisateur courant (me) dans la collection appropriée
    for (final col in collections) {
      final meRef = FirebaseFirestore.instance.collection(col).doc(currentUser!.uid);
      try {
        await meRef.update({'blocked': FieldValue.arrayUnion([otherId])});
        break; // stop dès qu'on a trouvé la collection
      } catch (_) {}
    }

    // Mettre à jour le doc de l'autre utilisateur
    for (final col in collections) {
      final otherRef = FirebaseFirestore.instance.collection(col).doc(otherId);
      try {
        await otherRef.update({'blockedBy': FieldValue.arrayUnion([currentUser!.uid])});
        break;
      } catch (_) {}
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Utilisateur bloqué')));
  } catch (e) {
    debugPrint('Block contact error: $e');
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de bloquer ce contact')));
  }
}


  Future<void> _confirmDeleteContact(String otherId) async {
    if (currentUser == null) return;
    final ok = await showDialog<bool>(context: context, builder: (c) {
      return AlertDialog(
        backgroundColor: tgBar,
        title: const Text('Supprimer le contact?', style: TextStyle(color: Colors.white)),
        content: const Text('Cette action supprimera le contact de votre liste. Les messages historiques restent inchangés.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      );
    });
    if (ok == true) await _deleteContact(otherId);
  }

Future<void> _deleteContact(String otherId) async {
  if (currentUser == null) return;

  final collections = ['classic_users', 'enterprise_users', 'pro_users'];

  try {
    for (final col in collections) {
      final meRef = FirebaseFirestore.instance.collection(col).doc(currentUser!.uid);
      try {
        await meRef.update({'contacts': FieldValue.arrayRemove([otherId])});
        break; // stop dès qu'on trouve la bonne collection
      } catch (_) {}
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact supprimé')));
  } catch (e) {
    debugPrint('Delete contact error: $e');
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de supprimer ce contact')));
  }
}


  Future<void> _saveToFirestore(Map<String, dynamic> data) async {
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').add({
      'senderId': currentUser?.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'delivered': false,
      'deliveredAt': null,
      ...data,
    });

    // Update chat doc: lastMessage, lastMessageTime and increment unreadCounts for other participants
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
    try {
      final chatSnap = await chatRef.get();
      Map<String, dynamic> updateData = {
        'lastMessage': data['text'] ?? "",
        'lastMessageTime': FieldValue.serverTimestamp(),
      };
      if (chatSnap.exists) {
        final chatData = chatSnap.data() ?? {};
        final parts = (chatData['participants'] is List) ? List.from(chatData['participants']) : [];
        if (currentUser != null && parts.isNotEmpty) {
          for (var p in parts) {
            if (p != currentUser!.uid) {
              updateData['unreadCounts.$p'] = FieldValue.increment(1);
            }
          }
        }
      }
      await chatRef.update(updateData);
      // --- Envoi d'une demande de notification au service notifier (client-to-server)
// --- Envoi d'une demande de notification au service notifier (client-to-server)
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final idToken = await user.getIdToken();
          final chatSnap = await chatRef.get();
          final chatData = chatSnap.data() ?? {};
          final parts = (chatData['participants'] is List) ? List.from(chatData['participants']) : [];
          final recipients = parts.where((p) => p != user.uid).toList();

            if (recipients.isNotEmpty) {
            final url = Uri.parse(kNotifierUrl);
            
            // On prépare le Nom et l'Avatar de l'utilisateur actuel
          // Sécurité : si le nom est vide, on met "Un utilisateur"
          final String senderName = (user.displayName != null && user.displayName!.isNotEmpty) 
              ? user.displayName! 
              : 'Un utilisateur';

          // Sécurité : si la photo est vide, on met une icône par défaut
          final String senderPhoto = (user.photoURL != null && user.photoURL!.isNotEmpty) 
              ? user.photoURL! 
              : 'https://cdn-icons-png.flaticon.com/512/149/149071.png';

            await http.post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $idToken',
              },
              body: jsonEncode({
                'recipients': recipients,
                'title': senderName,         // IRA DANS HEADINGS (NOM EN GRAS)
                'body': data['text'] ?? '',  // IRA DANS CONTENTS (LE MESSAGE)
                'senderAvatarUrl': senderPhoto, // IRA DANS LARGE_ICON (L'AVATAR)
                'data': { 
                  'chatId': widget.chatId,
                  'type': 'chat_message'
                }
              }),
            );
          }
        }
      }  catch (e) {
        debugPrint('Notifier call error: $e');
      }
    } catch (e) {
      debugPrint('Erreur update chat meta: $e');
    }
    // play local send sfx
    try { if (currentUser != null) await _playSfx('sounds/pop.mp3'); } catch (_) {}
  }


  Future<void> _markMessagesAsDeliveredAndRead(List<QueryDocumentSnapshot> docs) async {
    if (currentUser == null) return;
    WriteBatch batch = FirebaseFirestore.instance.batch();
    bool shouldClearUnread = false;
    for (var d in docs) {
      var m = d.data() as Map<String, dynamic>;
      try {
        if (m['senderId'] != currentUser!.uid) {
          if (m['delivered'] != true) {
            batch.update(d.reference, {'delivered': true, 'deliveredAt': FieldValue.serverTimestamp()});
          }
          if (m['isRead'] != true) {
            batch.update(d.reference, {'isRead': true});
            shouldClearUnread = true;
          }
        }
      } catch (_) {}
    }
    if (shouldClearUnread) {
      var chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      batch.update(chatRef, {'unreadCounts.${currentUser!.uid}': 0});
    }
    try {
      await batch.commit();
    } catch (e) {
      debugPrint('Erreur maj accusés: $e');
    }
  }

  Future<void> _setTyping(bool value) async {
    if (currentUser == null) return;
    try {
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
        'typing.${currentUser!.uid}': value,
      });
    } catch (e) { debugPrint('Set typing error: $e'); }
  }

  Future<void> _setUserAction(String action) async {
    if (currentUser == null) return;
    try {
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
        'userActions.${currentUser!.uid}': action,
      });
    } catch (e) { debugPrint('Set userAction error: $e'); }
  }

  Future<void> _setPresence(bool present) async {
    if (currentUser == null) return;
    try {
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
        'present.${currentUser!.uid}': present,
      });
    } catch (e) { debugPrint('Set presence error: $e'); }
  }

  // --- DIALOGUE DE SONDAGE RAPIDE ---
  void _showPollDialog() {
    String question = "";
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: tgBar,
        title: const Text("Nouveau sondage", style: TextStyle(color: Colors.white)),
        content: TextField(
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Posez votre question...",
            hintStyle: TextStyle(color: Colors.white24),
          ),
          onChanged: (v) => question = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          TextButton(
            onPressed: () {
              if (question.trim().isNotEmpty) {
                _saveToFirestore({'type': 'poll', 'question': question, 'text': '📊 Sondage: $question'});
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
          if (f != null) _uploadAndSend(XFile(f.path), 'image', 'chat_media', '📸 Photo');
        },
        onCameraTap: () async {
          Navigator.pop(parentContext);
          final XFile? media = await Navigator.push(parentContext, MaterialPageRoute(builder: (c) => const CameraScreen()));
          if (media != null) {
            final result = await Navigator.push(parentContext, MaterialPageRoute(
              builder: (c) => MediaPreviewScreen(mediaFile: media, type: media.path.endsWith('.mp4') ? 'video' : 'image')
            ));
            if (result != null) {
              _uploadAndSend(result['file'], media.path.endsWith('.mp4') ? 'video' : 'image', 'chat_media', result['caption']);
            }
          }
        },
        onGalleryTap: () async {
          Navigator.pop(parentContext);
          final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery);
          if (file != null) _uploadAndSend(file, 'image', 'chat_media', '📸 Photo');
        },
        onFileTap: () async {
          Navigator.pop(parentContext);
          FilePickerResult? res = await FilePicker.platform.pickFiles();
          if (res != null) {
            _uploadAndSend(File(res.files.single.path!), 'file', 'chat_media', '📄 Fichier', extraData: {'fileName': res.files.single.name});
          }
        },
        onLocationTap: () async {
          Navigator.pop(context);
          LocationPermission p = await Geolocator.requestPermission();
          if (p != LocationPermission.denied) {
            Position pos = await Geolocator.getCurrentPosition();
            _saveToFirestore({'type': 'location', 'lat': pos.latitude, 'lng': pos.longitude, 'text': '📍 Position'});
          }
        },
        onMusicTap: () async {
          Navigator.pop(context);
          FilePickerResult? res = await FilePicker.platform.pickFiles(type: FileType.audio);
          if (res != null) {
            _uploadAndSend(File(res.files.single.path!), 'audio', 'chat_media', '🎵 Musique', extraData: {'fileName': res.files.single.name});
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
                'phone': contact.phones.isNotEmpty ? contact.phones.first.number : "Pas de numéro",
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
  Future<Map<String, dynamic>?> getContactFromCollection(String collection) async {
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
        backgroundColor: tgBar,
        title: const Text('Modifier contact', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Nom',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Téléphone',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enregistrer')),
        ],
      );
    },
  );

  if (ok == true) {
    try {
      // Mettre à jour dans la collection où le contact a été trouvé
      final ref = FirebaseFirestore.instance
          .collection(contact != null && collections.contains('classic_users') ? 'classic_users' : 
                      contact != null && collections.contains('enterprise_users') ? 'enterprise_users' : 'pro_users')
          .doc(currentUser!.uid)
          .collection('contacts')
          .doc(otherId);

      await ref.set({
        'displayName': nCtrl.text.trim(),
        'phone': pCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp()
      });

      // Mettre à jour les localNames dans le chat pour affichage instantané
      try {
        final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
        await chatRef.set({
          'localNames': {currentUser!.uid: nCtrl.text.trim()}
        }, SetOptions(merge: true));
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact mis à jour')));
    } catch (e) {
      debugPrint('Edit contact error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de la mise à jour')));
    }
  }
}


  void _showCallOptions() async {
    // resolve other participant id from chat doc
    try {
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      final chatSnap = await chatRef.get();
      if (!chatSnap.exists) return;
      final data = chatSnap.data() ?? {};
      List participants = (data['participants'] is List) ? List.from(data['participants']) : [];
      String otherId = participants.firstWhere((id) => id != FirebaseAuth.instance.currentUser?.uid, orElse: () => "");
      if (otherId == "") return;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return Container(
            decoration: BoxDecoration(color: tgBar, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6))),
              ]),
              const SizedBox(height: 12),
              Text('Options d\'appel', style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _actionTile(icon: Icons.call, label: 'Audio', color: Colors.green, onTap: () { Navigator.pop(ctx); _startCall(otherId, false); }),
                _actionTile(icon: Icons.videocam, label: 'Vidéo', color: Colors.purple, onTap: () { Navigator.pop(ctx); _startCall(otherId, true); }),
                _actionTile(icon: Icons.schedule, label: 'Planifier', color: Colors.orange, onTap: () { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planifier un appel — bientôt'))); }),
              ]),
              const SizedBox(height: 16),
            ]),
          );
        }
      );
    } catch (e) {
      debugPrint('Show call options error: $e');
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
     Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => CallWebRTCPage(
      callId: callRef.id,
      otherId: otherId,
      isCaller: true,
      name: widget.chatName,
      avatarLetter: widget.chatName.isNotEmpty ? widget.chatName[0].toUpperCase() : '?',
    ),
  ),
);

    } catch (e) { debugPrint('Start call error: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: tgBg,
      appBar: AppBar(
        backgroundColor: tgBar,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: _selectionMode ? IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => _clearSelection()) : null,
        title: _selectionMode
            ? Text('${_selectedMessageIds.length} sélectionné(s)', style: const TextStyle(color: Colors.white))
            : StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
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
            if (displayName.isEmpty) displayName = currentUser?.displayName ?? "";
            if (snap.hasData && snap.data!.exists) {
              final rawChat = snap.data!.data();
              var data = rawChat is Map ? Map<String, dynamic>.from((rawChat as Map<String, dynamic>?) ?? {}) : <String, dynamic>{};
              isGroup = data['isGroup'] == true;
              if (isGroup) {
                groupPhoto = (data['groupPhoto'] as String?) ?? '';
                if (data['groupName'] is String && (data['groupName'] as String).trim().isNotEmpty) {
                  displayName = (data['groupName'] as String).trim();
                }
                if (data['description'] is String && (data['description'] as String).trim().isNotEmpty) {
                  groupDescription = (data['description'] as String).trim();
                }
                groupCreatorId = (data['creatorId'] ?? data['createdBy'] ?? data['ownerId'] ?? '') as String? ?? '';
              }
              // prefer explicit chat name from document
              // support local per-user override: data['localNames'] is a map of uid->name
              if (data['localNames'] is Map && currentUser != null) {
                try {
                  final ln = Map<String, dynamic>.from((data['localNames'] as Map<String, dynamic>?) ?? {});
                  if (ln.containsKey(currentUser!.uid) && (ln[currentUser!.uid] as String).trim().isNotEmpty) {
                    displayName = (ln[currentUser!.uid] as String).trim();
                  }
                } catch (_) {}
              }
              if (displayName.isEmpty && data['name'] is String && (data['name'] as String).trim().isNotEmpty) {
                displayName = (data['name'] as String).trim();
              }
              Map typing = (data['typing'] is Map) ? data['typing'] : {};
              Map actions = (data['userActions'] is Map) ? data['userActions'] : {};
              Map present = (data['present'] is Map) ? data['present'] : {};
              List others = (data['participants'] is List) ? List.from(data['participants']) : [];
              if (isGroup) {
                groupParticipants = others.map((e) => e.toString()).toList();
              }
              others.removeWhere((id) => id == currentUser?.uid);
              // priority: actions (recording) > typing > present
              List<String> recording = [];
              List<String> typingUsers = [];
              int presentCount = 0;
              for (var o in others) {
                if (actions[o] == 'recording') {
                  recording.add(o as String);
                } else if (typing[o] == true) typingUsers.add(o as String);
                if (present[o] == true) presentCount++;
              }
              if (!isGroup) {
                if (recording.isNotEmpty) {
                  status = recording.length == 1 ? "enregistrement audio..." : "plusieurs enregistrement(s)...";
                } else if (typingUsers.isNotEmpty) status = typingUsers.length == 1 ? "en train d'écrire..." : "plusieurs en train d'écrire...";
                else if (presentCount > 0) status = presentCount == 1 ? "1 personne présente" : "$presentCount personnes présentes";
              }
            }
            // sanitize accidental greeting strings like "bonjour utilisateur"
            final lower = displayName.toLowerCase();
            if (lower.contains('bonjour') || lower.contains('utilisateur')) {
              displayName = '';
            }

            // try to detect other participant uid from chat doc so we can lookup their user profile
            String otherId = "";
            if (snap.hasData && snap.data!.exists) {
              final rawChat2 = snap.data!.data();
              var data = rawChat2 is Map ? Map<String, dynamic>.from((rawChat2 as Map<String, dynamic>?) ?? {}) : <String, dynamic>{};
              List parts = (data['participants'] is List) ? List.from(data['participants']) : [];
              parts.removeWhere((id) => id == currentUser?.uid);
              if (parts.isNotEmpty) otherId = parts.first as String;
            }

            Widget buildRow(String name, {String? otherId}) {
              String displayNameLocal = name;
              final avatarLetter = displayNameLocal.isNotEmpty ? displayNameLocal[0].toUpperCase() : '?';

              Widget nameAndBadge(bool isCert) {
                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(name.isNotEmpty ? name : 'Utilisateur', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if (isCert) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified, color: Colors.blue, size: 16)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (status.isNotEmpty) Text(status, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.1)),
                    ],
                  ),
                );
              }

              if (otherId != null && otherId.isNotEmpty) {
                return FutureBuilder<DocumentSnapshot?>(
                  future: _getUserDoc(otherId),
                  builder: (ctx, userSnap) {
                    String photo = '';
                    bool isCert = false;
                    if (userSnap.hasData && userSnap.data != null && userSnap.data!.exists) {
                      final rawUd = userSnap.data!.data();
                      final ud = rawUd is Map ? Map<String, dynamic>.from(rawUd as Map<String, dynamic>) : <String, dynamic>{};
                      photo = (ud['photoUrl'] ?? ud['photo'] ?? ud['avatar'] ?? '') as String;
                      if (ud['displayName'] is String && (ud['displayName'] as String).trim().isNotEmpty) {
                        displayNameLocal = (ud['displayName'] as String).trim();
                      } else if (ud['name'] is String && (ud['name'] as String).trim().isNotEmpty) {
                        displayNameLocal = (ud['name'] as String).trim();
                      }
                      isCert = ud['isCertified'] == true;
                    }

                    final avatar = GestureDetector(
                      onTap: () => _showAvatarActions(otherId, canEdit: otherId == currentUser?.uid, photoUrl: photo),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Colors.white10, Colors.white12]),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.transparent,
                          backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null,
                          child: photo.isEmpty ? Text(avatarLetter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : null,
                        ),
                      ),
                    );

                    return Row(
                      children: [
                        avatar,
                        const SizedBox(width: 12),
                        // use resolvedNameTemp for display if available
                        Builder(builder: (_) {
                          return nameAndBadge(isCert);
                        }),
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
                      gradient: LinearGradient(colors: [Colors.white10, Colors.white12]),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: CircleAvatar(radius: 18, backgroundColor: Colors.transparent, child: Text(avatarLetter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(width: 12),
                  nameAndBadge(false),
                ],
              );
            }

            Widget buildGroupRow(String name, String photoUrl, List<String> participants, String creatorId, String description) {
              final ids = participants.where((p) => p != currentUser?.uid).toList();
              final lastTwo = ids.length <= 2 ? ids : ids.sublist(ids.length - 2);
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
                        gradient: LinearGradient(colors: [Colors.white10, Colors.white12]),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.transparent,
                        backgroundImage: photoUrl.isNotEmpty ? CachedNetworkImageProvider(photoUrl) as ImageProvider : null,
                        child: photoUrl.isEmpty ? const Icon(Icons.group, color: Colors.white70) : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name.isNotEmpty ? name : 'Groupe', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          if (lastTwo.isEmpty)
                            const Text('Aucun membre récent', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.1))
                          else
                            FutureBuilder<List<String>>(
                              future: _resolveNames(lastTwo),
                              builder: (ctx, snap) {
                                final names = snap.data ?? lastTwo;
                                final label = names.join(', ');
                                return Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis);
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
              final groupName = displayName.isNotEmpty ? displayName : (widget.chatName.isNotEmpty ? widget.chatName : 'Groupe');
              return buildGroupRow(groupName, groupPhoto, groupParticipants, groupCreatorId, groupDescription);
            }

            // If we have an other participant id, try to resolve displayName from users collection
            final needsLookup = otherId.isNotEmpty && (displayName.isEmpty || displayName.contains('@') || displayName.toLowerCase().contains('utilisateur'));
            if (needsLookup) {
              return FutureBuilder<DocumentSnapshot?>(
                future: _getUserDoc(otherId),
                builder: (ctx, userSnap) {
                  String resolved = displayName;
                  if (userSnap.hasData && userSnap.data != null && userSnap.data!.exists) {
                    final rawUd = userSnap.data!.data();
                    final ud = rawUd is Map ? Map<String, dynamic>.from(rawUd as Map<String, dynamic>) : <String, dynamic>{};
                    if (ud['displayName'] is String && (ud['displayName'] as String).trim().isNotEmpty) {
                      resolved = (ud['displayName'] as String).trim();
                    } else if (ud['name'] is String && (ud['name'] as String).trim().isNotEmpty) {
                      resolved = (ud['name'] as String).trim();
                    }
                  }
                  if (resolved.isEmpty) resolved = currentUser?.displayName ?? 'Utilisateur';
                  return buildRow(resolved, otherId: otherId);
                },
              );
            }

            // default
            if (displayName.isEmpty) displayName = currentUser?.displayName ?? 'Utilisateur';
            return buildRow(displayName, otherId: otherId);
          },
        ),
          actions: [
          _selectionMode ? IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => _confirmDeleteSelected()) : const SizedBox.shrink(),
          !_selectionMode ? IconButton(icon: const Icon(Icons.call, color: Colors.white), onPressed: () => _showCallOptions()) : const SizedBox.shrink(),
          !_selectionMode ? PopupMenuButton<String>(
            onSelected: (v) => _onMenuSelected(v),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'audio', child: Text('Appel audio')),
              const PopupMenuItem(value: 'video', child: Text('Appel vidéo')),
              const PopupMenuItem(value: 'info', child: Text('Info contact')),
              const PopupMenuItem(value: 'delete', child: Text('Supprimer la conversation')),
            ],
          ) : const SizedBox.shrink(),
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
                  colors: _bgGradients[_bgIndex].map((c) => c.withOpacity(0.18)).toList(),
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
                  colors: [tgBg.withOpacity(0.25), const Color(0xFF071011).withOpacity(0.35)],
                ),
              ),
              child: Stack(
                children: [
                  Column(
                children: [
                  Expanded(child: _buildMessageList()),
                  if (_isLoading) const LinearProgressIndicator(color: tgAccent, backgroundColor: tgBar),
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

  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        if (snapshot.hasData && snapshot.data!.docs.isEmpty) {
          return Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.86,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(14)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Aucun message ici pour l'instant...", style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text("Envoyez un message ou touchez la salutation ci‑dessous.", style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 150,
                    child: GestureDetector(
                      onTap: () async {
                        // send a quick greeting message
                        if (currentUser == null) return;
                        await _saveToFirestore({'type': 'text', 'text': 'salut'});
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salut envoyé')));
                      },
                      child: Lottie.network(
                        'https://assets10.lottiefiles.com/packages/lf20_touohxv0.json',
                        fit: BoxFit.contain,
                        repeat: true,
                        errorBuilder: (context, error, stackTrace) => Lottie.asset('assets/lottie/animated_orangutan.json', fit: BoxFit.contain, repeat: true),
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
        } catch (e) { debugPrint('Mark error: $e'); }

        if (_pendingJumpMessageId != null) {
          final jumpId = _pendingJumpMessageId!;
          final key = _messageKeys[jumpId];
          if (key != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = key.currentContext;
              if (ctx != null) {
                Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.3);
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
            final key = _messageKeys.putIfAbsent(doc.id, () => GlobalKey());
            return KeyedSubtree(key: key, child: _buildBubble(doc));
          },
        );
      },
    );
  }

  Widget _buildBubble(QueryDocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    bool isMe = m['senderId'] == currentUser?.uid;
    String type = m['type'] ?? 'text';
    String time = m['timestamp'] != null ? DateFormat('HH:mm').format((m['timestamp'] as Timestamp).toDate()) : "";
    final bool isHighlighted = _highlightMessageId == doc.id;
    Widget statusIcon = const SizedBox.shrink();
    if (isMe) {
      if ((m['isRead'] ?? false)) {
        statusIcon = Icon(Icons.done_all, size: 14, color: tgAccent);
      } else if ((m['delivered'] ?? false)) statusIcon = Icon(Icons.done_all, size: 14, color: Colors.white30);
      else statusIcon = Icon(Icons.done, size: 14, color: Colors.white30);
    }
    
    BoxDecoration bubbleDecoration = BoxDecoration(
      gradient: isMe
          ? LinearGradient(colors: [tgMyBubble, Color.lerp(tgMyBubble, Colors.white, 0.06)!], begin: Alignment.topLeft, end: Alignment.bottomRight)
          : LinearGradient(colors: [tgOtherBubble, Color.lerp(tgOtherBubble, Colors.black, 0.12)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: Radius.circular(isMe ? 16 : 4),
        bottomRight: Radius.circular(isMe ? 4 : 16),
      ),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4)),
      ],
    );

    // Special styling for alert messages to make them stand out
    if (type == 'alert') {
      bubbleDecoration = BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFFFF7043), Color(0xFFFFB74D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: Colors.redAccent, width: 6)),
        boxShadow: [
          BoxShadow(color: Colors.red.withOpacity(0.28), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      );
    }

    // Create the bubble widget (animation + content)
    final bubbleWidget = TweenAnimationBuilder<double>(
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
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          // highlight when selected
          decoration: _selectedMessageIds.contains(doc.id) || isHighlighted
              ? BoxDecoration(
                  gradient: bubbleDecoration.gradient,
                  borderRadius: bubbleDecoration.borderRadius as BorderRadius?,
                  boxShadow: bubbleDecoration.boxShadow,
                  border: Border.all(color: isHighlighted ? Colors.amber : tgAccent, width: 2),
                )
              : bubbleDecoration,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: bubbleDecoration.borderRadius as BorderRadius,
              onLongPress: () => _onMessageLongPress(doc, m),
              onDoubleTap: () => _toggleReaction(doc.reference, '❤️'),
              onTap: () {
                if (_selectionMode) _toggleSelection(doc.id);
                else _onMessageOpen(doc, m);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildContent(m, type),
                  const SizedBox(height: 6),
                  _buildReactions(m, doc.reference),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Spacer(),
                      Text(
                        time,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      if (isMe) const SizedBox(width: 8),
                      if (isMe)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            shape: BoxShape.circle,
                          ),
                          child: statusIcon,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // If the message is from the current user, show the bubble on the right as before
    if (isMe) return bubbleWidget;

    // For incoming messages, show avatar at left (load from user doc)
    final senderId = (m['senderId'] ?? '') as String;
    return FutureBuilder<DocumentSnapshot?>(
      future: senderId.isNotEmpty ? _getUserDoc(senderId) : Future.value(null),
      builder: (ctx, snap) {
        String photo = '';
        String avatarLetterLocal = '?';
        if (snap.hasData && snap.data != null && snap.data!.exists) {
          final raw = snap.data!.data();
          final ud = raw is Map ? Map<String, dynamic>.from(raw as Map<String, dynamic>) : <String, dynamic>{};
          photo = (ud['photoUrl'] ?? ud['photo'] ?? ud['avatar'] ?? '') as String;
          final nm = ud['displayName'] ?? ud['name'] ?? '';
          if (nm is String && nm.isNotEmpty) avatarLetterLocal = nm[0].toUpperCase();
        } else {
          // fallback to message senderName or id
          final maybeName = (m['senderName'] ?? '') as String? ?? '';
          if (maybeName.isNotEmpty) avatarLetterLocal = maybeName[0].toUpperCase();
        }

        final avatarWidget = GestureDetector(
          onTap: () => _showAvatarActions(senderId, canEdit: senderId == currentUser?.uid, photoUrl: photo),
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 8, left: 6),
            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6)]),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.transparent,
              backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null,
              child: photo.isEmpty ? Text(avatarLetterLocal, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : null,
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
        final ud = raw is Map ? Map<String, dynamic>.from(raw as Map<String, dynamic>) : <String, dynamic>{};
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
            color: tgBar,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Wrap(
            children: [
              // =======================
              // VOIR LA PHOTO
              // =======================
              if (photo.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.visibility, color: Colors.white70),
                  title: const Text(
                    'Voir la photo',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        child: InteractiveViewer(
                          child: Image.network(photo),
                        ),
                      ),
                    );
                  },
                ),

              // =======================
              // CHANGER LA PHOTO
              // =======================
              if (canEdit)
                ListTile(
                  leading:
                      const Icon(Icons.photo_camera, color: Colors.white70),
                  title: const Text(
                    'Changer la photo',
                    style: TextStyle(color: Colors.white),
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
                        final ref = FirebaseStorage.instance
                            .ref()
                            .child('users/$uid/profile.jpg');

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
                        'enterprise_users'
                      ]) {
                        final doc =
                            FirebaseFirestore.instance.collection(c).doc(uid);
                        final snap = await doc.get();
                        if (snap.exists) {
                          await doc.update({
                            'photoUrl': url,
                            'photo': url,
                          });
                          break;
                        }
                      }

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Photo mise à jour'),
                          ),
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
                  leading: const Icon(Icons.delete, color: Colors.white70),
                  title: const Text(
                    'Supprimer la photo',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);

                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Confirmer'),
                        content: const Text(
                          'Supprimer la photo de profil ?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(d, false),
                            child: const Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(d, true),
                            child: const Text('Supprimer'),
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
                        final ref = FirebaseStorage.instance
                            .ref()
                            .child('users/$uid/profile.jpg');
                        await ref.delete();
                      }
                    } catch (_) {}

                    // 🔹 Suppression Firestore + Auth
                    try {
                      for (var c in [
                        'classic_users',
                        'pro_users',
                        'enterprise_users'
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
                          const SnackBar(
                            content: Text('Photo supprimée'),
                          ),
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


  

  Widget _buildContent(Map m, String type) {
    // Afficher message supprimé pour l'utilisateur courant
    try {
      if (currentUser != null && m['deletedFor'] is Map) {
        final df = Map<String, dynamic>.from((m['deletedFor'] as Map<String, dynamic>?) ?? {});
        if (df[currentUser!.uid] == true) {
          return const Text('Message supprimé', style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic));
        }
      }
    } catch (_) {}
    switch (type) {
      case 'image':
        return m['url'] != null
            ? FutureBuilder<File?>(
                future: _getCachedMediaFile(m['url'].toString()),
                builder: (c, snap) {
                  final local = snap.data;
                  if (local != null && local.existsSync()) {
                    return GestureDetector(
                      onTap: () => _openMediaViewer(m['url'].toString(), 'image'),
                      child: Image.file(local, width: 220, fit: BoxFit.contain),
                    );
                  }
                  final url = m['url'].toString();
                  final downloading = _downloadingMedia.contains(url);
                  return GestureDetector(
                    onTap: () => _openMediaViewer(url, 'image'),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CachedNetworkImage(
                          imageUrl: url,
                          width: 220,
                          fit: BoxFit.contain,
                          placeholder: (c, s) => Center(child: CircularProgressIndicator(color: Theme.of(c).colorScheme.primary)),
                          errorWidget: (c, s, e) => const Icon(Icons.broken_image, color: Colors.white24, size: 50),
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                            child: downloading
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.download, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
            : const Icon(Icons.image, color: Colors.white24, size: 50);

      case 'video':
        return m['url'] != null
            ? FutureBuilder<File?>(
                future: _getCachedMediaFile(m['url'].toString()),
                builder: (c, snap) {
                  final local = snap.data;
                  final url = m['url'].toString();
                  final downloading = _downloadingMedia.contains(url);
                  return GestureDetector(
                    onTap: () => _openMediaViewer(url, 'video'),
                    child: Container(
                      width: 220,
                      height: 140,
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (local != null && local.existsSync())
                            const Icon(Icons.play_circle_fill, color: Colors.white70, size: 48)
                          else
                            const Icon(Icons.play_circle_fill, color: Colors.white54, size: 48),
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                              child: downloading
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.download, size: 14, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              )
            : const Icon(Icons.videocam, color: Colors.white24, size: 50);

      case 'file':
        return FutureBuilder<File?>(
          future: _getCachedMediaFile(m['url'] ?? ''),
          builder: (c, snap) {
            final url = (m['url'] ?? '').toString();
            final local = snap.data;
            final downloading = _downloadingMedia.contains(url);
            return GestureDetector(
              onTap: () async {
                if (url.isEmpty) return;
                if (local != null && local.existsSync()) {
                  // open local file by system
                  final uri = Uri.file(local.path);
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                  return;
                }
                final ok = await _askDownloadMedia();
                if (ok) {
                  await _downloadMediaToCache(url);
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file, color: Colors.white),
                  const SizedBox(width: 8),
                  Flexible(child: Text(m['fileName'] ?? "Fichier", style: const TextStyle(color: Colors.white))),
                  const SizedBox(width: 8),
                  downloading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download, color: Colors.white70, size: 16),
                ],
              ),
            );
          },
        );

      case 'audio':
        return FutureBuilder<File?>(
          future: _getCachedMediaFile(m['url'] ?? ''),
          builder: (c, snap) {
            final url = (m['url'] ?? '').toString();
            final local = snap.data;
            final downloading = _downloadingMedia.contains(url);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: AudioMessagePlayer(
                    url: (local != null && local.existsSync()) ? 'file://${local.path}' : url,
                    fileName: m['fileName'] ?? 'Audio',
                  ),
                ),
                if (url.isNotEmpty && (local == null || !local.existsSync()))
                  IconButton(
                    icon: downloading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download, color: Colors.white70, size: 18),
                    onPressed: downloading
                        ? null
                        : () async {
                            final ok = await _askDownloadMedia();
                            if (ok) await _downloadMediaToCache(url);
                          },
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
                Text(m['contactName'] ?? "Contact", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(m['phone'] ?? "", style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ],
        );

      case 'poll':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("📊 SONDAGE", style: TextStyle(color: Color(0xFF64B5F6), fontSize: 10, fontWeight: FontWeight.bold)),
            Text(m['question'] ?? "", style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        );

      case 'location':
        return const Column(
          children: [
            Icon(Icons.map, color: Color(0xFF64B5F6), size: 40),
            Text("Position partagée", style: TextStyle(color: Colors.white)),
          ],
        );

      case 'alert':
        try {
          final loc = m['location'];
          final hasLoc = loc != null && loc['lat'] != null && loc['lng'] != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFE082), size: 28),
                const SizedBox(width: 10),
                Expanded(child: Text(m['text'] ?? 'Je me sens en insécurité.', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
              ]),
              if (hasLoc) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final uri = Uri.tryParse('https://www.google.com/maps?q=${loc['lat']},${loc['lng']}');
                    if (uri == null) return;
                    try {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } catch (e) {
                      try { await launchUrl(uri); } catch (_) {}
                    }
                  },
                  child: Text('Voir la position', style: TextStyle(color: Colors.white70, decoration: TextDecoration.underline)),
                ),
              ],
            ],
          );
        } catch (_) {
          return Text(m['text'] ?? 'Je me sens en insécurité.', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800));
        }

      default:
        return Text(m['text'] ?? "", style: const TextStyle(color: Colors.white, fontSize: 16));
    }
  }

  void _confirmAndDeleteConversation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: tgBar,
        title: const Text('Supprimer la conversation', style: TextStyle(color: Colors.white)),
        content: const Text('Voulez-vous vraiment supprimer cette conversation pour tout le monde ?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer', style: TextStyle(color: tgAccent))),
        ],
      ),
    );
    if (ok != true) return;
    await _deleteConversation();
  }

  Future<void> _deleteConversation() async {
    try {
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      final msgsCol = chatRef.collection('messages');
      final snap = await msgsCol.get();
      WriteBatch batch = FirebaseFirestore.instance.batch();
      int count = 0;
      for (var d in snap.docs) {
        batch.delete(d.reference);
        count++;
        if (count % 400 == 0) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
        }
      }
      await batch.commit();
      // delete chat doc
      await chatRef.delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conversation supprimée')));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Delete conversation error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de la suppression')));
    }
  }

  Widget _buildInputArea() {
    final double kb = MediaQuery.of(context).viewInsets.bottom;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
      builder: (context, snap) {
        bool sendDisabled = false;
        bool isAdmin = false;
        if (snap.hasData && snap.data!.exists) {
          final data = (snap.data!.data() as Map<String, dynamic>?) ?? {};
          final perms = (data['permissions'] is Map) ? Map<String, dynamic>.from(data['permissions']) : <String, dynamic>{};
          sendDisabled = perms['sendDisabled'] == true;
          final admins = (data['admins'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
          isAdmin = admins.contains(currentUser?.uid ?? '');
        }
        final blocked = sendDisabled && !isAdmin;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.only(bottom: kb + MediaQuery.of(context).padding.bottom + 8),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (blocked)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orangeAccent.withOpacity(0.35)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.block, color: Colors.orangeAccent, size: 16),
                        SizedBox(width: 8),
                        Expanded(child: Text('L’envoi des messages est désactivé par les admins', style: TextStyle(color: Colors.orangeAccent, fontSize: 12))),
                      ],
                    ),
                  ),
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
                            decoration: BoxDecoration(color: tgBar, borderRadius: BorderRadius.circular(26)),
                            child: Row(
                              children: [
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(
                                    _showEmoji ? Icons.keyboard : Icons.sentiment_satisfied_alt,
                                    color: Colors.white38,
                                    size: 28,
                                  ),
                                  onPressed: blocked
                                      ? null
                                      : () {
                                          setState(() {
                                            _showEmoji = !_showEmoji;
                                            if (_showEmoji) FocusScope.of(context).unfocus();
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
                                        onTap: () => setState(() => _showEmoji = false),
                                        style: const TextStyle(color: Colors.white, fontSize: 16),
                                        maxLines: 5,
                                        minLines: 1,
                                        decoration: const InputDecoration(
                                          hintText: "Message",
                                          hintStyle: TextStyle(color: Colors.white24),
                                          border: InputBorder.none,
                                        ),
                                      ),
                                      if (_isRecording)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
                                          child: Row(
                                            children: [
                                              Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${(_recordSecondsNotifier.value ~/ 60).toString().padLeft(2, '0')}:${(_recordSecondsNotifier.value % 60).toString().padLeft(2, '0')}',
                                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                                              ),
                                              const Spacer(),
                                              if (!_recordLocked)
                                                const Text('Glisser pour annuler', style: TextStyle(color: Colors.white38, fontSize: 11)),
                                              if (_recordLocked)
                                                const Text('Verrouillé', style: TextStyle(color: Colors.white38, fontSize: 11)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(icon: const Icon(Icons.attach_file, color: Colors.white38, size: 26), onPressed: blocked ? null : _showAttachmentMenu),
                                const SizedBox(width: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: blocked
                            ? null
                            : () async {
                                if (_hasText) {
                                  _saveToFirestore({'text': _msgController.text.trim(), 'type': 'text'});
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
                            : (_) async {
                                if (_hasText || _isRecording) return;
                                await _startRecording();
                              },
                        onLongPressMoveUpdate: blocked
                            ? null
                            : (details) async {
                                if (!_isRecording || _recordLocked) return;
                                if (details.offsetFromOrigin.dx < -80 && !_recordCanceled) {
                                  setState(() => _recordCanceled = true);
                                  await _cancelRecording();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enregistrement annulé')));
                                  }
                                }
                                if (details.offsetFromOrigin.dy < -80 && !_recordLocked && !_recordCanceled) {
                                  setState(() => _recordLocked = true);
                                }
                              },
                        onLongPressEnd: blocked
                            ? null
                            : (_) async {
                                if (!_isRecording) return;
                                if (_recordCanceled) return;
                                if (_recordLocked) return;
                                await _stopRecording();
                              },
                        child: AnimatedScale(
                          scale: _hasText ? 1.06 : 1.0,
                          duration: const Duration(milliseconds: 160),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_isRecording ? Colors.redAccent : tgAccent.withOpacity(0.95), tgAccent]),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 4))],
                            ),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                                child: _recordLocked
                                    ? const Icon(Icons.send, key: ValueKey('send_locked'), color: Colors.white, size: 24)
                                    : (_isRecording
                                        ? const Icon(Icons.mic, key: ValueKey('mic_rec'), color: Colors.white, size: 24)
                                        : (_hasText ? const Icon(Icons.send, key: ValueKey('send'), color: Colors.white, size: 24) : const Icon(Icons.mic, key: ValueKey('mic'), color: Colors.white, size: 24))),
                              ),
                            ),
                          ),
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
                        emojiViewConfig: EmojiViewConfig(
                          backgroundColor: tgBar,
                        ),
                        categoryViewConfig: CategoryViewConfig(
                          backgroundColor: tgBar,
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission micro requise')));
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
      final path = '${dir.path}${Platform.pathSeparator}record_${DateTime.now().millisecondsSinceEpoch}.m4a';
      // signaler action "recording" dans le document chat
      await _setUserAction('recording');
        try {
        await _recorder!.startRecorder(toFile: path, codec: fs.Codec.aacADTS);
      } catch (e) {
        debugPrint('Start record error: $e — attempting fallback codec pcm16WAV');
        try {
          final wavPath = path.replaceAll('.m4a', '.wav');
          await _recorder!.startRecorder(toFile: wavPath, codec: fs.Codec.pcm16WAV);
        } catch (e2) {
          debugPrint('Fallback record error: $e2');
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de démarrer l\'enregistrement audio sur cet appareil')));
          return;
        }
      }
      if (mounted) setState(() => _isRecording = true);
      // start visible recorder timer
      _recordSecondsNotifier.value = 0;
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) _recordSecondsNotifier.value = _recordSecondsNotifier.value + 1;
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
          try { if (!kIsWeb) File(path).deleteSync(); } catch (_) {}
          return;
        }
        await _uploadAndSend(File(path), 'audio', 'chat_media', '🎤 Audio', extraData: {'fileName': path.split(Platform.pathSeparator).last});
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
    _msgListener = () => _onUserTyped(_msgController.text);
    _msgController.addListener(_msgListener);
    // mark presence when opening the chat
    _setPresence(true);
    // clear any pending alerts for this chat (stop header blinking)
    _clearPendingAlertsForChat();
    // lazy init recorder to avoid constructor side-effects during widget construction
    _recorder ??= fs.FlutterSoundRecorder();
    // animated background cycling
    _bgTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) setState(() => _bgIndex = (_bgIndex + 1) % _bgGradients.length);
    });
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
            try { _playSfx('sounds/ringtone.mp3'); } catch (_) {}
          }
        }

        // modified: check delivered transition for messages sent by current user
        if (change.type == DocumentChangeType.modified) {
          final wasDelivered = _deliveredMap[id] == true;
          if (data['senderId'] == currentUser?.uid && delivered && !wasDelivered) {
            try { _playTick(); } catch (_) {}
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
        try { await d.reference.delete(); } catch (_) {}
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
    if (_recorderInitialized) {
      try {
        _recorder?.closeRecorder();
      } catch (e) {
        debugPrint('Error closing recorder: $e');
      }
    }
    _bgTimer?.cancel();
    _recordTimer?.cancel();
    // clear typing and presence when leaving
    _typingTimer?.cancel();
    _setTyping(false);
    _setUserAction('idle');
    _setPresence(false);
    _messagesSub?.cancel();
    _listController.dispose();
    try { _sfxPlayer.dispose(); } catch (_) {}
    try { _recordSecondsNotifier.dispose(); } catch (_) {}
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

class AudioMessagePlayer extends StatefulWidget {
  final String url;
  final String fileName;
  const AudioMessagePlayer({super.key, required this.url, required this.fileName});

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
    _player.onDurationChanged.listen((d) { setState(() => _duration = d); });
    _player.onPositionChanged.listen((p) { setState(() => _position = p); });
    _player.onPlayerComplete.listen((_) { setState(() { _playing = false; _position = Duration.zero; }); });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) => '${d.inMinutes.toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de lire l\'audio')));
                setState(() => _playing = false);
              }
            }
          },
        ),
        SizedBox(width: 160, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Slider(value: _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0.0, onChanged: (v) async {
            if (_duration.inMilliseconds > 0) {
              final pos = Duration(milliseconds: (v * _duration.inMilliseconds).round());
              await _player.seek(pos);
            }
          }, activeColor: Colors.white, inactiveColor: Colors.white24),
          Row(children: [
            Expanded(child: Text(widget.fileName, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text(_fmt(_position), style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(width: 6),
            Text('/', style: TextStyle(color: Colors.white24, fontSize: 11)),
            const SizedBox(width: 6),
            Text(_fmt(_duration), style: const TextStyle(color: Colors.white24, fontSize: 11)),
          ])
        ]))
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
      _videoController = (widget.localPath != null && widget.localPath!.isNotEmpty)
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
            onPressed: () async {
              try {
                final uri = Uri.parse(widget.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  Clipboard.setData(ClipboardData(text: widget.url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié')));
                  }
                }
              } catch (_) {}
            },
          ),
          if (widget.messageId != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: tgBar,
                    title: const Text('Supprimer ce média ?', style: TextStyle(color: Colors.white)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                );
                if (ok != true) return;
                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;
                  bool canDelete = widget.senderId == user.uid;
                  if (!canDelete) {
                    final chatSnap = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
                    if (chatSnap.exists) {
                      final data = chatSnap.data() ?? {};
                      final admins = (data['admins'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
                      canDelete = admins.contains(user.uid);
                    }
                  }
                  if (!canDelete) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission refusée')));
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Média supprimé')));
                  }
                } catch (_) {}
              },
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
                    ? Image.file(File(widget.localPath!), fit: BoxFit.contain)
                    : CachedNetworkImage(
                        imageUrl: widget.url,
                        fit: BoxFit.contain,
                      ),
              ),
      ),
    );
  }
}

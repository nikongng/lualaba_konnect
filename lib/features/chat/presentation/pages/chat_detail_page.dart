import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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
import 'attachment_menu.dart';
import 'call_webrtc_page.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:lualaba_konnect/screnns/camera_screen.dart';
import 'package:lualaba_konnect/screnns/media_preview_screen.dart';
import 'package:lualaba_konnect/core/supabase_service.dart';
import 'package:lottie/lottie.dart';
import 'user_utils.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  
  // --- UPLOAD & SAVE HELPERS ---
  Future<void> _uploadAndSend(dynamic fileSource, String type, String folder, String text, {Map<String, dynamic>? extraData}) async {
    setState(() => _isLoading = true);
    try {
      String fileName = '${DateTime.now().millisecondsSinceEpoch}';
      // If Supabase initialized, upload there, otherwise fallback to Firebase Storage
      File file = fileSource is XFile ? File(fileSource.path) : fileSource as File;
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
          url = await SupabaseService.uploadFile(file, supabaseBucket);
          debugPrint('Uploaded to Supabase: $url');
        } else {
          throw Exception('Supabase not initialized');
        }
      } catch (e) {
        debugPrint('Supabase upload failed or unavailable: $e — falling back to Firebase Storage');
        Reference ref = FirebaseStorage.instance.ref().child(folder).child(fileName);
        await ref.putFile(file);
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
      // mark message read
      try { await doc.reference.update({'isRead': true}); } catch (_) {}
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
                    _actionTile(icon: Icons.message, label: 'Message', color: Colors.blueAccent, onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => ChatDetailPage(chatId: widget.chatId, chatName: displayName))); }),
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
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final idToken = await user.getIdToken();
          final chatSnap = await chatRef.get();
          final chatData = chatSnap.data() ?? {};
          final parts = (chatData['participants'] is List) ? List.from(chatData['participants']) : [];
          final recipients = parts.where((p) => p != user.uid).toList();
          if (recipients.isNotEmpty) {
            final url = Uri.parse(const String.fromEnvironment('NOTIFIER_URL', defaultValue: 'https://example.com/sendNotification'));
            final title = data['text'] ?? 'Nouveau message';
            final body = data['text'] ?? '';
            await http.post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $idToken',
              },
              body: jsonEncode({
                'recipients': recipients,
                'title': title,
                'body': body,
                'data': { 'chatId': widget.chatId }
              }),
            );
          }
        }
      } catch (e) {
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
      backgroundColor: tgBg,
      appBar: AppBar(
        backgroundColor: tgBar,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
          builder: (context, snap) {
            String status = "";
            // Determine a resilient display name: prefer chat doc 'name', then widget.chatName,
            // then current user's displayName, finally fallback to 'Utilisateur'.
            String displayName = widget.chatName.trim();
            if (displayName.isEmpty) displayName = currentUser?.displayName ?? "";
            if (snap.hasData && snap.data!.exists) {
              final rawChat = snap.data!.data();
              var data = rawChat is Map ? Map<String, dynamic>.from((rawChat as Map<String, dynamic>?) ?? {}) : <String, dynamic>{};
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
              if (recording.isNotEmpty) {
                status = recording.length == 1 ? "enregistrement audio..." : "plusieurs enregistrement(s)...";
              } else if (typingUsers.isNotEmpty) status = typingUsers.length == 1 ? "en train d'écrire..." : "plusieurs en train d'écrire...";
              else if (presentCount > 0) status = presentCount == 1 ? "1 personne présente" : "$presentCount personnes présentes";
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
              final avatarLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';

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
                    FutureBuilder<DocumentSnapshot?>(
                      future: _getUserDoc(otherId),
                      builder: (ctx, userSnap) {
                        bool isCert = false;
                        if (userSnap.hasData && userSnap.data != null && userSnap.data!.exists) {
                          final rawUd = userSnap.data!.data();
                          final ud = rawUd is Map ? Map<String, dynamic>.from(rawUd as Map<String, dynamic>) : <String, dynamic>{};
                          isCert = ud['isCertified'] == true;
                        }
                        return nameAndBadge(isCert);
                      },
                    ),
                  ],
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
          IconButton(icon: const Icon(Icons.call, color: Colors.white), onPressed: () => _showCallOptions()),
          PopupMenuButton<String>(
            onSelected: (v) => _onMenuSelected(v),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'audio', child: Text('Appel audio')),
              const PopupMenuItem(value: 'video', child: Text('Appel vidéo')),
              const PopupMenuItem(value: 'info', child: Text('Info contact')),
              const PopupMenuItem(value: 'delete', child: Text('Supprimer la conversation')),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // animated gradient background (subtle cycling)
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(seconds: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _bgGradients[_bgIndex],
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
              child: Column(
                children: [
                  Expanded(child: _buildMessageList()),
                  if (_isLoading) const LinearProgressIndicator(color: tgAccent, backgroundColor: tgBar),
                  _buildInputArea(),
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

        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.only(bottom: 10, top: 10),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            return _buildBubble(doc);
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

    return TweenAnimationBuilder<double>(
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
          decoration: bubbleDecoration,
              child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: bubbleDecoration.borderRadius as BorderRadius,
              onLongPress: () => _showMessageOptions(doc, m),
              onTap: () => _onMessageOpen(doc, m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildContent(m, type),
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
  }

  void _showMessageOptions(QueryDocumentSnapshot doc, Map m) {
    final isMe = m['senderId'] == currentUser?.uid;
    showModalBottomSheet(
      context: context,
      backgroundColor: tgBar,
      builder: (c) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.white),
                title: const Text('Supprimer pour moi', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteMessageForMe(doc.reference);
                },
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.white),
                  title: const Text('Supprimer pour tout le monde', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(context);
                    await _deleteMessageForEveryone(doc.reference);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close, color: Colors.white54),
                title: const Text('Annuler', style: TextStyle(color: Colors.white54)),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
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

  Future<void> _deleteMessageForMe(DocumentReference ref) async {
    if (currentUser == null) return;
    try {
      await ref.update({'deletedFor.${currentUser!.uid}': true});
      try { await _playSfx('sounds/pop.mp3'); } catch (_) {}
    } catch (e) {
      debugPrint('Delete for me error: $e');
    }
  }

  Future<void> _deleteMessageForEveryone(DocumentReference ref) async {
    try {
      await ref.delete();
      try { await _playSfx('sounds/pop.mp3'); } catch (_) {}
    } catch (e) {
      debugPrint('Delete for everyone error: $e');
    }
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
            ? CachedNetworkImage(
                imageUrl: m['url'].toString(),
                width: 220,
                fit: BoxFit.contain,
                placeholder: (c, s) => Center(child: CircularProgressIndicator(color: Theme.of(c).colorScheme.primary)),
                errorWidget: (c, s, e) => const Icon(Icons.broken_image, color: Colors.white24, size: 50),
              )
            : const Icon(Icons.image, color: Colors.white24, size: 50);

      case 'file':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(child: Text(m['fileName'] ?? "Fichier", style: const TextStyle(color: Colors.white))),
          ],
        );

      case 'audio':
        return AudioMessagePlayer(url: m['url'] ?? '', fileName: m['fileName'] ?? 'Audio');

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          color: Colors.transparent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: tgBar, borderRadius: BorderRadius.circular(26)),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          _showEmoji ? Icons.keyboard : Icons.sentiment_satisfied_alt, 
                          color: Colors.white38, 
                          size: 28
                        ),
                        onPressed: () {
                          setState(() {
                            _showEmoji = !_showEmoji;
                            if (_showEmoji) FocusScope.of(context).unfocus(); 
                          });
                        }
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: _msgController,
                              onTap: () => setState(() => _showEmoji = false),
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              maxLines: 5,
                              minLines: 1,
                              decoration: const InputDecoration(
                                hintText: "Message",
                                hintStyle: TextStyle(color: Colors.white24),
                                border: InputBorder.none
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
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.attach_file, color: Colors.white38, size: 26), 
                        onPressed: _showAttachmentMenu
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  if (_hasText) {
                    _saveToFirestore({'text': _msgController.text.trim(), 'type': 'text'});
                    _msgController.clear();
                    setState(() => _hasText = false);
                    _setTyping(false);
                    _setUserAction('sent');
                  } else {
                    // démarrer / arrêter enregistrement audio
                    if (!_isRecording) {
                      await _startRecording();
                    } else {
                      await _stopRecording();
                    }
                  }
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
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 8, offset: const Offset(0,4))],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(52),
                      onTap: () async {
                        if (_hasText) {
                          _saveToFirestore({'text': _msgController.text.trim(), 'type': 'text'});
                          _msgController.clear();
                          setState(() => _hasText = false);
                          _setTyping(false);
                          _setUserAction('sent');
                        } else {
                          if (!_isRecording) {
                            await _startRecording();
                          } else {
                            await _stopRecording();
                          }
                        }
                      },
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                          child: _isRecording
                              ? const Icon(Icons.stop, key: ValueKey('stop'), color: Colors.white, size: 24)
                              : (_hasText
                                  ? const Icon(Icons.send, key: ValueKey('send'), color: Colors.white, size: 24)
                                  : const Icon(Icons.mic, key: ValueKey('mic'), color: Colors.white, size: 24)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // AFFICHAGE DU PICKER CORRIGÉ (SANS CONST ET AVEC CONFIG RÉCENTE)
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
    );
  }

  Future<void> _startRecording() async {
    try {
      var status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission micro requise')));
        return;
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

      // show a modern bottom sheet while recording
      if (mounted) {
        await showModalBottomSheet(
          context: context,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          builder: (ctx) {
            return StatefulBuilder(builder: (ctx, setState) {
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: tgBar, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Text('Enregistrement...', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    ValueListenableBuilder<int>(
                      valueListenable: _recordSecondsNotifier,
                      builder: (ctx, secs, _) {
                        final mm = (secs ~/ 60).toString().padLeft(2, '0');
                        final ss = (secs % 60).toString().padLeft(2, '0');
                        return Text('$mm:$ss', style: const TextStyle(color: Colors.white70));
                      },
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () async { // cancel and discard
                      try { await _recorder?.stopRecorder(); } catch (_) {}
                      _recordTimer?.cancel();
                      _recordTimer = null;
                      if (mounted) setState(() { _isRecording = false; _recordSecondsNotifier.value = 0; });
                      Navigator.pop(ctx);
                    }, icon: const Icon(Icons.cancel, color: Colors.white), label: const Text('Annuler'))),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(onPressed: () async { // stop and upload
                      Navigator.pop(ctx);
                      await _stopRecording();
                    }, icon: const Icon(Icons.stop), label: const Text('Arrêter'), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent)),
                  ])
                ]),
              );
            });
          }
        );
      }
    } catch (e) {
      debugPrint('Start record error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder?.stopRecorder();
      if (mounted) setState(() => _isRecording = false);
      _recordTimer?.cancel();
      _recordTimer = null;
      _recordSecondsNotifier.value = 0;
      await _setUserAction('idle');
      if (path != null && path.isNotEmpty) {
        await _uploadAndSend(File(path), 'audio', 'chat_media', '🎤 Audio', extraData: {'fileName': path.split(Platform.pathSeparator).last});
      }
    } catch (e) {
      debugPrint('Stop record error: $e');
    }
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
                await _player.play(UrlSource(widget.url));
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
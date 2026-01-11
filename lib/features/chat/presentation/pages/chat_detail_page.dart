import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
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

const Color tgBg = Color(0xFF0B1418);
const Color tgAccent = Color(0xFF64B5F6);
const Color tgMyBubble = Color(0xFF1E88E5);
const Color tgOtherBubble = Color(0xFF263238);
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
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderInitialized = false;
  late final VoidCallback _msgListener;
  bool _showEmoji = false;

  bool _isLoading = false;
  bool _isRecording = false;
  bool _hasText = false;
  Timer? _typingTimer;
  
  // --- UPLOAD & SAVE HELPERS ---
  Future<void> _uploadAndSend(dynamic fileSource, String type, String folder, String text, {Map<String, dynamic>? extraData}) async {
    setState(() => _isLoading = true);
    try {
      String fileName = '${DateTime.now().millisecondsSinceEpoch}';
      Reference ref = FirebaseStorage.instance.ref().child(folder).child(fileName);
      
      File file = fileSource is XFile ? File(fileSource.path) : fileSource as File;
      await ref.putFile(file);
      String url = await ref.getDownloadURL();
      
      await _saveToFirestore({
        'type': type,
        'url': url,
        'text': text,
        if (extraData != null) ...extraData,
      });
    } catch (e) {
      debugPrint("Erreur upload: $e");
    }
    setState(() => _isLoading = false);
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
        final chatData = chatSnap.data() as Map<String, dynamic>? ?? {};
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
    } catch (e) {
      debugPrint('Erreur update chat meta: $e');
    }
  }


  Future<void> _markMessagesAsDeliveredAndRead(List<QueryDocumentSnapshot> docs) async {
    if (currentUser == null) return;
    WriteBatch batch = FirebaseFirestore.instance.batch();
    bool shouldClearUnread = false;
    for (var d in docs) {
      var m = d.data() as Map<String, dynamic>;
      if (m['senderId'] != currentUser!.uid) {
        if (m['delivered'] != true) {
          batch.update(d.reference, {'delivered': true, 'deliveredAt': FieldValue.serverTimestamp()});
        }
        if (m['isRead'] != true) {
          batch.update(d.reference, {'isRead': true});
          shouldClearUnread = true;
        }
      }
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => TelegramAttachmentSheet(
        onImageSelected: (asset) async {
          Navigator.pop(context);
          File? f = await asset.file;
          if (f != null) _uploadAndSend(XFile(f.path), 'image', 'chat_images', '📸 Photo');
        },
        onCameraTap: () async {
          Navigator.pop(context);
          final XFile? media = await Navigator.push(context, MaterialPageRoute(builder: (context) => const CameraScreen()));
          if (media != null) {
            final result = await Navigator.push(context, MaterialPageRoute(
              builder: (context) => MediaPreviewScreen(mediaFile: media, type: media.path.endsWith('.mp4') ? 'video' : 'image')
            ));
            if (result != null) {
              _uploadAndSend(result['file'], media.path.endsWith('.mp4') ? 'video' : 'image', 'chat_media', result['caption']);
            }
          }
        },
        onGalleryTap: () async {
          Navigator.pop(context);
          final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery);
          if (file != null) _uploadAndSend(file, 'image', 'chat_images', '📸 Photo');
        },
        onFileTap: () async {
          Navigator.pop(context);
          FilePickerResult? res = await FilePicker.platform.pickFiles();
          if (res != null) {
            _uploadAndSend(File(res.files.single.path!), 'file', 'chat_files', '📄 Fichier', extraData: {'fileName': res.files.single.name});
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
            _uploadAndSend(File(res.files.single.path!), 'audio', 'chat_musique', '🎵 Musique', extraData: {'fileName': res.files.single.name});
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
              var data = snap.data!.data() as Map<String, dynamic>? ?? {};
              // prefer explicit chat name from document
              if (data['name'] is String && (data['name'] as String).trim().isNotEmpty) {
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
                if (actions[o] == 'recording') recording.add(o as String);
                else if (typing[o] == true) typingUsers.add(o as String);
                if (present[o] == true) presentCount++;
              }
              if (recording.isNotEmpty) status = recording.length == 1 ? "enregistrement audio..." : "plusieurs enregistrement(s)...";
              else if (typingUsers.isNotEmpty) status = typingUsers.length == 1 ? "en train d'écrire..." : "plusieurs en train d'écrire...";
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
              var data = snap.data!.data() as Map<String, dynamic>? ?? {};
              List parts = (data['participants'] is List) ? List.from(data['participants']) : [];
              parts.removeWhere((id) => id == currentUser?.uid);
              if (parts.isNotEmpty) otherId = parts.first as String;
            }

            Widget buildRow(String name) {
              final avatarLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name.isNotEmpty ? name : 'Utilisateur', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        if (status.isNotEmpty) Text(status, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.1)),
                      ],
                    ),
                  ),
                ],
              );
            }

            // If we have an other participant id and the displayName is missing/Generic, fetch it from users collection
            final needsLookup = otherId.isNotEmpty && (displayName.isEmpty || displayName.contains('@') || displayName.toLowerCase().contains('utilisateur'));
            if (needsLookup) {
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(otherId).get(),
                builder: (ctx, userSnap) {
                  String resolved = displayName;
                  if (userSnap.hasData && userSnap.data!.exists) {
                    final ud = userSnap.data!.data() as Map<String, dynamic>? ?? {};
                    if (ud['displayName'] is String && (ud['displayName'] as String).trim().isNotEmpty) resolved = (ud['displayName'] as String).trim();
                    else if (ud['name'] is String && (ud['name'] as String).trim().isNotEmpty) resolved = (ud['name'] as String).trim();
                  }
                  if (resolved.isEmpty) resolved = currentUser?.displayName ?? 'Utilisateur';
                  return buildRow(resolved);
                },
              );
            }

            // default
            if (displayName.isEmpty) displayName = currentUser?.displayName ?? 'Utilisateur';
            return buildRow(displayName);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white),
            onPressed: () async {
              // create a call document and open WebRTC call page
              try {
                final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
                final chatSnap = await chatRef.get();
                if (!chatSnap.exists) return;
                final data = chatSnap.data() as Map<String, dynamic>? ?? {};
                List participants = (data['participants'] is List) ? List.from(data['participants']) : [];
                String otherId = participants.firstWhere((id) => id != FirebaseAuth.instance.currentUser?.uid, orElse: () => "");
                if (otherId == "") return;
                final callRef = await FirebaseFirestore.instance.collection('calls').add({
                  'caller': FirebaseAuth.instance.currentUser?.uid,
                  'callerName': FirebaseAuth.instance.currentUser?.displayName ?? '',
                  'callee': otherId,
                  'status': 'ringing',
                  'createdAt': FieldValue.serverTimestamp(),
                });
                Navigator.push(context, MaterialPageRoute(builder: (_) => CallWebRTCPage(callId: callRef.id, otherId: otherId, isCaller: true, name: widget.chatName)));
              } catch (e) { debugPrint('Call init error: $e'); }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _confirmAndDeleteConversation();
              else debugPrint('Menu: $v');
            },
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
          Positioned.fill(
            child: Image.asset('assets/images/chat_pattern.jpg', fit: BoxFit.cover),
          ),
          // glass blur
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
              child: Container(color: Colors.black.withOpacity(0.06)),
            ),
          ),
          // gradient overlay + content
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [tgBg.withOpacity(0.6), const Color(0xFF071011).withOpacity(0.85)],
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
                    child: Image.asset('assets/images/orangutan.png', fit: BoxFit.contain, errorBuilder: (c,e,s) => const Icon(Icons.chat_bubble_outline, size: 120, color: Colors.white24)),
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
      if ((m['isRead'] ?? false)) statusIcon = Icon(Icons.done_all, size: 14, color: tgAccent);
      else if ((m['delivered'] ?? false)) statusIcon = Icon(Icons.done_all, size: 14, color: Colors.white30);
      else statusIcon = Icon(Icons.done, size: 14, color: Colors.white30);
    }
    
    final bubbleDecoration = BoxDecoration(
      gradient: isMe
          ? LinearGradient(colors: [tgMyBubble, Color.lerp(tgMyBubble, Colors.black, 0.12)!], begin: Alignment.topLeft, end: Alignment.bottomRight)
          : LinearGradient(colors: [tgOtherBubble, Color(0xFF1A2A2B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: Radius.circular(isMe ? 16 : 4),
        bottomRight: Radius.circular(isMe ? 4 : 16),
      ),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 2)),
      ],
    );

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
        child: Container(
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
                        Container(
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

  Future<void> _deleteMessageForMe(DocumentReference ref) async {
    if (currentUser == null) return;
    try {
      await ref.update({'deletedFor.${currentUser!.uid}': true});
    } catch (e) {
      debugPrint('Delete for me error: $e');
    }
  }

  Future<void> _deleteMessageForEveryone(DocumentReference ref) async {
    try {
      await ref.delete();
    } catch (e) {
      debugPrint('Delete for everyone error: $e');
    }
  }

  Widget _buildContent(Map m, String type) {
    // Afficher message supprimé pour l'utilisateur courant
    try {
      if (currentUser != null && m['deletedFor'] is Map) {
        final df = Map<String, dynamic>.from(m['deletedFor']);
        if (df[currentUser!.uid] == true) {
          return const Text('Message supprimé', style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic));
        }
      }
    } catch (_) {}
    switch (type) {
      case 'image':
        return m['url'] != null 
            ? Image.network(m['url'], width: 220, fit: BoxFit.contain)
            : const Icon(Icons.image, color: Colors.white24, size: 50);

      case 'file':
      case 'audio':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(type == 'audio' ? Icons.music_note : Icons.insert_drive_file, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(child: Text(m['fileName'] ?? "Fichier", style: const TextStyle(color: Colors.white))),
          ],
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
                        child: TextField(
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
                        )
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
                  child: Material(
                    shape: const CircleBorder(),
                    color: tgAccent,
                    elevation: 6,
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                        child: _isRecording
                            ? const Icon(Icons.stop, key: ValueKey('stop'), color: Colors.white, size: 22)
                            : (_hasText
                                ? const Icon(Icons.send, key: ValueKey('send'), color: Colors.white, size: 22)
                                : const Icon(Icons.mic, key: ValueKey('mic'), color: Colors.white, size: 22)),
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
        await _recorder.openRecorder();
        _recorderInitialized = true;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}${Platform.pathSeparator}record_${DateTime.now().millisecondsSinceEpoch}.m4a';
      // signaler action "recording" dans le document chat
      await _setUserAction('recording');
      await _recorder.startRecorder(toFile: path, codec: Codec.aacADTS);
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('Start record error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder.stopRecorder();
      if (mounted) setState(() => _isRecording = false);
      await _setUserAction('idle');
      if (path != null && path.isNotEmpty) {
        await _uploadAndSend(File(path), 'audio', 'chat_musique', '🎤 Audio', extraData: {'fileName': path.split(Platform.pathSeparator).last});
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
      _recorder.closeRecorder();
    }
    // clear typing and presence when leaving
    _typingTimer?.cancel();
    _setTyping(false);
    _setUserAction('idle');
    _setPresence(false);
    super.dispose();
  }
}
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:audioplayers/audioplayers.dart'; // NOUVEAU

// --- CONFIGURATION COULEURS ---
const Color tgBg = Color(0xFF0E1621);
const Color tgBar = Color(0xFF17212B);
const Color tgMyBubble = Color(0xFF2B5278);
const Color tgOtherBubble = Color(0xFF182533);
const Color tgAccent = Color(0xFF64B5F6);

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
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer(); // NOUVEAU

  bool _hasText = false;
  bool _isAudioMode = true;
  bool _isRecording = false;
  bool _showEmoji = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _msgController.addListener(() {
      setState(() => _hasText = _msgController.text.trim().isNotEmpty);
      _updateTypingStatus(_msgController.text.isNotEmpty);
    });

    // --- INITIALISATION : COMPTEURS & LECTURE ---
    _resetMyUnreadCount();
    _markMessagesAsRead();
  }

  // NOUVEAU : Fonction pour la petite sonnerie
  void _playReceiveSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/pop.mp3'));
    } catch (e) {
      debugPrint("Erreur son: $e");
    }
  }

  // --- 1. ACCUSÉS DE RÉCEPTION & COMPTEURS ---
  void _resetMyUnreadCount() {
    FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
      'unreadCounts.${currentUser?.uid}': 0,
    });
  }

  void _markMessagesAsRead() async {
    final query = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: currentUser?.uid)
        .where('isRead', isEqualTo: false)
        .get();

    if (query.docs.isNotEmpty) {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in query.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
      HapticFeedback.lightImpact(); // Petite vibration "Telegram style"
    }
  }

  void _updateTypingStatus(bool isTyping) {
    FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
      'typing.${currentUser?.uid}': isTyping,
    });
  }

  // --- 2. ENVOI DE MESSAGE ---
  Future<void> _saveToFirestore(Map<String, dynamic> data) async {
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
    
    // On récupère les participants pour savoir qui incrémenter
    final chatSnap = await chatRef.get();
    final participants = List<String>.from(chatSnap.get('participants'));
    final otherUserId = participants.firstWhere((id) => id != currentUser?.uid);

    final batch = FirebaseFirestore.instance.batch();
    final msgRef = chatRef.collection('messages').doc();

    batch.set(msgRef, {
      'senderId': currentUser?.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      ...data,
    });

    batch.update(chatRef, {
      'lastMessage': data['text'] ?? "Média",
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': currentUser?.uid,
      'unreadCounts.$otherUserId': FieldValue.increment(1), // Incrémente pour l'autre
      'unreadCounts.${currentUser?.uid}': 0, // Remet le tien à zéro
    });

    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tgBg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          if (_isLoading) const LinearProgressIndicator(color: tgAccent),
          _buildInputArea(),
          if (_showEmoji) _buildEmojiPicker(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: tgBar,
      title: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
        builder: (context, snapshot) {
          bool isTyping = false;
          if (snapshot.hasData && snapshot.data!.exists) {
            Map typingMap = (snapshot.data!.data() as Map)['typing'] ?? {};
            typingMap.forEach((key, value) {
              if (key != currentUser?.uid && value == true) isTyping = true;
            });
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.chatName, style: const TextStyle(fontSize: 16)),
              Text(
                isTyping ? "écrit..." : "En ligne",
                style: TextStyle(fontSize: 12, color: isTyping ? tgAccent : Colors.white54),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        // NOUVEAU : Détection de nouveaux messages pour la sonnerie
        if (snapshot.data!.docChanges.isNotEmpty) {
          var change = snapshot.data!.docChanges.first;
          if (change.type == DocumentChangeType.added) {
            var data = change.doc.data() as Map<String, dynamic>?;
            // Si le message vient de l'autre et qu'il est récent
            if (data != null && data['senderId'] != currentUser?.uid) {
               _playReceiveSound(); 
               _markMessagesAsRead(); 
            }
          }
        }

        var docs = snapshot.data!.docs;
        return ListView.builder(
          reverse: true,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var m = docs[index].data() as Map<String, dynamic>;
            bool isMe = m['senderId'] == currentUser?.uid;
            return _buildBubble(m, isMe);
          },
        );
      },
    );
  }

  Widget _buildBubble(Map m, bool isMe) {
    bool isRead = m['isRead'] ?? false; // NOUVEAU : Récupération du statut Lu

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? tgMyBubble : tgOtherBubble,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m['type'] == 'text')
              Text(m['text'], style: const TextStyle(color: Colors.white, fontSize: 16)),
            
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format((m['timestamp'] as Timestamp? ?? Timestamp.now()).toDate()),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.done_all, 
                    size: 15, 
                    color: isRead ? tgAccent : Colors.white30, // NOUVEAU : Bleu si lu, gris sinon
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: tgBar,
      child: Row(
        children: [
          IconButton(
            icon: Icon(_showEmoji ? Icons.keyboard : Icons.sentiment_satisfied_alt, color: Colors.grey),
            onPressed: () => setState(() => _showEmoji = !_showEmoji),
          ),
          Expanded(
            child: TextField(
              controller: _msgController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: "Message", border: InputBorder.none, hintStyle: TextStyle(color: Colors.white24)),
            ),
          ),
          IconButton(
            icon: Icon(_hasText ? Icons.send : Icons.mic, color: tgAccent),
            onPressed: _hasText ? _sendTextMessage : null,
          ),
        ],
      ),
    );
  }

  void _sendTextMessage() {
    if (_msgController.text.trim().isEmpty) return;
    _saveToFirestore({'text': _msgController.text.trim(), 'type': 'text'});
    _msgController.clear();
  }

  Widget _buildEmojiPicker() {
    return SizedBox(height: 250, child: EmojiPicker(onEmojiSelected: (cat, emoji) => _msgController.text += emoji.emoji));
  }

  @override
  void dispose() {
    _updateTypingStatus(false);
    _msgController.dispose();
    _audioPlayer.dispose(); // NOUVEAU
    super.dispose();
  }
}
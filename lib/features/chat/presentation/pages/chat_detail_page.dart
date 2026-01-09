import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:geolocator/geolocator.dart';

class ChatDetailPage extends StatefulWidget {
  final String chatId;
  final String chatName;
  const ChatDetailPage({super.key, required this.chatId, required this.chatName});

  @override
  State<ChatDetailPage> createState() => _ChatState();
}

class _ChatState extends State<ChatDetailPage> {
  final _msgController = TextEditingController();
  bool _showEmoji = false;
  bool _hasText = false;

  // --- 1. SÉLECTEUR DE FICHIERS (GALERIE, VIDÉO, MUSIQUE, DOCS) ---
  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17212B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          children: [
            _buildActionItem(Icons.image, "Galerie", Colors.purple, () => _pickMedia(ImageSource.gallery, false)),
            _buildActionItem(Icons.videocam, "Vidéo", Colors.pink, () => _pickMedia(ImageSource.gallery, true)),
            _buildActionItem(Icons.insert_drive_file, "Fichier", Colors.blue, _pickGeneralFile),
            _buildActionItem(Icons.headset, "Musique", Colors.orange, _pickAudioFile),
            _buildActionItem(Icons.location_on, "Lieu", Colors.green, _sendLocation),
            _buildActionItem(Icons.person, "Contact", Colors.amber, _pickContact),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return SizedBox(
      width: 90,
      child: Column(
        children: [
          GestureDetector(
            onTap: () { Navigator.pop(context); onTap(); },
            child: CircleAvatar(radius: 28, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 28)),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  // --- 2. LOGIQUE D'ENVOI MULTIMÉDIA ---

  // Photos et Vidéos
  Future<void> _pickMedia(ImageSource source, bool isVideo) async {
    final picker = ImagePicker();
    final file = isVideo ? await picker.pickVideo(source: source) : await picker.pickImage(source: source);
    if (file != null) _uploadFile(File(file.path), isVideo ? 'video' : 'photo');
  }

  // Fichiers (PDF, etc.) et Musique
  Future<void> _pickGeneralFile() async => _pickFileWithFilter(FileType.any, 'fichier');
  Future<void> _pickAudioFile() async => _pickFileWithFilter(FileType.audio, 'musique');

  Future<void> _pickFileWithFilter(FileType type, String category) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: type);
    if (result != null) _uploadFile(File(result.files.single.path!), category);
  }

  // Localisation
  Future<void> _sendLocation() async {
    Position pos = await Geolocator.getCurrentPosition();
    _saveMessageToFirestore(null, 'location', lat: pos.latitude, lng: pos.longitude);
  }

  // Contacts
  void _pickContact() {
    // Ici tu peux ouvrir contacts_service
    _saveMessageToFirestore("Nom du Contact", 'contact');
  }

  // --- 3. UPLOAD ET FIRESTORE ---

  Future<void> _uploadFile(File file, String type) async {
    String name = "${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}";
    var ref = FirebaseStorage.instance.ref().child('chats/${widget.chatId}/$name');
    await ref.putFile(file);
    String url = await ref.getDownloadURL();
    _saveMessageToFirestore(url, type);
  }

  void _saveMessageToFirestore(String? content, String type, {double? lat, double? lng}) {
    FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').add({
      'senderId': 'ID_USER_ICI',
      'mediaUrl': content,
      'type': type,
      'lat': lat,
      'lng': lng,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  // --- 4. INTERFACE INPUT AVEC EMOJIS ---

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () {
        if (_showEmoji) { setState(() => _showEmoji = false); return Future.value(false); }
        return Future.value(true);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1621),
        body: Column(
          children: [
            const Expanded(child: Center(child: Text("Messages ici", style: TextStyle(color: Colors.white)))),
            
            // Barre d'input
            Container(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
              color: const Color(0xFF17212B),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // BOUTON EMOJI
                  IconButton(
                    icon: Icon(_showEmoji ? Icons.keyboard : Icons.sentiment_satisfied_alt, color: Colors.white54),
                    onPressed: () {
                      setState(() => _showEmoji = !_showEmoji);
                      if (_showEmoji) FocusScope.of(context).unfocus();
                    },
                  ),
                  
                  // CHAMP TEXTE
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFF0E1621), borderRadius: BorderRadius.circular(25)),
                      child: Row(
                        children: [
                          const SizedBox(width: 15),
                          Expanded(
                            child: TextField(
                              controller: _msgController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(hintText: "Message", border: InputBorder.none, hintStyle: TextStyle(color: Colors.white24)),
                              onChanged: (v) => setState(() => _hasText = v.trim().isNotEmpty),
                            ),
                          ),
                          // BOUTON TROMBONE (SÉLECTEUR)
                          IconButton(icon: const Icon(Icons.attach_file, color: Colors.white54), onPressed: _showAttachmentMenu),
                        ],
                      ),
                    ),
                  ),
                  
                  // BOUTON ENVOI / MICRO
                  const SizedBox(width: 5),
                  CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    child: Icon(_hasText ? Icons.send : Icons.mic, color: Colors.white),
                  ),
                ],
              ),
            ),
            
            // CLAVIER EMOJI
            if (_showEmoji)
              SizedBox(
                height: 250,
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    _msgController.text = _msgController.text + emoji.emoji;
                    setState(() => _hasText = true);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
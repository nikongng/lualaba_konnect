import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:camera/camera.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:photo_manager/photo_manager.dart';

// --- DESIGN TOKENS ---
const Color tgDark = Color(0xFF17212B);
const Color tgBg = Color(0xFF0E1621);
const Color tgMe = Color(0xFF2B5278);
const Color tgOther = Color(0xFF182533);

class ChatDetailPage extends StatefulWidget {
  final String chatId, chatName;
  const ChatDetailPage({super.key, required this.chatId, required this.chatName});

  @override
  State<ChatDetailPage> createState() => _ChatState();
}

class _ChatState extends State<ChatDetailPage> {
  final _msgController = TextEditingController();
  final _recorder = AudioRecorder();
  final currentUser = FirebaseAuth.instance.currentUser;
  
  CameraController? _cameraController;
  bool _isRecording = false, _isModeVideo = false, _hasText = false, _showEmoji = false;
  int _timerCount = 0;
  Timer? _timer;
  List<AssetEntity> _mediaList = [];

  @override
  void initState() {
    super.initState();
    _msgController.addListener(() => setState(() => _hasText = _msgController.text.trim().isNotEmpty));
    _fetchAssets();
  }

  // --- RÉCUPÉRATION GALERIE (SANS ERREUR) ---
  Future<void> _fetchAssets() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth || ps.hasAccess) {
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(onlyAll: true, type: RequestType.image);
      if (albums.isNotEmpty) {
        List<AssetEntity> media = await albums[0].getAssetListPaged(page: 0, size: 24);
        setState(() => _mediaList = media);
      }
    }
  }

  // --- LOGIQUE MULTIMÉDIA ---
  Future<void> _initCamera() async {
    final cams = await availableCameras();
    if (cams.isEmpty) return;
    final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams[0]);
    _cameraController = CameraController(front, ResolutionPreset.medium, enableAudio: true);
    await _cameraController!.initialize();
  }

  void _startRecording() async {
    try {
      if (_isModeVideo) {
        if (_cameraController == null || !_cameraController!.value.isInitialized) await _initCamera();
        await _cameraController?.startVideoRecording();
      } else if (await _recorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(), path: path);
      }
      setState(() { _isRecording = true; _timerCount = 0; _showEmoji = false; });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => _timerCount++));
    } catch (e) { debugPrint("Error: $e"); }
  }

  void _stopRecording() async {
    _timer?.cancel();
    try {
      if (_isModeVideo) {
        final file = await _cameraController?.stopVideoRecording();
        if (file != null) _uploadFile(File(file.path), 'video_message');
      } else {
        final path = await _recorder.stop();
        if (path != null) _uploadFile(File(path), 'audio');
      }
    } catch (e) { debugPrint("Stop Error: $e"); }
    setState(() => _isRecording = false);
  }

  Future<void> _uploadFile(File file, String type) async {
    final ref = FirebaseStorage.instance.ref().child('chats/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}');
    await ref.putFile(file);
    final url = await ref.getDownloadURL();
    _sendMessage(type: type, fileUrl: url);
  }

  void _sendMessage({required String type, String? text, String? fileUrl}) {
    FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').add({
      'senderId': currentUser!.uid,
      'type': type,
      'text': text ?? '',
      'fileUrl': fileUrl ?? '',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // --- ACTION : SUPPRIMER MESSAGE ---
  void _deleteMessage(String messageId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: tgDark,
        title: const Text("Supprimer ?", style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(messageId).delete();
              Navigator.pop(context);
            },
            child: const Text("Supprimer", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // --- MENU PIÈCE JOINTE ---
  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(color: tgBg, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 10), height: 4, width: 40, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
            Expanded(
              child: GridView.builder(
                controller: scrollController,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
                itemCount: _mediaList.length,
                itemBuilder: (context, index) {
                  return FutureBuilder<Uint8List?>(
                    future: _mediaList[index].thumbnailDataWithSize(const ThumbnailSize.square(250)),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                        return Image.memory(snapshot.data!, fit: BoxFit.cover);
                      }
                      return Container(color: tgDark);
                    },
                  );
                },
              ),
            ),
            _buildActionButtons(),
          ]),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.only(top: 10, bottom: 25),
      color: tgDark,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _actionIcon(Icons.image, "Galerie", Colors.blue, () async {
          final p = await ImagePicker().pickImage(source: ImageSource.gallery);
          if (p != null) _uploadFile(File(p.path), 'image');
        }),
        _actionIcon(Icons.insert_drive_file, "Fichier", Colors.lightBlueAccent, () async {
          final r = await FilePicker.platform.pickFiles();
          if (r != null) _uploadFile(File(r.files.single.path!), 'file');
        }),
        _actionIcon(Icons.location_on, "Lieu", Colors.green, () async {
          Position p = await Geolocator.getCurrentPosition();
          _sendMessage(type: 'location', text: "📍 Position: https://www.google.com/maps?q=${p.latitude},${p.longitude}");
        }),
      ]),
    );
  }

  Widget _actionIcon(IconData i, String l, Color c, VoidCallback onTap) {
    return GestureDetector(
      onTap: () { Navigator.pop(context); onTap(); },
      child: Column(children: [
        CircleAvatar(radius: 28, backgroundColor: c.withValues(alpha: 0.15), child: Icon(i, color: c, size: 28)),
        const SizedBox(height: 8),
        Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tgBg,
      appBar: AppBar(backgroundColor: tgDark, title: Text(widget.chatName), elevation: 0),
      body: PopScope(
        canPop: !_showEmoji,
        onPopInvokedWithResult: (didPop, _) { if (!didPop && _showEmoji) setState(() => _showEmoji = false); },
        child: Stack(children: [
          Column(children: [
            Expanded(child: _buildMessageList()),
            _buildInputArea(),
            if (_showEmoji) _buildEmojiPicker(),
          ]),
          if (_isRecording && _isModeVideo && _cameraController != null && _cameraController!.value.isInitialized)
            Positioned(bottom: 100, right: 20, child: _cameraCircle()),
        ]),
      ),
    );
  }

  Widget _buildEmojiPicker() => SizedBox(height: 250, child: EmojiPicker(
    textEditingController: _msgController,
    config: Config(
      emojiViewConfig: EmojiViewConfig(backgroundColor: tgDark),
      categoryViewConfig: const CategoryViewConfig(backgroundColor: tgDark, indicatorColor: Colors.blue, iconColorSelected: Colors.blue),
    ),
  ));

  Widget _cameraCircle() => Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
      child: ClipOval(child: CameraPreview(_cameraController!)));

  Widget _buildMessageList() => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').orderBy('timestamp', descending: true).snapshots(),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      return ListView.builder(reverse: true, itemCount: snap.data!.docs.length, itemBuilder: (c, i) {
        var doc = snap.data!.docs[i];
        var m = doc.data() as Map<String, dynamic>;
        bool isMe = m['senderId'] == currentUser?.uid;
        return GestureDetector(
          onLongPress: () => _deleteMessage(doc.id),
          child: _bubble(m, isMe),
        );
      });
    },
  );

  Widget _bubble(Map m, bool isMe) => Align(alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: isMe ? tgMe : tgOther, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m['type'] == 'image') ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(m['fileUrl'])),
        if (m['type'] == 'audio') TelegramAudioPlayer(url: m['fileUrl']),
        if (m['type'] == 'video_message') CircularVideoMessage(url: m['fileUrl']),
        if (m['type'] == 'text' || m['type'] == 'location') Text(m['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 4),
        Text(m['timestamp'] != null ? DateFormat('HH:mm').format((m['timestamp'] as Timestamp).toDate()) : '', style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ])));

  Widget _buildInputArea() => Container(padding: const EdgeInsets.all(8), child: Row(children: [
    Expanded(child: Container(decoration: BoxDecoration(color: tgDark, borderRadius: BorderRadius.circular(25)),
      child: Row(children: [
        IconButton(icon: Icon(_showEmoji ? Icons.keyboard : Icons.sentiment_satisfied_alt, color: Colors.white54), 
          onPressed: () { setState(() => _showEmoji = !_showEmoji); if (_showEmoji) FocusScope.of(context).unfocus(); }),
        Expanded(child: _isRecording ? Text("⏺ Recording... ${_timerCount}s", style: const TextStyle(color: Colors.redAccent)) 
          : TextField(controller: _msgController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Message", border: InputBorder.none))),
        IconButton(icon: const Icon(Icons.attach_file, color: Colors.white54), onPressed: _showAttachmentMenu),
      ]))),
    const SizedBox(width: 8),
    GestureDetector(
      onTap: () { if (_hasText) { _sendMessage(type: 'text', text: _msgController.text); _msgController.clear(); } else { setState(() => _isModeVideo = !_isModeVideo); } },
      onLongPressStart: (_) => _hasText ? null : _startRecording(),
      onLongPressEnd: (_) => _hasText ? null : _stopRecording(),
      child: CircleAvatar(radius: 25, backgroundColor: _isRecording ? Colors.red : tgMe, child: Icon(_hasText ? Icons.send : (_isModeVideo ? Icons.videocam : Icons.mic), color: Colors.white)),
    )
  ]));

  @override
  void dispose() { _cameraController?.dispose(); _msgController.dispose(); _recorder.dispose(); _timer?.cancel(); super.dispose(); }
}

// --- SOUS-WIDGETS ---
class TelegramAudioPlayer extends StatefulWidget {
  final String url;
  const TelegramAudioPlayer({super.key, required this.url});
  @override State<TelegramAudioPlayer> createState() => _AudioPState();
}
class _AudioPState extends State<TelegramAudioPlayer> {
  final _p = AudioPlayer(); bool _isP = false;
  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    IconButton(icon: Icon(_isP ? Icons.pause_circle : Icons.play_circle, color: Colors.white, size: 35), 
      onPressed: () async { _isP ? await _p.pause() : await _p.play(UrlSource(widget.url)); setState(() => _isP = !_isP); }),
    const Text("Audio Message", style: TextStyle(color: Colors.white70))
  ]);
  @override void dispose() { _p.dispose(); super.dispose(); }
}

class CircularVideoMessage extends StatefulWidget {
  final String url;
  const CircularVideoMessage({super.key, required this.url});
  @override State<CircularVideoMessage> createState() => _VideoMState();
}
class _VideoMState extends State<CircularVideoMessage> {
  late VideoPlayerController _c;
  @override void initState() { super.initState(); _c = VideoPlayerController.networkUrl(Uri.parse(widget.url))..initialize().then((_) { setState(() {}); _c.play(); _c.setLooping(true); _c.setVolume(0); }); }
  @override Widget build(BuildContext context) => _c.value.isInitialized ? ClipOval(child: SizedBox(width: 180, height: 180, child: VideoPlayer(_c))) : const Center(child: CircularProgressIndicator());
  @override void dispose() { _c.dispose(); super.dispose(); }
}
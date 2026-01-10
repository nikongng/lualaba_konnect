import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:timeago/timeago.dart' as timeago;

import '../../../auth/presentation/widgets/story_widgets.dart';
import '../../../auth/presentation/widgets/animated_fab.dart';
import 'chat_detail_page.dart';

class UserUtils {
  static String formatName(Map<String, dynamic>? data) {
    if (data == null) return "Utilisateur";
    final keysFirst = ['firstName', 'firstname', 'prenom', 'givenName'];
    final keysLast = ['lastName', 'lastname', 'nom', 'familyName'];
    String? first, last;
    for (var k in keysFirst) { if (data[k]?.toString().trim().isNotEmpty == true) { first = data[k].toString().trim(); break; } }
    for (var k in keysLast) { if (data[k]?.toString().trim().isNotEmpty == true) { last = data[k].toString().trim(); break; } }
    if (first != null && last != null) return '$first $last';
    if (first != null) return first;
    for (var k in ['displayName', 'name', 'fullName']) {
      if (data[k]?.toString().trim().isNotEmpty == true) return data[k].toString().split(' ').first;
    }
    return 'Utilisateur';
  }
}

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});
  @override
  ChatListPageState createState() => ChatListPageState();
}

class ChatListPageState extends State<ChatListPage> with WidgetsBindingObserver {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final Color primaryDark = const Color(0xFF1D2733);
  final Color orangeAccent = const Color(0xFFE57C00);
  final Color tgAccent = const Color(0xFF64B5F6);
  String selectedCategory = "TOUS";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnlineStatus(true);
    _cleanupOldStories();
    timeago.setLocaleMessages('fr', timeago.FrMessages());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setOnlineStatus(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setOnlineStatus(state == AppLifecycleState.resumed);
  }

  Future<void> _setOnlineStatus(bool isOnline) async {
    if (currentUser != null) {
      await FirebaseFirestore.instance.collection('classic_users').doc(currentUser!.uid).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _cleanupOldStories() async {
    final now = DateTime.now();
    final expired = await FirebaseFirestore.instance.collection('stories').where('expiresAt', isLessThan: now).get();
    for (var doc in expired.docs) {
      try {
        String? url = doc.data()['imageUrl'];
        if (url != null) await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (e) { debugPrint("Erreur Story: $e"); }
      await doc.reference.delete();
    }
  }

  Future<void> _handleCameraAction() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null && currentUser != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Publication de la story...")));
      String fileName = 'story_${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference ref = FirebaseStorage.instance.ref().child('stories').child(fileName);
      await ref.putFile(File(image.path));
      String url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('stories').add({
        'userId': currentUser!.uid,
        'userName': currentUser!.displayName ?? "Moi",
        'imageUrl': url,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': DateTime.now().add(const Duration(hours: 24)),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryDark,
      appBar: AppBar(
        backgroundColor: primaryDark,
        elevation: 0,
        leading: const Icon(Icons.menu, color: Colors.white54),
        title: const Text('Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: const [Icon(Icons.search, color: Colors.white54), SizedBox(width: 15)],
      ),
      body: Column(
        children: [
          StoryBar(currentUserId: currentUser?.uid ?? "", onAddStoryTap: _handleCameraAction),
          _buildCategoryTabs(),
          Expanded(child: _buildChatList()),
        ],
      ),
      floatingActionButton: AnimatedFabColumn(onCameraTap: _handleCameraAction, onEditTap: _showNewChatDialog),
    );
  }

  Widget _buildCategoryTabs() {
    final tabs = ["TOUS", "PRO", "ENTERPRISE", "NON LUS"];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.map((label) {
            bool isActive = selectedCategory == label;
            return GestureDetector(
              onTap: () => setState(() => selectedCategory = label),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Column(
                  children: [
                    Text(label, style: TextStyle(color: isActive ? orangeAccent : Colors.white38, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Container(height: 2, width: 40, color: isActive ? orangeAccent : Colors.transparent),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildChatList() {
    Query query = FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: currentUser?.uid);
    
    return StreamBuilder<QuerySnapshot>(
      stream: query.orderBy('lastMessageTime', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var docs = snapshot.data!.docs;

        // FILTRAGE LOCAL PAR TYPE & NON LUS
        if (selectedCategory == "PRO") {
          docs = docs.where((doc) => (doc.data() as Map)['userTypes']?.values.contains("pro_users") ?? false).toList();
        } else if (selectedCategory == "ENTERPRISE") {
          docs = docs.where((doc) => (doc.data() as Map)['userTypes']?.values.contains("enterprise_users") ?? false).toList();
        } else if (selectedCategory == "NON LUS") {
          docs = docs.where((doc) {
            Map unreadMap = (doc.data() as Map)['unreadCounts'] ?? {};
            return (unreadMap[currentUser?.uid] ?? 0) > 0;
          }).toList();
        }

        if (docs.isEmpty) return const Center(child: Text("Aucune discussion", style: TextStyle(color: Colors.white38)));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final chat = docs[index].data() as Map<String, dynamic>;
            final String docId = docs[index].id;
            
            List participants = chat['participants'] ?? [];
            String otherUserId = participants.firstWhere((id) => id != currentUser?.uid, orElse: () => "");
            Map userTypes = chat['userTypes'] ?? {};
            String collection = userTypes[otherUserId] ?? 'classic_users';

            return Dismissible(
              key: Key(docId),
              direction: DismissDirection.endToStart,
              background: Container(color: Colors.redAccent, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
              onDismissed: (_) => FirebaseFirestore.instance.collection('chats').doc(docId).delete(),
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection(collection).doc(otherUserId).snapshots(),
                builder: (context, userSnap) {
                  String finalName = "Utilisateur";
                  bool isOnline = false;
                  bool isCert = false;

                  if (userSnap.hasData && userSnap.data!.exists) {
                    final userData = userSnap.data!.data() as Map<String, dynamic>;
                    finalName = UserUtils.formatName(userData);
                    isOnline = userData['isOnline'] ?? false;
                    isCert = userData['isCertified'] ?? false;
                  }

                  // LOGIQUE "EN TRAIN D'ÉCRIRE"
                  Map typingMap = chat['typing'] ?? {};
                  bool isTyping = typingMap[otherUserId] ?? false;

                  return ListTile(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatDetailPage(chatId: docId, chatName: finalName))),
                    leading: Stack(
                      children: [
                        const CircleAvatar(radius: 26, backgroundColor: Color(0xFF2C3E50), child: Icon(Icons.person, color: Colors.white54)),
                        if (isOnline) Positioned(right: 1, bottom: 1, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.all(color: primaryDark, width: 2)))),
                      ],
                    ),
                    title: Row(
                      children: [
                        Flexible(child: Text(finalName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        if (isCert) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified, color: Colors.blue, size: 16)),
                        if (collection == "pro_users") const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified, color: Colors.orange, size: 16)),
                        if (collection == "enterprise_users") const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.stars, color: Colors.greenAccent, size: 16)),
                      ],
                    ),
                    subtitle: Text(
                      isTyping ? "en train d'écrire..." : (chat['lastMessage'] ?? "Nouvelle discussion"), 
                      style: TextStyle(color: isTyping ? tgAccent : Colors.white54, fontWeight: isTyping ? FontWeight.bold : FontWeight.normal), 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis
                    ),
                    trailing: _buildTimeAndBadge(chat),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTimeAndBadge(Map chat) {
    String time = "";
    if (chat['lastMessageTime'] != null) time = timeago.format((chat['lastMessageTime'] as Timestamp).toDate(), locale: 'fr');
    
    // CORRECTION DU BADGE : On lit le compteur de l'utilisateur actuel uniquement
    Map unreadCounts = chat['unreadCounts'] ?? {};
    int myUnread = unreadCounts[currentUser?.uid] ?? 0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(time, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        if (myUnread > 0)
          Container(
            margin: const EdgeInsets.only(top: 4), 
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), 
            decoration: BoxDecoration(color: Colors.greenAccent[700], borderRadius: BorderRadius.circular(10)), 
            child: Text("$myUnread", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
          ),
      ],
    );
  }

  void _showNewChatDialog() {
    // Ton code existant pour le modal de recherche...
  }
}
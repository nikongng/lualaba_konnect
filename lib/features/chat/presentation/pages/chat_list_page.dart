import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:timeago/timeago.dart' as timeago;

// Tes imports personnalisés (vérifie bien les chemins)
import '../../../auth/presentation/widgets/story_widgets.dart';
import '../../../auth/presentation/widgets/animated_fab.dart';
import 'chat_detail_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});
  @override
  ChatListPageState createState() => ChatListPageState();
}

class ChatListPageState extends State<ChatListPage> with WidgetsBindingObserver {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final Color primaryDark = const Color(0xFF1D2733);
  final Color orangeAccent = const Color(0xFFE57C00);
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
    if (state == AppLifecycleState.resumed) {
      _setOnlineStatus(true);
    } else {
      _setOnlineStatus(false);
    }
  }

  Future<void> _setOnlineStatus(bool isOnline) async {
    if (currentUser != null) {
      await FirebaseFirestore.instance
          .collection('classic_users')
          .doc(currentUser!.uid)
          .update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _cleanupOldStories() async {
    final now = DateTime.now();
    final expired = await FirebaseFirestore.instance
        .collection('stories')
        .where('expiresAt', isLessThan: now)
        .get();

    for (var doc in expired.docs) {
      try {
        String? url = doc.data()['imageUrl'];
        if (url != null) await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (e) {
        debugPrint("Erreur Storage Story: $e");
      }
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
        actions: const [
          Icon(Icons.search, color: Colors.white54),
          SizedBox(width: 15),
        ],
      ),
      body: Column(
        children: [
          StoryBar(
            currentUserId: currentUser?.uid ?? "",
            onAddStoryTap: _handleCameraAction,
          ),
          _buildCategoryTabs(),
          Expanded(child: _buildChatList()),
        ],
      ),
      floatingActionButton: AnimatedFabColumn(
        onCameraTap: _handleCameraAction,
        onEditTap: _showNewChatDialog,
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: ["TOUS", "PRO", "NON LUS"].map((label) {
          bool isActive = selectedCategory == label;
          return GestureDetector(
            onTap: () => setState(() => selectedCategory = label),
            child: Column(
              children: [
                Text(label,
                    style: TextStyle(
                        color: isActive ? orangeAccent : Colors.white38,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                    height: 2,
                    width: 40,
                    color: isActive ? orangeAccent : Colors.transparent),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChatList() {
    Query query = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: currentUser?.uid);

    // Filtre pour les messages non lus
    if (selectedCategory == "NON LUS") {
      query = query.where('unreadCount', isGreaterThan: 0);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.orderBy('lastMessageTime', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text("Aucune discussion", style: TextStyle(color: Colors.white38)));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final chat = docs[index].data() as Map<String, dynamic>;
            final String docId = docs[index].id;

            List participants = chat['participants'] ?? [];
            String otherUserId = participants.firstWhere((id) => id != currentUser?.uid, orElse: () => "");

            List names = chat['displayNames'] ?? ["Utilisateur", "Utilisateur"];
            List emails = chat['participantNames'] ?? ["", ""];
            int otherIdx = (emails[0] == currentUser?.email) ? 1 : 0;
            String title = names[otherIdx];

            String timeDisplay = "";
            if (chat['lastMessageTime'] != null) {
              DateTime date = (chat['lastMessageTime'] as Timestamp).toDate();
              timeDisplay = timeago.format(date, locale: 'fr', allowFromNow: true);
            }

            // Gestion du texte pour les types spéciaux (Audio/Vidéo)
            Widget lastMsgWidget = Text(
              chat['lastMessage'] ?? '',
              style: const TextStyle(color: Colors.white54),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('classic_users').doc(otherUserId).snapshots(),
              builder: (context, userSnap) {
                bool isOnline = false;
                if (userSnap.hasData && userSnap.data!.exists) {
                  isOnline = (userSnap.data!.data() as Map<String, dynamic>)['isOnline'] ?? false;
                }

                return ListTile(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (context) => ChatDetailPage(chatId: docId, chatName: title)
                  )),
                  leading: Stack(
                    children: [
                      const CircleAvatar(
                        radius: 26,
                        backgroundColor: Color(0xFF2C3E50),
                        child: Icon(Icons.person, color: Colors.white54),
                      ),
                      Positioned(
                        right: 1,
                        bottom: 1,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.greenAccent[400] : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(color: isOnline ? primaryDark : Colors.transparent, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: lastMsgWidget,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(timeDisplay, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                      const SizedBox(height: 4),
                      // BADGE NON LU
                      if (chat['unreadCount'] != null && chat['unreadCount'] > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent[700],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            chat['unreadCount'].toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
  Future<void> _startChat(String otherUserId, String otherName, String otherEmail) async {
  // 1. On crée un ID unique basé sur les deux IDs (triés pour être unique)
  List<String> ids = [currentUser!.uid, otherUserId];
  ids.sort();
  String chatId = ids.join("_");

  // 2. On vérifie si le chat existe déjà
  DocumentReference chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
  DocumentSnapshot doc = await chatRef.get();

  if (!doc.exists) {
    // 3. Si non, on le crée avec les infos nécessaires pour tes StreamBuilders
    await chatRef.set({
      'participants': ids,
      'participantNames': [currentUser!.email, otherEmail],
      'displayNames': [currentUser!.displayName ?? "Moi", otherName],
      'lastMessage': "Nouvelle discussion lancée",
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount': 0,
    });
  }

  // 4. On navigue vers la page de détail
  if (mounted) {
    Navigator.push(context, MaterialPageRoute(
      builder: (context) => ChatDetailPage(chatId: chatId, chatName: otherName)
    ));
  }
}

void _showNewChatDialog() {
  showModalBottomSheet(
    context: context,
    backgroundColor: primaryDark,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 20),
          const Text("Nouveau Message", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white10),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // On récupère la liste des utilisateurs (adapte 'classic_users' si besoin)
              stream: FirebaseFirestore.instance.collection('classic_users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                // On filtre pour ne pas se voir soi-même dans la liste
                final users = snapshot.data!.docs.where((doc) => doc.id != currentUser?.uid).toList();

                return ListView.builder(
                  controller: scrollController,
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index].data() as Map<String, dynamic>;
                    final String userId = users[index].id;

                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.white10,
                        child: Icon(Icons.person, color: Colors.white70),
                      ),
                      title: Text(user['displayName'] ?? "Utilisateur", style: const TextStyle(color: Colors.white)),
                      subtitle: Text(user['email'] ?? "", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context); // Fermer le menu
                        _startChat(userId, user['displayName'] ?? "Utilisateur", user['email'] ?? "");
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
}
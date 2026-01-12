import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:timeago/timeago.dart' as timeago;
import 'call_webrtc_page.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../../../auth/presentation/pages/ModernDashboard.dart';
import 'package:flutter/services.dart';

import '../../../auth/presentation/widgets/story_widgets.dart';
import '../../../auth/presentation/widgets/animated_fab.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/chat_detail_page.dart';

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

class ChatListPageState extends State<ChatListPage> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final Color primaryDark = const Color(0xFF1D2733);
  final Color orangeAccent = const Color(0xFFE57C00);
  final Color tgAccent = const Color(0xFF64B5F6);
  String selectedCategory = "TOUS";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _menuController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _searchController = TextEditingController();
    _searchFocus = FocusNode();
    _scaffoldKey = GlobalKey<ScaffoldState>();
    _setOnlineStatus(true);
    _cleanupOldStories();
    timeago.setLocaleMessages('fr', timeago.FrMessages());
    _listenIncomingCalls();
    _listenUnreadTotals();
  }

  StreamSubscription<QuerySnapshot>? _incomingCallSub;
    StreamSubscription<QuerySnapshot>? _unreadSub;
    int _prevTotalUnread = 0;
    int _totalUnread = 0;

    int get unreadTotal => _totalUnread;
  bool _showingIncoming = false;
  late AnimationController _menuController;
  late TextEditingController _searchController;
  late FocusNode _searchFocus;
  bool _isSearchActive = false;
  late GlobalKey<ScaffoldState> _scaffoldKey;

  void _listenIncomingCalls() {
    final uid = currentUser?.uid;
    if (uid == null) return;
    _incomingCallSub = FirebaseFirestore.instance.collection('calls')
      .where('callee', isEqualTo: uid)
      .where('status', isEqualTo: 'ringing')
      .snapshots()
      .listen((snap) async {
        if (!mounted) return;
        for (var change in snap.docChanges) {
          if (change.type == DocumentChangeType.added && !_showingIncoming) {
            final doc = change.doc;
            NotificationService.playRingtone();
            _showingIncoming = true;
            final data = doc.data() as Map<String, dynamic>;
            final callerId = data['caller'] ?? '';
            final callerName = data['callerName'] ?? 'Appel entrant';
            // show incoming call dialog
            showModalBottomSheet(
              context: context,
              isDismissible: false,
              enableDrag: false,
              backgroundColor: Colors.transparent,
              builder: (ctx) {
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFF17212B), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$callerName', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Appel entrant', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          // reject
                          try {
                            await FirebaseFirestore.instance.collection('calls').doc(doc.id).update({'status': 'rejected'});
                          } catch (e) {
                            debugPrint('Reject err: $e');
                          }
                          NotificationService.stopRingtone();
                          Navigator.pop(ctx);
                          _showingIncoming = false;
                        },
                        icon: const Icon(Icons.call_end),
                        label: const Text('Refuser'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // accept: open call page as callee
                          NotificationService.stopRingtone();
                          Navigator.pop(ctx);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => CallWebRTCPage(callId: doc.id, otherId: callerId, isCaller: false, name: callerName)));
                          _showingIncoming = false;
                        },
                        icon: const Icon(Icons.call),
                        label: const Text('Accepter'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      ),
                    ])
                  ]),
                );
              }
            );
          }
        }
      });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setOnlineStatus(false);
    _incomingCallSub?.cancel();
    _unreadSub?.cancel();
    _menuController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          hintText: 'Rechercher',
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
        ),
        onChanged: (v) => setState(() {}),
      ),
    );
  }

  Widget _menuTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }

  void _showModernMenu() {
    _menuController.forward();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = Curves.easeOut.transform(anim1.value);
        return Transform.translate(
          offset: Offset(-200 * (1 - curved), 0),
          child: Opacity(
            opacity: anim1.value,
            child: SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.78,
                    height: MediaQuery.of(context).size.height,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F171A),
                      borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45 * anim1.value), blurRadius: 30 * anim1.value)],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18.0),
                          child: Row(children: [
                            const CircleAvatar(radius: 26, backgroundColor: Color(0xFF2C3E50), child: Icon(Icons.person, color: Colors.white54)),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(currentUser?.displayName ?? 'Utilisateur', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(currentUser?.email ?? '', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                            ])),
                            IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () { Navigator.pop(ctx); _menuController.reverse(); }),
                          ]),
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            children: [
                              _menuTile(Icons.group, 'Nouveau groupe', () { Navigator.pop(ctx); _menuController.reverse(); _showCreateGroupDialog(); }),
                              _menuTile(Icons.person_add, 'Contacts', () async {
                                Navigator.pop(ctx);
                                _menuController.reverse();
                                if (await FlutterContacts.requestPermission()) {
                                  final list = await FlutterContacts.getContacts(withProperties: true);
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: const Color(0xFF0F171A),
                                    builder: (_) {
                                      return Material(
                                        color: Colors.transparent,
                                        child: SizedBox(
                                          height: 520,
                                          child: ListView.builder(
                                            itemCount: list.length,
                                            itemBuilder: (c, i) {
                                              final contact = list[i];
                                              return ListTile(
                                                title: Text(contact.displayName, style: const TextStyle(color: Colors.white)),
                                                subtitle: contact.emails.isNotEmpty ? Text(contact.emails.first.address, style: const TextStyle(color: Colors.white60)) : null,
                                                onTap: () async {
                                                  final email = contact.emails.isNotEmpty ? contact.emails.first.address : '';
                                                  if (email.isEmpty) {
                                                    Navigator.pop(context);
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact sans email utilisable')));
                                                    return;
                                                  }
                                                  // try to find user by email
                                                  List<String> cols = ['classic_users', 'pro_users', 'enterprise_users'];
                                                  String? foundId;
                                                  String foundName = contact.displayName;
                                                  for (var col in cols) {
                                                    final res = await FirebaseFirestore.instance.collection(col).where('email', isEqualTo: email).limit(1).get();
                                                    if (res.docs.isNotEmpty) { foundId = res.docs.first.id; foundName = UserUtils.formatName(res.docs.first.data() as Map<String, dynamic>?); break; }
                                                  }
                                                  Navigator.pop(context);
                                                  if (foundId != null) {
                                                    _startChatWithUser(foundId, foundName, 'classic_users');
                                                  } else {
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun utilisateur trouvé avec cet email')));
                                                  }
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission contacts refusée')));
                                }
                              }),
                              _menuTile(Icons.call, 'Appels', () async {
                                Navigator.pop(ctx); _menuController.reverse();
                                final snap = await FirebaseFirestore.instance.collection('calls')
                                  .where('caller', isEqualTo: currentUser?.uid)
                                  .orderBy('createdAt', descending: true)
                                  .limit(50)
                                  .get();
                                showModalBottomSheet(
                                  context: context,
                                  backgroundColor: const Color(0xFF0F171A),
                                  builder: (_) {
                                    return Material(
                                      color: Colors.transparent,
                                      child: SizedBox(
                                        height: 520,
                                        child: ListView(
                                          children: snap.docs.map((d) {
                                            final data = d.data();
                                            final calleeId = data['callee'] ?? '';
                                            final calleeName = data['calleeName'] ?? data['callerName'] ?? 'Appel';
                                            return ListTile(
                                              title: Text(calleeName, style: const TextStyle(color: Colors.white)),
                                              subtitle: Text(data['status'] ?? '', style: const TextStyle(color: Colors.white60)),
                                              trailing: IconButton(
                                                icon: const Icon(Icons.call, color: Colors.green),
                                                onPressed: () async {
                                                  if (currentUser == null) return;
                                                  try {
                                                    final callDoc = await FirebaseFirestore.instance.collection('calls').add({
                                                      'caller': currentUser!.uid,
                                                      'callee': calleeId,
                                                      'callerName': currentUser!.displayName ?? '',
                                                      'calleeName': calleeName,
                                                      'status': 'ringing',
                                                      'createdAt': FieldValue.serverTimestamp(),
                                                    });
                                                    Navigator.pop(context);
                                                    Navigator.push(context, MaterialPageRoute(builder: (_) => CallWebRTCPage(callId: callDoc.id, otherId: calleeId, isCaller: true, name: calleeName)));
                                                  } catch (e) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de l\'appel'))); }
                                                },
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }),
                              _menuTile(Icons.bookmark, 'Messages sauvegardés', () { Navigator.pop(ctx); _menuController.reverse(); _showSavedMessages(); }),
                              _menuTile(Icons.settings, 'Paramètres', () { Navigator.pop(ctx); _menuController.reverse(); Navigator.push(context, MaterialPageRoute(builder: (_) => const ModernDashboard())); }),
                              _menuTile(Icons.person, 'Profil', () { Navigator.pop(ctx); _menuController.reverse(); Navigator.push(context, MaterialPageRoute(builder: (_) => const ModernDashboard())); }),
                              _menuTile(Icons.group_add, 'Inviter des amis', () { Navigator.pop(ctx); _menuController.reverse(); _showInviteDialog(); }),
                            ],
                          ),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 12.0), child: ElevatedButton.icon(onPressed: () async { Navigator.pop(ctx); _menuController.reverse(); try { await FirebaseAuth.instance.signOut(); } catch (_) {} }, icon: const Icon(Icons.logout), label: const Text('Déconnexion'), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) => _menuController.reverse());
  }

  void _listenUnreadTotals() {
    final uid = currentUser?.uid;
    if (uid == null) return;
    _unreadSub = FirebaseFirestore.instance.collection('chats')
      .where('participants', arrayContains: uid)
      .snapshots()
      .listen((snap) {
        if (!mounted) return;
        int total = 0;
        for (var doc in snap.docs) {
          Map data = doc.data() as Map? ?? {};
          Map unread = (data['unreadCounts'] is Map) ? data['unreadCounts'] : {};
          total += (unread[uid] ?? 0) as int;
        }
        if (total > _prevTotalUnread) {
          NotificationService.showNotification('Nouveau message', "Vous avez ${total - _prevTotalUnread} nouveau(x) message(s)");
        }
        setState(() { _prevTotalUnread = total; _totalUnread = total; });
      });
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

  // --- LOGIQUE DE RECHERCHE CORRIGÉE ---

  void _showNewChatDialog() {
    String searchEmail = "";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 500),
        tween: Tween(begin: 0.0, end: 1.0),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Opacity(
            // Le .clamp(0.0, 1.0) empêche l'erreur d'assertion
            opacity: value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 80 * (1 - value)),
              child: child,
            ),
          );
        },
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: primaryDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 45, height: 5, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10))),
              Padding(
                padding: const EdgeInsets.all(25),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  onChanged: (val) => searchEmail = val.trim(),
                  onSubmitted: (val) => _performEmailSearch(val),
                  decoration: InputDecoration(
                    hintText: "Saisissez l'email exact...",
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
                    prefixIcon: const Icon(Icons.alternate_email, color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.03),
                    contentPadding: const EdgeInsets.symmetric(vertical: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: tgAccent.withOpacity(0.1), shape: BoxShape.circle),
                        child: Icon(Icons.arrow_forward_ios_rounded, color: tgAccent, size: 16),
                      ),
                      onPressed: () => _performEmailSearch(searchEmail),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                child: Align(alignment: Alignment.centerLeft, child: Text("CONTACTS RÉCENTS", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: currentUser?.uid).orderBy('lastMessageTime', descending: true).limit(10).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) return const Center(child: Text("Lancez votre première discussion", style: TextStyle(color: Colors.white24)));
                    
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final chat = docs[index].data() as Map<String, dynamic>?;
                        if (chat == null) return const SizedBox();
                        String otherId = (chat['participants'] as List).firstWhere((id) => id != currentUser?.uid, orElse: () => "");
                        if (otherId.isEmpty) return const SizedBox();
                        Map types = (chat['userTypes'] is Map) ? chat['userTypes'] : {};
                        String col = types[otherId] ?? 'classic_users';
                        
                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection(col).doc(otherId).get(),
                          builder: (context, userSnap) {
                            if (!userSnap.hasData || !userSnap.data!.exists) return const SizedBox();
                            var uData = userSnap.data!.data() as Map<String, dynamic>?;
                            String name = UserUtils.formatName(uData);
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                              leading: CircleAvatar(radius: 24, backgroundColor: Colors.white.withOpacity(0.05), child: Text(name.isNotEmpty ? name[0].toUpperCase() : "?", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                              title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                              subtitle: Text(uData?['email'] ?? "", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                              onTap: () {
                                Navigator.pop(context);
                                _startChatWithUser(otherId, name, col);
                              },
                            );
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
      ),
    );
  }

  void _performEmailSearch(String email) async {
    if (email.isEmpty) return;
    if (currentUser != null && email.toLowerCase() == currentUser!.email?.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Action impossible sur votre propre compte")));
      return;
    }

    List<String> collections = ['classic_users', 'pro_users', 'enterprise_users'];
    for (String col in collections) {
      try {
        var res = await FirebaseFirestore.instance.collection(col).where('email', isEqualTo: email).limit(1).get();
        if (res.docs.isNotEmpty) {
          var doc = res.docs.first;
          if (mounted) {
            Navigator.pop(context);
            _startChatWithUser(doc.id, UserUtils.formatName(doc.data()), col);
          }
          return;
        }
      } catch (e) { debugPrint("Search Error: $e"); }
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Email non trouvé")));
  }

  void _startChatWithUser(String targetUid, String targetName, String targetCol) async {
    if (currentUser == null) return;
    var existing = await FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: currentUser!.uid).get();
    String? cid;
    for (var d in existing.docs) { 
      List p = d['participants'] ?? [];
      if (p.contains(targetUid)) { cid = d.id; break; } 
    }

    if (cid == null) {
      var newChat = await FirebaseFirestore.instance.collection('chats').add({
        'participants': [currentUser!.uid, targetUid],
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCounts': {currentUser!.uid: 0, targetUid: 0},
        'userTypes': {currentUser!.uid: 'classic_users', targetUid: targetCol},
        'typing': {currentUser!.uid: false, targetUid: false},
      });
      cid = newChat.id;
    }
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (context) => ChatDetailPage(chatId: cid!, chatName: targetName)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: primaryDark,
      onDrawerChanged: (isOpen) {
        if (isOpen) _menuController.forward(); else _menuController.reverse();
      },
      appBar: AppBar(
        backgroundColor: primaryDark,
        elevation: 0,
        leading: IconButton(
          icon: AnimatedIcon(icon: AnimatedIcons.menu_arrow, progress: _menuController),
          color: Colors.white54,
          onPressed: () {
            if (_menuController.isCompleted) _menuController.reverse();
            _showModernMenu();
          },
        ),
        title: _isSearchActive ? _buildSearchField() : const Text('Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (!_isSearchActive)
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white54),
              onPressed: () {
                setState(() => _isSearchActive = true);
                Future.delayed(const Duration(milliseconds: 50), () => _searchFocus.requestFocus());
              },
            ),
          if (_isSearchActive)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () {
                setState(() {
                  _isSearchActive = false;
                  _searchController.clear();
                });
                FocusScope.of(context).unfocus();
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          StoryBar(currentUserId: currentUser?.uid ?? "", onAddStoryTap: _handleCameraAction),
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

        if (selectedCategory == "PRO") {
          docs = docs.where((doc) {
            Map? types = (doc.data() as Map?)?['userTypes'] as Map?;
            return types?.values.contains("pro_users") ?? false;
          }).toList();
        } else if (selectedCategory == "ENTERPRISE") {
          docs = docs.where((doc) {
            Map? types = (doc.data() as Map?)?['userTypes'] as Map?;
            return types?.values.contains("enterprise_users") ?? false;
          }).toList();
        } else if (selectedCategory == "NON LUS") {
          docs = docs.where((doc) {
            Map? unread = (doc.data() as Map?)?['unreadCounts'] as Map?;
            return (unread?[currentUser?.uid] ?? 0) > 0;
          }).toList();
        }

        if (docs.isEmpty) return const Center(child: Text("Aucune discussion", style: TextStyle(color: Colors.white38)));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final chat = docs[index].data() as Map<String, dynamic>?;
            if (chat == null) return const SizedBox();
            final String docId = docs[index].id;
            String otherUserId = (chat['participants'] as List).firstWhere((id) => id != currentUser?.uid, orElse: () => "");
            if (otherUserId.isEmpty) return const SizedBox();
            Map userTypes = (chat['userTypes'] is Map) ? chat['userTypes'] : {};
            String collection = userTypes[otherUserId] ?? 'classic_users';

            return Dismissible(
              key: Key(docId),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => FirebaseFirestore.instance.collection('chats').doc(docId).delete(),
              background: Container(color: Colors.redAccent, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection(collection).doc(otherUserId).snapshots(),
                builder: (context, userSnap) {
                  String name = "Utilisateur";
                  bool isOnline = false, isCert = false;
                  if (userSnap.hasData && userSnap.data!.exists) {
                    var ud = userSnap.data!.data() as Map<String, dynamic>;
                    name = UserUtils.formatName(ud);
                    isOnline = ud['isOnline'] ?? false;
                    isCert = ud['isCertified'] ?? false;
                  }
                  Map typing = (chat['typing'] is Map) ? chat['typing'] : {};
                  Map actions = (chat['userActions'] is Map) ? chat['userActions'] : {};
                  bool isTyping = typing[otherUserId] ?? false;
                  String subtitleText = (chat['lastMessage'] ?? 'Nouvelle discussion');
                  if (actions[otherUserId] == 'recording') subtitleText = 'enregistrement audio...';
                  else if (isTyping) subtitleText = 'en train d\'écrire...';

                  return ListTile(
                    onTap: () async {
                      ModernDashboardGlobals.navBarVisible.value = false;
                      await Navigator.push(context, MaterialPageRoute(builder: (context) => ChatDetailPage(chatId: docId, chatName: name)));
                      ModernDashboardGlobals.navBarVisible.value = true;
                    },
                    leading: Stack(
                      children: [
                        const CircleAvatar(radius: 26, backgroundColor: Color(0xFF2C3E50), child: Icon(Icons.person, color: Colors.white54)),
                        if (isOnline) Positioned(right: 1, bottom: 1, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.all(color: primaryDark, width: 2)))),
                      ],
                    ),
                    title: Row(
                      children: [
                        Flexible(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        if (isCert) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified, color: Colors.blue, size: 16)),
                        if (collection == "pro_users") const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.verified, color: Colors.orange, size: 16)),
                        if (collection == "enterprise_users") const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.stars, color: Colors.greenAccent, size: 16)),
                      ],
                    ),
                    subtitle: Text(subtitleText, style: TextStyle(color: (subtitleText == 'en train d\'écrire...' || subtitleText == 'enregistrement audio...') ? tgAccent : Colors.white54, fontWeight: (subtitleText == 'en train d\'écrire...' || subtitleText == 'enregistrement audio...') ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    if (chat['lastMessageTime'] != null) {
      try { time = timeago.format((chat['lastMessageTime'] as Timestamp).toDate(), locale: 'fr'); } catch (e) { time = ""; }
    }
    Map unread = (chat['unreadCounts'] is Map) ? chat['unreadCounts'] : {};
    int myUnread = unread[currentUser?.uid] ?? 0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(time, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        if (myUnread > 0)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: tgAccent, shape: BoxShape.circle),
            child: Text("$myUnread", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  void _showInviteDialog() {
    final inviteLink = 'https://lualaba.app/invite';
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F171A),
          title: const Text('Inviter des amis', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Partagez ce lien pour inviter vos amis :', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              SelectableText(inviteLink, style: const TextStyle(color: Colors.white)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: inviteLink));
                Navigator.pop(ctx);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié dans le presse-papier')));
              },
              child: const Text('Copier', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer', style: TextStyle(color: Colors.white70)),
            ),
          ],
        );
      },
    );
  }

  void _showCreateGroupDialog() async {
    if (!await FlutterContacts.requestPermission()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission contacts refusée')));
      return;
    }
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    List<int> selected = [];
    String groupName = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(color: primaryDark, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Container(width: 45, height: 5, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(hintText: 'Nom du groupe', hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                    onChanged: (v) => setState(() => groupName = v.trim()),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (c, i) {
                      final ct = contacts[i];
                      final hasEmail = ct.emails.isNotEmpty;
                      return CheckboxListTile(
                        value: selected.contains(i),
                        onChanged: (v) => setState(() { if (v == true) selected.add(i); else selected.remove(i); }),
                        title: Text(ct.displayName, style: const TextStyle(color: Colors.white)),
                        subtitle: hasEmail ? Text(ct.emails.first.address, style: const TextStyle(color: Colors.white60)) : null,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler', style: TextStyle(color: Colors.white70)))),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (currentUser == null) return;
                        // resolve selected contacts to app user ids via email
                        List<String> participantIds = [currentUser!.uid];
                        for (var idx in selected) {
                          final ct = contacts[idx];
                          if (ct.emails.isEmpty) continue;
                          final String? email = ct.emails.first.address;
                          if (email == null || email.isEmpty) continue;
                          for (var col in ['classic_users', 'pro_users', 'enterprise_users']) {
                            final res = await FirebaseFirestore.instance.collection(col).where('email', isEqualTo: email).limit(1).get();
                            if (res.docs.isNotEmpty) { participantIds.add(res.docs.first.id); break; }
                          }
                        }
                        if (participantIds.length < 2) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sélectionnez au moins 1 contact présent dans l\'application')));
                          return;
                        }
                        // create group chat
                        final newChat = await FirebaseFirestore.instance.collection('chats').add({
                          'participants': participantIds,
                          'lastMessage': '',
                          'lastMessageTime': FieldValue.serverTimestamp(),
                          'unreadCounts': Map.fromEntries(participantIds.map((id) => MapEntry(id, 0))),
                          'isGroup': true,
                          'groupName': groupName.isNotEmpty ? groupName : 'Groupe',
                          'userTypes': Map.fromEntries(participantIds.map((p) => MapEntry(p, 'classic_users'))),
                          'typing': Map.fromEntries(participantIds.map((p) => MapEntry(p, false))),
                        });
                        Navigator.pop(ctx);
                        if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ChatDetailPage(chatId: newChat.id, chatName: groupName.isNotEmpty ? groupName : 'Groupe')));
                      },
                      child: const Text('Créer'),
                    ),
                  ],
                ),
              ],
            ),
          );
        });
      },
    );
  }

  void _showSavedMessages() async {
    if (currentUser == null) return;
    final snap = await FirebaseFirestore.instance.collection('saved_messages').where('userId', isEqualTo: currentUser!.uid).orderBy('createdAt', descending: true).get();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F171A),
      builder: (_) {
        return Material(
          color: Colors.transparent,
          child: SizedBox(
            height: 520,
            child: snap.docs.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Aucun message sauvegardé', style: TextStyle(color: Colors.white38))))
              : ListView.builder(
                itemCount: snap.docs.length,
                itemBuilder: (c, i) {
                  final d = snap.docs[i];
                  final data = d.data();
                  return ListTile(
                    title: Text(data['text'] ?? '', style: const TextStyle(color: Colors.white)),
                    subtitle: data['sourceName'] != null ? Text(data['sourceName'], style: const TextStyle(color: Colors.white60)) : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async { await d.reference.delete(); if (mounted) { Navigator.pop(context); _showSavedMessages(); } },
                    ),
                  );
                },
              ),
          ),
        );
      },
    );
  }
}
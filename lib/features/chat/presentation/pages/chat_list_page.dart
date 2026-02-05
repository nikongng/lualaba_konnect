import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:convert';
import 'call_webrtc_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:lualaba_konnect/core/supabase_service.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../../../auth/presentation/pages/ModernDashboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../../auth/presentation/widgets/story_widgets.dart';
import '../../../auth/presentation/widgets/animated_fab.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/chat_detail_page.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/group_chat_detail_page.dart';
import 'user_utils.dart';

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
    _initAudio();
  }
  
  Future<void> _showProfileMenu() async {
    String displayName = currentUser?.displayName ?? 'Utilisateur';
    String? photoUrl = currentUser?.photoURL;
    try {
      final prefs = await SharedPreferences.getInstance();
      String? userCollection = prefs.getString('user_collection');
      DocumentSnapshot? doc;
      if (userCollection != null && currentUser != null) {
        final d = await FirebaseFirestore.instance.collection(userCollection).doc(currentUser!.uid).get();
        if (d.exists) doc = d;
      }
      if ((doc == null || !doc.exists) && currentUser != null) {
        for (var c in ['classic_users', 'pro_users', 'enterprise_users']) {
          final d = await FirebaseFirestore.instance.collection(c).doc(currentUser!.uid).get();
          if (d.exists) { doc = d; break; }
        }
      }
      if (doc != null && doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          displayName = UserUtils.formatName(data);
          photoUrl = (data['photoUrl'] ?? data['photo'] ?? photoUrl) as String?;
        }
      }
    } catch (e) { debugPrint('Profile load err: $e'); }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F171A),
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF0F171A), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
            child: Wrap(children: [
              Row(children: [
                CircleAvatar(radius: 28, backgroundColor: const Color(0xFF2C3E50), backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? CachedNetworkImageProvider(photoUrl) as ImageProvider : null, child: (photoUrl == null || photoUrl.isEmpty) ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white54)) : null),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(currentUser?.email ?? '', style: const TextStyle(color: Colors.white60, fontSize: 12))])),
                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
              ]),
              const SizedBox(height: 12),
              ListTile(leading: const Icon(Icons.edit, color: Colors.white70), title: const Text('Modifier bio / nom', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(ctx); _showEditProfileDialog(); }),
              ListTile(leading: const Icon(Icons.photo_camera, color: Colors.white70), title: const Text('Changer la photo', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(ctx); _changeProfilePhoto(); }),
              ListTile(leading: const Icon(Icons.lock, color: Colors.white70), title: const Text('Sécurité', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(ctx); _showSecurityMenu(); }),
              ListTile(leading: const Icon(Icons.privacy_tip, color: Colors.white70), title: const Text('Confidentialité', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(ctx); _showPrivacyMenu(); }),
              ListTile(leading: const Icon(Icons.chat_bubble_outline, color: Colors.white70), title: const Text('Discussion (thème)', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(ctx); _showChatSettingsMenu(); }),
              const SizedBox(height: 8),
            ]),
          ),
        );
      }
    );
  }

  Future<void> _showEditProfileDialog() async {
    String newName = currentUser?.displayName ?? '';
    String newBio = '';
    await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF0F171A), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Modifier profil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(decoration: const InputDecoration(hintText: 'Nom d\'utilisateur', hintStyle: TextStyle(color: Colors.white38)), style: const TextStyle(color: Colors.white), onChanged: (v) => newName = v, controller: TextEditingController(text: newName)),
            const SizedBox(height: 8),
            TextField(decoration: const InputDecoration(hintText: 'Bio', hintStyle: TextStyle(color: Colors.white38)), style: const TextStyle(color: Colors.white), onChanged: (v) => newBio = v),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler'))), const SizedBox(width: 12), ElevatedButton(onPressed: () async {
              Navigator.pop(ctx);
              if (currentUser == null) return;
              try {
                final prefs = await SharedPreferences.getInstance();
                final col = prefs.getString('user_collection');
                if (col != null) {
                  await FirebaseFirestore.instance.collection(col).doc(currentUser!.uid).set({'displayName': newName, 'bio': newBio}, SetOptions(merge: true));
                  try {
                    await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
                    if (mounted) setState(() {});
                  } catch (e) {
                    debugPrint('Auth profile update failed: $e');
                  }
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil mis à jour')));
                } else {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de localiser la collection utilisateur')));
                }
              } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'))); }
            }, child: const Text('Enregistrer'))])
          ]),
        ),
      );
    });
  }

  Future<void> _showSecurityMenu() async {
    // Load current user settings
    final prefs = await SharedPreferences.getInstance();
    String? userCollection = prefs.getString('user_collection');
    Map<String, dynamic> userData = {};
    if (userCollection != null && currentUser != null) {
      final doc = await FirebaseFirestore.instance.collection(userCollection).doc(currentUser!.uid).get();
      if (doc.exists) userData = doc.data() ?? {};
    }

    bool autoDelete = (userData['autoDeleteMessages'] ?? false) as bool;

    await showModalBottomSheet(context: context, backgroundColor: const Color(0xFF0F171A), builder: (ctx) {
      return StatefulBuilder(builder: (mCtx, setStateModal) {
        return Container(
          padding: const EdgeInsets.all(12),
          child: Wrap(children: [
            const ListTile(title: Text('Sécurité', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            SwitchListTile(value: autoDelete, onChanged: (v) async {
              setStateModal(() => autoDelete = v);
              if (currentUser == null || userCollection == null) return;
              try {
                await FirebaseFirestore.instance.collection(userCollection).doc(currentUser!.uid).set({'autoDeleteMessages': v}, SetOptions(merge: true));
              } catch (e) { debugPrint('Failed save autoDelete: $e'); }
            }, title: const Text('Autosuppression des messages', style: TextStyle(color: Colors.white))),
            ListTile(title: const Text('Utilisateurs bloqués', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(ctx); _showBlockedUsers(); }),
            ListTile(title: const Text('Appareils connectés', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(ctx); _showConnectedDevices(userData); }),
            const SizedBox(height: 8),
          ]),
        );
      });
    });
  }

  Future<void> _showBlockedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final col = prefs.getString('user_collection');
    if (col == null || currentUser == null) return;
    final docRef = FirebaseFirestore.instance.collection(col).doc(currentUser!.uid);
    final doc = await docRef.get();
    final data = doc.exists ? (doc.data() ?? {}) : {};
    final blocked = List<String>.from(data['blockedUsers'] ?? []);

    await showModalBottomSheet(context: context, backgroundColor: const Color(0xFF0F171A), builder: (ctx) {
      return Container(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Utilisateurs bloqués', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          if (blocked.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Aucun utilisateur bloqué', style: TextStyle(color: Colors.white38))),
          ...blocked.map((b) => FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('classic_users').doc(b).get(),
            builder: (ctx, snap) {
              final name = (snap.hasData && snap.data!.exists) ? UserUtils.formatName(snap.data!.data() as Map<String, dynamic>?) : b;
              return ListTile(
                title: Text(name, style: const TextStyle(color: Colors.white)),
                trailing: TextButton(onPressed: () async {
                  try {
                    await docRef.update({'blockedUsers': FieldValue.arrayRemove([b])});
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Utilisateur débloqué')));
                    Navigator.pop(ctx);
                    _showBlockedUsers();
                  } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'))); }
                }, child: const Text('Débloquer')),
              );
            }
          )).toList(),
        ]),
      );
    });
  }

  void _showConnectedDevices(Map<String, dynamic> userData) {
    final devices = (userData['devices'] is List) ? List<String>.from(userData['devices']) : <String>[];
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF0F171A), builder: (ctx) {
      return Container(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Appareils connectés', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          if (devices.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Aucun appareil connecté', style: TextStyle(color: Colors.white38))),
          ...devices.map((d) => ListTile(title: Text(d, style: const TextStyle(color: Colors.white)), subtitle: const Text('Dernière activité', style: TextStyle(color: Colors.white38))))
        ]),
      );
    });
  }

  Future<void> _changeProfilePhoto() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked == null) return;
      String? url;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        url = await _uploadProfileImage(null, bytes);
      } else {
        final file = File(picked.path);
        url = await _uploadProfileImage(file, null);
      }
      if (url == null) return;
      // update auth and firestore
      await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
      final prefs = await SharedPreferences.getInstance();
      final col = prefs.getString('user_collection');
      if (col != null && FirebaseAuth.instance.currentUser != null) {
        await FirebaseFirestore.instance.collection(col).doc(FirebaseAuth.instance.currentUser!.uid).set({'photoUrl': url}, SetOptions(merge: true));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo de profil mise à jour')));
    } catch (e) {
      debugPrint('Change photo err: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<String?> _uploadProfileImage(File? file, Uint8List? bytes) async {
    try {
      final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      String url;
      if (SupabaseService.isInitialized) {
        // Prefer Supabase bucket 'profiles'
        final bucket = 'profiles';
        try {
          if (file != null) {
            await supabase.Supabase.instance.client.storage.from(bucket).upload(fileName, file);
            final pub = supabase.Supabase.instance.client.storage.from(bucket).getPublicUrl(fileName);
            url = pub.toString();
          } else if (bytes != null) {
            // Uploading raw bytes to Supabase from web may not be supported by this client API.
            // Return null so caller can handle or show an error.
            debugPrint('Supabase upload of bytes not supported in this build - upload skipped');
            return null;
          } else {
            return null;
          }
        } catch (e) {
          debugPrint('Supabase upload failed: $e');
          return null;
        }
      } else {
        debugPrint('No Supabase configured; profile upload not supported');
        return null;
      }
      return url;
    } catch (e) {
      debugPrint('Upload profile err: $e');
      return null;
    }
  }

  Future<void> _showPrivacyMenu() async {
    final prefs = await SharedPreferences.getInstance();
    bool showToContacts = prefs.getBool('show_phone_to_contacts') ?? true;
    bool showOnline = prefs.getBool('show_online_presence') ?? true;
    bool showProfilePhotos = prefs.getBool('show_profile_photos') ?? true;
    bool showBio = prefs.getBool('show_bio') ?? true;
    bool showStatus = prefs.getBool('show_status') ?? true;

    await showModalBottomSheet(context: context, backgroundColor: const Color(0xFF0F171A), builder: (ctx) {
      return StatefulBuilder(builder: (mCtx, setStateModal) {
        return Container(
          padding: const EdgeInsets.all(12),
          child: Wrap(children: [
            const ListTile(title: Text('Confidentialité', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            SwitchListTile(value: showToContacts, onChanged: (v) async { setStateModal(() => showToContacts = v); await prefs.setBool('show_phone_to_contacts', v); }, title: const Text('Visible pour les contacts', style: TextStyle(color: Colors.white))),
            SwitchListTile(value: showOnline, onChanged: (v) async { setStateModal(() => showOnline = v); await prefs.setBool('show_online_presence', v); }, title: const Text('Présence en ligne', style: TextStyle(color: Colors.white))),
            SwitchListTile(value: showProfilePhotos, onChanged: (v) async { setStateModal(() => showProfilePhotos = v); await prefs.setBool('show_profile_photos', v); }, title: const Text('Photos de profil', style: TextStyle(color: Colors.white))),
            SwitchListTile(value: showBio, onChanged: (v) async { setStateModal(() => showBio = v); await prefs.setBool('show_bio', v); }, title: const Text('Bio', style: TextStyle(color: Colors.white))),
            SwitchListTile(value: showStatus, onChanged: (v) async { setStateModal(() => showStatus = v); await prefs.setBool('show_status', v); }, title: const Text('Statut', style: TextStyle(color: Colors.white))),
            const SizedBox(height: 8),
          ]),
        );
      });
    });
  }

  Future<void> _showChatSettingsMenu() async {
    final prefs = await SharedPreferences.getInstance();
    String theme = prefs.getString('chat_theme') ?? 'system';
    await showModalBottomSheet(context: context, backgroundColor: const Color(0xFF0F171A), builder: (ctx) {
      return StatefulBuilder(builder: (mCtx, setStateModal) {
        return Container(
          padding: const EdgeInsets.all(12),
          child: Wrap(children: [
            const ListTile(title: Text('Thème discussion', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            RadioListTile<String>(value: 'system', groupValue: theme, onChanged: (v) async { if (v != null) { setStateModal(() => theme = v); await prefs.setString('chat_theme', v); } }, title: const Text('Système', style: TextStyle(color: Colors.white))),
            RadioListTile<String>(value: 'light', groupValue: theme, onChanged: (v) async { if (v != null) { setStateModal(() => theme = v); await prefs.setString('chat_theme', v); } }, title: const Text('Clair', style: TextStyle(color: Colors.white))),
            RadioListTile<String>(value: 'dark', groupValue: theme, onChanged: (v) async { if (v != null) { setStateModal(() => theme = v); await prefs.setString('chat_theme', v); } }, title: const Text('Sombre', style: TextStyle(color: Colors.white))),
          ]),
        );
      });
    });
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



  // Audio recording/player
  final FlutterSoundRecorder _soundRecorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _soundPlayer = FlutterSoundPlayer();
  bool _recorderInitialized = false;
  bool _playerInitialized = false;
  bool _isRecordingAudio = false;
  // Upload / preview state
  bool _isUploading = false;
  double? _uploadProgress;
  VideoPlayerController? _videoController;

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
                          Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => CallWebRTCPage(
      callId: doc.id,
      otherId: callerId,
      isCaller: false,
      name: callerName,
      avatarLetter: callerName.isNotEmpty ? callerName[0].toUpperCase() : '?', // <-- ici !
    ),
  ),
);

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
    if (_recorderInitialized) _soundRecorder.closeRecorder();
    if (_playerInitialized) _soundPlayer.closePlayer();
    super.dispose();
  }

  Future<void> _archiveChat(String chatId) async {
    if (currentUser == null) return;
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
        'archivedBy': FieldValue.arrayUnion([currentUser!.uid])
      }, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Discussion archivée')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'))); }
  }

  Future<void> _blockUser(String otherId) async {
    if (currentUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final col = prefs.getString('user_collection');
      if (col == null) return;
      final ref = FirebaseFirestore.instance.collection(col).doc(currentUser!.uid);
      await ref.set({'blockedUsers': FieldValue.arrayUnion([otherId])}, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Utilisateur bloqué')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'))); }
  }

  Future<void> _toggleMuteChat(String chatId) async {
    if (currentUser == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('chats').doc(chatId);
      final snap = await ref.get();
      final data = snap.exists ? (snap.data() ?? {}) : {};
      Map<String, dynamic> muted = (data['muted'] is Map) ? Map<String, dynamic>.from(data['muted']) : {};
      final cur = muted[currentUser!.uid] == true;
      muted[currentUser!.uid] = !cur;
      await ref.set({'muted': muted}, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(!cur ? 'Discussion mise en silencieux' : 'Mode silencieux désactivé')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'))); }
  }

  Future<void> _showContactInfoFromList(String otherId) async {
    try {
      DocumentSnapshot? doc;
      for (var c in ['classic_users', 'pro_users', 'enterprise_users']) {
        final d = await FirebaseFirestore.instance.collection(c).doc(otherId).get();
        if (d.exists) { doc = d; break; }
      }
      if (doc == null || !doc.exists) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact introuvable')));
        return;
      }
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final displayName = UserUtils.formatName(data);
      final email = data['email'] ?? '';
      showModalBottomSheet(context: context, backgroundColor: const Color(0xFF0F171A), builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: CircleAvatar(backgroundImage: (data['photoUrl'] ?? data['photo'])?.isNotEmpty == true ? CachedNetworkImageProvider((data['photoUrl'] ?? data['photo']) as String) as ImageProvider : null), title: Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), subtitle: Text(email, style: const TextStyle(color: Colors.white60))),
            Row(children: [Expanded(child: OutlinedButton(onPressed: () { Navigator.pop(ctx); _startChatWithUser(otherId, displayName, 'auto'); }, child: const Text('Message'))), const SizedBox(width: 8), OutlinedButton(onPressed: () { Navigator.pop(ctx); }, child: const Text('Fermer'))]),
          ]),
        );
      });
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'))); }
  }

  Future<void> _initAudio() async {
    try {
      await Permission.microphone.request();
    } catch (e) {}
    try {
      await _soundRecorder.openRecorder();
      _recorderInitialized = true;
    } catch (e) {
      debugPrint('Recorder init failed: $e');
    }
    try {
      await _soundPlayer.openPlayer();
      _playerInitialized = true;
    } catch (e) {
      debugPrint('Player init failed: $e');
    }
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

  Future<void> _showModernMenu() async {
    String displayName = currentUser?.displayName ?? 'Utilisateur';
    String? photoUrl = currentUser?.photoURL;
    try {
      final prefs = await SharedPreferences.getInstance();
      String? userCollection = prefs.getString('user_collection');
      DocumentSnapshot? doc;
      if (userCollection != null && currentUser != null) {
        final d = await FirebaseFirestore.instance.collection(userCollection).doc(currentUser!.uid).get();
        if (d.exists) doc = d;
      }
      if ((doc == null || !doc.exists) && currentUser != null) {
        for (var c in ['classic_users', 'pro_users', 'enterprise_users']) {
          final d = await FirebaseFirestore.instance.collection(c).doc(currentUser!.uid).get();
          if (d.exists) { doc = d; break; }
        }
      }
      if (doc != null && doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          displayName = UserUtils.formatName(data);
          photoUrl = (data['photoUrl'] ?? data['photo'] ?? photoUrl) as String?;
        }
      }
    } catch (e) {
      debugPrint('Menu user load err: $e');
    }

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
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: const Color(0xFF2C3E50),
                              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? CachedNetworkImageProvider(photoUrl) as ImageProvider : null,
                              child: (photoUrl == null || photoUrl.isEmpty) ? Text((displayName.isNotEmpty ? displayName[0].toUpperCase() : '?'), style: const TextStyle(color: Colors.white54)) : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                              _menuTile(Icons.account_circle_outlined, 'Mon profil', () { Navigator.pop(ctx); _menuController.reverse(); _showProfileMenu(); }),
                              _menuTile(Icons.group_add, 'Nouveau groupe', () { Navigator.pop(ctx); _menuController.reverse(); _showCreateGroupDialog(); }),
                              _menuTile(Icons.contacts, 'Contacts', () async {
                                Navigator.pop(ctx);
                                _menuController.reverse();
                                if (kIsWeb) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Accès aux contacts non supporté sur le web')));
                                  return;
                                }
                                try {
                                  if (await FlutterContacts.requestPermission()) {
                                    final list = await FlutterContacts.getContacts(withProperties: true);
                                    // Resolve to app users
                                    final List<Map<String, dynamic>> appUsers = [];
                                    for (final contact in list) {
                                      if (contact.emails.isEmpty) continue;
                                      final email = contact.emails.first.address;
                                      if (email.isEmpty) continue;
                                      for (var col in ['classic_users', 'pro_users', 'enterprise_users']) {
                                        final res = await FirebaseFirestore.instance.collection(col).where('email', isEqualTo: email).limit(1).get();
                                        if (res.docs.isNotEmpty) {
                                          final d = res.docs.first;
                                          final data = d.data();
                                          appUsers.add({
                                            'uid': d.id,
                                            'name': UserUtils.formatName(data) ,
                                            'email': email,
                                            'photo': data['photoUrl'] ?? data['photo'] ?? '',
                                          });
                                          break;
                                        }
                                      }
                                    }

                                    final List<Map<String, dynamic>> visibleAppUsers = List.from(appUsers);
                                    final TextEditingController contactsSearchCtrl = TextEditingController();
                                    showModalBottomSheet(
                                      context: context,
                                      backgroundColor: const Color(0xFF0F171A),
                                      builder: (_) {
                                        return StatefulBuilder(builder: (mCtx, setStateModal) {
                                          return Material(
                                            color: Colors.transparent,
                                            child: Container(
                                              height: 520,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(color: const Color(0xFF0F171A)),
                                              child: Column(
                                                children: [
                                                  Row(children: [
                                                    Expanded(
                                                      child: TextField(
                                                        controller: contactsSearchCtrl,
                                                        style: const TextStyle(color: Colors.white),
                                                        decoration: InputDecoration(
                                                          prefixIcon: const Icon(Icons.search, color: Colors.white54),
                                                          hintText: 'Rechercher un contact...',
                                                          hintStyle: const TextStyle(color: Colors.white38),
                                                          filled: true,
                                                          fillColor: Colors.white10,
                                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                                        ),
                                                        onChanged: (q) => setStateModal(() {
                                                          final s = q.trim().toLowerCase();
                                                          if (s.isEmpty) {
                                                            visibleAppUsers.clear();
                                                            visibleAppUsers.addAll(appUsers);
                                                          } else {
                                                            visibleAppUsers.clear();
                                                            visibleAppUsers.addAll(appUsers.where((u) {
                                                              final name = (u['name'] as String? ?? '').toLowerCase();
                                                              final email = (u['email'] as String? ?? '').toLowerCase();
                                                              return name.contains(s) || email.contains(s);
                                                            }));
                                                          }
                                                        }),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    IconButton(
                                                      tooltip: 'Inviter',
                                                      icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
                                                      onPressed: () async {
                                                        final inviteLink = 'https://lualaba.app/invite';
                                                        await Clipboard.setData(ClipboardData(text: inviteLink));
                                                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien d\'invitation copié')));
                                                      },
                                                    ),
                                                  ]),
                                                  const SizedBox(height: 8),
                                                  Expanded(
                                                    child: visibleAppUsers.isEmpty
                                                        ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Aucun contact de l\'application trouvé', style: TextStyle(color: Colors.white38))))
                                                        : ListView.builder(
                                                            itemCount: visibleAppUsers.length,
                                                            itemBuilder: (c, i) {
                                                              final u = visibleAppUsers[i];
                                                              return ListTile(
                                                                title: Text(u['name'] ?? '', style: const TextStyle(color: Colors.white)),
                                                                subtitle: u['email'] != null ? Text(u['email'], style: const TextStyle(color: Colors.white60)) : null,
                                                                leading: CircleAvatar(
                                                                  backgroundColor: Colors.white10,
                                                                  backgroundImage: (u['photo'] as String?)?.isNotEmpty == true ? CachedNetworkImageProvider(u['photo']) as ImageProvider : null,
                                                                  child: (u['photo'] as String?)?.isNotEmpty == true ? null : Text((u['name'] as String?)?.isNotEmpty == true ? (u['name'] as String)[0].toUpperCase() : '?'),
                                                                ),
                                                                onTap: () {
                                                                  Navigator.pop(context);
                                                                  _startChatWithUser(u['uid'], u['name'], 'classic_users');
                                                                },
                                                              );
                                                            },
                                                          ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        });
                                      },
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission contacts refusée')));
                                  }
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur contacts: $e')));
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
                                                   Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (_) => CallWebRTCPage(
                                                            callId: callDoc.id,
                                                            otherId: calleeId,
                                                            isCaller: true,
                                                            name: calleeName,
                                                            avatarLetter: calleeName.isNotEmpty ? calleeName[0].toUpperCase() : '?',
                                                          ),
                                                        ),
                                                      );

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
                              _menuTile(Icons.bookmark, 'Messages enregistrés', () { Navigator.pop(ctx); _menuController.reverse(); _showSavedMessages(); }),
                              _menuTile(Icons.person_add_alt_1, 'Inviter des amis', () { Navigator.pop(ctx); _menuController.reverse(); _showInviteDialog(); }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
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
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final prefs = await SharedPreferences.getInstance();
  final collection = prefs.getString('user_collection');

  if (collection == null) return;

  await FirebaseFirestore.instance
      .collection(collection)
      .doc(user.uid)
      .set(
    {
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true), // 🔥 évite tout crash
  );
}


  Future<void> _cleanupOldStories() async {
    final now = DateTime.now();
    final expired = await FirebaseFirestore.instance.collection('stories').where('expiresAt', isLessThan: now).get();
    for (var doc in expired.docs) {
              try {
                String? url = doc.data()['imageUrl'] ?? doc.data()['videoUrl'] ?? doc.data()['audioUrl'];
                if (url != null) {
                  // Try to delete from Supabase bucket 'stories' when URL matches storage public path
                  try {
                    final envBase = const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
                    if (envBase.isNotEmpty) {
                      final base = envBase.replaceAll(RegExp(r'\/\$'), '');
                      final bucket = 'stories';
                      final path = url.replaceFirst('$base/storage/v1/object/public/', '');
                      await supabase.Supabase.instance.client.storage.from(bucket).remove([path]);
                    } else {
                      // fallback: attempt Firebase delete if url is a Firebase Storage URL
                      try { await FirebaseStorage.instance.refFromURL(url).delete(); } catch (_) {}
                    }
                  } catch (e) {
                    debugPrint('Error deleting storage file: $e');
                  }
        }
      } catch (e) { debugPrint("Erreur Story: $e"); }
      await doc.reference.delete();
    }
  }

  Future<void> _handleCameraAction() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null) {
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        await _showImagePreview(bytes: bytes);
      } else {
        await _showImagePreview(file: File(image.path));
      }
    }
  }

  // Nouveau: menu moderne de création de story (texte, audio, enregistrement, vidéo, lien)
  void _showStoryCreationMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(color: primaryDark, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Créer une story', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.95,
                padding: const EdgeInsets.all(8),
                children: [
                  _storyOption(icon: Icons.text_fields, label: 'Texte', onTap: () { Navigator.pop(ctx); _createTextStory(); }),
                  _storyOption(icon: Icons.mic, label: 'Audio (fichier)', onTap: () { Navigator.pop(ctx); _pickAudioFile(); }),
                  _storyOption(icon: Icons.mic_none, label: 'Enregistrer', onTap: () { Navigator.pop(ctx); _recordAudioStory(); }),
                  _storyOption(icon: Icons.videocam, label: 'Vidéo', onTap: () { Navigator.pop(ctx); _createVideoStory(); }),
                  _storyOption(icon: Icons.link, label: 'Lien', onTap: () { Navigator.pop(ctx); _createLinkStory(); }),
                  _storyOption(icon: Icons.camera_alt, label: 'Photo', onTap: () { Navigator.pop(ctx); _handleCameraAction(); }),
                  _storyOption(icon: Icons.photo_library, label: 'Galerie', onTap: () { Navigator.pop(ctx); _pickGalleryImages(); }),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _storyOption({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _createTextStory() async {
    String text = '';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: primaryDark, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Nouvelle story texte', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                maxLines: 6,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(hintText: 'Votre texte...', hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                onChanged: (v) => text = v,
              ),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler'))), const SizedBox(width: 12), ElevatedButton(onPressed: () async {
                if (text.trim().isEmpty) return;
                if (currentUser == null) return;
                Navigator.pop(ctx);
                await FirebaseFirestore.instance.collection('stories').add({
                  'userId': currentUser!.uid,
                  'userName': currentUser!.displayName ?? 'Moi',
                  'text': text.trim(),
                  'createdAt': FieldValue.serverTimestamp(),
                  'expiresAt': DateTime.now().add(const Duration(hours: 24)),
                });
              }, child: const Text('Publier'))])
            ]),
          ),
        );
      }
    );
  }

  Future<void> _pickAudioFile() async {
    // Use FilePicker to pick an audio file and preview before upload
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (res == null || res.files.isEmpty) return;
      final path = res.files.first.path;
      if (path == null) return;
      final file = File(path);
      await _showAudioPreview(file);
    } catch (e) {
      debugPrint('Pick audio error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de la sélection audio')));
    }
  }

  Future<void> _recordAudioStory() async {
    if (!_recorderInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enregistreur non initialisé')));
      return;
    }

    if (_isRecordingAudio) {
      // stop
      try {
        final path = await _soundRecorder.stopRecorder();
        _isRecordingAudio = false;
        if (path != null) {
          final file = File(path);
          await _showAudioPreview(file, isRecorded: true);
        }
      } catch (e) {
        debugPrint('Stop record error: $e');
      }
      setState(() {});
      return;
    }

    // start recording
    try {
      final tmpDir = await getTemporaryDirectory();
      final filePath = '${tmpDir.path}/story_record_${DateTime.now().millisecondsSinceEpoch}.aac';
      await _soundRecorder.startRecorder(toFile: filePath, codec: Codec.aacADTS);
      _isRecordingAudio = true;
      setState(() {});

      // show a small UI to stop recording
      showModalBottomSheet(
        context: context,
        isDismissible: false,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: primaryDark, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Enregistrement en cours', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  if (!_isRecordingAudio) return;
                  try {
                    final path = await _soundRecorder.stopRecorder();
                    _isRecordingAudio = false;
                    Navigator.pop(ctx);
                    if (path != null) await _showAudioPreview(File(path), isRecorded: true);
                  } catch (e) { debugPrint('Stop record error: $e'); }
                  setState(() {});
                },
                icon: const Icon(Icons.stop),
                label: const Text('Arrêter'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              ),
            ]),
          );
        }
      );
    } catch (e) {
      debugPrint('Start record error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de démarrer l\'enregistrement')));
    }
  }

  Future<void> _showAudioPreview(File file, {bool isRecorded = false}) async {
    bool isPlaying = false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: primaryDark, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Prévisualisation audio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(children: [
                IconButton(
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  onPressed: () async {
                    if (!_playerInitialized) return;
                    if (!isPlaying) {
                      await _soundPlayer.startPlayer(fromURI: file.path, codec: Codec.aacADTS, whenFinished: () { setState(() => isPlaying = false); });
                      setState(() => isPlaying = true);
                    } else {
                      await _soundPlayer.pausePlayer();
                      setState(() => isPlaying = false);
                    }
                  },
                ),
                Expanded(child: Text(file.path.split('/').last, style: const TextStyle(color: Colors.white70))),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
                const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (currentUser == null) return;
                        final ext = file.path.split('.').last;
                        final fileName = 'story_audio_${DateTime.now().millisecondsSinceEpoch}.$ext';
                        final url = await _uploadFileWithProgress(file, fileName);
                        if (url != null) {
                          await _saveStoryDoc({'audioUrl': url});
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audio publié')));
                        }
                      },
                      child: const Text('Publier'),
                    ),
              ]),
              const SizedBox(height: 12),
            ]),
          );
        });
      }
    );
    if (_playerInitialized && _soundPlayer.isPlaying) await _soundPlayer.stopPlayer();
  }

  Future<void> _createVideoStory() async {
    final ImagePicker picker = ImagePicker();
    final XFile? video = await picker.pickVideo(source: ImageSource.camera);
    if (video != null) {
      final String vpath = video.path;
      if (kIsWeb) {
        // On web: pas de VideoPlayer.file — upload direct sans aperçu
        try {
          final bytes = await video.readAsBytes();
          final ext = (video.name.split('.').isNotEmpty) ? video.name.split('.').last : 'mp4';
          final fileName = 'story_video_${DateTime.now().millisecondsSinceEpoch}.$ext';
          String? url;
          if (SupabaseService.isInitialized) {
            url = await SupabaseService.uploadBytes(bytes, fileName, 'stories');
          } else {
            final ref = FirebaseStorage.instance.ref().child('stories/$fileName');
            await ref.putData(bytes);
            url = await ref.getDownloadURL();
          }
          await _saveStoryDoc({'videoUrl': url});
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vidéo publiée')));
                } catch (e) {
          debugPrint('upload video web err: $e');
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de l\'upload vidéo')));
        }
              } else {
                  await _showVideoPreview(File(vpath));
              }
    }
  }

  Future<void> _createLinkStory() async {
    String link = '';
    await showDialog(context: context, builder: (ctx) {
      return AlertDialog(
        backgroundColor: primaryDark,
        title: const Text('Ajouter un lien', style: TextStyle(color: Colors.white)),
        content: TextField(style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'https://...'), onChanged: (v) => link = v.trim()),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')), TextButton(onPressed: () async { if (link.isEmpty || currentUser == null) return; Navigator.pop(ctx); await FirebaseFirestore.instance.collection('stories').add({'userId': currentUser!.uid, 'userName': currentUser!.displayName ?? 'Moi', 'link': link, 'createdAt': FieldValue.serverTimestamp(), 'expiresAt': DateTime.now().add(const Duration(hours: 24))}); }, child: const Text('Publier'))],
      );
    });
  }

  Future<void> _pickGalleryImages() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);
      if (res == null || res.files.isEmpty) return;
      for (var f in res.files) {
        if (kIsWeb) {
          final bytes = f.bytes;
          if (bytes != null) await _showImagePreview(bytes: bytes);
        } else {
          if (f.path != null) {
            await _showImagePreview(file: File(f.path!));
          }
        }
      }
    } catch (e) {
      debugPrint('Pick gallery images error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de la sélection d\'images')));
    }
  }

Future<String?> _uploadFileWithProgress(File file, String destName) async {
  try {
    setState(() {
      _isUploading = true;
      _uploadProgress = null;
    });

    final String bucket = 'stories';
    final String path = destName;
    final client = supabase.Supabase.instance.client;

    // Upload vers Supabase avec upsert = true pour écraser si nécessaire
    try {
      await client.storage.from(bucket).upload(path, file);
    } catch (uploadErr) {
      debugPrint('Supabase upload failed: $uploadErr');
      rethrow;
    }

    // Récupération de l'URL publique (supporte différents retours)
    final dynamic publicRes = client.storage.from(bucket).getPublicUrl(path);
    String url;
    if (publicRes is String) {
      url = publicRes;
    } else if (publicRes is Map) {
      url = (publicRes['publicUrl'] ?? publicRes['publicURL'] ?? publicRes['url'] ?? publicRes.toString()).toString();
    } else {
      url = publicRes.toString();
    }

    setState(() {
      _isUploading = false;
      _uploadProgress = 0.0;
    });

    return url;
  } catch (e, st) {
    debugPrint('Upload error (Supabase): $e\n$st');

    setState(() {
      _isUploading = false;
      _uploadProgress = 0.0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Erreur lors de l'upload")),
    );

    return null;
  }
}


Future<void> _saveStoryDoc(Map<String, dynamic> data) async {
  if (currentUser == null) return;

  final Map<String, dynamic> doc = {
    'userId': currentUser!.uid,
    'userName': currentUser!.displayName ?? 'Moi',
    'createdAt': FieldValue.serverTimestamp(),
    'expiresAt': DateTime.now().add(const Duration(hours: 24)),
  };

  doc.addAll(data);

  await FirebaseFirestore.instance
      .collection('stories')
      .add(doc);
  // Mise en cache locale minimale pour affichage immédiat
  try {
    final prefs = await SharedPreferences.getInstance();
    final List<String> cached = prefs.getStringList('cached_stories') ?? [];
    final expires = DateTime.now().add(const Duration(hours: 24));
    final cacheItem = jsonEncode({
      'userId': currentUser!.uid,
      'userName': (doc['userName'] ?? currentUser!.displayName ?? 'Utilisateur'),
      'imageUrl': doc['imageUrl'] ?? doc['videoUrl'] ?? doc['audioUrl'],
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'expiresAt': expires.millisecondsSinceEpoch,
    });
    cached.insert(0, cacheItem);
    // keep only recent 50 items
    if (cached.length > 50) cached.removeRange(50, cached.length);
    await prefs.setStringList('cached_stories', cached);
  } catch (e) {
    debugPrint('Cache story write error: $e');
  }
}


  Future<void> _showImagePreview({File? file, Uint8List? bytes}) async {
    String caption = '';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9 - MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: primaryDark, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: bytes != null
                                  ? Image.memory(bytes, fit: BoxFit.contain)
                              : (file != null
                                  ? Image.file(file, fit: BoxFit.cover)
                                  : const SizedBox.shrink()),
                        ),
                        const SizedBox(height: 12),
                        if (_isUploading) ...[
                          LinearProgressIndicator(value: _uploadProgress, backgroundColor: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.08), valueColor: AlwaysStoppedAnimation<Color>(Theme.of(ctx).colorScheme.primary)),
                          const SizedBox(height: 8),
                        ],
                      ]),
                    ),
                  ),
                  // caption outside scroll area so it remains visible above keyboard
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(hintText: 'Ajouter une légende...', hintStyle: TextStyle(color: Colors.white38), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none)),
                      onChanged: (v) => caption = v,
                    ),
                  ),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler'))),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isUploading ? null : () async {
                        Navigator.pop(ctx);
                        if (currentUser == null) return;
                        String? url;
                        

                        if (bytes != null) {
                          final ext = 'jpg';
                          final fileName = 'story_image_${DateTime.now().millisecondsSinceEpoch}.$ext';
                          try {
                            if (SupabaseService.isInitialized) {
                              url = await SupabaseService.uploadBytes(bytes, fileName, 'stories');
                            } else {
                              final ref = FirebaseStorage.instance.ref().child('stories/$fileName');
                              await ref.putData(bytes);
                              url = await ref.getDownloadURL();
                            }
                          } catch (e) {
                            debugPrint('upload bytes err: $e');
                          }
                        } else if (file != null) {
                          final ext = file.path.split('.').last;
                          final fileName = 'story_image_${DateTime.now().millisecondsSinceEpoch}.$ext';
                          url = await _uploadFileWithProgress(file, fileName);
                        }

                        if (url != null) {
                          await _saveStoryDoc({'imageUrl': url, 'caption': caption});
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image publiée')));
                        }
                      },
                      child: const Text('Publier'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                ]),
              ),
            ),
          );
        });
      }
    );
  }

  Future<void> _showVideoPreview(File file) async {
    String caption = '';
    _videoController?.dispose();
    _videoController = VideoPlayerController.file(file);
    await _videoController!.initialize();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: primaryDark, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(children: [
                        AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: VideoPlayer(_videoController!)),
                        const SizedBox(height: 8),
                        Row(children: [
                          IconButton(icon: Icon(_videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white), onPressed: () async { if (_videoController!.value.isPlaying) {
                            await _videoController!.pause();
                          } else {
                            await _videoController!.play();
                          } setState(() {}); }),
                          Expanded(child: Text(file.path.split('/').last, style: const TextStyle(color: Colors.white70))),
                        ]),
                        const SizedBox(height: 8),
                        if (_isUploading) ...[
                          LinearProgressIndicator(value: _uploadProgress, backgroundColor: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.08), valueColor: AlwaysStoppedAnimation<Color>(Theme.of(ctx).colorScheme.primary)),
                          const SizedBox(height: 8),
                        ],
                      ]),
                    ),
                  ),
                  // caption outside scroll area
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(hintText: 'Ajouter une légende...', hintStyle: TextStyle(color: Colors.white38), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none)),
                      onChanged: (v) => caption = v,
                    ),
                  ),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () { _videoController?.pause(); Navigator.pop(ctx); }, child: const Text('Annuler'))),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isUploading ? null : () async {
                        Navigator.pop(ctx);
                        final ext = file.path.split('.').last;
                        final fileName = 'story_video_${DateTime.now().millisecondsSinceEpoch}.$ext';
                        final url = await _uploadFileWithProgress(file, fileName);
                        if (url != null) {
                          await _saveStoryDoc({'videoUrl': url, 'caption': caption});
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vidéo publiée')));
                        }
                      },
                      child: const Text('Publier'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                ]),
              ),
            ),
          );
        });
      }
    );
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
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
                    if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: Colors.orange));
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) return const Center(child: Text("Lancez votre première discussion", style: TextStyle(color: Colors.white24)));
                    
return ListView.builder(
  padding: const EdgeInsets.symmetric(horizontal: 10),
  itemCount: docs.length,
  itemBuilder: (context, index) {
    final chat = docs[index].data() as Map<String, dynamic>?;
    if (chat == null) return const SizedBox();

    // trouver l'autre participant
    String otherId = (chat['participants'] as List)
        .firstWhere((id) => id != currentUser?.uid, orElse: () => "");
    if (otherId.isEmpty) return const SizedBox();

    // fonction pour chercher l'utilisateur dans les collections
    Future<DocumentSnapshot?> fetchUser() async {
      final collections = ['classic_users', 'enterprise_users', 'pro_users'];
      for (var col in collections) {
        final doc = await FirebaseFirestore.instance.collection(col).doc(otherId).get();
        if (doc.exists) return doc;
      }
      return null;
    }

    return FutureBuilder<DocumentSnapshot?>(
      future: fetchUser(),
      builder: (context, userSnap) {
        if (!userSnap.hasData || userSnap.data == null || !userSnap.data!.exists) {
          return const SizedBox();
        }

        var uData = userSnap.data!.data() as Map<String, dynamic>?;
        String name = UserUtils.formatName(uData);

        final photo = (uData?['photoUrl'] ?? uData?['photo'] ?? uData?['avatar'] ?? '') as String? ?? '';
        final docId = docs[index].id;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white.withOpacity(0.05),
            backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null,
            child: photo.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : "?",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          title: Text(
            name,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            uData?['email'] ?? "",
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          onTap: () {
            Navigator.pop(context);
            _startChatWithUser(otherId, name, 'auto'); // on peut mettre 'auto' car la collection n'a plus d'importance ici
          },
          onLongPress: () {
            showModalBottomSheet(context: context, backgroundColor: const Color(0xFF0F171A), builder: (ctx) {
              return SafeArea(
                child: Wrap(children: [
                  ListTile(leading: const Icon(Icons.archive, color: Colors.white70), title: const Text('Archiver la discussion', style: TextStyle(color: Colors.white)), onTap: () async { Navigator.pop(ctx); await _archiveChat(docId); }),
                  ListTile(leading: const Icon(Icons.person, color: Colors.white70), title: const Text('Afficher le contact', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(ctx); _showContactInfoFromList(otherId); }),
                  ListTile(leading: const Icon(Icons.block, color: Colors.white70), title: const Text('Bloquer', style: TextStyle(color: Colors.white)), onTap: () async { Navigator.pop(ctx); await _blockUser(otherId); }),
                  ListTile(leading: const Icon(Icons.volume_off, color: Colors.white70), title: const Text('Activer mode silencieux', style: TextStyle(color: Colors.white)), onTap: () async { Navigator.pop(ctx); await _toggleMuteChat(docId); }),
                  ListTile(leading: const Icon(Icons.close, color: Colors.white54), title: const Text('Annuler', style: TextStyle(color: Colors.white54)), onTap: () => Navigator.pop(ctx)),
                ]),
              );
            });
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

void _startChatWithUser(String targetUid, String targetName, [String? targetCol]) async {
  if (currentUser == null) return;

  // Si targetCol n'est pas fourni, chercher l'utilisateur dans les 3 collections
  if (targetCol == null || targetCol.isEmpty) {
    final collections = ['classic_users', 'enterprise_users', 'pro_users'];
    for (var col in collections) {
      final doc = await FirebaseFirestore.instance.collection(col).doc(targetUid).get();
      if (doc.exists) {
        targetCol = col;
        break;
      }
    }
    if (targetCol == null || targetCol.isEmpty) {
      // Utilisateur introuvable
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Utilisateur introuvable"))
      );
      return;
    }
  }

  // Chercher un chat existant
  var existing = await FirebaseFirestore.instance
      .collection('chats')
      .where('participants', arrayContains: currentUser!.uid)
      .get();
  String? cid;
  for (var d in existing.docs) {
    final partsRaw = d.data()?['participants'];
    final List parts = partsRaw is List ? List.from(partsRaw) : [];
    // only treat as existing 1:1 chat when it's exactly two participants
    if (parts.length == 2 && parts.contains(targetUid)) {
      cid = d.id;
      break;
    }
  }

  // Créer un nouveau chat si aucun chat existant
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

  // Naviguer vers la page de chat
  if (mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailPage(chatId: cid!, chatName: targetName),
      ),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: primaryDark,
      onDrawerChanged: (isOpen) {
        if (isOpen) {
          _menuController.forward();
        } else {
          _menuController.reverse();
        }
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
        onCameraTap: _showStoryCreationMenu,
        onEditTap: _showNewChatDialog,
      ),
    );
  }

  Widget _buildCategoryTabs() {
    final tabs = ["TOUS", "PRO", "ENTERPRISE", "NON LUS", "GROUPES"];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.map((label) {
            bool isActive = selectedCategory == label;
            Widget labelWidget;
            if (label == 'NON LUS' && _totalUnread > 0) {
              final int count = _totalUnread;
              labelWidget = Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: TextStyle(color: isActive ? orangeAccent : Colors.white38, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(12)),
                  child: Text(count > 99 ? '99+' : count.toString(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                )
              ]);
            } else {
              labelWidget = Text(label, style: TextStyle(color: isActive ? orangeAccent : Colors.white38, fontWeight: FontWeight.bold, fontSize: 13));
            }

            return GestureDetector(
              onTap: () => setState(() => selectedCategory = label),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Column(
                  children: [
                    labelWidget,
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
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: Colors.orange));
        var docs = snapshot.data!.docs;

        if (selectedCategory == "PRO") {
          docs = docs.where((doc) {
            final data = doc.data() as Map? ?? {};
            final parts = List<String>.from((data['participants'] as List? ?? []).map((e) => e.toString()));
            final types = (data['userTypes'] is Map) ? data['userTypes'] as Map : {};
            // check other participants (exclude current user)
            for (var p in parts) {
              if (p == currentUser?.uid) continue;
              final t = types[p] as String?;
              if (t == 'pro_users') return true;
            }
            return false;
          }).toList();
        } else if (selectedCategory == "ENTERPRISE") {
          docs = docs.where((doc) {
            final data = doc.data() as Map? ?? {};
            final parts = List<String>.from((data['participants'] as List? ?? []).map((e) => e.toString()));
            final types = (data['userTypes'] is Map) ? data['userTypes'] as Map : {};
            for (var p in parts) {
              if (p == currentUser?.uid) continue;
              final t = types[p] as String?;
              if (t == 'enterprise_users') return true;
            }
            return false;
          }).toList();
        } else if (selectedCategory == "NON LUS") {
          docs = docs.where((doc) {
            Map? unread = (doc.data() as Map?)?['unreadCounts'] as Map?;
            return (unread?[currentUser?.uid] ?? 0) > 0;
          }).toList();
        } else if (selectedCategory == "GROUPES") {
          docs = docs.where((doc) {
            final data = doc.data() as Map? ?? {};
            return data['isGroup'] == true;
          }).toList();
        }

        // Dédupliquer les discussions 1:1 au cas où il existerait plusieurs documents
        if (docs.isEmpty) return const Center(child: Text("Aucune discussion", style: TextStyle(color: Colors.white38)));

        // Build a map to keep only one chat per peer (for non-group chats).
        try {
          final Map<String, QueryDocumentSnapshot> unique = {};
          for (var d in docs) {
            final data = d.data() as Map<String, dynamic>? ?? {};
            final bool isGroup = data['isGroup'] == true;
            if (isGroup) {
              // keep groups by their doc id
              unique['group_${d.id}'] = d;
              continue;
            }

            // participants list without current user
            final parts = List<String>.from((data['participants'] as List? ?? []).map((e) => e.toString()));
            parts.remove(currentUser?.uid);
            parts.sort();
            final key = 'peer_${parts.join('-')}';

            if (!unique.containsKey(key)) {
              unique[key] = d;
            } else {
              // keep the most recent chat by lastMessageTime
              try {
                final existing = unique[key]!;
                final existingTime = (existing.data() as Map<String, dynamic>?)?['lastMessageTime'] as Timestamp?;
                final newTime = data['lastMessageTime'] as Timestamp?;
                if (newTime != null && (existingTime == null || newTime.seconds > existingTime.seconds)) {
                  unique[key] = d;
                }
              } catch (_) {
                unique[key] = d;
              }
            }
          }

          // Replace docs with deduped list ordered by lastMessageTime desc
          var deduped = unique.values.toList();
          deduped.sort((a, b) {
            final aTime = ((a.data() as Map<String, dynamic>?)?['lastMessageTime']) as Timestamp?;
            final bTime = ((b.data() as Map<String, dynamic>?)?['lastMessageTime']) as Timestamp?;
            final aMillis = aTime?.millisecondsSinceEpoch ?? 0;
            final bMillis = bTime?.millisecondsSinceEpoch ?? 0;
            return bMillis.compareTo(aMillis);
          });
          // place non-group chats first, then append groups at the end
          final nonGroup = deduped.where((d) {
            final data = d.data() as Map<String, dynamic>?;
            return data == null ? true : (data['isGroup'] == true ? false : true);
          }).toList();
          final groupChats = deduped.where((d) {
            final data = d.data() as Map<String, dynamic>?;
            return data != null && data['isGroup'] == true;
          }).toList();
          docs = [...nonGroup, ...groupChats];
        } catch (e) {
          // en cas d'erreur, revenir à la liste originale
          debugPrint('Dedup chat list error: $e');
        }

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
              child: (() {
                final bool isGroup = (chat['isGroup'] == true);
                if (isGroup) {
                  final String name = (chat['groupName'] as String?) ?? 'Groupe';
                  final String photo = (chat['groupPhoto'] as String?) ?? '';
                  String subtitleText = (chat['lastMessage'] ?? 'Nouvelle discussion');
                  return ListTile(
                    onTap: () async {
                      ModernDashboardGlobals.navBarVisible.value = false;
                      await Navigator.push(context, MaterialPageRoute(builder: (context) => GroupChatDetailPage(chatId: docId, chatName: name)));
                      ModernDashboardGlobals.navBarVisible.value = true;
                    },
                    leading: CircleAvatar(radius: 26, backgroundColor: const Color(0xFF2C3E50), backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null, child: photo.isEmpty ? const Icon(Icons.group, color: Colors.white54) : null),
                    title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(subtitleText, style: TextStyle(color: Colors.white54), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: _buildTimeAndBadge(chat),
                  );
                }

                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection(collection).doc(otherUserId).snapshots(),
                  builder: (context, userSnap) {
                    String name = "Utilisateur";
                    bool isOnline = false, isCert = false;
                    // prefer local override stored in chats/{chatId}.localNames.{myUid}
                    try {
                      final myUid = currentUser?.uid ?? '';
                      Map localNames = (chat['localNames'] is Map) ? chat['localNames'] : {};
                      final override = (localNames[myUid] ?? '').toString();
                      if (override.trim().isNotEmpty) {
                        name = override;
                      }
                    } catch (e) {
                      // ignore and fallback to user doc
                    }

                    if (name == "Utilisateur") {
                      if (userSnap.hasData && userSnap.data!.exists) {
                        var ud = userSnap.data!.data() as Map<String, dynamic>?;
                        if (ud != null) {
                          name = UserUtils.formatName(ud);
                          isOnline = ud['isOnline'] ?? false;
                          isCert = ud['isCertified'] ?? false;
                        }
                      }
                    } else {
                      // still attempt to read presence/cert from user doc
                      if (userSnap.hasData && userSnap.data!.exists) {
                        var ud = userSnap.data!.data() as Map<String, dynamic>?;
                        if (ud != null) {
                          isOnline = ud['isOnline'] ?? false;
                          isCert = ud['isCertified'] ?? false;
                        }
                      }
                    }
                    Map typing = (chat['typing'] is Map) ? chat['typing'] : {};
                    Map actions = (chat['userActions'] is Map) ? chat['userActions'] : {};
                    bool isTyping = typing[otherUserId] ?? false;
                    String subtitleText = (chat['lastMessage'] ?? 'Nouvelle discussion');
                    if (actions[otherUserId] == 'recording') {
                      subtitleText = 'enregistrement audio...';
                    } else if (isTyping) subtitleText = 'en train d\'écrire...';

                    final photo = (userSnap.hasData && userSnap.data!.exists) ? ((userSnap.data!.data() as Map<String, dynamic>?)?['photoUrl'] ?? (userSnap.data!.data() as Map<String, dynamic>?)?['photo'] ?? (userSnap.data!.data() as Map<String, dynamic>?)?['avatar'] ?? '') as String : '';
                    return ListTile(
                      onTap: () async {
                        ModernDashboardGlobals.navBarVisible.value = false;
                        await Navigator.push(context, MaterialPageRoute(builder: (context) => ChatDetailPage(chatId: docId, chatName: name)));
                        ModernDashboardGlobals.navBarVisible.value = true;
                      },
                      leading: GestureDetector(
                        onTap: () => _showAvatarActions(context, otherUserId, canEdit: otherUserId == currentUser?.uid, photoUrl: photo),
                        child: Stack(
                          children: [
                            CircleAvatar(radius: 26, backgroundColor: const Color(0xFF2C3E50), backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null, child: photo.isEmpty ? const Icon(Icons.person, color: Colors.white54) : null),
                            if (isOnline) Positioned(right: 1, bottom: 1, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle, border: Border.all(color: primaryDark, width: 2)))),
                          ],
                        ),
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
                );
              }()),
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
    // Resolve contacts to app users (by email) to display only app users
    final List<Map<String, dynamic>> appUsers = [];
    for (final ct in contacts) {
      if (ct.emails.isEmpty) continue;
      final email = ct.emails.first.address;
      if (email.isEmpty) continue;
      for (var col in ['classic_users', 'pro_users', 'enterprise_users']) {
        final res = await FirebaseFirestore.instance.collection(col).where('email', isEqualTo: email).limit(1).get();
        if (res.docs.isNotEmpty) {
          final d = res.docs.first;
          final data = d.data();
          final formatted = UserUtils.formatName(data);
          String fallbackName = '';
          if (data['displayName']?.toString().trim().isNotEmpty == true) fallbackName = data['displayName'];
          if (fallbackName.isEmpty && data['display_name']?.toString().trim().isNotEmpty == true) fallbackName = data['display_name'];
          if (fallbackName.isEmpty && data['name']?.toString().trim().isNotEmpty == true) fallbackName = data['name'];
          if (fallbackName.isEmpty && data['username']?.toString().trim().isNotEmpty == true) fallbackName = data['username'];
          if (fallbackName.isEmpty && (email ?? '').toString().trim().isNotEmpty) fallbackName = email;
          if (fallbackName.isEmpty) fallbackName = d.id;

          appUsers.add({
            'uid': d.id,
            'name': formatted.isNotEmpty ? formatted : fallbackName,
            'email': email,
            'photo': data['photoUrl'] ?? data['photo'] ?? '',
            'contactIndex': contacts.indexOf(ct),
          });
          break;
        }
      }
    }

    // Only show users that the current user already has in their chats
    final Set<String> existingChatUids = {};
    final user = currentUser;
    if (user != null) {
      final chatSnap = await FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: user.uid).get();
      for (final d in chatSnap.docs) {
        final data = d.data();
        final participants = List<String>.from(data['participants'] ?? []);
        for (final p in participants) {
          if (p != user.uid) existingChatUids.add(p);
        }
      }
    }

    // Build profiles for participants: prefer device-resolved appUsers, then
    // fetch missing participant profiles from user collections so names match
    // the chat list UI.
    final Map<String, Map<String, dynamic>> profilesByUid = {};
    for (final u in appUsers) {
      final uid = u['uid'] as String? ?? '';
      if (uid.isNotEmpty && existingChatUids.contains(uid)) {
        profilesByUid[uid] = Map<String, dynamic>.from(u);
      }
    }

    for (final uid in existingChatUids) {
      if (profilesByUid.containsKey(uid)) continue;
      Map<String, dynamic>? profile;
      for (var col in ['classic_users', 'pro_users', 'enterprise_users']) {
        try {
          final doc = await FirebaseFirestore.instance.collection(col).doc(uid).get();
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>;
            final formatted = UserUtils.formatName(data);
            String fallbackName = '';
            if (data['displayName']?.toString().trim().isNotEmpty == true) fallbackName = data['displayName'];
            if (fallbackName.isEmpty && data['display_name']?.toString().trim().isNotEmpty == true) fallbackName = data['display_name'];
            if (fallbackName.isEmpty && data['name']?.toString().trim().isNotEmpty == true) fallbackName = data['name'];
            if (fallbackName.isEmpty && data['username']?.toString().trim().isNotEmpty == true) fallbackName = data['username'];
            if (fallbackName.isEmpty && (data['email'] ?? '').toString().trim().isNotEmpty) fallbackName = data['email'];
            if (fallbackName.isEmpty) fallbackName = uid;

            profile = {
              'uid': uid,
              'name': formatted.isNotEmpty ? formatted : fallbackName,
              'email': data['email'] ?? '',
              'photo': data['photoUrl'] ?? data['photo'] ?? '',
            };
            break;
          }
        } catch (e) {
          debugPrint('load participant $uid from $col err: $e');
        }
      }
      if (profile != null) profilesByUid[uid] = profile;
    }

    // visibleUsers is the list shown in the modal and can be filtered by search
    List<Map<String, dynamic>> visibleUsers = profilesByUid.values.toList();
    final TextEditingController groupSearchCtrl = TextEditingController();
    final TextEditingController addEmailCtrl = TextEditingController();

    List<String> selectedUids = [];
    String groupName = '';
    String description = '';
    XFile? groupPhoto;
    final Map<String, XFile?> memberPhotos = {};
    String canAddMembers = 'admins'; // 'admins' or 'all'
    String canChangeInfo = 'admins';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
              child: Container(
                decoration: BoxDecoration(color: primaryDark, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 45, height: 5, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 12),

                    // header: photo + name/description
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          final img = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
                          if (img != null) setState(() => groupPhoto = img);
                        },
                        child: CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.white10,
                          backgroundImage: groupPhoto != null ? FileImage(File(groupPhoto!.path)) : null,
                          child: groupPhoto == null ? const Icon(Icons.group, color: Colors.white70, size: 32) : null,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          TextField(
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(hintText: 'Nom du groupe', hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: Colors.white10, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                            onChanged: (v) => setState(() => groupName = v.trim()),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            style: const TextStyle(color: Colors.white70),
                            decoration: InputDecoration(hintText: 'Description (optionnelle)', hintStyle: const TextStyle(color: Colors.white30), filled: true, fillColor: Colors.white10, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                            maxLines: 2,
                            onChanged: (v) => setState(() => description = v.trim()),
                          ),
                        ]),
                      ),
                    ]),

                    const SizedBox(height: 8),
                    // permissions row
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            color: Colors.transparent,
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Qui peut ajouter des membres ?', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                  DropdownButton<String>(
                                    value: canAddMembers,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(value: 'admins', child: Text('Admins seulement')),
                                      DropdownMenuItem(value: 'all', child: Text('Tous les membres')),
                                    ],
                                    onChanged: (v) => setState(() => canAddMembers = v ?? 'admins'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Card(
                            color: Colors.transparent,
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Qui peut changer les infos ?', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                  DropdownButton<String>(
                                    value: canChangeInfo,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(value: 'admins', child: Text('Admins seulement')),
                                      DropdownMenuItem(value: 'all', child: Text('Tous les membres')),
                                    ],
                                    onChanged: (v) => setState(() => canChangeInfo = v ?? 'admins'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 10),
                    Text('Sélectionnez des contacts', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),

                    // search + add by email
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: groupSearchCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search, color: Colors.white54),
                              hintText: 'Rechercher un contact...',
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: Colors.white10,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                            onChanged: (q) => setState(() {
                              final s = q.trim().toLowerCase();
                              final base = profilesByUid.values.toList();
                              if (s.isEmpty) {
                                visibleUsers = base.toList();
                              } else {
                                visibleUsers = base.where((u) {
                                  final name = (u['name'] as String? ?? '').toLowerCase();
                                  final email = (u['email'] as String? ?? '').toLowerCase();
                                  return name.contains(s) || email.contains(s);
                                }).toList();
                              }
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, padding: EdgeInsets.zero),
                            onPressed: () async {
                              final email = addEmailCtrl.text.trim();
                              if (email.isEmpty) return;
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recherche...')));
                              Map<String, dynamic>? foundUser;
                              for (var col in ['classic_users', 'pro_users', 'enterprise_users']) {
                                try {
                                  final res = await FirebaseFirestore.instance.collection(col).where('email', isEqualTo: email).limit(1).get();
                                  if (res.docs.isNotEmpty) {
                                    final d = res.docs.first;
                                    final data = d.data();
                                    foundUser = {'uid': d.id, 'name': UserUtils.formatName(data), 'email': data['email'] ?? email, 'photo': data['photoUrl'] ?? data['photo'] ?? ''};
                                    break;
                                  }
                                } catch (e) {
                                  debugPrint('email search err: $e');
                                }
                              }
                              if (foundUser == null) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun utilisateur trouvé pour cet email')));
                                return;
                              }
                              final exists = visibleUsers.any((u) => u['uid'] == foundUser!['uid']);
                              if (!exists) {
                                setState(() {
                                  visibleUsers.insert(0, foundUser!);
                                  selectedUids.add(foundUser['uid']);
                                });
                              } else {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Utilisateur déjà dans la liste')));
                              }
                            },
                            child: const Icon(Icons.add, color: Colors.white),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // selected members chips
                    if (selectedUids.isNotEmpty) SizedBox(height: 72, child: ListView(scrollDirection: Axis.horizontal, children: selectedUids.map((uid) {
                      final u = visibleUsers.cast<Map<String, dynamic>>().firstWhere((e) => e['uid'] == uid, orElse: () => <String, dynamic>{});
                      final rawName = u.isNotEmpty ? (u['name'] as String? ?? '') : '';
                      final email = u.isNotEmpty ? (u['email'] as String? ?? '') : '';
                      final name = rawName.isNotEmpty ? rawName : (email.isNotEmpty ? email : uid);
                      final photo = u.isNotEmpty ? (u['photo'] as String? ?? '') : '';
                      return Padding(padding: const EdgeInsets.only(right: 8), child: Chip(backgroundColor: Colors.white10, avatar: CircleAvatar(backgroundImage: photo.isNotEmpty ? NetworkImage(photo) as ImageProvider : null, child: photo.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?') : null), label: Row(children: [Text(name, style: const TextStyle(color: Colors.white70)), const SizedBox(width: 8), GestureDetector(onTap: () => setState(() => selectedUids.remove(uid)), child: const Icon(Icons.close, size: 16, color: Colors.white54))],)), );
                    }).toList())),

                    const SizedBox(height: 8),

                    // members list
                    Expanded(child: visibleUsers.isEmpty ? const Center(child: Text('Aucun contact trouvé dans l\'application', style: TextStyle(color: Colors.white38))) : ListView.builder(itemCount: visibleUsers.length, itemBuilder: (c,i) { final u = visibleUsers[i]; final uid = u['uid'] as String; final rawName = (u['name'] as String? ?? ''); final email = (u['email'] as String? ?? ''); final name = rawName.isNotEmpty ? rawName : (email.isNotEmpty ? email : uid); final photo = u['photo'] as String? ?? ''; final selected = selectedUids.contains(uid); return Card(color: Colors.transparent, child: ListTile(leading: GestureDetector(onTap: () async { final picker = ImagePicker(); final img = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800); if (img != null) setState(() => memberPhotos[uid] = img); }, child: CircleAvatar(radius: 22, backgroundColor: Colors.white10, backgroundImage: memberPhotos[uid] != null ? FileImage(File(memberPhotos[uid]!.path)) : (photo.isNotEmpty ? NetworkImage(photo) as ImageProvider : null), child: (memberPhotos[uid] == null && (photo.isEmpty)) ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?') : null, )), title: Text(name, style: const TextStyle(color: Colors.white)), subtitle: Text(u['email'] ?? '', style: const TextStyle(color: Colors.white60)), trailing: Checkbox(value: selected, onChanged: (v) => setState(() => v == true ? selectedUids.add(uid) : selectedUids.remove(uid))), onTap: () => setState(() => selectedUids.contains(uid) ? selectedUids.remove(uid) : selectedUids.add(uid)), )); })),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler', style: TextStyle(color: Colors.white70)))),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () async {
                            if (currentUser == null) return;
                            if (selectedUids.isEmpty) {
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sélectionnez au moins 1 contact')));
                              return;
                            }
                            if (groupName.trim().isEmpty) {
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Donnez un nom au groupe')));
                              return;
                            }

                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Création du groupe...')));

                            try {
                              final participantIds = [currentUser!.uid, ...selectedUids].toSet().toList();

                              // create chat doc
                              final newChatRef = await FirebaseFirestore.instance.collection('chats').add({
                                'participants': participantIds,
                                'lastMessage': '',
                                'lastMessageTime': FieldValue.serverTimestamp(),
                                'unreadCounts': Map.fromEntries(participantIds.map((id) => MapEntry(id, 0))),
                                'isGroup': true,
                                'groupName': groupName.isNotEmpty ? groupName : 'Groupe',
                                'description': description,
                                'admins': [currentUser!.uid],
                                'permissions': {'canAddMembers': canAddMembers, 'canChangeInfo': canChangeInfo},
                                'userTypes': Map.fromEntries(participantIds.map((p) => MapEntry(p, 'classic_users'))),
                                'typing': Map.fromEntries(participantIds.map((p) => MapEntry(p, false))),
                              });

                              final updates = <String, dynamic>{};

                              // upload group photo if any (Supabase if available, otherwise Firebase Storage)
                              if (groupPhoto != null) {
                                final XFile gp = groupPhoto!; // capture local non-null reference
                                try {
                                  String url = '';
                                  if (SupabaseService.isInitialized) {
                                    final bytes = await File(gp.path).readAsBytes();
                                    url = await SupabaseService.uploadBytes(bytes, '${newChatRef.id}/group_photo.jpg', 'chat_media');
                                  } else {
                                    final ref = FirebaseStorage.instance.ref().child('chats/${newChatRef.id}/group_photo.jpg');
                                    await ref.putFile(File(gp.path));
                                    url = await ref.getDownloadURL();
                                  }
                                  updates['groupPhoto'] = url;
                                } catch (e) {
                                  debugPrint('upload group photo err: $e');
                                }
                              }

                              // upload member photos if selected
                              final Map<String, String> memberAvatars = {};
                              for (final e in memberPhotos.entries) {
                                final uid = e.key;
                                final x = e.value;
                                if (x == null) continue;
                                final XFile xLocal = x; // capture local non-null reference
                                try {
                                  String url = '';
                                  if (SupabaseService.isInitialized) {
                                    final bytes = await File(xLocal.path).readAsBytes();
                                    url = await SupabaseService.uploadBytes(bytes, '${newChatRef.id}/members/$uid.jpg', 'chat_media');
                                  } else {
                                    final r = FirebaseStorage.instance.ref().child('chats/${newChatRef.id}/members/$uid.jpg');
                                    await r.putFile(File(xLocal.path));
                                    url = await r.getDownloadURL();
                                  }
                                  memberAvatars[uid] = url;
                                } catch (e) {
                                  debugPrint('upload member photo $uid err: $e');
                                }
                              }
                              if (memberAvatars.isNotEmpty) updates['memberAvatars'] = memberAvatars;

                              if (updates.isNotEmpty) await newChatRef.update(updates);

                              // notify members: create a system message announcing group creation and additions
                              try {
                                final creatorName = FirebaseAuth.instance.currentUser?.displayName ?? 'Un utilisateur';
                                final addedCount = selectedUids.length;
                                final text = '$creatorName a créé le groupe' + (addedCount > 0 ? ' et a ajouté $addedCount membre(s)' : '');
                                // add system message
                                await newChatRef.collection('messages').add({
                                  'type': 'system',
                                  'text': text,
                                  'senderId': FirebaseAuth.instance.currentUser?.uid,
                                  'timestamp': FieldValue.serverTimestamp(),
                                  'isRead': false,
                                  'delivered': false,
                                });
                                // update chat meta: lastMessage + unread increments for other participants
                                final updates2 = {
                                  'lastMessage': text,
                                  'lastMessageTime': FieldValue.serverTimestamp(),
                                };
                                for (var p in participantIds) {
                                  if (p != currentUser!.uid) updates2['unreadCounts.$p'] = FieldValue.increment(1);
                                }
                                await newChatRef.update(updates2);
                              } catch (e) {
                                debugPrint('Group creation notify error: $e');
                              }

                              if (mounted) {
                                Navigator.pop(ctx);
                                Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatDetailPage(chatId: newChatRef.id, chatName: groupName.isNotEmpty ? groupName : 'Groupe')));
                              }
                            } catch (e) {
                              debugPrint('create group err: $e');
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de la création du groupe')));
                            }
                          },
                          child: const Text('Créer'),
                        ),
                      ],
                    ),
              ],
            ),
          ),
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
      isScrollControlled: true,
      builder: (_) {
        return Material(
          color: Colors.transparent,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            child: snap.docs.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Aucun message sauvegardé', style: TextStyle(color: Colors.white38))))
              : ListView.builder(
                itemCount: snap.docs.length,
                itemBuilder: (c, i) {
                  final d = snap.docs[i];
                  final data = d.data() as Map<String, dynamic>;
                  final type = (data['type'] ?? 'text') as String;
                  final createdAt = data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : DateTime.now();
                  final timeLabel = timeago.format(createdAt, locale: 'fr');

                  Widget leading;
                  if (type == 'image' && (data['url'] ?? '').toString().isNotEmpty) {
                    leading = CircleAvatar(backgroundColor: Colors.white10, backgroundImage: CachedNetworkImageProvider(data['url']) as ImageProvider);
                  } else if (type == 'video') {
                    leading = const CircleAvatar(backgroundColor: Colors.white10, child: Icon(Icons.videocam, color: Colors.white));
                  } else if (type == 'audio') {
                    leading = const CircleAvatar(backgroundColor: Colors.white10, child: Icon(Icons.audiotrack, color: Colors.white));
                  } else {
                    leading = const CircleAvatar(backgroundColor: Colors.white10, child: Icon(Icons.bookmark, color: Colors.white));
                  }

                  return ListTile(
                    leading: leading,
                    title: Text((data['text'] ?? (data['url'] ?? '')) as String, style: const TextStyle(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${data['sourceName'] ?? ''} • $timeLabel', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    onTap: () async {
                      // If we have chatId, open conversation
                      final chatId = data['chatId'] as String?;
                      if (chatId != null && chatId.isNotEmpty) {
                        Navigator.pop(context);
                        try {
                          final doc = await FirebaseFirestore.instance.collection('chats').doc(chatId).get();
                          final isGroup = doc.exists && ((doc.data() as Map<String, dynamic>?)?['isGroup'] == true);
                          if (mounted) {
                            if (isGroup) {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatDetailPage(chatId: chatId, chatName: data['sourceName'] ?? 'Discussion')));
                            } else {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => ChatDetailPage(chatId: chatId, chatName: data['sourceName'] ?? 'Discussion')));
                            }
                          }
                        } catch (e) {
                          debugPrint('Error opening saved message chat: $e');
                        }
                        return;
                      }

                      // For images show preview
                      final url = (data['url'] ?? '') as String;
                      if (type == 'image' && url.isNotEmpty) {
                        Navigator.pop(context);
                        showDialog(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url))));
                        return;
                      }

                      // For text: copy to clipboard
                      if (type == 'text' && (data['text'] ?? '').toString().isNotEmpty) {
                        await Clipboard.setData(ClipboardData(text: data['text'] ?? ''));
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Texte copié')));
                        return;
                      }
                    },
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.open_in_new, color: Colors.white54), onPressed: () async {
                        final url = (data['url'] ?? '') as String;
                        if (url.isNotEmpty) {
                          try {
                            await Clipboard.setData(ClipboardData(text: url));
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL copiée')));
                          } catch (_) {}
                        }
                      }),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async { await d.reference.delete(); if (mounted) { Navigator.pop(context); _showSavedMessages(); } }),
                    ]),
                  );
                },
              ),
          ),
        );
      },
    );
  }
}

Future<void> _showAvatarActions(
  BuildContext context,
  String uid, {
  required bool canEdit,
  String? photoUrl,
}) async {
  const Color primaryDark = Color(0xFF0F172A); // ✅ couleur définie

  final photo = photoUrl ?? '';

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: primaryDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Wrap(
            children: [
              // ===== Voir la photo =====
              if (photo.isNotEmpty)
                ListTile(
                  leading:
                      const Icon(Icons.visibility, color: Colors.white70),
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

              // ===== Changer la photo =====
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
                      } else {
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

                      if (uid == FirebaseAuth.instance.currentUser?.uid) {
                        try {
                          await FirebaseAuth.instance.currentUser
                              ?.updatePhotoURL(url);
                        } catch (_) {}
                      }

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

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Photo mise à jour'),
                        ),
                      );
                    } catch (e) {
                      debugPrint('update avatar err: $e');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Erreur lors de l\'upload'),
                        ),
                      );
                    }
                  },
                ),

              // ===== Supprimer la photo =====
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
                            'Supprimer la photo de profil ?'),
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

                    try {
                      if (SupabaseService.isInitialized) {
                        await supabase.Supabase.instance.client.storage
                            .from('IDENTITY')
                            .remove(['users/$uid/profile.jpg']);
                      } else {
                        final ref = FirebaseStorage.instance
                            .ref()
                            .child('users/$uid/profile.jpg');
                        await ref.delete();
                      }
                    } catch (_) {}

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

                      if (uid == FirebaseAuth.instance.currentUser?.uid) {
                        try {
                          await FirebaseAuth.instance.currentUser
                              ?.updatePhotoURL('');
                        } catch (_) {}
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Photo supprimée'),
                        ),
                      );
                    } catch (e) {
                      debugPrint('delete avatar err: $e');
                    }
                  },
                ),

              // ===== Annuler =====
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

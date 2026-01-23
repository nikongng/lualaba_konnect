import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../chat/presentation/pages/story_viewer_page.dart';

class StoryBar extends StatefulWidget {
  final String currentUserId;
  final VoidCallback onAddStoryTap;

  const StoryBar({
    super.key,
    required this.currentUserId,
    required this.onAddStoryTap,
  });

  @override
  State<StoryBar> createState() => _StoryBarState();
}

class _StoryBarState extends State<StoryBar> {
  final Map<String, bool> _visibilityCache = {};
  final Set<String> _pendingChecks = {};
  final Set<String> _peerIds = {};
  StreamSubscription<QuerySnapshot>? _chatsSub;
  List<Map<String, dynamic>> _cachedStories = [];
  bool _cachedLoaded = false;

  @override
  void dispose() {
    _pendingChecks.clear();
    _chatsSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _listenPeers();
    // pre-load cached stories once
    _loadCachedStories().then((list) {
      if (!mounted) return;
      setState(() {
        _cachedStories = list;
        _cachedLoaded = true;
      });
    });
  }

  Future<List<Map<String, dynamic>>> _loadCachedStories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('cached_stories') ?? [];
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final parsed = <Map<String, dynamic>>[];
      for (final s in list) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          final expires = (m['expiresAt'] is int) ? (m['expiresAt'] as int) : (m['expiresAt'] is String ? int.tryParse(m['expiresAt']) : null);
          if (expires != null && expires < nowMs) continue; // skip expired
          if (m.containsKey('userId')) parsed.add(m);
        } catch (_) {}
      }
      // rewrite cleaned cache (remove expired)
      try {
        final prefs2 = await SharedPreferences.getInstance();
        final rew = parsed.map((m) => jsonEncode(m)).toList();
        await prefs2.setStringList('cached_stories', rew);
      } catch (_) {}
      return parsed;
    } catch (_) {
      return [];
    }
  }

  Future<void> _removeCachedForUsers(List<String> userIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('cached_stories') ?? [];
      final kept = <String>[];
      for (final s in list) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          final uid = m['userId']?.toString() ?? '';
          if (userIds.contains(uid)) continue;
          kept.add(s);
        } catch (_) { kept.add(s); }
      }
      await prefs.setStringList('cached_stories', kept);
    } catch (_) {}
  }

  void _listenPeers() {
    try {
      final uid = widget.currentUserId;
      if (uid.isEmpty) return;
      _chatsSub = FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: uid)
          .snapshots()
          .listen((snap) {
        final Set<String> peers = {};
        for (var d in snap.docs) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          final parts = List<String>.from((data['participants'] as List? ?? []).map((e) => e.toString()));
          for (var p in parts) {
            if (p != uid) peers.add(p);
          }
        }
        if (!mounted) return;
        setState(() {
          _peerIds
            ..clear()
            ..addAll(peers);
        });
      });
    } catch (_) {}
  }

  Future<bool> _checkViewerAllowed(String ownerId, String? viewerEmail) async {
    if (_visibilityCache.containsKey(ownerId)) return _visibilityCache[ownerId]!;
    if (_pendingChecks.contains(ownerId)) return false;
    _pendingChecks.add(ownerId);

    final collections = ['classic_users', 'pro_users', 'enterprise_users', 'users'];
    bool allowed = false;
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;

    // Owner must always see their own stories
    if (viewerUid != null && ownerId == viewerUid) {
      _visibilityCache[ownerId] = true;
      _pendingChecks.remove(ownerId);
      return true;
    }

    for (final col in collections) {
      try {
        final docRef = FirebaseFirestore.instance.collection(col).doc(ownerId);
        final doc = await docRef.get();
        if (!doc.exists) continue;
        final data = doc.data();
        if (data == null) continue;

        // Public override
        if (data['publicStories'] == true) {
          allowed = true;
          break;
        }

        // Check common array fields that may list emails
        final arrayFields = ['allowedEmails', 'sharedWith', 'contactsEmails', 'permittedEmails', 'sharedWithEmails'];
        if (viewerEmail != null && viewerEmail.trim().isNotEmpty) {
          for (final f in arrayFields) {
            final v = data[f];
            if (v is List && v.any((e) => e != null && e.toString().toLowerCase() == viewerEmail.toLowerCase())) {
              allowed = true;
              break;
            }
          }
          if (allowed) break;
        }

        // Check if owner has a contacts subcollection with a doc for this viewer (by uid)
        try {
          if (viewerUid != null) {
            final byUid = await docRef.collection('contacts').doc(viewerUid).get();
            if (byUid.exists) {
              allowed = true;
              break;
            }
          }
        } catch (_) {}

        // Check contacts subcollection searching by email
        if (viewerEmail != null && viewerEmail.trim().isNotEmpty) {
          try {
            final q = await docRef.collection('contacts').where('email', isEqualTo: viewerEmail).limit(1).get();
            if (q.docs.isNotEmpty) {
              allowed = true;
              break;
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    _visibilityCache[ownerId] = allowed;
    _pendingChecks.remove(ownerId);
    return allowed;
  }

  void _ensureVisibilityFor(List<String> userIds, String? viewerEmail) {
    final toCheck = userIds.where((id) => !_visibilityCache.containsKey(id) && !_pendingChecks.contains(id)).toList();
    if (toCheck.isEmpty) return;
    for (final id in toCheck) {
      _checkViewerAllowed(id, viewerEmail).then((_) { if (mounted) setState(() {}); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    final viewerId = widget.currentUserId;

    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('stories')
            .where('expiresAt', isGreaterThan: Timestamp.fromDate(DateTime.now()))
            .orderBy('expiresAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const SizedBox.shrink();
          if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 110, child: Center(child: CircularProgressIndicator()));

          final stories = snapshot.data?.docs ?? [];
          final Map<String, List<DocumentSnapshot>> grouped = {};
          for (var doc in stories) {
            final data = doc.data() as Map<String, dynamic>;
            final String userId = data['userId'] ?? 'unknown';
            grouped.putIfAbsent(userId, () => []).add(doc);
          }

          var groupedList = grouped.entries.map((e) {
            e.value.sort((a, b) {
              final aa = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              final bb = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              return (bb?.toDate() ?? DateTime.now()).compareTo(aa?.toDate() ?? DateTime.now());
            });
            final first = e.value.first.data() as Map<String, dynamic>;
            return {
              'userId': e.key,
              'userName': first['userName'] ?? 'Utilisateur',
              'imageUrl': first['imageUrl'],
              'stories': e.value,
            };
          }).toList();

          // Filtrer pour ne montrer que les stories des pairs (avec lesquels on a eu une discussion)
          try {
            groupedList = groupedList.where((entry) {
              final uid = entry['userId'] as String? ?? '';
              // toujours montrer la story du viewer en premier
              if (uid == widget.currentUserId) return true;
              return _peerIds.contains(uid);
            }).toList();

            // Merge cached stories so freshly published stories appear immediately
            final cached = _cachedLoaded ? _cachedStories : [];
            // collect firestore-backed userIds to remove their cache entries afterwards
            final firestoreUserIds = groupedList.map((e) => (e['userId'] as String? ?? '')).where((s) => s.isNotEmpty).toList();
            for (final c in cached) {
              final uid = c['userId'] as String? ?? '';
              if (uid.isEmpty) continue;
              // if we already have this user's stories from Firestore, skip
              final exists = groupedList.any((e) => (e['userId'] as String?) == uid);
              if (exists) continue;
              // Only include cached if peer or self
              if (uid == widget.currentUserId || _peerIds.contains(uid)) {
                groupedList.insert(0, {
                  'userId': uid,
                  'userName': c['userName'] ?? 'Utilisateur',
                  'imageUrl': c['imageUrl'],
                  'stories': <DocumentSnapshot>[],
                });
              }
            }

            // Remove cache entries for users that are now confirmed in Firestore
            if (firestoreUserIds.isNotEmpty) {
              Future.microtask(() => _removeCachedForUsers(firestoreUserIds));
            }
          } catch (_) {}

          groupedList.sort((a, b) {
            final aId = a['userId'] as String? ?? '';
            final bId = b['userId'] as String? ?? '';
            if (aId == viewerId) return -1;
            if (bId == viewerId) return 1;
            return 0;
          });

          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ids = groupedList.map((e) => e['userId'] as String).toList();
            final viewerEmail = FirebaseAuth.instance.currentUser?.email;
            _ensureVisibilityFor(ids, viewerEmail);
          });

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: groupedList.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _buildMyStoryCircle(authUser);
              final entry = groupedList[index - 1];
              final userStories = entry['stories'] as List<DocumentSnapshot>;
              final userId = entry['userId'] as String;
              final visible = _visibilityCache[userId];
              if (visible == null) return const SizedBox.shrink();
              if (visible != true) return const SizedBox.shrink();
              return _buildFriendStoryCircle(
                context,
                userId,
                entry['userName'] as String?,
                entry['imageUrl'] as String?,
                userStories,
                viewerId,
              );
            },
          );
        },
      ),
    );
  }

  // --- CERCLE POUR L'UTILISATEUR ACTUEL (+) ---
  Widget _buildMyStoryCircle(User? user) {
    return GestureDetector(
      onTap: widget.onAddStoryTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 15, right: 5),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey[900],
                    backgroundImage: (user?.photoURL != null)
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: (user?.photoURL == null)
                        ? const Icon(Icons.person, color: Colors.white54)
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              user != null ? 'Moi' : 'Ma story',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // --- CERCLE POUR LES STORIES DES AMIS ---
  Widget _buildFriendStoryCircle(
    BuildContext context,
    String userId,
    String? name,
    String? url,
    List<DocumentSnapshot> userStories,
    String viewerId,
  ) {
    // Si le nom enregistré est 'Moi' (ou absent) et que ce n'est pas le viewer,
    // on récupère le nom réel depuis la fiche utilisateur.
    final needsLookup = (name == null || name.trim().isEmpty || name == 'Moi') && userId != viewerId;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StoryViewerPage(
              stories: userStories,
              initialIndex: 0,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 5),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE57C00),
                      width: 2.5,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey[800],
                    backgroundImage: url != null ? NetworkImage(url) : null,
                    child: url == null
                        ? const Icon(Icons.person, color: Colors.white54)
                        : null,
                  ),
                ),
                if (userStories.length > 1)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${userStories.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 70,
              child: needsLookup
                ? FutureBuilder<String?>(
                    future: _getFirstNameFromCollections(userId),
                    builder: (context, snap) {
                      final firstName = snap.data?.trim();
                      return Text(
                        (firstName != null && firstName.isNotEmpty)
                            ? firstName
                            : 'Utilisateur',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  )

                  : Text(
                      name ?? 'Utilisateur',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ],
        ),
      ),
    );
  }
  Future<String?> _getFirstNameFromCollections(String userId) async {
  try {
    final firestore = FirebaseFirestore.instance;

    final collections = [
      'classic_users',
      'pro_users',
      'enterprise_users',
    ];

    for (final col in collections) {
      final doc = await firestore.collection(col).doc(userId).get();
      if (doc.exists) {
        final data = doc.data();
        final firstName = data?['firstName'];
        if (firstName is String && firstName.trim().isNotEmpty) {
          return firstName;
        }
      }
    }
  } catch (_) {}

  return null;
}

}
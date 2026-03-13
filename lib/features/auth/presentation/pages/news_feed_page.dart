import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:share_plus/share_plus.dart';
import 'package:lualaba_konnect/shared/widgets/account_badge.dart';
import 'package:http/http.dart' as http;
import 'package:lualaba_konnect/features/chat/presentation/pages/user_utils.dart';
import 'package:lualaba_konnect/core/config.dart';
import 'package:lualaba_konnect/features/auth/presentation/pages/notifications_page.dart';
import 'package:flutter/foundation.dart';
import 'package:lualaba_konnect/core/supabase_service.dart';
import 'package:video_player/video_player.dart';

// ==========================================
// DONNEES DEMO (utilisees si aucun post)
// ==========================================
// Stories removed from News Feed for now.

final RegExp _mentionExpGlobal = RegExp(r'@\w+');
const String _newsFeedBucket = 'Publications';

class _PostMediaEntry {
  final String type; // image | video
  final String url;
  const _PostMediaEntry({required this.type, required this.url});

  bool get isVideo => type == 'video';
}

List<_PostMediaEntry> _extractPostMediaEntries(Map<String, dynamic> data) {
  final out = <_PostMediaEntry>[];

  final rawMedia = data['media'];
  if (rawMedia is List) {
    for (final raw in rawMedia) {
      if (raw is! Map) continue;
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      final type = (map['type'] ?? '').toString().toLowerCase();
      final url = (map['url'] ?? '').toString().trim();
      if (url.isEmpty) continue;
      out.add(_PostMediaEntry(type: type == 'video' ? 'video' : 'image', url: url));
    }
  }
  if (out.isNotEmpty) return out;

  final images = (data['images'] is List)
      ? List<String>.from((data['images'] as List).map((e) => e.toString()))
      : const <String>[];
  final videos = (data['videos'] is List)
      ? List<String>.from((data['videos'] as List).map((e) => e.toString()))
      : const <String>[];

  out.addAll(images.where((u) => u.trim().isNotEmpty).map((u) => _PostMediaEntry(type: 'image', url: u)));
  out.addAll(videos.where((u) => u.trim().isNotEmpty).map((u) => _PostMediaEntry(type: 'video', url: u)));
  return out;
}

String? _firstPostMediaUrl(Map<String, dynamic> data, {bool preferImage = true}) {
  final items = _extractPostMediaEntries(data);
  if (items.isEmpty) return null;
  if (preferImage) {
    for (final item in items) {
      if (!item.isVideo) return item.url;
    }
  }
  return items.first.url;
}

Widget _buildMentionTextInline(String text, {TextStyle? base, TextStyle? mention}) {
  final spans = <TextSpan>[];
  final matches = _mentionExpGlobal.allMatches(text);
  int last = 0;
  for (final m in matches) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: base));
    }
    spans.add(TextSpan(text: m.group(0), style: mention));
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: base));
  }
  return RichText(text: TextSpan(children: spans, style: base));
}

class NewsFeedPage extends StatefulWidget {
  final String? initialPostId;
  final String? initialCommentId;
  final String? initialReplyId;
  const NewsFeedPage({
    super.key,
    this.initialPostId,
    this.initialCommentId,
    this.initialReplyId,
  });

  @override
  State<NewsFeedPage> createState() => _NewsFeedPageState();
}

class _NewsFeedPageState extends State<NewsFeedPage> with SingleTickerProviderStateMixin {
  final List<String> _categories = ["Tout", "Infos Officielles", "Communauté", "Buzz", "Alertes"];
  int _selectedCategory = 0;
  final ScrollController _scrollCtrl = ScrollController();
  double _scrollOffset = 0;
  static const int _pageSize = 8;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _activeCategory;
  DocumentSnapshot? _lastDoc;
  final List<QueryDocumentSnapshot> _posts = [];
  final Map<String, Map<String, dynamic>> _localOverrides = {};
  final Set<String> _boostedAuthors = {};
  final Map<String, bool> _notifyDisabledCache = {};
  late final AnimationController _bellCtl;
  int _unreadNotifCount = 0;
  static final RegExp _mentionExp = RegExp(r'@\w+');
  bool _truthy(dynamic v) {
    return v == true || v == 1 || v == '1' || v == 'true' || v == 'True';
  }

  Future<bool> _notificationsEnabledForUser(String uid) async {
    if (uid.isEmpty) return false;
    final cached = _notifyDisabledCache[uid];
    if (cached != null) return cached != true;
    try {
      final snap = await FirebaseFirestore.instance.collection('notification_settings').doc(uid).get();
      final data = snap.data() ?? <String, dynamic>{};
      final disabled = data['disabled'] == true || data['disabled'] == 1 || data['disabled'] == '1' || data['disabled'] == 'true';
      _notifyDisabledCache[uid] = disabled;
      return !disabled;
    } catch (_) {
      // Fail-open: if settings cannot be read, keep notifications enabled.
      return true;
    }
  }

  void _setBellAnimating(bool animate) {
    if (animate) {
      if (!_bellCtl.isAnimating) _bellCtl.repeat(reverse: true);
    } else {
      if (_bellCtl.isAnimating) _bellCtl.stop();
      _bellCtl.value = 0;
    }
  }

  void _maybeUpdateBellAnimation(int unreadCount) {
    if (_unreadNotifCount == unreadCount) return;
    _unreadNotifCount = unreadCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setBellAnimating(unreadCount > 0);
    });
  }

  void _openSearch() {
    showSearch<void>(
      context: context,
      delegate: _NewsFeedSearchDelegate(
        isDark: Theme.of(context).brightness == Brightness.dark,
        onOpenPost: (postId) => _openComments(postId),
      ),
    );
  }
  String _safeName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Utilisateur';
    if (n.contains('@')) {
      return 'Utilisateur';
    }
    return n;
  }

  String _firstNameFromData(Map<String, dynamic> data) {
    final keys = ['firstName', 'firstname', 'prenom', 'givenName'];
    for (final k in keys) {
      final v = data[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  Widget _buildNameWithBadge({
    required String authorId,
    required String fallbackName,
    required TextStyle textStyle,
    double badgeFont = 10,
  }) {
    if (authorId.isEmpty) {
      return Text(fallbackName, style: textStyle);
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchAuthorProfile(authorId: authorId, fallbackName: fallbackName),
      builder: (context, snap) {
        final displayName = _safeName(snap.data?['name']?.toString() ?? fallbackName);
        final accountType = snap.data?['collection']?.toString();
        final isCert = snap.data?['isCert'] == true;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(displayName, style: textStyle)),
            if (isCert || accountType != null) ...[
              const SizedBox(width: 6),
              AccountBadges(isCertified: isCert, accountType: accountType, fontSize: badgeFont),
            ],
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchAuthorProfile({
    required String authorId,
    required String fallbackName,
  }) async {
    try {
      for (final col in ['enterprise_users', 'pro_users', 'classic_users']) {
        final doc = await FirebaseFirestore.instance.collection(col).doc(authorId).get();
        if (doc.exists) {
          final data = doc.data() ?? {};
          final first = _firstNameFromData(data);
          final name = UserUtils.formatName(data);
          final displayName = _safeName(first.isNotEmpty ? first : (name.isNotEmpty ? name : fallbackName));
          final isCert = _truthy(data['isCertified']);
          return {'name': displayName, 'collection': col, 'isCert': isCert};
        }
      }
      final doc = await FirebaseFirestore.instance.collection('users').doc(authorId).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final first = _firstNameFromData(data);
        final name = UserUtils.formatName(data);
        final displayName = _safeName(first.isNotEmpty ? first : (name.isNotEmpty ? name : fallbackName));
        final isCert = _truthy(data['isCertified']);
        return {'name': displayName, 'collection': null, 'isCert': isCert};
      }
    } catch (e) {
      debugPrint('NewsFeed author profile error: $e');
    }
    return {'name': _safeName(fallbackName), 'collection': null, 'isCert': false};
  }

  Future<Map<String, dynamic>> _getUserProfileAny(String uid) async {
    const cols = ['enterprise_users', 'pro_users', 'classic_users', 'users'];
    Map<String, dynamic>? firstData;
    String? firstCol;
    Map<String, dynamic>? bestNameData;
    String? bestNameCol;
    for (final col in cols) {
      try {
        final snap = await FirebaseFirestore.instance.collection(col).doc(uid).get();
        if (!snap.exists) continue;
        final data = snap.data() ?? <String, dynamic>{};
        firstData ??= data;
        firstCol ??= col;

        final avatar = (data['photoUrl'] ?? data['photo'] ?? data['avatar'] ?? data['profilePhoto'] ?? '').toString().trim();
        final firstName = _firstNameFromData(data).trim();
        final formatted = UserUtils.formatName(data).trim();
        // Prefer a doc that actually contains a photo first (fixes cases where one collection has name but no photo).
        if (avatar.isNotEmpty) return {'collection': col, 'data': data};

        // If no avatar, keep the first non-empty name as a fallback.
        if (bestNameData == null && (firstName.isNotEmpty || formatted.isNotEmpty)) {
          bestNameData = data;
          bestNameCol = col;
        }
      } catch (_) {}
    }
    if (bestNameData != null) return {'collection': bestNameCol, 'data': bestNameData};
    return {'collection': firstCol, 'data': firstData ?? <String, dynamic>{}};
  }
  static const List<Map<String, String>> _reactionOptions = [
    {'key': 'like', 'emoji': '👍'},
    {'key': 'love', 'emoji': '❤️'},
    {'key': 'laugh', 'emoji': '😂'},
    {'key': 'wow', 'emoji': '😮'},
    {'key': 'sad', 'emoji': '😢'},
  ];

  @override
  void initState() {
    super.initState();
    _bellCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _scrollCtrl.addListener(() {
      if (!mounted) return;
      setState(() => _scrollOffset = _scrollCtrl.offset);
      final max = _scrollCtrl.position.maxScrollExtent;
      if (!_loadingInitial && _scrollCtrl.position.pixels > max - 420) {
        _loadMorePosts();
      }
    });
    _loadInitialPosts();
    if (widget.initialPostId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openComments(
          widget.initialPostId!,
          jumpCommentId: widget.initialCommentId,
          jumpReplyId: widget.initialReplyId,
        );
      });
    }
  }

  List<QueryDocumentSnapshot> _buildDisplayPosts() {
    if (_boostedAuthors.isEmpty) return _posts;
    final out = <QueryDocumentSnapshot>[];
    for (var i = 0; i < _posts.length; i++) {
      final doc = _posts[i];
      out.add(doc);
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final authorId = (data['authorId'] ?? '').toString();
      if (authorId.isNotEmpty && _boostedAuthors.contains(authorId) && i % 2 == 0) {
        // Boost: re-show a followed author's post more often.
        out.add(doc);
      }
    }
    return out;
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _bellCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF4F4F7);
    final Color cardBg = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color textColor = isDark ? const Color(0xFFE9EDEF) : Colors.black87;
    final Color subText = isDark ? const Color(0xFF8696A0) : Colors.black54;
    final Color chipBg = isDark ? const Color(0xFF202C33) : Colors.white;
    final Color inputBg = isDark ? const Color(0xFF202C33) : const Color(0xFFF6F1EA);
    final Color divider = isDark ? const Color(0xFF1F2A33) : Colors.black12;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF9F3EC), Color(0xFFF2F4F7), Color(0xFFEFF3F8)],
                ),
              ),
            ),
          ),
          if (isDark)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0E1114), Color(0xFF14181C), Color(0xFF101316)],
                  ),
                ),
              ),
            ),
          RefreshIndicator(
            onRefresh: _loadInitialPosts,
            child: CustomScrollView(
              controller: _scrollCtrl,
              slivers: [
                SliverAppBar(
                  pinned: true,
                  floating: true,
                  expandedHeight: 90,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  flexibleSpace: FlexibleSpaceBar(
                    background: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                        child: _buildHeader((_scrollOffset / 80).clamp(0.0, 1.0)),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildFilterBar()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: _buildCreatePostArea(),
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 16)),
                _buildPostsSliver(),
                _buildLoadMoreSliver(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadInitialPosts() async {
    if (!mounted) return;
    setState(() {
      _loadingInitial = true;
      _posts.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    try {
      Query query = FirebaseFirestore.instance.collection('posts').orderBy('createdAt', descending: true);
      if (_activeCategory != null) {
        query = query.where('category', isEqualTo: _activeCategory);
      }
      // Cache-first for offline/fast UI
      try {
        final cacheSnap = await query.limit(_pageSize).get(const GetOptions(source: Source.cache));
        if (cacheSnap.docs.isNotEmpty) {
          _posts
            ..clear()
            ..addAll(cacheSnap.docs);
          _lastDoc = cacheSnap.docs.last;
          _hasMore = cacheSnap.docs.length >= _pageSize;
          if (mounted) setState(() => _loadingInitial = false);
        }
      } catch (_) {}

      final snap = await query.limit(_pageSize).get(const GetOptions(source: Source.serverAndCache));
      _posts
        ..clear()
        ..addAll(snap.docs);
      _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMore = snap.docs.length >= _pageSize;
    } catch (_) {
      _hasMore = false;
    } finally {
      if (mounted) setState(() => _loadingInitial = false);
    }
  }

  Future<void> _loadMorePosts() async {
    if (_loadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      Query query = FirebaseFirestore.instance.collection('posts').orderBy('createdAt', descending: true);
      if (_activeCategory != null) {
        query = query.where('category', isEqualTo: _activeCategory);
      }
      QuerySnapshot snap;
      try {
        snap = await query.startAfterDocument(_lastDoc!).limit(_pageSize).get(const GetOptions(source: Source.serverAndCache));
      } catch (_) {
        snap = await query.startAfterDocument(_lastDoc!).limit(_pageSize).get(const GetOptions(source: Source.cache));
      }
      if (snap.docs.isNotEmpty) {
        _posts.addAll(snap.docs);
        _lastDoc = snap.docs.last;
      }
      _hasMore = snap.docs.length >= _pageSize;
    } catch (_) {
      _hasMore = false;
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onCategoryChanged(int index) {
    setState(() => _selectedCategory = index);
    _activeCategory = index == 0 ? null : _categories[index];
    _loadInitialPosts();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _currentUserDocStream() async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      yield* const Stream.empty();
      return;
    }
    final uid = user.uid;
    final collections = ['enterprise_users', 'pro_users', 'classic_users', 'users'];
    for (final col in collections) {
      try {
        final doc = await FirebaseFirestore.instance.collection(col).doc(uid).get();
        if (doc.exists) {
          yield* FirebaseFirestore.instance.collection(col).doc(uid).snapshots();
          return;
        }
      } catch (_) {}
    }
    yield* FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  String _pickAvatar(Map<String, dynamic>? data, User? user) {
    final raw = (data?['photoUrl'] ?? data?['photo'] ?? data?['avatar'] ?? user?.photoURL ?? '') as String? ?? '';
    return raw;
  }

  String _pickName(Map<String, dynamic>? data, User? user) {
    final name = UserUtils.formatName(data);
    if (name.isNotEmpty) return name;
    if ((data?['displayName'] ?? '').toString().isNotEmpty) return data!['displayName'].toString();
    return user?.displayName ?? 'Utilisateur';
  }

  void _patchLocalPost(String postId, Map<String, dynamic> patch) {
    final current = _localOverrides[postId] ?? {};
    _localOverrides[postId] = {...current, ...patch};
    if (mounted) setState(() {});
  }

  int _getPostInt(String postId, String key) {
    final override = _localOverrides[postId];
    if (override != null && override[key] is int) return override[key] as int;
    for (final doc in _posts) {
      if (doc.id == postId) {
        final base = doc.data() as Map<String, dynamic>? ?? {};
        final val = base[key];
        if (val is int) return val;
      }
    }
    return 0;
  }

  List<String> _extractMentions(String text) {
    return _mentionExp.allMatches(text).map((m) => m.group(0) ?? '').where((e) => e.isNotEmpty).toList();
  }

  String _activeMentionQuery(String text) {
    final idx = text.lastIndexOf('@');
    if (idx == -1) return '';
    final after = text.substring(idx + 1);
    if (after.contains(' ') || after.contains('\n')) return '';
    return after.trim();
  }

  String _applyMention(String text, String display) {
    final idx = text.lastIndexOf('@');
    if (idx == -1) return text;
    final before = text.substring(0, idx);
    final compact = display.replaceAll(' ', '');
    return '$before@$compact ';
  }

  Widget _buildMentionText(String text, {TextStyle? base, TextStyle? mention}) {
    final spans = <TextSpan>[];
    final matches = _mentionExp.allMatches(text);
    int last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      }
      spans.add(TextSpan(text: m.group(0), style: mention));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: base));
    }
    return RichText(text: TextSpan(children: spans, style: base));
  }

  Widget _buildPostsSliver() {
    if (_loadingInitial) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 40, 16, 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_posts.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: _buildEmptyState(),
        ),
      );
    }

    final displayPosts = _buildDisplayPosts();
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
                        final doc = displayPosts[index];
                        final base = doc.data() as Map<String, dynamic>? ?? {};
                        final override = _localOverrides[doc.id] ?? {};
                        final data = {...base, ...override};
                        final authorId = (data['authorId'] ?? '').toString();
                        final isFollowing = authorId.isNotEmpty && _boostedAuthors.contains(authorId);
                        final int animMs = 320 + (index % 6) * 40;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 20, end: 0),
              duration: Duration(milliseconds: animMs),
              curve: Curves.easeOutQuart,
              builder: (context, v, child) => Transform.translate(
                offset: Offset(0, v),
                child: Opacity(opacity: (1 - v / 20).clamp(0.0, 1.0), child: child),
              ),
                              child: VerticalNewsPost(
                                postId: doc.id,
                                data: data,
                                onLikeToggle: () => _toggleLike(doc.id, data),
                                onReaction: (key) => _toggleReaction(doc.id, data, key),
                                onCommentTap: () => _openComments(doc.id),
                                onShareTap: () => _sharePost(doc.id, data),
                                onEdit: () => _openEditPost(doc.id, data),
                                onDelete: () => _deletePost(doc.id),
                                isFollowing: isFollowing,
                                onFollowToggle: authorId.isEmpty
                                    ? null
                                    : () {
                                        setState(() {
                                          if (isFollowing) {
                                            _boostedAuthors.remove(authorId);
                                          } else {
                                            _boostedAuthors.add(authorId);
                                          }
                                        });
                                      },
                              ),
            ),
          );
        },
        childCount: displayPosts.length,
      ),
    );
  }

  Widget _buildLoadMoreSliver() {
    if (_loadingMore) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_hasMore) {
      return const SliverToBoxAdapter(child: SizedBox(height: 24));
    }
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 6, 16, 24),
        child: Center(child: Text('Fin du fil')),
      ),
    );
  }

  Widget _buildHeader(double opacity) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? const Color(0xFFE9EDEF) : Colors.black;
    final Color card = isDark ? const Color(0xFF111B21) : Colors.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: card.withOpacity(0.85 + (opacity * 0.1)),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08 * opacity), blurRadius: 18, offset: const Offset(0, 10)),
        ],
      ),
      child: Transform.scale(
        scale: 0.98 + (opacity * 0.02),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 6))],
                ),
                child: Icon(Icons.arrow_back, color: textColor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Actu",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: textColor),
              ),
            ),
            GestureDetector(
              onTap: _openSearch,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 6))],
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: textColor),
                    const SizedBox(width: 8),
                    Text('Rechercher', style: TextStyle(color: textColor)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsPage()),
                );
              },
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .where('toUserId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                    .snapshots(),
                builder: (context, snap) {
                  final docs = snap.data?.docs ?? const <QueryDocumentSnapshot>[];
                  final count = docs.where((d) {
                    final data = d.data() as Map<String, dynamic>? ?? const {};
                    return data['seen'] != true;
                  }).length;
                  _maybeUpdateBellAnimation(count);

                  final bell = AnimatedBuilder(
                    animation: _bellCtl,
                    builder: (context, child) {
                      if (count <= 0) return child!;
                      final v = Curves.easeInOut.transform(_bellCtl.value);
                      final scale = 1.0 + (0.06 * v);
                      final rot = math.sin(_bellCtl.value * math.pi * 2) * 0.06;
                      return Transform.rotate(
                        angle: rot,
                        child: Transform.scale(scale: scale, child: child),
                      );
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 6)),
                          if (count > 0) BoxShadow(color: const Color(0xFFFB8C00).withOpacity(0.22), blurRadius: 14, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: Icon(Icons.notifications_none, color: textColor),
                    ),
                  );

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      bell,
                      if (count > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3))],
                            ),
                            child: Text(
                              count > 99 ? '99+' : '$count',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildFilterBar() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => _onCategoryChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                gradient: i == _selectedCategory
                    ? const LinearGradient(colors: [Color(0xFFFB8C00), Color(0xFFF4511E)])
                    : null,
                color: i == _selectedCategory ? null : (isDark ? const Color(0xFF202C33) : Colors.white),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(i == _selectedCategory ? 0.18 : 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 160),
                scale: i == _selectedCategory ? 1.02 : 1.0,
                child: Text(
                  _categories[i],
                  style: TextStyle(
                    color: i == _selectedCategory ? Colors.white : (isDark ? const Color(0xFFE9EDEF) : Colors.black87),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreatePostArea() {
    final user = FirebaseAuth.instance.currentUser;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color card = isDark ? const Color(0xFF1B1F23) : Colors.white;
    final Color inputBg = isDark ? const Color(0xFF20252B) : const Color(0xFFF6F1EA);
    final Color hint = isDark ? Colors.white60 : Colors.black54;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _currentUserDocStream(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final avatar = _pickAvatar(data, user);
        final avatarUrl = avatar.isNotEmpty ? avatar : '';
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundImage: avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null,
                child: avatarUrl.isEmpty ? Icon(Icons.person, color: isDark ? Colors.white70 : Colors.black54) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _openCreatePostSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: inputBg,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      "A quoi pensez-vous ?",
                      style: TextStyle(color: hint),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _openCreatePostSheet,
                child: AnimatedScale(
                  scale: 1.0,
                  duration: const Duration(milliseconds: 140),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFFB8C00), Color(0xFFF4511E)]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                    ),
                    child: const Icon(Icons.add_a_photo_outlined, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color card = isDark ? const Color(0xFF1B1F23) : Colors.white;
    final Color text = isDark ? Colors.white : Colors.black87;
    final Color sub = isDark ? Colors.white70 : Colors.black54;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Text('Aucune publication', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: text)),
          const SizedBox(height: 6),
          Text('Sois le premier a publier quelque chose.', style: TextStyle(color: sub)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _openCreatePostSheet,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Creer un post'),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Aucun exemple disponible.'),
        ],
      ),
    );
  }

  Future<void> _openCreatePostSheet() async {
    final textCtrl = TextEditingController();
    final picker = ImagePicker();
    final List<_PickedMedia> selectedMedia = [];
    String selectedCat = _selectedCategory == 0 ? _categories[1] : _categories[_selectedCategory];
    bool isPosting = false;
    double uploadProgress = 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subText = isDark ? Colors.white70 : Colors.black54;
    final muted = isDark ? Colors.white54 : Colors.black38;
    final divider = isDark ? Colors.white12 : Colors.black12;
    final fieldBg = isDark ? const Color(0xFF132026) : const Color(0xFFF2F4F5);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx2, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(height: 4, width: 40, decoration: BoxDecoration(color: divider, borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Creer une publication', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textCtrl,
                    minLines: 3,
                    maxLines: 6,
                    onChanged: (_) => setModal(() {}),
                    decoration: InputDecoration(
                      hintText: "Ecris quelque chose...",
                      hintStyle: TextStyle(color: muted),
                      filled: true,
                      fillColor: fieldBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: divider)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: divider)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
                    ),
                    style: TextStyle(color: textColor),
                  ),
                  if (_activeMentionQuery(textCtrl.text).isNotEmpty)
                    SizedBox(
                      height: 130,
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('users').limit(20).snapshots(),
                        builder: (context, snap) {
                          final query = _activeMentionQuery(textCtrl.text).toLowerCase();
                          final docs = snap.data?.docs ?? [];
                          final matches = docs.where((d) {
                            final data = d.data() as Map<String, dynamic>? ?? {};
                            final name = UserUtils.formatName(data);
                            final display = name.isNotEmpty ? name : (data['displayName'] ?? 'Utilisateur').toString();
                            final lower = display.toLowerCase();
                            final compact = lower.replaceAll(' ', '');
                            return lower.contains(query) || compact.contains(query);
                          }).take(6).toList();
                          if (matches.isEmpty) return const SizedBox.shrink();
                          return ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (c, i) {
                              final data = matches[i].data() as Map<String, dynamic>? ?? {};
                              final name = UserUtils.formatName(data);
                              final display = name.isNotEmpty ? name : (data['displayName'] ?? 'Utilisateur').toString();
                              final avatar = (data['photoUrl'] ?? data['photo'] ?? data['avatar'] ?? '').toString();
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                                  child: avatar.isEmpty ? Icon(Icons.person, color: subText) : null,
                                ),
                                title: Text(display, style: TextStyle(fontSize: 13, color: textColor)),
                                onTap: () {
                                  final updated = _applyMention(textCtrl.text, display);
                                  textCtrl.text = updated;
                                  textCtrl.selection = TextSelection.collapsed(offset: updated.length);
                                  setModal(() {});
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (isPosting)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LinearProgressIndicator(
                        value: uploadProgress == 0.0 ? null : uploadProgress,
                        minHeight: 6,
                        color: Colors.orange,
                        backgroundColor: Colors.orange.withOpacity(0.15),
                      ),
                    ),
                  Row(
                    children: [
                      Text('Categorie:', style: TextStyle(color: textColor)),
                      const SizedBox(width: 10),
                      DropdownButton<String>(
                        value: selectedCat,
                        dropdownColor: sheetBg,
                        style: TextStyle(color: textColor),
                        items: _categories.where((c) => c != 'Tout').map((c) {
                          return DropdownMenuItem(value: c, child: Text(c));
                        }).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setModal(() => selectedCat = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (selectedMedia.isNotEmpty)
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: selectedMedia.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final media = selectedMedia[i];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: media.isVideo
                                ? Container(
                                    width: 80,
                                    height: 80,
                                    color: const Color(0xFF111827),
                                    child: const Center(
                                      child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 34),
                                    ),
                                  )
                                : (kIsWeb
                                    ? Image.memory(media.bytes ?? Uint8List(0), width: 80, height: 80, fit: BoxFit.cover)
                                    : Image.file(File(media.path ?? ''), width: 80, height: 80, fit: BoxFit.cover)),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final imgs = await picker.pickMultiImage(imageQuality: 80);
                          if (imgs.isNotEmpty) {
                            final picked = <_PickedMedia>[];
                            for (final x in imgs) {
                              if (kIsWeb) {
                                final bytes = await x.readAsBytes();
                                picked.add(_PickedMedia(bytes: bytes, name: x.name));
                              } else {
                                picked.add(_PickedMedia(path: x.path, name: x.name));
                              }
                            }
                            setModal(() {
                              selectedMedia.addAll(picked);
                            });
                          }
                        },
                        icon: Icon(Icons.photo_library_outlined, color: subText),
                        label: Text('Photos', style: TextStyle(color: textColor)),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final vid = await picker.pickVideo(source: ImageSource.gallery);
                          if (vid == null) return;
                          if (kIsWeb) {
                            final bytes = await vid.readAsBytes();
                            if (bytes.isEmpty) return;
                            setModal(() {
                              selectedMedia.add(_PickedMedia(bytes: bytes, isVideo: true, name: vid.name));
                            });
                          } else {
                            setModal(() {
                              selectedMedia.add(_PickedMedia(path: vid.path, isVideo: true, name: vid.name));
                            });
                          }
                        },
                        icon: Icon(Icons.videocam_outlined, color: subText),
                        label: Text('Videos', style: TextStyle(color: textColor)),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: isPosting
                            ? null
                            : () async {
                                final text = textCtrl.text.trim();
                                if (text.isEmpty && selectedMedia.isEmpty) return;
                                debugPrint('[NewsFeed] Publish tapped. textLen=${text.length} media=${selectedMedia.length} cat=$selectedCat');
                                setModal(() {
                                  isPosting = true;
                                  uploadProgress = 0.0;
                                });
                                try {
                                  await _createPost(
                                    text,
                                    selectedMedia,
                                    selectedCat,
                                    onProgress: (p) {
                                      setModal(() => uploadProgress = p);
                                    },
                                  );
                                  await _loadInitialPosts();
                                  if (context.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  debugPrint('[NewsFeed] Publish error: $e');
                                  setModal(() => isPosting = false);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Echec de publication: $e')),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        child: isPosting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Publier'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  String _safeMediaExt(String? value, {required bool isVideo}) {
    final src = (value ?? '').trim();
    final dot = src.lastIndexOf('.');
    final fallback = isVideo ? '.mp4' : '.jpg';
    if (dot == -1 || dot == src.length - 1) return fallback;
    final ext = src.substring(dot).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,6}$').hasMatch(ext)) return fallback;
    if (isVideo) {
      const allowed = {'.mp4', '.mov', '.m4v', '.webm', '.mkv', '.avi', '.3gp'};
      return allowed.contains(ext) ? ext : '.mp4';
    }
    const allowed = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic', '.heif'};
    return allowed.contains(ext) ? ext : '.jpg';
  }

  Future<void> _createPost(
    String text,
    List<_PickedMedia> localMedia,
    String category, {
    required void Function(double) onProgress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    debugPrint('[NewsFeed] _createPost start user=${user.uid} media=${localMedia.length} cat=$category');
    final profile = await _getUserProfileAny(user.uid);
    final userData = profile['data'] as Map<String, dynamic>?;
    final authorName = _pickName(userData, user);
    final authorAvatar = _pickAvatar(userData, user);

    final List<String> imageUrls = [];
    final List<String> videoUrls = [];
    final List<Map<String, String>> media = [];
    final int total = localMedia.isEmpty ? 1 : localMedia.length;
    for (int i = 0; i < localMedia.length; i++) {
      final picked = localMedia[i];
      if (kIsWeb && (picked.bytes == null || picked.bytes!.isEmpty)) {
        debugPrint('[NewsFeed] skip empty web media index=$i');
        continue;
      }
      if (!kIsWeb && (picked.path == null || picked.path!.isEmpty)) {
        debugPrint('[NewsFeed] skip empty file media index=$i');
        continue;
      }
      final mediaType = picked.isVideo ? 'video' : 'image';
      debugPrint('[NewsFeed] upload $mediaType index=$i (supabase)');
      if (!SupabaseService.isInitialized) {
        throw Exception('Supabase non initialisé. Vérifie SUPABASE_URL et SUPABASE_ANON_KEY.');
      }
      final ext = _safeMediaExt(picked.name ?? picked.path, isVideo: picked.isVideo);
      final fileName = 'news_feed/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$i$ext';
      final startProgress = i / total;
      final stepWeight = 1 / total;
      onProgress((startProgress + (0.06 * stepWeight)).clamp(0.0, 1.0));
      Uint8List bytes = picked.bytes ?? Uint8List(0);
      if (bytes.isEmpty && !kIsWeb && (picked.path ?? '').trim().isNotEmpty) {
        final path = picked.path!.trim();
        try {
          bytes = await XFile(path).readAsBytes();
        } catch (_) {}
        if (bytes.isEmpty) {
          try {
            bytes = await File(path).readAsBytes();
          } catch (_) {}
        }
      }
      if (bytes.isEmpty) {
        throw Exception('Media local inaccessible sur ce telephone. Selectionne le fichier a nouveau.');
      }
      final publicUrl = await SupabaseService.uploadBytes(
        bytes,
        fileName,
        _newsFeedBucket,
      );
      if (picked.isVideo) {
        videoUrls.add(publicUrl);
        media.add({'type': 'video', 'url': publicUrl});
      } else {
        imageUrls.add(publicUrl);
        media.add({'type': 'image', 'url': publicUrl});
      }
      final current = (i + 1) / total;
      onProgress(current.clamp(0.0, 1.0));
    }

    debugPrint('[NewsFeed] uploading done images=${imageUrls.length} videos=${videoUrls.length}');
    final docRef = await FirebaseFirestore.instance.collection('posts').add({
      'authorId': user.uid,
      'authorName': authorName,
      'authorAvatar': authorAvatar,
      'text': text,
      'images': imageUrls,
      'videos': videoUrls,
      'media': media,
      'category': category,
      'createdAt': FieldValue.serverTimestamp(),
      'likes': 0,
      'likedBy': [],
      'reactions': {},
      'reactionsBy': {},
      'commentsCount': 0,
      'sharesCount': 0,
      'updatedAt': FieldValue.serverTimestamp(),
      'mentions': _extractMentions(text),
    });
    debugPrint('[NewsFeed] post created id=${docRef.id}');
    await _notifyMentions(
      text: text,
      fromUserId: user.uid,
      fromName: authorName,
      fromAvatar: authorAvatar,
      postId: docRef.id,
      commentId: null,
      replyId: null,
    );
    debugPrint('[NewsFeed] _createPost done');
  }

  Future<void> _toggleLike(String postId, Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final List<dynamic> likedByLocal = List<dynamic>.from(data['likedBy'] ?? []);
    final bool isLikedLocal = likedByLocal.contains(user.uid);
    if (isLikedLocal) {
      likedByLocal.remove(user.uid);
    } else {
      likedByLocal.add(user.uid);
    }
    final int likesLocal = (data['likes'] ?? 0) + (isLikedLocal ? -1 : 1);
    _patchLocalPost(postId, {'likedBy': likedByLocal, 'likes': likesLocal});

    final ref = FirebaseFirestore.instance.collection('posts').doc(postId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final d = snap.data() as Map<String, dynamic>;
      final List<dynamic> likedBy = List<dynamic>.from(d['likedBy'] ?? []);
      final bool isLiked = likedBy.contains(user.uid);
      if (isLiked) {
        likedBy.remove(user.uid);
        tx.update(ref, {'likedBy': likedBy, 'likes': FieldValue.increment(-1)});
      } else {
        likedBy.add(user.uid);
        tx.update(ref, {'likedBy': likedBy, 'likes': FieldValue.increment(1)});
      }
    });
  }

  Future<void> _openComments(
    String postId, {
    String? jumpCommentId,
    String? jumpReplyId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final ctrl = TextEditingController();
    bool isSending = false;
    int commentLimit = jumpCommentId != null ? 50 : 12;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subText = isDark ? Colors.white70 : Colors.black54;
    final muted = isDark ? Colors.white54 : Colors.black38;
    final divider = isDark ? Colors.white12 : Colors.black12;
    final fieldBg = isDark ? const Color(0xFF132026) : const Color(0xFFF2F4F5);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModal) {
            final media = MediaQuery.of(ctx2);
            // Keep the sheet responsive when the keyboard is shown.
            // Using AnimatedPadding alone can overflow if we also use a fixed height.
            final desiredH = media.size.height * 0.82;
            final sheetH = (desiredH - media.viewInsets.bottom).clamp(320.0, desiredH);

            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
              child: SizedBox(
                height: sheetH,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      children: [
                  Container(height: 4, width: 40, decoration: BoxDecoration(color: divider, borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Commentaires', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('posts')
                          .doc(postId)
                          .collection('comments')
                          .orderBy('createdAt', descending: true)
                          .limit(commentLimit)
                          .snapshots(),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return Center(child: Text('Aucun commentaire', style: TextStyle(color: muted)));
                        }
                        if (jumpCommentId != null) {
                          final hasTarget = docs.any((d) => d.id == jumpCommentId);
                          if (hasTarget && jumpReplyId != null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _openReplies(postId, jumpCommentId, jumpReplyId: jumpReplyId);
                            });
                            jumpReplyId = null;
                          }
                        }
                        return ListView.separated(
                          itemCount: docs.length + 1,
                          separatorBuilder: (_, __) => Divider(height: 1, color: divider),
                          itemBuilder: (c, i) {
                            if (i == docs.length) {
                              if (docs.length < commentLimit) return const SizedBox.shrink();
                              return TextButton(
                                onPressed: () => setModal(() => commentLimit += 10),
                                child: Text('Charger plus', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                              );
                            }
                            final doc = docs[i];
                            final data = doc.data() as Map<String, dynamic>? ?? {};
                            final name = (data['authorName'] ?? 'Utilisateur').toString();
                            final authorId = (data['authorId'] ?? '').toString();
                            final avatar = (data['authorAvatar'] ?? '').toString();
                            final text = (data['text'] ?? '').toString();
                            final repliesCount = data['repliesCount'] is int ? data['repliesCount'] as int : 0;
                            final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
                            final reactionsBy = Map<String, dynamic>.from(data['reactionsBy'] ?? {});
                            final myReaction = user != null ? reactionsBy[user.uid] as String? : null;
                            final ts = data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null;
                            final when = ts != null ? timeago.format(ts, locale: 'fr') : '';
                            final isMine = user != null && data['authorId'] == user.uid;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                                    child: avatar.isEmpty ? Icon(Icons.person, color: subText) : null,
                                  ),
                                  title: _buildNameWithBadge(
                                    authorId: authorId,
                                    fallbackName: name,
                                    textStyle: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                                    badgeFont: 10,
                                  ),
                                  subtitle: _buildMentionText(
                                    '$text${when.isNotEmpty ? '  ·  $when' : ''}',
                                    base: TextStyle(color: textColor),
                                    mention: const TextStyle(color: Color(0xFFF4511E), fontWeight: FontWeight.w700),
                                  ),
                                  trailing: isMine
                                      ? IconButton(
                                          onPressed: () => _deleteComment(postId, doc.id),
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                        )
                                      : null,
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 64, right: 16, bottom: 6),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _reactionOptions.map((opt) {
                                      final key = opt['key']!;
                                      final emoji = opt['emoji']!;
                                      final count = reactions[key] is int ? reactions[key] as int : 0;
                                      final selected = myReaction == key;
                                      return GestureDetector(
                                        onTap: () => _toggleCommentReaction(postId, doc.id, key),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 160),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: selected ? const Color(0xFFFFF3E0) : (isDark ? const Color(0xFF132026) : Colors.white),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: selected ? const Color(0xFFF4511E) : divider),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(emoji, style: const TextStyle(fontSize: 12)),
                                              const SizedBox(width: 4),
                                              Text('$count', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: textColor)),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 64, right: 16, bottom: 6),
                                  child: Row(
                                    children: [
                                      TextButton(
                                        onPressed: () => _openReplies(postId, doc.id),
                                        child: Text('Répondre', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                                      ),
                                      if (repliesCount > 0)
                                        TextButton(
                                          onPressed: () => _openReplies(postId, doc.id),
                                          child: Text('Voir $repliesCount réponses', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          onChanged: (_) => setModal(() {}),
                          decoration: InputDecoration(
                            hintText: 'Ecrire un commentaire...',
                            hintStyle: TextStyle(color: muted),
                            filled: true,
                            fillColor: fieldBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: divider)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: divider)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
                          ),
                          style: TextStyle(color: textColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: isSending
                            ? null
                            : () async {
                                if (user == null) return;
                                final text = ctrl.text.trim();
                                if (text.isEmpty) return;
                                setModal(() => isSending = true);
                                ctrl.clear();
                                final profile = await _getUserProfileAny(user.uid);
                                final userData = profile['data'] as Map<String, dynamic>?;
                                final ref = FirebaseFirestore.instance.collection('posts').doc(postId);
                                final commentRef = await ref.collection('comments').add({
                                  'authorId': user.uid,
                                  'authorName': _pickName(userData, user),
                                  'authorAvatar': _pickAvatar(userData, user),
                                  'text': text,
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'repliesCount': 0,
                                  'reactions': {},
                                  'reactionsBy': {},
                                  'mentions': _extractMentions(text),
                                });
                                await ref.update({'commentsCount': FieldValue.increment(1)});
                                _patchLocalPost(postId, {'commentsCount': _getPostInt(postId, 'commentsCount') + 1});
                                await _notifyPostAuthorOnComment(
                                  postId: postId,
                                  commentId: commentRef.id,
                                  fromUserId: user.uid,
                                  fromName: _pickName(userData, user),
                                  fromAvatar: _pickAvatar(userData, user),
                                  text: text,
                                );
                                await _notifyMentions(
                                  text: text,
                                  fromUserId: user.uid,
                                  fromName: _pickName(userData, user),
                                  fromAvatar: _pickAvatar(userData, user),
                                  postId: postId,
                                  commentId: commentRef.id,
                                  replyId: null,
                                );
                                setModal(() => isSending = false);
                              },
                        icon: isSending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send, color: Colors.orange),
                      ),
                    ],
                  ),
                  if (_activeMentionQuery(ctrl.text).isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: media.size.height * 0.22),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('users').limit(20).snapshots(),
                        builder: (context, snap) {
                          final query = _activeMentionQuery(ctrl.text).toLowerCase();
                          final docs = snap.data?.docs ?? [];
                          final matches = docs.where((d) {
                            final data = d.data() as Map<String, dynamic>? ?? {};
                            final name = UserUtils.formatName(data);
                            final display = name.isNotEmpty ? name : (data['displayName'] ?? 'Utilisateur').toString();
                            return display.toLowerCase().contains(query);
                          }).take(6).toList();
                          if (matches.isEmpty) return const SizedBox.shrink();
                          return ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (c, i) {
                              final data = matches[i].data() as Map<String, dynamic>? ?? {};
                              final name = UserUtils.formatName(data);
                              final display = name.isNotEmpty ? name : (data['displayName'] ?? 'Utilisateur').toString();
                              final avatar = (data['photoUrl'] ?? data['photo'] ?? data['avatar'] ?? '').toString();
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                                  child: avatar.isEmpty ? Icon(Icons.person, color: subText) : null,
                                ),
                                title: Text(display, style: TextStyle(fontSize: 13, color: textColor)),
                                onTap: () {
                                  final updated = _applyMention(ctrl.text, display);
                                  ctrl.text = updated;
                                  ctrl.selection = TextSelection.collapsed(offset: updated.length);
                                  setModal(() {});
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
              ),
            );
          },
        );
      },
    );
  }

  void _sharePost(String postId, Map<String, dynamic> data) async {
    final text = (data['text'] ?? '').toString();
    if (text.isEmpty) return;
    final firstMediaUrl = _firstPostMediaUrl(data, preferImage: true);
    final content = firstMediaUrl != null ? '$text\n$firstMediaUrl' : text;
    await Share.share(content, subject: 'Publication');
    final currentShares = data['sharesCount'] is int ? data['sharesCount'] as int : 0;
    _patchLocalPost(postId, {'sharesCount': currentShares + 1});
    try {
      await FirebaseFirestore.instance.collection('posts').doc(postId).update({
        'sharesCount': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  Future<void> _deleteComment(String postId, String commentId) async {
    final ref = FirebaseFirestore.instance.collection('posts').doc(postId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      tx.delete(ref.collection('comments').doc(commentId));
      final current = (snap.data())?['commentsCount'] ?? 0;
      final next = (current is int && current > 0) ? current - 1 : 0;
      tx.update(ref, {'commentsCount': next});
    });
    final next = _getPostInt(postId, 'commentsCount') - 1;
    _patchLocalPost(postId, {'commentsCount': next < 0 ? 0 : next});
  }

  Future<void> _openReplies(
    String postId,
    String commentId, {
    String? jumpReplyId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final ctrl = TextEditingController();
    bool isSending = false;
    int replyLimit = jumpReplyId != null ? 40 : 10;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subText = isDark ? Colors.white70 : Colors.black54;
    final muted = isDark ? Colors.white54 : Colors.black38;
    final divider = isDark ? Colors.white12 : Colors.black12;
    final fieldBg = isDark ? const Color(0xFF132026) : const Color(0xFFF2F4F5);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModal) {
            // Keep the sheet responsive when the keyboard is shown.
            final media = MediaQuery.of(ctx2);
            final desiredH = media.size.height * 0.78;
            final sheetH = (desiredH - media.viewInsets.bottom).clamp(280.0, desiredH);

            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
              child: SizedBox(
                height: sheetH,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      children: [
                        Container(height: 4, width: 40, decoration: BoxDecoration(color: divider, borderRadius: BorderRadius.circular(10))),
                        const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Réponses', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('posts')
                          .doc(postId)
                          .collection('comments')
                          .doc(commentId)
                          .collection('replies')
                          .orderBy('createdAt', descending: true)
                          .limit(replyLimit)
                          .snapshots(),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return Center(child: Text('Aucune réponse', style: TextStyle(color: muted)));
                        }
                        if (jumpReplyId != null) {
                          final hasTarget = docs.any((d) => d.id == jumpReplyId);
                          if (hasTarget) {
                            jumpReplyId = null;
                          }
                        }
                        return ListView.separated(
                          itemCount: docs.length + 1,
                          separatorBuilder: (_, __) => Divider(height: 1, color: divider),
                          itemBuilder: (c, i) {
                            if (i == docs.length) {
                              if (docs.length < replyLimit) return const SizedBox.shrink();
                              return TextButton(
                                onPressed: () => setModal(() => replyLimit += 10),
                                child: Text('Charger plus', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                              );
                            }
                            final doc = docs[i];
                            final data = doc.data() as Map<String, dynamic>? ?? {};
                            final name = (data['authorName'] ?? 'Utilisateur').toString();
                            final authorId = (data['authorId'] ?? '').toString();
                            final avatar = (data['authorAvatar'] ?? '').toString();
                            final text = (data['text'] ?? '').toString();
                            final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
                            final reactionsBy = Map<String, dynamic>.from(data['reactionsBy'] ?? {});
                            final myReaction = user != null ? reactionsBy[user.uid] as String? : null;
                            final ts = data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null;
                            final when = ts != null ? timeago.format(ts, locale: 'fr') : '';
                            final isMine = user != null && data['authorId'] == user.uid;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                                    child: avatar.isEmpty ? Icon(Icons.person, color: subText) : null,
                                  ),
                                  title: _buildNameWithBadge(
                                    authorId: authorId,
                                    fallbackName: name,
                                    textStyle: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                                    badgeFont: 10,
                                  ),
                                  subtitle: _buildMentionText(
                                    '$text${when.isNotEmpty ? '  ·  $when' : ''}',
                                    base: TextStyle(color: textColor),
                                    mention: const TextStyle(color: Color(0xFFF4511E), fontWeight: FontWeight.w700),
                                  ),
                                  trailing: isMine
                                      ? IconButton(
                                          onPressed: () => _deleteReply(postId, commentId, doc.id),
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                        )
                                      : null,
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 64, right: 16, bottom: 6),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _reactionOptions.map((opt) {
                                      final key = opt['key']!;
                                      final emoji = opt['emoji']!;
                                      final count = reactions[key] is int ? reactions[key] as int : 0;
                                      final selected = myReaction == key;
                                      return GestureDetector(
                                        onTap: () => _toggleReplyReaction(postId, commentId, doc.id, key),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 160),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: selected ? const Color(0xFFFFF3E0) : (isDark ? const Color(0xFF132026) : Colors.white),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: selected ? const Color(0xFFF4511E) : divider),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(emoji, style: const TextStyle(fontSize: 12)),
                                              const SizedBox(width: 4),
                                              Text('$count', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: textColor)),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          onChanged: (_) => setModal(() {}),
                          decoration: InputDecoration(
                            hintText: 'Ecrire une réponse...',
                            hintStyle: TextStyle(color: muted),
                            filled: true,
                            fillColor: fieldBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: divider)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: divider)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
                          ),
                          style: TextStyle(color: textColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: isSending
                            ? null
                            : () async {
                                if (user == null) return;
                                final text = ctrl.text.trim();
                                if (text.isEmpty) return;
                                setModal(() => isSending = true);
                                ctrl.clear();
                                final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                                final userData = userDoc.data();
                                final ref = FirebaseFirestore.instance
                                    .collection('posts')
                                    .doc(postId)
                                    .collection('comments')
                                    .doc(commentId);
                                final replyRef = await ref.collection('replies').add({
                                  'authorId': user.uid,
                                  'authorName': _pickName(userData, user),
                                  'authorAvatar': _pickAvatar(userData, user),
                                  'text': text,
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'mentions': _extractMentions(text),
                                  'reactions': {},
                                  'reactionsBy': {},
                                });
                                await ref.update({'repliesCount': FieldValue.increment(1)});
                                await _notifyMentions(
                                  text: text,
                                  fromUserId: user.uid,
                                  fromName: _pickName(userData, user),
                                  fromAvatar: _pickAvatar(userData, user),
                                  postId: postId,
                                  commentId: commentId,
                                  replyId: replyRef.id,
                                );
                                setModal(() => isSending = false);
                              },
                        icon: isSending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send, color: Colors.orange),
                      ),
                    ],
                  ),
                  if (_activeMentionQuery(ctrl.text).isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: media.size.height * 0.22),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('users').limit(20).snapshots(),
                        builder: (context, snap) {
                          final query = _activeMentionQuery(ctrl.text).toLowerCase();
                          final docs = snap.data?.docs ?? [];
                          final matches = docs.where((d) {
                            final data = d.data() as Map<String, dynamic>? ?? {};
                            final name = UserUtils.formatName(data);
                            final display = name.isNotEmpty ? name : (data['displayName'] ?? 'Utilisateur').toString();
                            return display.toLowerCase().contains(query);
                          }).take(6).toList();
                          if (matches.isEmpty) return const SizedBox.shrink();
                          return ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (c, i) {
                              final data = matches[i].data() as Map<String, dynamic>? ?? {};
                              final name = UserUtils.formatName(data);
                              final display = name.isNotEmpty ? name : (data['displayName'] ?? 'Utilisateur').toString();
                              final avatar = (data['photoUrl'] ?? data['photo'] ?? data['avatar'] ?? '').toString();
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                                  child: avatar.isEmpty ? Icon(Icons.person, color: subText) : null,
                                ),
                                title: Text(display, style: TextStyle(fontSize: 13, color: textColor)),
                                onTap: () {
                                  final updated = _applyMention(ctrl.text, display);
                                  ctrl.text = updated;
                                  ctrl.selection = TextSelection.collapsed(offset: updated.length);
                                  setModal(() {});
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
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteReply(String postId, String commentId, String replyId) async {
    final ref = FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      tx.delete(ref.collection('replies').doc(replyId));
      final current = (snap.data())?['repliesCount'] ?? 0;
      final next = (current is int && current > 0) ? current - 1 : 0;
      tx.update(ref, {'repliesCount': next});
    });
  }

  Future<void> _toggleReaction(String postId, Map<String, dynamic> data, String reactionKey) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final Map<String, dynamic> reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
    final Map<String, dynamic> reactionsBy = Map<String, dynamic>.from(data['reactionsBy'] ?? {});
    final String? current = reactionsBy[user.uid] as String?;

    if (current == reactionKey) {
      reactionsBy.remove(user.uid);
      reactions[reactionKey] = ((reactions[reactionKey] ?? 0) as int) - 1;
    } else {
      if (current != null) {
        reactions[current] = ((reactions[current] ?? 0) as int) - 1;
      }
      reactionsBy[user.uid] = reactionKey;
      reactions[reactionKey] = ((reactions[reactionKey] ?? 0) as int) + 1;
    }

    _patchLocalPost(postId, {'reactions': reactions, 'reactionsBy': reactionsBy});

    final ref = FirebaseFirestore.instance.collection('posts').doc(postId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final d = snap.data() as Map<String, dynamic>;
      final Map<String, dynamic> r = Map<String, dynamic>.from(d['reactions'] ?? {});
      final Map<String, dynamic> rb = Map<String, dynamic>.from(d['reactionsBy'] ?? {});
      final String? curr = rb[user.uid] as String?;
      if (curr == reactionKey) {
        rb.remove(user.uid);
        r[reactionKey] = ((r[reactionKey] ?? 0) as int) - 1;
      } else {
        if (curr != null) {
          r[curr] = ((r[curr] ?? 0) as int) - 1;
        }
        rb[user.uid] = reactionKey;
        r[reactionKey] = ((r[reactionKey] ?? 0) as int) + 1;
      }
      tx.update(ref, {'reactions': r, 'reactionsBy': rb});
    });
  }

  Future<void> _toggleCommentReaction(
    String postId,
    String commentId,
    String reactionKey,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('posts').doc(postId).collection('comments').doc(commentId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final d = snap.data() as Map<String, dynamic>;
      final Map<String, dynamic> r = Map<String, dynamic>.from(d['reactions'] ?? {});
      final Map<String, dynamic> rb = Map<String, dynamic>.from(d['reactionsBy'] ?? {});
      final String? curr = rb[user.uid] as String?;
      if (curr == reactionKey) {
        rb.remove(user.uid);
        r[reactionKey] = ((r[reactionKey] ?? 0) as int) - 1;
      } else {
        if (curr != null) {
          r[curr] = ((r[curr] ?? 0) as int) - 1;
        }
        rb[user.uid] = reactionKey;
        r[reactionKey] = ((r[reactionKey] ?? 0) as int) + 1;
      }
      tx.update(ref, {'reactions': r, 'reactionsBy': rb});
    });
  }

  Future<void> _toggleReplyReaction(
    String postId,
    String commentId,
    String replyId,
    String reactionKey,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .doc(replyId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final d = snap.data() as Map<String, dynamic>;
      final Map<String, dynamic> r = Map<String, dynamic>.from(d['reactions'] ?? {});
      final Map<String, dynamic> rb = Map<String, dynamic>.from(d['reactionsBy'] ?? {});
      final String? curr = rb[user.uid] as String?;
      if (curr == reactionKey) {
        rb.remove(user.uid);
        r[reactionKey] = ((r[reactionKey] ?? 0) as int) - 1;
      } else {
        if (curr != null) {
          r[curr] = ((r[curr] ?? 0) as int) - 1;
        }
        rb[user.uid] = reactionKey;
        r[reactionKey] = ((r[reactionKey] ?? 0) as int) + 1;
      }
      tx.update(ref, {'reactions': r, 'reactionsBy': rb});
    });
  }

  Future<void> _notifyPostAuthorOnComment({
    required String postId,
    required String commentId,
    required String fromUserId,
    required String fromName,
    required String fromAvatar,
    required String text,
  }) async {
    try {
      final postSnap = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
      final post = postSnap.data() ?? <String, dynamic>{};
      // Backward-compatible: older posts may not use `authorId`.
      final toUserId = (post['authorId'] ?? post['userId'] ?? post['uid'] ?? post['authorUid'] ?? '').toString();
      if (toUserId.isEmpty) return;
      if (toUserId == fromUserId) return;
      if (!await _notificationsEnabledForUser(toUserId)) return;

      final notifRef = await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'comment',
        'toUserId': toUserId,
        'fromUserId': fromUserId,
        'fromName': fromName,
        'fromAvatar': fromAvatar,
        'postId': postId,
        'commentId': commentId,
        'replyId': null,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        'seen': false,
      });
      debugPrint('[NewsFeed] notify(comment) ok id=${notifRef.id} toUserId=$toUserId postId=$postId commentId=$commentId');
    } catch (e) {
      debugPrint('[NewsFeed] notify comment error: $e');
    }
  }

  Future<void> _notifyMentions({
    required String text,
    required String fromUserId,
    required String fromName,
    required String fromAvatar,
    required String postId,
    required String? commentId,
    required String? replyId,
  }) async {
    final rawMentions = _extractMentions(text).map((e) => e.replaceFirst('@', '').toLowerCase()).toSet();
    if (rawMentions.isEmpty) return;

    final usersSnap = await FirebaseFirestore.instance.collection('users').get();
    final recipients = <String>[];
    for (final doc in usersSnap.docs) {
      final data = doc.data();
      final name = UserUtils.formatName(data);
      final display = name.isNotEmpty ? name : (data['displayName'] ?? 'Utilisateur').toString();
      if (display.isEmpty) continue;
      final key = display.toLowerCase().replaceAll(' ', '');
      if (!rawMentions.contains(key)) continue;
      if (doc.id == fromUserId) continue;
      if (!await _notificationsEnabledForUser(doc.id)) continue;
      recipients.add(doc.id);
      await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'mention',
        'toUserId': doc.id,
        'fromUserId': fromUserId,
        'fromName': fromName,
        'fromAvatar': fromAvatar,
        'postId': postId,
        'commentId': commentId,
        'replyId': replyId,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        'seen': false,
      });
    }
    if (recipients.isNotEmpty) {
      String? imageUrl;
      try {
        final postSnap = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
        final p = postSnap.data() ?? {};
        imageUrl = _firstPostMediaUrl(p, preferImage: true);
      } catch (_) {}
      await _sendMentionPush(
        recipients: recipients,
        fromName: fromName,
        text: text,
        postId: postId,
        commentId: commentId,
        replyId: replyId,
        imageUrl: imageUrl,
      );
    }
  }

  Future<void> _sendMentionPush({
    required List<String> recipients,
    required String fromName,
    required String text,
    required String postId,
    required String? commentId,
    required String? replyId,
    String? imageUrl,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      final String avatar = user.photoURL ?? '';
      final String body = text.length > 120 ? '${text.substring(0, 117)}...' : text;
      await http.post(
        Uri.parse(kNotifierUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'recipients': recipients,
          'title': fromName,
          'body': 'vous a mentionné: $body',
          'senderAvatarUrl': avatar,
          'imageUrl': imageUrl ?? '',
          'data': {
            'type': 'mention',
            'postId': postId,
            'commentId': commentId,
            'replyId': replyId,
          },
        }),
      );
    } catch (_) {}
  }

  Future<void> _deletePost(String postId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        final isDark = Theme.of(c).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF0F171A) : Colors.white;
        final text = isDark ? Colors.white : Colors.black87;
        final sub = isDark ? Colors.white70 : Colors.black54;
        return AlertDialog(
          backgroundColor: bg,
          title: Text('Supprimer la publication ?', style: TextStyle(color: text)),
          content: Text('Cette action est definitive.', style: TextStyle(color: sub)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Annuler', style: TextStyle(color: text))),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
          ],
        );
      },
    );
    if (ok != true) return;
    await FirebaseFirestore.instance.collection('posts').doc(postId).delete();
    _loadInitialPosts();
  }

  Future<void> _openEditPost(String postId, Map<String, dynamic> data) async {
    final textCtrl = TextEditingController(text: (data['text'] ?? '').toString());
    String selectedCat = (data['category'] ?? _categories[1]).toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subText = isDark ? Colors.white70 : Colors.black54;
    final muted = isDark ? Colors.white54 : Colors.black38;
    final divider = isDark ? Colors.white12 : Colors.black12;
    final fieldBg = isDark ? const Color(0xFF132026) : const Color(0xFFF2F4F5);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 4, width: 40, decoration: BoxDecoration(color: divider, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Modifier la publication', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: "Modifier le texte...",
                  hintStyle: TextStyle(color: muted),
                  filled: true,
                  fillColor: fieldBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
                ),
                style: TextStyle(color: textColor),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('Categorie:', style: TextStyle(color: textColor)),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: selectedCat,
                    dropdownColor: sheetBg,
                    style: TextStyle(color: textColor),
                    items: _categories.where((c) => c != 'Tout').map((c) {
                      return DropdownMenuItem(value: c, child: Text(c));
                    }).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      selectedCat = v;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  await FirebaseFirestore.instance.collection('posts').doc(postId).update({
                    'text': textCtrl.text.trim(),
                    'category': selectedCat,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  _loadInitialPosts();
                  if (context.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class VerticalNewsPost extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> data;
  final VoidCallback onLikeToggle;
  final void Function(String) onReaction;
  final VoidCallback onCommentTap;
  final VoidCallback onShareTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isFollowing;
  final VoidCallback? onFollowToggle;

  const VerticalNewsPost({
    super.key,
    required this.postId,
    required this.data,
    required this.onLikeToggle,
    required this.onReaction,
    required this.onCommentTap,
    required this.onShareTap,
    this.onEdit,
    this.onDelete,
    this.isFollowing = false,
    this.onFollowToggle,
  });

  @override
  State<VerticalNewsPost> createState() => _VerticalNewsPostState();
}

class _VerticalNewsPostState extends State<VerticalNewsPost> {
  bool _truthy(dynamic v) {
    return v == true || v == 1 || v == '1' || v == 'true' || v == 'True';
  }
  String _safeName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Utilisateur';
    if (n.contains('@')) {
      return 'Utilisateur';
    }
    return n;
  }

  String _firstNameFromData(Map<String, dynamic> data) {
    final keys = ['firstName', 'firstname', 'prenom', 'givenName'];
    for (final k in keys) {
      final v = data[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }
  bool _likePressed = false;
  bool _commentPressed = false;
  bool _sharePressed = false;
  bool _isHovered = false;
  final List<Map<String, String>> _reactionOptions = _NewsFeedPageState._reactionOptions;

  String _formatCount(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)} M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)} K';
    return '$v';
  }

  Widget _actionButton({
    required bool pressed,
    required VoidCallback onTapDown,
    required VoidCallback onTapUp,
    required VoidCallback onTapCancel,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.black87,
  }) {
    return Expanded(
      child: InkWell(
        onTapDown: (_) => onTapDown(),
        onTapUp: (_) => onTapUp(),
        onTapCancel: () => onTapCancel(),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthorRow({
    required String authorId,
    required bool isFollowing,
    required VoidCallback? onFollowToggle,
    required String name,
    required String avatarUrl,
    required String timeLabel,
    required String category,
    String? accountType,
    bool isCert = false,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color text = isDark ? Colors.white : Colors.black87;
    final Color sub = isDark ? Colors.white70 : Colors.black54;
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: isDark ? Colors.white10 : Colors.black12,
          backgroundImage: avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null,
          child: avatarUrl.isEmpty ? Icon(Icons.person, size: 18, color: sub) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    name,
                    style: TextStyle(fontWeight: FontWeight.bold, color: text, fontSize: 16),
                  ),
                  if (isCert || accountType != null) ...[
                    const SizedBox(width: 6),
                    AccountBadges(isCertified: isCert, accountType: accountType, fontSize: 10),
                  ],
                  const SizedBox(width: 6),
                  Text('•', style: TextStyle(color: sub)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: authorId.isEmpty ? null : onFollowToggle,
                    child: Text(
                      isFollowing ? 'Suivi' : 'Suivre',
                      style: TextStyle(
                        color: isFollowing ? const Color(0xFF00CBA9) : const Color(0xFF64B5F6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    timeLabel,
                    style: TextStyle(color: sub, fontSize: 12),
                  ),
                  const SizedBox(width: 6),
                  Text('•', style: TextStyle(color: sub)),
                  const SizedBox(width: 6),
                  Icon(Icons.public, size: 14, color: sub),
                ],
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit' && widget.onEdit != null) widget.onEdit!();
            if (v == 'delete' && widget.onDelete != null) widget.onDelete!();
          },
          itemBuilder: (ctx) {
            final userId = FirebaseAuth.instance.currentUser?.uid;
            final isOwner = userId != null && (widget.data['authorId'] == userId);
            return [
              if (isOwner) const PopupMenuItem(value: 'edit', child: Text('Modifier')),
              if (isOwner) const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ];
          },
          child: Icon(Icons.more_horiz, color: sub),
        ),
      ],
    );
  }

  Widget _buildAuthorHeader(Map<String, dynamic> data, String timeLabel) {
    final authorId = data['authorId']?.toString();
    final fallbackName = (data['authorName'] ?? 'Utilisateur').toString();
    final fallbackAvatar = (data['authorAvatar'] ?? '').toString();
    final category = (data['category'] ?? 'INFO').toString();
    final postIsCert = _truthy(data['authorIsCertified'] ?? data['isCertified'] ?? data['certified']);
    final postAccountType = (data['authorCollection'] ?? data['authorType'] ?? data['accountType'])?.toString();

    if (authorId == null || authorId.isEmpty) {
      return _buildAuthorRow(
        authorId: '',
        isFollowing: false,
        onFollowToggle: () {},
        name: fallbackName,
        avatarUrl: fallbackAvatar,
        timeLabel: timeLabel,
        category: category,
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchAuthorProfile(authorId: authorId, fallbackName: fallbackName, fallbackAvatar: fallbackAvatar),
      builder: (context, snap) {
        final profile = snap.data;
        final displayName = _safeName(profile?['name']?.toString() ?? fallbackName);
        final avatar = profile?['avatar']?.toString() ?? fallbackAvatar;
        final collection = profile?['collection']?.toString() ?? postAccountType;
        final isCert = _truthy(profile?['isCert']) || postIsCert;
        debugPrint('[NewsFeed] authorId=$authorId postCert=$postIsCert postType=$postAccountType profileCert=${profile?['isCert']} profileType=${profile?['collection']}');
        return _buildAuthorRow(
          authorId: authorId,
          isFollowing: widget.isFollowing,
          onFollowToggle: widget.onFollowToggle,
          name: displayName,
          avatarUrl: avatar,
          timeLabel: timeLabel,
          category: category,
          accountType: collection,
          isCert: isCert,
        );
      },
    );
  }

  Widget _buildNameWithBadge({
    required String authorId,
    required String fallbackName,
    required TextStyle textStyle,
    double badgeFont = 10,
  }) {
    if (authorId.isEmpty) {
      return Text(fallbackName, style: textStyle);
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchAuthorProfile(authorId: authorId, fallbackName: fallbackName, fallbackAvatar: ''),
      builder: (context, snap) {
        final displayName = _safeName(snap.data?['name']?.toString() ?? fallbackName);
        final accountType = snap.data?['collection']?.toString();
        final isCert = snap.data?['isCert'] == true;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(displayName, style: textStyle)),
            if (isCert || accountType != null) ...[
              const SizedBox(width: 6),
              AccountBadges(isCertified: isCert, accountType: accountType, fontSize: badgeFont),
            ],
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchAuthorProfile({
    required String authorId,
    required String fallbackName,
    required String fallbackAvatar,
  }) async {
    try {
      for (final col in ['enterprise_users', 'pro_users', 'classic_users']) {
        final doc = await FirebaseFirestore.instance.collection(col).doc(authorId).get();
        if (doc.exists) {
          final data = doc.data() ?? {};
          final first = _firstNameFromData(data);
          final name = UserUtils.formatName(data);
          final displayName = _safeName(first.isNotEmpty ? first : (name.isNotEmpty ? name : fallbackName));
          final avatar = (data['photoUrl'] ?? data['photo'] ?? data['avatar'] ?? fallbackAvatar) as String? ?? '';
          final isCert = _truthy(data['isCertified']);
          return {
            'name': displayName,
            'avatar': avatar,
            'collection': col,
            'isCert': isCert,
          };
        }
      }

      final doc = await FirebaseFirestore.instance.collection('users').doc(authorId).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final first = _firstNameFromData(data);
        final name = UserUtils.formatName(data);
        final displayName = _safeName(first.isNotEmpty ? first : (name.isNotEmpty ? name : fallbackName));
        final avatar = (data['photoUrl'] ?? data['photo'] ?? data['avatar'] ?? fallbackAvatar) as String? ?? '';
        final isCert = _truthy(data['isCertified']);
        return {
          'name': displayName,
          'avatar': avatar,
          'collection': null,
          'isCert': isCert,
        };
      }
    } catch (e) {
      debugPrint('NewsFeed author profile error: $e');
    }
    return {
      'name': _safeName(fallbackName),
      'avatar': fallbackAvatar,
      'collection': null,
      'isCert': false,
    };
  }

  Widget _actionChip({
    required bool pressed,
    required VoidCallback onTap,
    required VoidCallback onTapDown,
    required VoidCallback onTapUp,
    required VoidCallback onTapCancel,
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    return GestureDetector(
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: () => onTapCancel(),
      onTap: onTap,
      child: AnimatedScale(
        scale: pressed ? 0.86 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: pressed ? Colors.orange.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: pressed
                ? [BoxShadow(color: Colors.orange.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))]
                : [],
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }
    final mediaItems = _extractPostMediaEntries(data);
    final likes = asInt(data['likes']);
    final comments = asInt(data['commentsCount']);
    final shares = asInt(data['sharesCount']);
    final likedBy = List<dynamic>.from(data['likedBy'] ?? []);
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final isLiked = userId != null && likedBy.contains(userId);
    final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
    final reactionsBy = Map<String, dynamic>.from(data['reactionsBy'] ?? {});
    final myReaction = userId != null ? reactionsBy[userId] as String? : null;
    final ts = data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null;
    final timeLabel = ts != null ? timeago.format(ts, locale: 'fr') : 'A l\'instant';

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color card = isDark ? const Color(0xFF111B21) : Colors.white;
    final Color text = isDark ? const Color(0xFFE9EDEF) : Colors.black87;
    final Color sub = isDark ? const Color(0xFF8696A0) : Colors.black54;
    final Color divider = isDark ? const Color(0xFF1F2A33) : Colors.black12;
    final glow = isDark ? const Color(0x3325D0C1) : const Color(0x22000000);
    final emojiByKey = <String, String>{
      for (final opt in _reactionOptions)
        if ((opt['key'] ?? '').isNotEmpty) opt['key']!: (opt['emoji'] ?? ''),
    };
    final reactionCounts = <String, int>{};
    for (final opt in _reactionOptions) {
      final key = opt['key'];
      if (key == null || key.isEmpty) continue;
      final cnt = asInt(reactions[key]);
      reactionCounts[key] = cnt < 0 ? 0 : cnt;
    }
    // Merge likes counter into the like reaction for the summary line.
    reactionCounts['like'] = (reactionCounts['like'] ?? 0) + likes;
    if (reactionCounts['like']! < 0) reactionCounts['like'] = 0;
    final totalReactions = reactionCounts.values.fold<int>(0, (a, b) => a + b);
    final sortedReactionKeys = reactionCounts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final visibleKeys = sortedReactionKeys.take(3).map((e) => e.key).toList();
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _isHovered ? glow : Colors.black.withOpacity(0.08),
              blurRadius: _isHovered ? 24 : 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: _buildAuthorHeader(data, timeLabel),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _buildMentionTextInline(
              (data['text'] ?? '').toString(),
              base: TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: text,
              ),
              mention: const TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1976D2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (mediaItems.isNotEmpty) _buildMediaGrid(mediaItems, widget.postId),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                if (totalReactions > 0) ...[
                  for (var i = 0; i < visibleKeys.length; i++) ...[
                    Text(emojiByKey[visibleKeys[i]] ?? '', style: const TextStyle(fontSize: 14)),
                    if (i != visibleKeys.length - 1) const SizedBox(width: 4),
                  ],
                  const SizedBox(width: 6),
                  Text(_formatCount(totalReactions), style: TextStyle(color: text)),
                ],
                const Spacer(),
                Text('${_formatCount(comments)} commentaires', style: TextStyle(color: text)),
                const SizedBox(width: 10),
                Text(_formatCount(shares), style: TextStyle(color: text)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: divider),
          Row(
            children: [
              _actionButton(
                pressed: _likePressed,
                onTapDown: () => setState(() => _likePressed = true),
                onTapUp: () => setState(() => _likePressed = false),
                onTapCancel: () => setState(() => _likePressed = false),
                icon: isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                label: 'J\'aime',
                color: isLiked ? const Color(0xFF64B5F6) : text,
                onTap: widget.onLikeToggle,
              ),
              _actionButton(
                pressed: _commentPressed,
                onTapDown: () => setState(() => _commentPressed = true),
                onTapUp: () => setState(() => _commentPressed = false),
                onTapCancel: () => setState(() => _commentPressed = false),
                icon: Icons.chat_bubble_outline,
                label: 'Commenter',
                color: text,
                onTap: widget.onCommentTap,
              ),
              _actionButton(
                pressed: _sharePressed,
                onTapDown: () => setState(() => _sharePressed = true),
                onTapUp: () => setState(() => _sharePressed = false),
                onTapCancel: () => setState(() => _sharePressed = false),
                icon: Icons.share_outlined,
                label: 'Partager',
                color: text,
                onTap: widget.onShareTap,
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  void _openMediaViewer(_PostMediaEntry media, String tag) {
    if (media.isVideo) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _VideoViewerPage(videoUrl: media.url)),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ImageViewerPage(tag: tag, imageUrl: media.url),
      ),
    );
  }

  Widget _buildMediaTile(_PostMediaEntry media, String tag) {
    if (media.isVideo) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _FeedVideoThumbnail(
            videoUrl: media.url,
            fit: BoxFit.cover,
          ),
          const Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: Colors.white70,
              size: 64,
            ),
          ),
          const Positioned(
            right: 10,
            bottom: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x99000000),
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(
                  'Video',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Hero(
      tag: tag,
      child: CachedNetworkImage(
        imageUrl: media.url,
        fit: BoxFit.cover,
        width: double.infinity,
        placeholder: (c, s) => Container(
          color: Colors.black12,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (c, s, e) => Container(
          color: Colors.black12,
          child: const Center(
            child: Icon(Icons.broken_image_outlined, size: 40, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaGrid(List<_PostMediaEntry> mediaItems, String postId) {
    if (mediaItems.isEmpty) return const SizedBox.shrink();

    if (mediaItems.length == 1) {
      final media = mediaItems.first;
      final tag = 'post-$postId-0';
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: GestureDetector(
            onTap: () => _openMediaViewer(media, tag),
            child: _buildMediaTile(media, tag),
          ),
        ),
      );
    }

    return SizedBox(
      height: 230,
      child: PageView.builder(
        itemCount: mediaItems.length,
        controller: PageController(viewportFraction: 0.95),
        itemBuilder: (context, i) {
          final media = mediaItems[i];
          final tag = 'post-$postId-$i';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: GestureDetector(
                onTap: () => _openMediaViewer(media, tag),
                child: _buildMediaTile(media, tag),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeedVideoThumbnail extends StatefulWidget {
  final String videoUrl;
  final BoxFit fit;
  const _FeedVideoThumbnail({
    required this.videoUrl,
    this.fit = BoxFit.cover,
  });

  @override
  State<_FeedVideoThumbnail> createState() => _FeedVideoThumbnailState();
}

class _FeedVideoThumbnailState extends State<_FeedVideoThumbnail> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _FeedVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _init();
    }
  }

  Future<void> _init() async {
    _ready = false;
    final prev = _controller;
    _controller = null;
    await prev?.dispose();
    final raw = widget.videoUrl.trim();
    if (raw.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(raw));
      await c.setVolume(0);
      await c.initialize();
      await c.seekTo(Duration.zero);
      if (!mounted) {
        await c.dispose();
        return;
      }
      _controller = c;
      _ready = true;
      setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (!_ready || c == null || !c.value.isInitialized) {
      return Container(color: const Color(0xFF0F172A));
    }
    final size = c.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return Container(color: const Color(0xFF0F172A));
    }
    return Container(
      color: const Color(0xFF0F172A),
      child: SizedBox.expand(
        child: FittedBox(
          fit: widget.fit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(c),
          ),
        ),
      ),
    );
  }
}

class _ImageViewerPage extends StatelessWidget {
  final String tag;
  final String imageUrl;
  const _ImageViewerPage({required this.tag, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Hero(
          tag: tag,
          child: InteractiveViewer(
            child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _VideoViewerPage extends StatefulWidget {
  final String videoUrl;
  const _VideoViewerPage({required this.videoUrl});

  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<_VideoViewerPage> {
  VideoPlayerController? _controller;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = c;
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) return;
      setState(() {});
      c.play();
    } catch (e) {
      if (!mounted) return;
      setState(() => _videoError = e.toString());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _videoError != null
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Lecture impossible.\n$_videoError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              )
            : (c != null && c.value.isInitialized)
                ? AspectRatio(
                    aspectRatio: c.value.aspectRatio,
                    child: VideoPlayer(c),
                  )
                : const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      ),
      floatingActionButton: (c != null && c.value.isInitialized)
          ? FloatingActionButton(
              backgroundColor: Colors.white24,
              onPressed: () {
                if (c.value.isPlaying) {
                  c.pause();
                } else {
                  c.play();
                }
                setState(() {});
              },
              child: Icon(
                c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.72),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.6)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PickedMedia {
  final String? path;
  final Uint8List? bytes;
  final bool isVideo;
  final String? name;
  const _PickedMedia({
    this.path,
    this.bytes,
    this.isVideo = false,
    this.name,
  });
}

class _NewsFeedSearchDelegate extends SearchDelegate<void> {
  _NewsFeedSearchDelegate({
    required this.isDark,
    required this.onOpenPost,
  }) : _recentFuture = FirebaseFirestore.instance.collection('posts').orderBy('createdAt', descending: true).limit(80).get();

  final bool isDark;
  final void Function(String postId) onOpenPost;
  final Future<QuerySnapshot> _recentFuture;
  final Map<String, Future<Map<String, dynamic>?>> _profileFutures = {};

  Color get _bg => isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
  Color get _card => isDark ? const Color(0xFF111B21) : Colors.white;
  Color get _text => isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
  Color get _sub => isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
  Color get _divider => isDark ? Colors.white12 : Colors.black12;
  static const Color _accent = Color(0xFFFB8C00);

  @override
  String get searchFieldLabel => 'Rechercher une publication...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      scaffoldBackgroundColor: _bg,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: _bg,
        foregroundColor: _text,
        elevation: 0,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: TextStyle(color: _sub),
        border: InputBorder.none,
      ),
      textTheme: base.textTheme.apply(bodyColor: _text, displayColor: _text),
    );
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Retour',
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isEmpty) return null;
    return [
      IconButton(
        tooltip: 'Effacer',
        icon: const Icon(Icons.close),
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
      ),
    ];
  }

  DateTime? _dateFrom(Map<String, dynamic> data) {
    final ts = data['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    final m = data['createdAtMs'];
    if (m is int) return DateTime.fromMillisecondsSinceEpoch(m);
    if (m is num) return DateTime.fromMillisecondsSinceEpoch(m.toInt());
    return null;
  }

  String _formatWhen(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 7) {
      String two(int v) => v < 10 ? '0$v' : '$v';
      return '${two(dt.day)}/${two(dt.month)}/${dt.year}';
    }
    return timeago.format(dt, locale: 'fr');
  }

  String _safeName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Utilisateur';
    if (n.contains('@')) return 'Utilisateur';
    return n;
  }

  String _firstName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Utilisateur';
    final parts = n.split(RegExp(r'\\s+'));
    return parts.isNotEmpty ? parts.first : n;
  }

  Future<Map<String, dynamic>?> _fetchUserDocAny(String uid) async {
    const cols = ['enterprise_users', 'pro_users', 'classic_users', 'users'];
    Map<String, dynamic>? first;
    Map<String, dynamic>? bestName;
    for (final c in cols) {
      final snap = await FirebaseFirestore.instance.collection(c).doc(uid).get();
      if (!snap.exists) continue;
      final data = snap.data();
      if (data == null) continue;
      first ??= data;
      final avatar = _pickAvatarFromProfile(data);
      final name = _pickNameFromProfile(data, '');
      // Prefer avatar first (fixes cases where one collection has name but no photo).
      if (avatar.toString().trim().isNotEmpty) return data;
      if (bestName == null && name.toString().trim().isNotEmpty) bestName = data;
    }
    return bestName ?? first;
  }

  Future<Map<String, dynamic>?> _getProfileAny(String uid) {
    return _profileFutures.putIfAbsent(uid, () => _fetchUserDocAny(uid));
  }

  String _pickAvatarFromProfile(Map<String, dynamic>? d) {
    if (d == null) return '';
    return (d['photoUrl'] ??
            d['photoURL'] ??
            d['photo_url'] ??
            d['avatarUrl'] ??
            d['photo'] ??
            d['avatar'] ??
            d['profilePhoto'] ??
            d['profile_photo'] ??
            d['imageUrl'] ??
            d['image_url'] ??
            '')
        .toString();
  }

  String _pickNameFromProfile(Map<String, dynamic>? d, String fallback) {
    if (d != null) {
      final first = (d['firstName'] ?? d['firstname'] ?? d['prenom'] ?? d['givenName'] ?? '').toString().trim();
      if (first.isNotEmpty) return first;
      final formatted = UserUtils.formatName(d).trim();
      if (formatted.isNotEmpty) return formatted;
      final dn = (d['displayName'] ?? d['name'] ?? '').toString().trim();
      if (dn.isNotEmpty) return dn;
    }
    return fallback.trim().isNotEmpty ? fallback : 'Utilisateur';
  }

  bool _match(Map<String, dynamic> data, String q) {
    final text = (data['text'] ?? '').toString().toLowerCase();
    final author = (data['authorName'] ?? '').toString().toLowerCase();
    final cat = (data['category'] ?? '').toString().toLowerCase();
    return text.contains(q) || author.contains(q) || cat.contains(q);
  }

  Widget _buildList(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: _recentFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Erreur de recherche.\n${snap.error}', textAlign: TextAlign.center, style: TextStyle(color: _sub)));
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: _accent.withOpacity(0.9)));
        }
        final q = query.trim().toLowerCase();
        final docsAll = snap.data!.docs.cast<QueryDocumentSnapshot>();
        final docs = q.isEmpty ? docsAll : docsAll.where((d) => _match(d.data() as Map<String, dynamic>? ?? const {}, q)).toList();

        if (docs.isEmpty) {
          return Center(child: Text('Aucun resultat', style: TextStyle(color: _sub, fontWeight: FontWeight.w600)));
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final postId = doc.id;
            final authorId = (data['authorId'] ?? data['userId'] ?? data['uid'] ?? data['authorUid'] ?? '').toString();
            final fallbackNameRaw = (data['authorName'] ?? '').toString().trim();
            final fallbackName = fallbackNameRaw.contains('@') ? '' : fallbackNameRaw;
            final text = (data['text'] ?? '').toString();
            final fallbackAvatar = (data['authorAvatar'] ?? '').toString();
            final category = (data['category'] ?? '').toString();
            final when = _formatWhen(_dateFrom(data));
            final mediaItems = _extractPostMediaEntries(data);
            final thumbMedia = mediaItems.isNotEmpty ? mediaItems.first : null;

            Widget tile = FutureBuilder<Map<String, dynamic>?>(
              future: authorId.isEmpty ? null : _getProfileAny(authorId),
              builder: (context, profSnap) {
                final prof = profSnap.data;
                final name = _firstName(_safeName(_pickNameFromProfile(prof, fallbackName)));
                final avatar = fallbackAvatar.isNotEmpty ? fallbackAvatar : _pickAvatarFromProfile(prof);
                if (authorId.isNotEmpty && avatar.trim().isEmpty) {
                  debugPrint('[Search] missing avatar authorId=$authorId fallbackAvatarEmpty=${fallbackAvatar.trim().isEmpty} fallbackName="$fallbackName"');
                }

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      close(context, null);
                      onOpenPost(postId);
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _divider),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(isDark ? 0.26 : 0.06), blurRadius: 18, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: isDark ? Colors.white10 : Colors.black12,
                            backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                            child: avatar.isEmpty ? Icon(Icons.person, color: _sub) : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name.isEmpty ? 'Utilisateur' : name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: _text, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                                      ),
                                    ),
                                    if (when.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(when, style: TextStyle(color: _sub, fontWeight: FontWeight.w600, fontSize: 12)),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (category.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _accent.withOpacity(isDark ? 0.20 : 0.12),
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(color: _accent.withOpacity(0.25)),
                                    ),
                                    child: Text(category, style: TextStyle(color: _accent, fontWeight: FontWeight.w700, fontSize: 12)),
                                  ),
                                if (category.isNotEmpty) const SizedBox(height: 8),
                                if (text.isNotEmpty)
                                  Text(
                                    text,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: _sub, fontWeight: FontWeight.w600, height: 1.25),
                                  ),
                              ],
                            ),
                          ),
                          if (thumbMedia != null) ...[
                            const SizedBox(width: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 62,
                                height: 62,
                                color: isDark ? Colors.white10 : Colors.black12,
                                child: thumbMedia.isVideo
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          _FeedVideoThumbnail(
                                            videoUrl: thumbMedia.url,
                                            fit: BoxFit.cover,
                                          ),
                                          const Center(
                                            child: Icon(
                                              Icons.play_circle_fill_rounded,
                                              color: Colors.white70,
                                              size: 28,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Image.network(
                                        thumbMedia.url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported_outlined, color: _sub),
                                      ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );

            tile = TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 360 + (i.clamp(0, 10) * 30)),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) {
                return Opacity(
                  opacity: v,
                  child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
                );
              },
              child: tile,
            );

            return Padding(
              padding: EdgeInsets.only(bottom: i == docs.length - 1 ? 0 : 10),
              child: tile,
            );
          },
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);
}

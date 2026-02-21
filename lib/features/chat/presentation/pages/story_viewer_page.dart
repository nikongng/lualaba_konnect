import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:intl/intl.dart';
import 'package:lualaba_konnect/shared/widgets/account_badge.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/user_utils.dart';

class StoryViewerPage extends StatefulWidget {
  final List<DocumentSnapshot> stories;
  final int initialIndex;

  const StoryViewerPage({
    super.key,
    required this.stories,
    required this.initialIndex,
  });

  @override
  StoryViewerPageState createState() => StoryViewerPageState();
}

class StoryViewerPageState extends State<StoryViewerPage>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animController;
  late final AnimationStatusListener _animStatusListener;
  int _currentIndex = 0;
  bool _isPaused = false;
  bool _isClosing = false;
  VideoPlayerController? _videoController;
  final Set<int> _likedIndices = {};
  final Map<String, String> _localCachePaths = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    // Contrôleur pour la barre de progression (5 secondes par story)
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _loadStory(index: _currentIndex);

    _animStatusListener = (status) {
      if (!mounted || _isClosing) return;
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    };
    _animController.addStatusListener(_animStatusListener);
  }

  Future<void> _loadStory({required int index, bool animatePage = true}) async {
    if (!mounted || _isClosing) return;
    if (index < 0 || index >= widget.stories.length) return;

    _animController.stop();
    _animController.reset();
    final prevController = _videoController;
    _videoController = null;
    try {
      await prevController?.dispose();
    } catch (_) {}

    final data = widget.stories[index].data() as Map<String, dynamic>;
    final videoUrl = data['videoUrl'] as String?;

    if (animatePage && _pageController.hasClients) {
      _pageController.jumpToPage(index);
    }

    // Enregistrer la vue pour la story courante
    _recordViewForStory(index);

    if (videoUrl != null && videoUrl.isNotEmpty) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _videoController = controller;
      try {
        await controller.initialize();
      } catch (e) {
        debugPrint('Story video init error: $e');
        if (identical(_videoController, controller)) _videoController = null;
        return;
      }
      if (!mounted || _isClosing || !identical(_videoController, controller)) {
        try {
          await controller.dispose();
        } catch (_) {}
        return;
      }
      setState(() {});
      final d = controller.value.duration;
      _animController.duration = (d.inMilliseconds > 0)
          ? d
          : const Duration(seconds: 5);
      controller.play();
      _animController.forward();
      return;
    }

    _animController.duration = const Duration(seconds: 5); // Image = 5 sec
    if (mounted && !_isClosing) _animController.forward();
  }

  Future<void> _recordViewForStory(int index) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = widget.stories[index];
      final id = doc.id;
      final name = FirebaseAuth.instance.currentUser?.displayName ?? '';
      final ref = FirebaseFirestore.instance
          .collection('stories')
          .doc(id)
          .collection('views')
          .doc(uid);
      await ref.set({
        'viewerId': uid,
        'viewerName': name,
        'seenAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Record view error: $e');
    }
  }

  void _nextStory() {
    if (!mounted || _isClosing) return;
    if (_currentIndex < widget.stories.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _loadStory(index: _currentIndex);
    } else {
      // Si c'est la dernière story, on ferme l'afficheur
      _closeViewer();
    }
  }

  void _prevStory() {
    if (!mounted || _isClosing) return;
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _loadStory(index: _currentIndex);
    }
  }

  void _showCommentsSheet(int index) {
    final doc = widget.stories[index];
    final id = doc.id;
    String text = '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subText = isDark ? Colors.white70 : Colors.black54;
    final muted = isDark ? Colors.white54 : Colors.black38;
    final divider = isDark ? Colors.white12 : Colors.black12;
    final fieldBg = isDark ? const Color(0xFF132026) : const Color(0xFFF2F4F6);
    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SizedBox(
            height: 360,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    'Commentaires',
                    style: TextStyle(color: textColor, fontSize: 18),
                  ),
                ),
                Divider(color: divider),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('stories')
                        .doc(id)
                        .collection('comments')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (c, snap) {
                      if (!snap.hasData || snap.data!.docs.isEmpty) {
                        return Center(
                          child: Text(
                            'Aucun commentaire',
                            style: TextStyle(color: muted),
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: snap.data!.docs.length,
                        itemBuilder: (ctx, i) {
                          final d =
                              snap.data!.docs[i].data() as Map<String, dynamic>;
                          final authorId = (d['authorId'] ?? '').toString();
                          final authorName = (d['authorName'] ?? 'Utilisateur')
                              .toString();
                          return ListTile(
                            title: Text(
                              d['text'] ?? '',
                              style: TextStyle(color: textColor),
                            ),
                            subtitle: authorId.isEmpty
                                ? Text(
                                    authorName,
                                    style: TextStyle(color: subText),
                                  )
                                : FutureBuilder<Map<String, dynamic>>(
                                    future: _fetchStoryProfile({
                                      'userId': authorId,
                                      'userName': authorName,
                                    }),
                                    builder: (context, snap) {
                                      final display =
                                          snap.data?['name']?.toString() ??
                                          authorName;
                                      final accountType = snap
                                          .data?['collection']
                                          ?.toString();
                                      final isCert =
                                          snap.data?['isCert'] == true;
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            display,
                                            style: TextStyle(color: subText),
                                          ),
                                          if (isCert ||
                                              accountType != null) ...[
                                            const SizedBox(width: 6),
                                            AccountBadges(
                                              isCertified: isCert,
                                              accountType: accountType,
                                              fontSize: 9,
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Ajouter un commentaire',
                            hintStyle: TextStyle(color: muted),
                            filled: true,
                            fillColor: fieldBg,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: divider),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          onChanged: (v) => text = v,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.send,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () async {
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          final name =
                              FirebaseAuth.instance.currentUser?.displayName ??
                              '';
                          if (text.trim().isEmpty || uid == null) return;
                          await FirebaseFirestore.instance
                              .collection('stories')
                              .doc(id)
                              .collection('comments')
                              .add({
                                'text': text.trim(),
                                'authorId': uid,
                                'authorName': name,
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                          Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Commentaire ajouté'),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showViewersSheet(int index) {
    final doc = widget.stories[index];
    final id = doc.id;
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ownerId = _ownerIdOf(data);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || ownerId.isEmpty || ownerId != uid) {
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subText = isDark ? Colors.white70 : Colors.black54;
    final muted = isDark ? Colors.white54 : Colors.black38;
    final divider = isDark ? Colors.white12 : Colors.black12;
    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    'Vus par',
                    style: TextStyle(color: textColor, fontSize: 18),
                  ),
                ),
                Divider(color: divider),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('stories')
                        .doc(id)
                        .collection('views')
                        .orderBy('seenAt', descending: true)
                        .snapshots(),
                    builder: (c, snap) {
                      if (!snap.hasData || snap.data!.docs.isEmpty) {
                        return Center(
                          child: Text(
                            'Aucun visiteur',
                            style: TextStyle(color: muted),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: snap.data!.docs.length,
                        separatorBuilder: (_, __) => Divider(color: divider),
                        itemBuilder: (ctx, i) {
                          final d =
                              snap.data!.docs[i].data() as Map<String, dynamic>;
                          final seen = d['seenAt'] is Timestamp
                              ? DateFormat.yMd().add_Hm().format(
                                  (d['seenAt'] as Timestamp).toDate(),
                                )
                              : '';
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isDark
                                  ? Colors.white24
                                  : Colors.black12,
                              child: Icon(
                                Icons.person,
                                color: textColor,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              seen,
                              style: TextStyle(color: textColor),
                            ),
                            subtitle: d['viewerName'] != null
                                ? Text(
                                    '${d['viewerName']}',
                                    style: TextStyle(color: subText),
                                  )
                                : null,
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
      },
    );
  }

  @override
  void dispose() {
    _isClosing = true;
    _pageController.dispose();
    _animController.removeStatusListener(_animStatusListener);
    _animController.stop();
    _animController.dispose();
    final controller = _videoController;
    _videoController = null;
    controller?.dispose();
    super.dispose();
  }

  void _closeViewer() {
    if (!mounted || _isClosing) return;
    _isClosing = true;
    _animController.stop();
    _videoController?.pause();
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  // ignore: unused_element
  Future<void> _ensureCached(DocumentSnapshot doc) async {
    try {
      if (!mounted) return;
      final id = doc.id;
      if (_localCachePaths.containsKey(id) && _localCachePaths[id] != null) {
        final p = _localCachePaths[id]!;
        if (File(p).existsSync()) return;
      }
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final String? url =
          data['imageUrl'] ?? data['videoUrl'] ?? data['audioUrl'];
      if (url == null || url.toString().isEmpty) return;
      final path = await _downloadAndSave(url.toString());
      if (path.isNotEmpty) {
        _localCachePaths[id] = path;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('ensureCached error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Pause au maintien, reprise au relâchement
        onTapDown: (_) {
          if (!mounted || _isClosing) return;
          setState(() => _isPaused = true);
          _animController.stop();
          _videoController?.pause();
        },

        // 2. Si le doigt quitte l'écran (on vérifie si c'est un clic ou un relâchement de maintien)
        onTapUp: (details) {
          if (!mounted || _isClosing) return;
          setState(() => _isPaused = false);

          // On calcule si on doit changer de story ou juste reprendre
          final double screenWidth = MediaQuery.of(context).size.width;
          final double dx = details.globalPosition.dx;

          // Si l'appui était court (clic), on change de story
          // Si l'appui était long, le simple fait de relâcher va déclencher la suite :
          if (dx < screenWidth / 3) {
            _prevStory();
          } else {
            _nextStory();
          }

          // On relance l'animation si on n'a pas quitté la page
          if (mounted && !_isClosing && !_animController.isCompleted) {
            _animController.forward();
            _videoController?.play();
          }
        },

        // 3. Cas où l'appui est interrompu (ex: l'utilisateur fait défiler le centre de notifications)
        onTapCancel: () {
          if (!mounted || _isClosing) return;
          setState(() => _isPaused = false);
          if (!_animController.isCompleted) _animController.forward();
          _videoController?.play();
        },
        child: Stack(
          children: [
            // Affichage du média (Page view)
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.stories.length,
              itemBuilder: (context, index) {
                final story =
                    widget.stories[index].data() as Map<String, dynamic>;
                final videoUrl = story['videoUrl'] as String?;
                final imageUrl = story['imageUrl'] as String?;
                final audioUrl = story['audioUrl'] as String?;
                final caption =
                    (story['caption'] ??
                            story['text'] ??
                            story['legende'] ??
                            '')
                        as String;

                if (videoUrl != null &&
                    videoUrl.isNotEmpty &&
                    index == _currentIndex) {
                  return _videoController != null &&
                          _videoController!.value.isInitialized
                      ? Center(
                          child: AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: VideoPlayer(_videoController!),
                          ),
                        )
                      : Center(
                          child: CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        );
                }

                if (audioUrl != null &&
                    audioUrl.isNotEmpty &&
                    index == _currentIndex) {
                  return Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            videoUrl == null && imageUrl == null
                                ? Icons.mic
                                : Icons.music_note,
                            size: 80,
                            color: Colors.white54,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Lecture audio...',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SizedBox.expand(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl ?? '',
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (context, url, error) => const Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 60,
                    ),
                  ),
                );
              },
            ),

            // Barres de progression (top)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 10,
              right: 10,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isPaused ? 0.0 : 1.0,
                child: Row(
                  children: widget.stories.asMap().entries.map((entry) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: AnimatedBuilder(
                          animation: _animController,
                          builder: (context, child) {
                            double val = 0.0;
                            if (entry.key < _currentIndex) {
                              val = 1.0;
                            } else if (entry.key == _currentIndex)
                              val = _animController.value;
                            return LinearProgressIndicator(
                              value: val,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              minHeight: 3,
                            );
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Infos utilisateur + close
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              left: 15,
              right: 15,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isPaused ? 0.0 : 1.0,
                child: IgnorePointer(
                  ignoring: _isPaused,
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white24,
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      FutureBuilder<Map<String, dynamic>>(
                        key: ValueKey(widget.stories[_currentIndex].id),
                        future: _fetchStoryProfile(
                          widget.stories[_currentIndex].data()
                              as Map<String, dynamic>,
                        ),
                        builder: (context, snap) {
                          final display =
                              snap.data?['name']?.toString() ?? '...';
                          final accountType = snap.data?['collection']
                              ?.toString();
                          final isCert = snap.data?['isCert'] == true;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                display,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(blurRadius: 10, color: Colors.black),
                                  ],
                                ),
                              ),
                              if (isCert || accountType != null) ...[
                                const SizedBox(width: 6),
                                AccountBadges(
                                  isCertified: isCert,
                                  accountType: accountType,
                                  fontSize: 10,
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _closeViewer,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Actions column (left, bottom)
            Positioned(
              left: 12,
              bottom: MediaQuery.of(context).padding.bottom + 20,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isPaused ? 0.0 : 1.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton(
                          heroTag: 'like_btn',
                          mini: true,
                          backgroundColor: _likedIndices.contains(_currentIndex)
                              ? Colors.red
                              : Colors.white24,
                          onPressed: () async {
                            try {
                              final doc = widget.stories[_currentIndex];
                              final id = doc.id;
                              final uid =
                                  FirebaseAuth.instance.currentUser?.uid;
                              if (uid == null) return;
                              final ref = FirebaseFirestore.instance
                                  .collection('stories')
                                  .doc(id)
                                  .collection('reactions')
                                  .doc(uid);
                              final snap = await ref.get();
                              if (snap.exists) {
                                await ref.delete();
                                if (mounted) {
                                  setState(
                                    () => _likedIndices.remove(_currentIndex),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Like retiré'),
                                    ),
                                  );
                                }
                              } else {
                                await ref.set({
                                  'authorId': uid,
                                  'type': 'like',
                                  'createdAt': FieldValue.serverTimestamp(),
                                });
                                if (mounted) {
                                  setState(
                                    () => _likedIndices.add(_currentIndex),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Story aimée'),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              debugPrint('Reaction error: $e');
                            }
                          },
                          child: Icon(
                            _likedIndices.contains(_currentIndex)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('stories')
                              .doc(widget.stories[_currentIndex].id)
                              .collection('reactions')
                              .snapshots(),
                          builder: (c, snap) {
                            final count = snap.hasData
                                ? snap.data!.docs.length
                                : 0;
                            return Text(
                              '$count',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        Builder(
                          builder: (context) {
                            final data =
                                widget.stories[_currentIndex].data()
                                    as Map<String, dynamic>? ??
                                {};
                            final ownerId = _ownerIdOf(data);
                            final uid = FirebaseAuth.instance.currentUser?.uid;
                            final isOwner =
                                uid != null &&
                                ownerId.isNotEmpty &&
                                ownerId == uid;
                            if (!isOwner) return const SizedBox.shrink();
                            return StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('stories')
                                  .doc(widget.stories[_currentIndex].id)
                                  .collection('views')
                                  .snapshots(),
                              builder: (c, snap) {
                                final vcount = snap.hasData
                                    ? snap.data!.docs.length
                                    : 0;
                                return GestureDetector(
                                  onTap: () => _showViewersSheet(_currentIndex),
                                  child: Text(
                                    '$vcount vues',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'comment_btn',
                      mini: true,
                      backgroundColor: Colors.white24,
                      onPressed: () {
                        _showCommentsSheet(_currentIndex);
                      },
                      child: const Icon(
                        Icons.mode_comment_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'save_btn',
                      mini: true,
                      backgroundColor: Colors.white24,
                      onPressed: () async {
                        try {
                          final doc = widget.stories[_currentIndex];
                          final data =
                              doc.data() as Map<String, dynamic>? ?? {};
                          final String? url =
                              data['imageUrl'] ??
                              data['videoUrl'] ??
                              data['audioUrl'];
                          if (url == null || url.isEmpty) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Pas de média à enregistrer'),
                                ),
                              );
                            }
                            return;
                          }
                          final path = await _downloadAndSave(url);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Enregistré: $path')),
                            );
                          }
                        } catch (e) {
                          debugPrint('Save story error: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Erreur lors de l’enregistrement',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: const Icon(
                        Icons.bookmark_border,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'share_btn',
                      mini: true,
                      backgroundColor: Colors.white24,
                      onPressed: () async {
                        try {
                          final doc = widget.stories[_currentIndex];
                          final data =
                              doc.data() as Map<String, dynamic>? ?? {};
                          final String? url =
                              data['imageUrl'] ??
                              data['videoUrl'] ??
                              data['audioUrl'];
                          if (url == null || url.isEmpty) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Rien à partager'),
                                ),
                              );
                            }
                            return;
                          }
                          await Clipboard.setData(ClipboardData(text: url));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Lien copié dans le presse‑papier',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Share story error: $e');
                        }
                      },
                      child: const Icon(
                        Icons.share,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'hide_btn',
                      mini: true,
                      backgroundColor: Colors.white24,
                      onPressed: () async {
                        try {
                          final doc = widget.stories[_currentIndex];
                          final data =
                              doc.data() as Map<String, dynamic>? ?? {};
                          final owner = _ownerIdOf(data);
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          if (uid == null) return;
                          final meRef = FirebaseFirestore.instance
                              .collection('classic_users')
                              .doc(uid);
                          await meRef.update({
                            'hiddenStories': FieldValue.arrayUnion([owner]),
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Stories masquées pour cet utilisateur',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Hide story error: $e');
                        }
                      },
                      child: const Icon(
                        Icons.visibility_off,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'block_btn',
                      mini: true,
                      backgroundColor: Colors.white24,
                      onPressed: () async {
                        try {
                          final doc = widget.stories[_currentIndex];
                          final data =
                              doc.data() as Map<String, dynamic>? ?? {};
                          final owner = _ownerIdOf(data);
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          if (uid == null) return;
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) {
                              final isDark =
                                  Theme.of(c).brightness == Brightness.dark;
                              final dialogBg = isDark
                                  ? const Color(0xFF0F171A)
                                  : Colors.white;
                              final textColor = isDark
                                  ? Colors.white
                                  : Colors.black87;
                              final subText = isDark
                                  ? Colors.white70
                                  : Colors.black54;
                              return AlertDialog(
                                backgroundColor: dialogBg,
                                title: Text(
                                  'Bloquer cet utilisateur?',
                                  style: TextStyle(color: textColor),
                                ),
                                content: Text(
                                  'Vous ne verrez plus les stories de cet utilisateur.',
                                  style: TextStyle(color: subText),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: Text(
                                      'Annuler',
                                      style: TextStyle(color: textColor),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text(
                                      'Bloquer',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                          if (ok == true) {
                            final meRef = FirebaseFirestore.instance
                                .collection('classic_users')
                                .doc(uid);
                            await meRef.update({
                              'blocked': FieldValue.arrayUnion([owner]),
                            });
                            final otherRef = FirebaseFirestore.instance
                                .collection('classic_users')
                                .doc(owner);
                            try {
                              await otherRef.update({
                                'blockedBy': FieldValue.arrayUnion([uid]),
                              });
                            } catch (_) {}
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Utilisateur bloqué'),
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          debugPrint('Block story owner error: $e');
                        }
                      },
                      child: const Icon(
                        Icons.block,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Delete button handled inline (only visible to owner)
            Positioned(
              left: 12,
              bottom: MediaQuery.of(context).padding.bottom + 20,
              child: Builder(
                builder: (ctx) {
                  try {
                    final doc = widget.stories[_currentIndex];
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final owner = _ownerIdOf(data);
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid == null || owner != uid) {
                      return const SizedBox.shrink();
                    }
                    return FloatingActionButton(
                      heroTag: 'delete_story',
                      mini: true,
                      backgroundColor: Colors.redAccent,
                      onPressed: () async {
                        try {
                          final id = doc.id;
                          final url =
                              data['imageUrl'] ??
                              data['videoUrl'] ??
                              data['audioUrl'];
                          if (url is String && url.isNotEmpty) {
                            try {
                              final path =
                                  url.contains('/storage/v1/object/public/')
                                  ? url.split('/storage/v1/object/public/').last
                                  : url.split('/').last;
                              if (path.isNotEmpty) {
                                try {
                                  await supabase
                                      .Supabase
                                      .instance
                                      .client
                                      .storage
                                      .from('stories')
                                      .remove([path]);
                                } catch (e) {
                                  debugPrint('Supabase delete file error: $e');
                                }
                              }
                            } catch (e) {
                              debugPrint('Supabase delete file error: $e');
                            }
                          }
                          await FirebaseFirestore.instance
                              .collection('stories')
                              .doc(id)
                              .delete();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Story supprimée')),
                            );
                          }
                          if (mounted &&
                              _currentIndex >= widget.stories.length - 1) {
                            _closeViewer();
                          }
                        } catch (e) {
                          debugPrint('Delete story error: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Erreur lors de la suppression'),
                              ),
                            );
                          }
                        }
                      },
                      child: const Icon(
                        Icons.delete,
                        color: Colors.white,
                        size: 18,
                      ),
                    );
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                },
              ),
            ),

            // Caption overlay (on top)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 10,
              // augmenter la marge gauche pour ne pas chevaucher la colonne de boutons à gauche
              left: MediaQuery.of(context).padding.left + 100,
              right: 30,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isPaused ? 0.0 : 1.0,
                child: Builder(
                  builder: (ctx) {
                    final data =
                        widget.stories[_currentIndex].data()
                            as Map<String, dynamic>;
                    final currentCaption =
                        (data['caption'] ??
                                data['text'] ??
                                data['legende'] ??
                                '')
                            as String;
                    if (currentCaption.trim().isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth:
                            MediaQuery.of(ctx).size.width -
                            (MediaQuery.of(ctx).padding.left + 100) -
                            30,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          currentCaption,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.center,
                          softWrap: true,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helpers
Future<String> _downloadAndSave(String url) async {
  try {
    final uri = Uri.parse(url);
    final client = HttpClient();
    final req = await client.getUrl(uri);
    final res = await req.close();
    if (res.statusCode != 200) {
      throw Exception('Download failed: ${res.statusCode}');
    }
    final bytes = await consolidateHttpClientResponseBytes(res);
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/Downloads/stories');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final file = File(
      '${folder.path}/${uri.pathSegments.isNotEmpty ? uri.pathSegments.last : DateTime.now().millisecondsSinceEpoch}',
    );
    await file.writeAsBytes(bytes);
    return file.path;
  } catch (e) {
    debugPrint('downloadAndSave error: $e');
    rethrow;
  }
}

String _ownerIdOf(Map<String, dynamic> data) {
  if (data.containsKey('userId')) return data['userId'] as String? ?? '';
  if (data.containsKey('ownerId')) return data['ownerId'] as String? ?? '';
  if (data.containsKey('uid')) return data['uid'] as String? ?? '';
  if (data.containsKey('posterId')) return data['posterId'] as String? ?? '';
  return '';
}

Future<Map<String, dynamic>> _fetchStoryProfile(
  Map<String, dynamic> data,
) async {
  try {
    final ownerId = _ownerIdOf(data);
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (currentUid != null && ownerId == currentUid) {
      return {'name': 'Moi', 'collection': null, 'isCert': false};
    }

    final collections = ['classic_users', 'pro_users', 'enterprise_users'];
    for (String col in collections) {
      final snap = await FirebaseFirestore.instance
          .collection(col)
          .doc(ownerId)
          .get();
      if (snap.exists) {
        final userData = snap.data();
        if (userData != null) {
          final name = UserUtils.formatName(userData);
          final firstName = (userData['firstName'] ?? '').toString();
          final display = name.isNotEmpty
              ? name
              : (firstName.isNotEmpty ? firstName : 'Utilisateur');
          final isCert = userData['isCertified'] == true;
          return {'name': display, 'collection': col, 'isCert': isCert};
        }
      }
    }

    final storyUserName = data['userName'] as String?;
    if (storyUserName != null &&
        storyUserName.isNotEmpty &&
        storyUserName != 'Moi') {
      return {'name': storyUserName, 'collection': null, 'isCert': false};
    }

    return {'name': 'Utilisateur', 'collection': null, 'isCert': false};
  } catch (e) {
    debugPrint('Erreur fetchStoryProfile: $e');
    return {'name': 'Utilisateur', 'collection': null, 'isCert': false};
  }
}

Future<String> _fetchDisplayNameForData(Map<String, dynamic> data) async {
  try {
    // 1. On récupère l'ID du créateur de la story
    final ownerId = _ownerIdOf(data);
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    // 2. Si c'est ma propre story, on affiche "Moi"
    if (currentUid != null && ownerId == currentUid) {
      return 'Moi';
    }

    // 3. Liste de vos collections d'utilisateurs
    final collections = ['classic_users', 'pro_users', 'enterprise_users'];

    for (String col in collections) {
      final snap = await FirebaseFirestore.instance
          .collection(col)
          .doc(ownerId)
          .get();

      if (snap.exists) {
        final userData = snap.data();
        if (userData != null && userData['firstName'] != null) {
          // On renvoie le prénom trouvé dans la collection
          return userData['firstName'] as String;
        }
      }
    }

    // 4. Fallback : si on ne trouve rien dans les profils, on utilise le userName
    // de la story seulement s'il est différent de "Moi"
    final storyUserName = data['userName'] as String?;
    if (storyUserName != null &&
        storyUserName.isNotEmpty &&
        storyUserName != 'Moi') {
      return storyUserName;
    }

    return 'Utilisateur';
  } catch (e) {
    debugPrint('Erreur fetchDisplayName: $e');
    return 'Utilisateur';
  }
}

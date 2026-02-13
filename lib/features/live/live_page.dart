import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:video_player/video_player.dart';

import 'package:lualaba_konnect/features/chat/presentation/pages/group_call_webrtc_page.dart';
import 'package:lualaba_konnect/core/supabase_service.dart';

class LivePage extends StatefulWidget {
  final VoidCallback onBack;
  const LivePage({super.key, required this.onBack});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final ImagePicker _picker = ImagePicker();
  static const int _maxSupabaseBytes = 50 * 1024 * 1024; // 50 MiB

  bool _uploading = false;
  double _uploadProgress = 0.0;
  String _uploadLabel = '';

  int _activeVideoIndex = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!mounted) return;
        setState(() {});
      });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtMb(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} Mo';
  }

  Future<void> _showTooLargeDialog({required int bytes}) async {
    if (!mounted) return;
    final size = _fmtMb(bytes);
    const limit = '50 Mo';
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF111B21),
        title: const Text('Vidéo trop lourde', style: TextStyle(color: Colors.white)),
        content: Text(
          'Taille: $size\nLimite actuelle Supabase: $limit\n\n'
          "Solutions:\n"
          "- réduire la durée / la qualité (compression)\n"
          "- ou augmenter la limite du bucket dans Supabase Storage (si ton plan le permet)",
          style: const TextStyle(color: Colors.white70, height: 1.25),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
  }

  String _appendUrlVersion(String url, int v) => url.contains('?') ? '$url&v=$v' : '$url?v=$v';

  Future<String> _resolveDisplayName(User u) async {
    final fromAuth = (u.displayName ?? '').trim();
    if (fromAuth.isNotEmpty) return fromAuth;

    try {
      final cols = ['classic_users', 'pro_users', 'enterprise_users', 'users'];
      for (final col in cols) {
        try {
          final snap = await FirebaseFirestore.instance.collection(col).doc(u.uid).get();
          if (!snap.exists) continue;
          final d = snap.data() ?? <String, dynamic>{};
          String pick(List<String> keys) {
            for (final k in keys) {
              final v = d[k];
              if (v == null) continue;
              final s = v.toString().trim();
              if (s.isNotEmpty) return s;
            }
            return '';
          }

          final name = pick(['displayName', 'name', 'username']);
          if (name.isNotEmpty) return name;
          final fn = pick(['firstName']);
          final ln = pick(['lastName']);
          final full = ('$fn $ln').trim();
          if (full.isNotEmpty) return full;
        } catch (_) {}
      }
    } catch (_) {}

    return 'Utilisateur';
  }

  Future<String?> _promptText({required String title, required String hint, String? okLabel}) async {
    final ctrl = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (c) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111B21),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white54),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(okLabel ?? 'OK')),
          ],
        );
      },
    );
    return res;
  }

  Future<void> _startLive() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Connecte-toi pour démarrer un live.');
      return;
    }

    final title = await _promptText(title: 'Titre du live', hint: 'Ex: Live Kolwezi', okLabel: 'Démarrer');
    if (title == null) return;
    final cleanTitle = title.isEmpty ? 'Live' : title;

    final hostName = await _resolveDisplayName(user);
    final callRef = FirebaseFirestore.instance.collection('calls').doc();

    try {
      await callRef.set({
        'kind': 'live',
        'mode': 'broadcast',
        'status': 'live',
        'type': 'video',
        'hostUid': user.uid,
        'hostName': hostName,
        'title': cleanTitle,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        'isGroup': true,
      }, SetOptions(merge: true));
    } catch (e) {
      _snack('Erreur création live: $e');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupCallWebRTCPage(
          callId: callRef.id,
          name: cleanTitle,
          isVideo: true,
          isCaller: true,
          publishAudio: true,
        ),
      ),
    );

    try {
      await callRef.set({'status': 'ended', 'endedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _joinLive(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data() ?? <String, dynamic>{};
    final status = (data['status'] ?? '').toString();
    if (status != 'live') {
      _snack("Ce live s'est terminé.");
      return;
    }
    final title = (data['title'] ?? data['hostName'] ?? 'Live').toString();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupCallWebRTCPage(
          callId: doc.id,
          name: title,
          isVideo: false,
          isCaller: false,
          publishAudio: false,
          startMuted: true,
        ),
      ),
    );
  }

  Future<void> _publishVideo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Connecte-toi pour publier.');
      return;
    }

    final caption = await _promptText(title: 'Description', hint: 'Ajoute une description (optionnel)', okLabel: 'Continuer');
    if (caption == null) return;

    XFile? picked;
    try {
      picked = await _picker.pickVideo(source: ImageSource.gallery);
    } catch (e) {
      _snack('Impossible de choisir une vidéo: $e');
      return;
    }
    if (picked == null) return;

    final sizeBytes = await picked.length();
    if (sizeBytes > _maxSupabaseBytes) {
      await _showTooLargeDialog(bytes: sizeBytes);
      return;
    }

    setState(() {
      _uploading = true;
      _uploadProgress = double.nan; // Supabase uploadBinary has no progress callback
      _uploadLabel = 'Upload vidéo (${_fmtMb(sizeBytes)})...';
    });

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;

      if (!SupabaseService.isInitialized) {
        throw Exception('Supabase non initialisé');
      }
      final client = Supabase.instance.client;
      const bucket = 'stories'; // bucket existant dans le projet
      final path = 'short_videos/${user.uid}/$ts.mp4';
      final bytes = await picked.readAsBytes();

      await client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true, contentType: 'video/mp4'),
          );
      final publicUrl = client.storage.from(bucket).getPublicUrl(path).toString();
      final url = _appendUrlVersion(publicUrl, ts);
      final name = await _resolveDisplayName(user);

      await FirebaseFirestore.instance.collection('short_videos').add({
        'userId': user.uid,
        'userName': name,
        'caption': caption,
        'url': url,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': ts,
        'likeCount': 0,
        'commentCount': 0,
      });

      _snack('Vidéo publiée.');
    } catch (e) {
      _snack('Erreur publication: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadProgress = 0;
        _uploadLabel = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack,
        ),
        title: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.orange,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Streaming'),
            Tab(text: 'Vidéos'),
          ],
        ),
        actions: [
          if (_tab.index == 1)
            IconButton(
              onPressed: _publishVideo,
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              tooltip: 'Publier une vidéo',
            ),
          if (_tab.index == 0)
            IconButton(
              onPressed: _startLive,
              icon: const Icon(Icons.wifi_tethering, color: Colors.white),
              tooltip: 'Démarrer un live',
            ),
        ],
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tab,
            children: [
              _LiveStreamingTab(onJoin: _joinLive),
              _ShortVideosTab(
                activeIndex: _activeVideoIndex,
                onActiveIndexChanged: (i) => setState(() => _activeVideoIndex = i),
              ),
            ],
          ),
          if (_uploading) _UploadOverlay(label: _uploadLabel, progress: _uploadProgress),
        ],
      ),
      floatingActionButton: _tab.index == 1
          ? FloatingActionButton.extended(
              onPressed: _publishVideo,
              backgroundColor: Colors.orange,
              icon: const Icon(Icons.upload, color: Colors.black),
              label: const Text('Publier', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
            )
          : FloatingActionButton.extended(
              onPressed: _startLive,
              backgroundColor: Colors.orange,
              icon: const Icon(Icons.videocam, color: Colors.black),
              label: const Text('Go Live', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
            ),
    );
  }
}

class _UploadOverlay extends StatelessWidget {
  final String label;
  final double progress;
  const _UploadOverlay({required this.label, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111B21),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress.isFinite ? progress.clamp(0.0, 1.0) : null,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                  minHeight: 8,
                ),
                const SizedBox(height: 8),
                Text(
                  progress.isFinite ? '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%' : '...',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveStreamingTab extends StatelessWidget {
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc) onJoin;
  const _LiveStreamingTab({required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('calls').where('status', isEqualTo: 'live').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Erreur: ${snap.error}', style: const TextStyle(color: Colors.white70)));
        }
        final raw = snap.data?.docs ?? const [];
        final docs = raw.where((d) {
          final data = d.data();
          final kind = (data['kind'] ?? '').toString().toLowerCase();
          final mode = (data['mode'] ?? '').toString().toLowerCase();
          return kind == 'live' || mode == 'broadcast';
        }).toList();

        docs.sort((a, b) {
          final ams = (a.data()['createdAtMs'] is num) ? (a.data()['createdAtMs'] as num).toInt() : 0;
          final bms = (b.data()['createdAtMs'] is num) ? (b.data()['createdAtMs'] as num).toInt() : 0;
          return bms.compareTo(ams);
        });

        if (docs.isEmpty) {
          return const Center(
            child: Text('Aucun live pour le moment.', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (c, i) => _LiveRoomCard(doc: docs[i], onJoin: onJoin),
        );
      },
    );
  }
}

class _LiveRoomCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc) onJoin;
  const _LiveRoomCard({required this.doc, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() ?? <String, dynamic>{};
    final title = (data['title'] ?? 'Live').toString();
    final host = (data['hostName'] ?? 'Hôte').toString();

    return InkWell(
      onTap: () => onJoin(doc),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF111B21),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(colors: [Colors.orange, Colors.deepOrange]),
              ),
              child: const Icon(Icons.wifi_tethering, color: Colors.black),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15.5)),
                  const SizedBox(height: 4),
                  Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('calls').doc(doc.id).collection('participants').snapshots(),
                    builder: (context, snap) {
                      final p = snap.data?.docs ?? const [];
                      final active = p.where((x) => x.data()['leftAt'] == null).length;
                      return Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
                            ),
                            child: const Text('EN DIRECT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 11)),
                          ),
                          const SizedBox(width: 10),
                          Text('$active spectateurs', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _ShortVideosTab extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onActiveIndexChanged;
  const _ShortVideosTab({required this.activeIndex, required this.onActiveIndexChanged});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('short_videos').orderBy('createdAtMs', descending: true).limit(80).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Erreur: ${snap.error}', style: const TextStyle(color: Colors.white70)));
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(child: Text('Aucune vidéo.', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)));
        }

        return PageView.builder(
          scrollDirection: Axis.vertical,
          onPageChanged: onActiveIndexChanged,
          itemCount: docs.length,
          itemBuilder: (c, i) {
            final d = docs[i];
            return _ShortVideoItem(
              key: ValueKey(d.id),
              videoId: d.id,
              data: d.data(),
              active: i == activeIndex,
            );
          },
        );
      },
    );
  }
}

class _ShortVideoItem extends StatefulWidget {
  final String videoId;
  final Map<String, dynamic> data;
  final bool active;
  const _ShortVideoItem({super.key, required this.videoId, required this.data, required this.active});

  @override
  State<_ShortVideoItem> createState() => _ShortVideoItemState();
}

class _ShortVideoItemState extends State<_ShortVideoItem> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _initialized = false;
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
    _initVideo();
  }

  @override
  void didUpdateWidget(covariant _ShortVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        try {
          if (_initialized) _controller?.play();
        } catch (_) {}
      } else {
        try {
          _controller?.pause();
        } catch (_) {}
      }
    }
  }

  Future<void> _initVideo() async {
    final url = (widget.data['url'] ?? '').toString();
    if (url.isEmpty) return;
    _controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await _controller!.setVolume(1.0);
      await _controller!.initialize();
      await _controller!.setLooping(true);
      if (!mounted) return;
      setState(() => _initialized = true);
      if (widget.active) _controller!.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller?.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleLike({required bool liked}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final vRef = FirebaseFirestore.instance.collection('short_videos').doc(widget.videoId);
    final likeRef = vRef.collection('likes').doc(user.uid);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final vSnap = await tx.get(vRef);
      final cur = (vSnap.data()?['likeCount'] is num) ? (vSnap.data()!['likeCount'] as num).toInt() : 0;
      if (liked) {
        tx.delete(likeRef);
        tx.update(vRef, {'likeCount': (cur - 1) < 0 ? 0 : (cur - 1)});
      } else {
        tx.set(likeRef, {'uid': user.uid, 'createdAt': FieldValue.serverTimestamp()});
        tx.update(vRef, {'likeCount': cur + 1});
      }
    });
  }

  Future<void> _openComments() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B141A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _CommentsSheet(videoId: widget.videoId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final size = MediaQuery.of(context).size;
    final url = (widget.data['url'] ?? '').toString();
    final userName = (widget.data['userName'] ?? 'Utilisateur').toString();
    final caption = (widget.data['caption'] ?? '').toString();

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () {
            if (!_initialized) return;
            setState(() {
              final p = _controller!.value.isPlaying;
              p ? _controller!.pause() : _controller!.play();
            });
          },
          child: (_initialized && url.isNotEmpty)
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                )
              : const Center(child: CircularProgressIndicator(color: Colors.orange)),
        ),
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.25),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.85),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          bottom: bottomPadding + 34,
          child: SizedBox(
            width: size.width * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('@$userName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 8),
                if (caption.trim().isNotEmpty)
                  Text(
                    caption,
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.25),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: bottomPadding + 40,
          child: Column(
            children: [
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('short_videos').doc(widget.videoId).snapshots(),
                builder: (context, snap) {
                  final likeCount = (snap.data?.data()?['likeCount'] is num)
                      ? (snap.data!.data()!['likeCount'] as num).toInt()
                      : ((widget.data['likeCount'] is num) ? (widget.data['likeCount'] as num).toInt() : 0);
                  final commentCount = (snap.data?.data()?['commentCount'] is num)
                      ? (snap.data!.data()!['commentCount'] as num).toInt()
                      : ((widget.data['commentCount'] is num) ? (widget.data['commentCount'] as num).toInt() : 0);

                  return Column(
                    children: [
                      _LikeButton(videoId: widget.videoId, onToggle: _toggleLike),
                      const SizedBox(height: 2),
                      Text('$likeCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: _openComments,
                        child: const Icon(Icons.chat_bubble, color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 4),
                      Text('$commentCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              AnimatedBuilder(
                animation: _spinCtrl,
                builder: (context, child) => Transform.rotate(
                  angle: _spinCtrl.value * 6.28318,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Colors.grey.shade800, Colors.black, Colors.grey.shade800]),
                      border: Border.all(color: Colors.white10, width: 4),
                    ),
                    child: const Icon(Icons.music_note, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_initialized && !(_controller?.value.isPlaying ?? true))
          const Center(child: Icon(Icons.play_arrow, color: Colors.white54, size: 100)),
      ],
    );
  }
}

class _LikeButton extends StatelessWidget {
  final String videoId;
  final Future<void> Function({required bool liked}) onToggle;
  const _LikeButton({required this.videoId, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Icon(Icons.favorite_border, color: Colors.white, size: 34);
    }
    final likeDoc = FirebaseFirestore.instance.collection('short_videos').doc(videoId).collection('likes').doc(user.uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: likeDoc.snapshots(),
      builder: (context, snap) {
        final liked = snap.data?.exists == true;
        return InkWell(
          onTap: () => onToggle(liked: liked),
          child: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.redAccent : Colors.white, size: 34),
        );
      },
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  final String videoId;
  const _CommentsSheet({required this.videoId});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final vRef = FirebaseFirestore.instance.collection('short_videos').doc(widget.videoId);
      await vRef.collection('comments').add({
        'uid': user.uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(vRef);
        final cur = (snap.data()?['commentCount'] is num) ? (snap.data()!['commentCount'] as num).toInt() : 0;
        tx.update(vRef, {'commentCount': cur + 1});
      });
      _ctrl.clear();
    } catch (_) {} finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final vRef = FirebaseFirestore.instance.collection('short_videos').doc(widget.videoId);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 46, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 10),
            const Text('Commentaires', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: vRef.collection('comments').orderBy('createdAtMs', descending: true).limit(200).snapshots(),
                builder: (context, snap) {
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return const Center(child: Text('Aucun commentaire.', style: TextStyle(color: Colors.white70)));
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    itemCount: docs.length,
                    itemBuilder: (c, i) {
                      final d = docs[docs.length - 1 - i].data();
                      final text = (d['text'] ?? '').toString();
                      final uid = (d['uid'] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.white10,
                              child: Text(uid.isNotEmpty ? uid[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text(text, style: const TextStyle(color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: const BoxDecoration(color: Color(0xFF111B21), border: Border(top: BorderSide(color: Colors.white12))),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Écrire un commentaire...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.black26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: Icon(Icons.send, color: _sending ? Colors.white30 : Colors.orange),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

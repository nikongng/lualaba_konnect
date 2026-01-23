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

class StoryViewerPageState extends State<StoryViewerPage> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animController;
  int _currentIndex = 0;
  bool _isPaused = false;
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

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });
  }

void _loadStory({required int index, bool animatePage = true}) async {
  _animController.stop();
  _animController.reset();
  _videoController?.dispose(); // On nettoie la vidéo précédente
  _videoController = null;

  final data = widget.stories[index].data() as Map<String, dynamic>;
  final videoUrl = data['videoUrl'] as String?;

  if (animatePage && _pageController.hasClients) {
    _pageController.jumpToPage(index);
  }

  if (videoUrl != null && videoUrl.isNotEmpty) {
    _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
      ..initialize().then((_) {
        setState(() {});
        if (mounted) {
          _animController.duration = _videoController!.value.duration; // La barre suit la vidéo
          _videoController!.play();
          _animController.forward();
        }
      });
  } else {
    _animController.duration = const Duration(seconds: 5); // Image = 5 sec
    _animController.forward();
  }
}

  void _nextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _loadStory(index: _currentIndex);
    } else {
      // Si c'est la dernière story, on ferme l'afficheur
      Navigator.of(context).pop();
    }
  }

  void _prevStory() {
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: 360,
            child: Column(
              children: [
                const Padding(padding: EdgeInsets.all(12.0), child: Text('Commentaires', style: TextStyle(color: Colors.white, fontSize: 18))),
                const Divider(color: Colors.white24),
                Expanded(child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('stories').doc(id).collection('comments').orderBy('createdAt', descending: true).snapshots(),
                  builder: (c, snap) {
                    if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Text('Aucun commentaire', style: TextStyle(color: Colors.white54)));
                    return ListView.builder(
                      itemCount: snap.data!.docs.length,
                      itemBuilder: (ctx, i) {
                        final d = snap.data!.docs[i].data() as Map<String, dynamic>;
                        return ListTile(title: Text(d['text'] ?? '', style: TextStyle(color: Colors.white)), subtitle: Text(d['authorName'] ?? '', style: TextStyle(color: Colors.white70)));
                      },
                    );
                  },
                )),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(children: [
                    Expanded(child: TextField(style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Ajouter un commentaire', hintStyle: TextStyle(color: Colors.white38)), onChanged: (v) => text = v)),
                    IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: () async {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      final name = FirebaseAuth.instance.currentUser?.displayName ?? '';
                      if (text.trim().isEmpty || uid == null) return;
                      await FirebaseFirestore.instance.collection('stories').doc(id).collection('comments').add({'text': text.trim(), 'authorId': uid, 'authorName': name, 'createdAt': FieldValue.serverTimestamp()});
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commentaire ajouté')));
                    })
                  ]),
                )
              ],
            ),
          ),
        );
      }
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _ensureCached(DocumentSnapshot doc) async {
    try {
      if (!mounted) return;
      final id = doc.id;
      if (_localCachePaths.containsKey(id) && _localCachePaths[id] != null) {
        final p = _localCachePaths[id]!;
        if (File(p).existsSync()) return;
      }
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final String? url = data['imageUrl'] ?? data['videoUrl'] ?? data['audioUrl'];
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
            setState(() => _isPaused = true);
            _animController.stop();
            _videoController?.pause();
          },

          // 2. Si le doigt quitte l'écran (on vérifie si c'est un clic ou un relâchement de maintien)
          onTapUp: (details) {
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
            if (mounted && !_animController.isCompleted) {
              _animController.forward();
              _videoController?.play();
            }
          },

          // 3. Cas où l'appui est interrompu (ex: l'utilisateur fait défiler le centre de notifications)
          onTapCancel: () {
            setState(() => _isPaused = false);
            _animController.forward();
            _videoController?.play();
          },
        child: Stack(
          children: [
            // Affichage de l'image
            PageView.builder(

              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // On gère via le clic
              itemCount: widget.stories.length,
itemBuilder: (context, index) {
  final story = widget.stories[index].data() as Map<String, dynamic>;
  final videoUrl = story['videoUrl'] as String?;
  final imageUrl = story['imageUrl'] as String?;
  final audioUrl = story['audioUrl'] as String?; // On récupère l'URL audio
  final caption = (story['caption'] ?? story['text'] ?? story['legende'] ?? '') as String;

  return Stack(
    alignment: Alignment.center,
    children: [
      // 1. LE MÉDIA (VIDÉO, AUDIO OU IMAGE)
      Builder(builder: (context) {
        // --- CAS VIDÉO ---
        if (videoUrl != null && videoUrl.isNotEmpty && index == _currentIndex) {
          return _videoController != null && _videoController!.value.isInitialized
              ? Center(
                  child: AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ),
                )
              : const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        // --- CAS AUDIO / ENREGISTREMENT ---
        // On vérifie si c'est un audio et si c'est la story en cours
        if (audioUrl != null && audioUrl.isNotEmpty && index == _currentIndex) {
          return Container(
            color: Colors.black, 
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icône micro pour enregistrement, note pour musique
                  Icon(
                    videoUrl == null && imageUrl == null ? Icons.mic : Icons.music_note,
                    size: 80,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 20),
                  const Text("Lecture audio...", style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          );
        }

        // --- CAS IMAGE (Par défaut) ---
        return SizedBox.expand(
          child: CachedNetworkImage(
            imageUrl: imageUrl ?? '',
            fit: BoxFit.contain,
            placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.white54, size: 60),
          ),
        );
      }),

      // 2. LA LÉGENDE (S'affiche par-dessus le média)
      if (caption.trim().isNotEmpty)
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _isPaused ? 0.0 : 1.0,
          child: Positioned(
            bottom: 50,
            left: 30,
            right: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                caption,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.center,
                softWrap: true,
              ),
            ),
          ),
        ),
    ],
  );
}
            ),

// Barres de progression (disparaissent au maintien)
AnimatedOpacity(
  duration: const Duration(milliseconds: 200),
  opacity: _isPaused ? 0.0 : 1.0,
  child: Positioned(
    top: 50,
    left: 10,
    right: 10,
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
                } else if (entry.key == _currentIndex) {
                  val = _animController.value;
                }
                return LinearProgressIndicator(
                  value: val,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
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

            // Infos (Nom + Bouton fermer)
// Infos utilisateur (Avatar, Nom, Bouton Fermer) - Disparaît au maintien
AnimatedOpacity(
  duration: const Duration(milliseconds: 200),
  opacity: _isPaused ? 0.0 : 1.0,
  child: IgnorePointer(
    ignoring: _isPaused, // Empêche de cliquer sur fermer accidentellement pendant la pause
    child: Positioned(
      top: 65,
      left: 15,
      right: 15,
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white24,
            child: Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Builder(builder: (ctx) {
            final data = (widget.stories[_currentIndex].data() as Map<String, dynamic>?) ?? {};
            return FutureBuilder<String>(
              key: ValueKey(widget.stories[_currentIndex].id),
              future: _fetchDisplayNameForData(data),
              builder: (context, snap) {
                final display = snap.hasData ? snap.data! : '...';
                return Text(
                  display,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                  ),
                );
              },
            );
          }),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  ),
),

            // Actions (like/comment/save/share/hide/block)
AnimatedOpacity(
  duration: const Duration(milliseconds: 200),
  opacity: _isPaused ? 0.0 : 1.0,
  child: IgnorePointer(
    ignoring: _isPaused,
    child: Positioned(
      left: 12,
      bottom: 5,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Like (store reaction in Firestore under stories/{id}/reactions/{uid})
          FloatingActionButton(
            heroTag: 'like_btn',
            mini: true,
            backgroundColor: _likedIndices.contains(_currentIndex) ? Colors.red : Colors.white24,
            onPressed: () async {
              try {
                final doc = widget.stories[_currentIndex];
                final id = doc.id;
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null) return;
                final ref = FirebaseFirestore.instance.collection('stories').doc(id).collection('reactions').doc(uid);
                final snap = await ref.get();
                if (snap.exists) {
                  await ref.delete();
                  setState(() => _likedIndices.remove(_currentIndex));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Like retiré')));
                } else {
                  await ref.set({'authorId': uid, 'type': 'like', 'createdAt': FieldValue.serverTimestamp()});
                  setState(() => _likedIndices.add(_currentIndex));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Story aimée')));
                }
              } catch (e) {
                debugPrint('Reaction error: $e');
              }
            },
            child: Icon(
              _likedIndices.contains(_currentIndex) ? Icons.favorite : Icons.favorite_border,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(height: 8),
          
          // Comment
          FloatingActionButton(
            heroTag: 'comment_btn',
            mini: true,
            backgroundColor: Colors.white24,
            onPressed: () { _showCommentsSheet(_currentIndex); },
            child: const Icon(Icons.mode_comment_outlined, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 8),
          
          // Save
          FloatingActionButton(
            heroTag: 'save_btn',
            mini: true,
            backgroundColor: Colors.white24,
            onPressed: () async {
              try {
                final doc = widget.stories[_currentIndex];
                final data = doc.data() as Map<String, dynamic>? ?? {};
                final String? url = data['imageUrl'] ?? data['videoUrl'] ?? data['audioUrl'];
                if (url == null || url.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pas de média à enregistrer')));
                  return;
                }
                final path = await _downloadAndSave(url);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistré: $path')));
              } catch (e) {
                debugPrint('Save story error: $e');
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de l’enregistrement')));
              }
            },
            child: const Icon(Icons.bookmark_border, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 8),
          
          // Share
          FloatingActionButton(
            heroTag: 'share_btn',
            mini: true,
            backgroundColor: Colors.white24,
            onPressed: () async {
              try {
                final doc = widget.stories[_currentIndex];
                final data = doc.data() as Map<String, dynamic>? ?? {};
                final String? url = data['imageUrl'] ?? data['videoUrl'] ?? data['audioUrl'];
                if (url == null || url.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rien à partager')));
                  return;
                }
                await Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié dans le presse‑papier')));
              } catch (e) {
                debugPrint('Share story error: $e');
              }
            },
            child: const Icon(Icons.share, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 8),
          
          // Hide
          FloatingActionButton(
            heroTag: 'hide_btn',
            mini: true,
            backgroundColor: Colors.white24,
            onPressed: () async {
              try {
                final doc = widget.stories[_currentIndex];
                final data = doc.data() as Map<String, dynamic>? ?? {};
                final owner = _ownerIdOf(data);
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null) return;
                final meRef = FirebaseFirestore.instance.collection('classic_users').doc(uid);
                await meRef.update({'hiddenStories': FieldValue.arrayUnion([owner])});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stories masquées pour cet utilisateur')));
              } catch (e) {
                debugPrint('Hide story error: $e');
              }
            },
            child: const Icon(Icons.visibility_off, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 8),
          
          // Block
          FloatingActionButton(
            heroTag: 'block_btn',
            mini: true,
            backgroundColor: Colors.white24,
            onPressed: () async {
              try {
                final doc = widget.stories[_currentIndex];
                final data = doc.data() as Map<String, dynamic>? ?? {};
                final owner = _ownerIdOf(data);
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null) return;
                final ok = await showDialog<bool>(context: context, builder: (c) {
                  return AlertDialog(
                    backgroundColor: Colors.black87,
                    title: const Text('Bloquer cet utilisateur?', style: TextStyle(color: Colors.white)),
                    content: const Text('Vous ne verrez plus les stories de cet utilisateur.', style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Bloquer', style: TextStyle(color: Colors.red)))
                    ],
                  );
                });
                if (ok == true) {
                  final meRef = FirebaseFirestore.instance.collection('classic_users').doc(uid);
                  await meRef.update({'blocked': FieldValue.arrayUnion([owner])});
                  final otherRef = FirebaseFirestore.instance.collection('classic_users').doc(owner);
                  try { await otherRef.update({'blockedBy': FieldValue.arrayUnion([uid])}); } catch(_) {}
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Utilisateur bloqué')));
                }
              } catch (e) { debugPrint('Block story owner error: $e'); }
            },
            child: const Icon(Icons.block, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 8),
          
          // Delete story — only visible to owner
          Builder(builder: (ctx) {
            try {
              final doc = widget.stories[_currentIndex];
              final data = doc.data() as Map<String, dynamic>? ?? {};
              final owner = _ownerIdOf(data);
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null || owner != uid) return const SizedBox.shrink();
              return FloatingActionButton(
                heroTag: 'delete_story',
                mini: true,
                backgroundColor: Colors.redAccent,
                onPressed: () async {
                  try {
                    final id = doc.id;
                    final url = data['imageUrl'] ?? data['videoUrl'] ?? data['audioUrl'];
                    if (url is String && url.isNotEmpty) {
                      try {
                        final path = url.contains('/storage/v1/object/public/') 
                            ? url.split('/storage/v1/object/public/').last 
                            : url.split('/').last;
                        if (path.isNotEmpty) {
                          try { await supabase.Supabase.instance.client.storage.from('stories').remove([path]); } 
                          catch (e) { debugPrint('Supabase delete file error: $e'); }
                        }
                      } catch (e) { debugPrint('Supabase delete file error: $e'); }
                    }
                    await FirebaseFirestore.instance.collection('stories').doc(id).delete();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Story supprimée')));
                    if (_currentIndex >= widget.stories.length - 1) Navigator.of(context).pop();
                  } catch (e) {
                    debugPrint('Delete story error: $e');
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de la suppression')));
                  }
                },
                child: const Icon(Icons.delete, color: Colors.white, size: 18),
              );
            } catch (_) {
              return const SizedBox.shrink();
            }
          }),
        ],
      ),
    ),
  ),
)
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
    if (res.statusCode != 200) throw Exception('Download failed: ${res.statusCode}');
    final bytes = await consolidateHttpClientResponseBytes(res);
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/Downloads/stories');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final file = File('${folder.path}/${uri.pathSegments.isNotEmpty ? uri.pathSegments.last : DateTime.now().millisecondsSinceEpoch}');
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
      final snap = await FirebaseFirestore.instance.collection(col).doc(ownerId).get();
      
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
    if (storyUserName != null && storyUserName.isNotEmpty && storyUserName != 'Moi') {
      return storyUserName;
    }

    return 'Utilisateur';
  } catch (e) {
    debugPrint('Erreur fetchDisplayName: $e');
    return 'Utilisateur';
  }
}


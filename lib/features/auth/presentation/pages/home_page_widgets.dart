import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import 'news_feed_page.dart';

class _HomeNewsMediaEntry {
  final String url;
  final bool isVideo;
  const _HomeNewsMediaEntry({
    required this.url,
    required this.isVideo,
  });
}

List<_HomeNewsMediaEntry> _extractHomeNewsMedia(Map<String, dynamic> data) {
  final out = <_HomeNewsMediaEntry>[];
  final rawMedia = data['media'];
  if (rawMedia is List) {
    for (final raw in rawMedia) {
      if (raw is! Map) continue;
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      final url = (map['url'] ?? '').toString().trim();
      if (url.isEmpty) continue;
      final type = (map['type'] ?? '').toString().toLowerCase();
      out.add(_HomeNewsMediaEntry(url: url, isVideo: type == 'video'));
    }
  }
  if (out.isNotEmpty) return out;

  final images = (data['images'] is List)
      ? List<String>.from((data['images'] as List).map((e) => e.toString()))
      : const <String>[];
  final videos = (data['videos'] is List)
      ? List<String>.from((data['videos'] as List).map((e) => e.toString()))
      : const <String>[];

  out.addAll(
    images
        .where((u) => u.trim().isNotEmpty)
        .map((u) => _HomeNewsMediaEntry(url: u, isVideo: false)),
  );
  out.addAll(
    videos
        .where((u) => u.trim().isNotEmpty)
        .map((u) => _HomeNewsMediaEntry(url: u, isVideo: true)),
  );
  return out;
}

_HomeNewsMediaEntry? _firstHomeNewsMedia(
  Map<String, dynamic> data, {
  bool preferImage = true,
}) {
  final items = _extractHomeNewsMedia(data);
  if (items.isEmpty) return null;
  if (preferImage) {
    for (final item in items) {
      if (!item.isVideo) return item;
    }
  }
  return items.first;
}

class _HomeNewsVideoThumbnail extends StatefulWidget {
  final String videoUrl;
  final BoxFit fit;
  const _HomeNewsVideoThumbnail({
    required this.videoUrl,
    this.fit = BoxFit.cover,
  });

  @override
  State<_HomeNewsVideoThumbnail> createState() => _HomeNewsVideoThumbnailState();
}

class _HomeNewsVideoThumbnailState extends State<_HomeNewsVideoThumbnail> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _HomeNewsVideoThumbnail oldWidget) {
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
      await c.pause();
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
      return Container(color: const Color(0xFF202C33));
    }
    final size = c.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return Container(color: const Color(0xFF202C33));
    }
    return Container(
      color: const Color(0xFF202C33),
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

// Widgets pour la page d'accueil
class HomePageWidgets {
  static Widget buildHeader(bool isDark, Color textColor) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [
        CircleAvatar(radius: 28, backgroundImage: CachedNetworkImageProvider('https://i.pravatar.cc/150?img=3')),
        const SizedBox(width: 15),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("LUALABACONNECT", style: TextStyle(color: Color(0xFF00CBA9), fontSize: 10, fontWeight: FontWeight.w900)),
          Text("Bonjour, Ir Punga", style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.bold)),
          Text("Jeudi 01 Janvier", style: TextStyle(color: isDark ? Colors.white60 : Colors.black45, fontSize: 13)),
        ]),
      ]),
      GestureDetector(onTap: () => _showSOSMenu(), child: const CircleAvatar(backgroundColor: Color(0xFFD32F2F), radius: 25, child: Text("sos", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
    ]);
  }

  static Widget buildWeatherCard(Color bg, Color text, Color sub, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(32)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Lubumbashi", style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.bold)),
            Text("22°", style: TextStyle(color: text, fontSize: 55, fontWeight: FontWeight.w200)),
          ]),
          Icon(Icons.cloudy_snowing, color: isDark ? Colors.white70 : Colors.orange, size: 45),
        ]),
        Divider(color: isDark ? Colors.white10 : Colors.black12, height: 30),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: ["MAINT.", "13 H", "14 H", "15 H", "16 H"].map((t) => Column(children: [
          Text(t, style: TextStyle(color: sub, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Icon(Icons.cloud_queue, color: text, size: 18),
          Text("22°", style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.bold)),
        ])).toList()),
      ]),
    );
  }

  static Widget buildMastaCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7F00FF), Color(0xFFE100FF)]), borderRadius: BorderRadius.circular(32)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [CircleAvatar(backgroundColor: Colors.white, radius: 18, child: Icon(Icons.face, color: Color(0xFF7F00FF))), SizedBox(width: 12), Text("Masta", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)), Spacer(), Text("Bêta", style: TextStyle(color: Colors.white70, fontSize: 10))]),
        const SizedBox(height: 10),
        const Text("Pose-moi une question, je suis ton assistant personnel", style: TextStyle(color: Colors.white, fontSize: 13)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Container(height: 50, decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(15)), padding: const EdgeInsets.symmetric(horizontal: 15), alignment: Alignment.centerLeft, child: const Text("Posez votre question...", style: TextStyle(color: Colors.white60)))),
          const SizedBox(width: 10),
          Container(height: 50, width: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF7F00FF))),
        ]),
      ]),
    );
  }

  static Widget buildSearchBar(bool isDark) {
    return Container(
      height: 55, decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(30), border: isDark ? null : Border.all(color: Colors.black12)),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Row(children: [Icon(Icons.search, color: Colors.grey), SizedBox(width: 10), Text("Rechercher un service, un produit...", style: TextStyle(color: Colors.grey, fontSize: 14))]),
    );
  }

  static Widget buildCopperCard(Color bg, Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(32)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("COURS DU CUIVRE (LME)", style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.bold)), const Text("\$9,840.50", style: TextStyle(color: Color(0xFF00E676), fontSize: 28, fontWeight: FontWeight.w900)), const Text("+1.2% aujourd'hui", style: TextStyle(color: Color(0xFF00E676), fontSize: 11))]),
        const Icon(Icons.auto_graph, color: Color(0xFF00E676), size: 35),
      ]),
    );
  }

  static Widget buildNewsSection(Color text, bool isDark, BuildContext context) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text("Actu", style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.bold)),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NewsFeedPage())),
          child: const Text("Tout voir", style: TextStyle(color: Colors.orange, fontSize: 13))
        )
      ]),
      const SizedBox(height: 15),
      SizedBox(
        height: 280,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('posts')
              .orderBy('createdAt', descending: true)
              .limit(12)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              // Skeletons
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(width: 15),
                itemBuilder: (_, __) => Container(
                  width: 260,
                  margin: const EdgeInsets.only(right: 15),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E3E3B) : Colors.white,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 120, height: 14, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8))),
                      const SizedBox(height: 12),
                      Expanded(child: Container(decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(15)))),
                      const SizedBox(height: 12),
                      Container(width: 200, height: 14, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8))),
                    ],
                  ),
                ),
              );
            }

            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return Center(
                child: Text(
                  "Aucune actu pour l'instant",
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
                ),
              );
            }

            return ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final raw = docs[index].data();
                final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

                final source = (data['category'] ?? data['authorName'] ?? 'Actu').toString();
                final title = (data['text'] ?? '').toString();
                final media = _firstHomeNewsMedia(data, preferImage: true);
                final mediaUrl = media?.url ?? '';
                final mediaIsVideo = media?.isVideo ?? false;

                return _newsCard(
                  source,
                  title,
                  isDark,
                  mediaUrl,
                  isVideo: mediaIsVideo,
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  static Widget _newsCard(
    String source,
    String title,
    bool isDark,
    String mediaUrl, {
    required bool isVideo,
  }) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E3E3B) : Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- HEADER ----
          Row(
            children: [
              const CircleAvatar(
                radius: 12,
                backgroundColor: Colors.black,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ---- IMAGE ----
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: mediaUrl.isEmpty
                  ? Container(
                      color: Colors.black12,
                      child: const Center(
                        child: Icon(
                          Icons.article_outlined,
                          size: 40,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : isVideo
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            _HomeNewsVideoThumbnail(
                              videoUrl: mediaUrl,
                              fit: BoxFit.cover,
                            ),
                            Container(
                              color: Colors.black26,
                              child: const Center(
                                child: Icon(
                                  Icons.play_circle_fill_rounded,
                                  color: Colors.white70,
                                  size: 40,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Image.network(
                          mediaUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,

                          // 🔄 Loader
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.black12,
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },

                          // ❌ Fallback si image cassée / 404
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.black12,
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 40,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),

          const SizedBox(height: 12),

          // ---- TITLE ----
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  static Widget buildServicesSection() {
    return Column(children: [
      _serviceTile("Services Rapides", "Food, Ménage, Auto & plus...", [const Color(0xFF448AFF), const Color(0xFF2962FF)], Icons.grid_view_rounded, "NOUVEAU"),
      const SizedBox(height: 16),
      _serviceTile("Emploi & Annonce", "Recrutement, Freelance, Annonces", [const Color(0xFFD500F9), const Color(0xFFAA00FF)], Icons.work_outline, "OPPORTUNITÉS"),
      const SizedBox(height: 16),
      _serviceTile("Conseil du jour", "Hydratez-vous régulièrement aujourd'hui.", [const Color(0xFF00CBA9), const Color(0xFF00A88E)], Icons.lightbulb_outline, "SANTÉ"),
    ]);
  }

  static Widget _serviceTile(String title, String sub, List<Color> colors, IconData icon, String tag) {
    return Container(
      padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(28)),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: Colors.white, size: 28)),
        const SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tag, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)), Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)), Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 11))])),
        const CircleAvatar(backgroundColor: Colors.white, radius: 18, child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black)),
      ]),
    );
  }

  static void _showSOSMenu() {
    // Note: This needs context, so it should be called from a widget with context
  }
}

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:math' as math;
import 'dart:ui'; 

class LivePage extends StatefulWidget {
  final VoidCallback onBack; 

  const LivePage({super.key, required this.onBack});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  final List<String> videoUrls = [
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
  ];

  late List<Map<String, String>> lualabaVideos;

  @override
  void initState() {
    super.initState();
    lualabaVideos = List.generate(20, (index) {
      return {
        "user": "Lualaba_Konnect_${index + 1}",
        "desc": "Modernisation de la province du Lualaba à Kolwezi. Développement des infrastructures et impact social pour les citoyens. 🏗️💎 #Lualaba #RDCONGO",
        "url": videoUrls[index % videoUrls.length],
        "likes": "${(index + 1) * 2}K",
        "comments": "${(index + 10) * 5}",
        "shares": "${index + 5}",
        "music": "Musique Originale - Lualaba Konnect",
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: lualabaVideos.length,
        itemBuilder: (context, index) {
          return VideoItem(
            key: ValueKey("${lualabaVideos[index]['url']}_$index"),
            videoData: lualabaVideos[index],
            onBack: widget.onBack,
          );
        },
      ),
    );
  }
}

class VideoItem extends StatefulWidget {
  final Map<String, String> videoData;
  final VoidCallback onBack;
  const VideoItem({super.key, required this.videoData, required this.onBack});

  @override
  State<VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<VideoItem> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  late AnimationController _musicAnimationController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _musicAnimationController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat();
  }

  void _initializeVideo() async {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoData['url']!));
    try {
      await _controller!.setVolume(0.5); 
      await _controller!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
        _controller!.setLooping(true);
        _controller!.play();
      }
    } catch (e) {
      debugPrint("Erreur : $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _musicAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final size = MediaQuery.of(context).size;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. LECTEUR VIDÉO
        GestureDetector(
          onTap: () {
            if (_isInitialized) {
              setState(() {
                _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
              });
            }
          },
          child: _isInitialized
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

        // 2. DÉGRADÉ DE FOND (Lisibilité)
        _buildGradientOverlay(),

        // 3. BOUTON RETOUR (Haut Gauche)
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 15,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: InkWell(
                onTap: widget.onBack,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ),

        // 4. BOUTONS LATÉRAUX (Droite)
        Positioned(
          right: 10,
          bottom: bottomPadding + 40, 
          child: Column(
            children: [
              _buildProfileAvatar(),
              const SizedBox(height: 20),
              _sideButton(Icons.favorite, widget.videoData['likes']!, color: Colors.red),
              _sideButton(Icons.chat_bubble, widget.videoData['comments']!),
              _sideButton(Icons.reply, widget.videoData['shares']!, isShare: true),
              const SizedBox(height: 15),
              _buildMusicDisc(), // Disque tournant
            ],
          ),
        ),

        // 5. INFOS VIDÉO (Bas Gauche)
        Positioned(
          left: 15,
          bottom: bottomPadding + 35,
          child: _buildVideoInfo(size.width),
        ),

        // 6. BARRE DE PROGRESSION
        Positioned(
          bottom: bottomPadding + 5,
          left: 0,
          right: 0,
          child: _isInitialized
              ? VideoProgressIndicator(
                  _controller!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.orange,
                    bufferedColor: Colors.white10,
                    backgroundColor: Colors.white24,
                  ),
                )
              : const SizedBox(),
        ),

        if (_isInitialized && !_controller!.value.isPlaying)
          const Center(child: Icon(Icons.play_arrow, color: Colors.white54, size: 100)),
      ],
    );
  }

  Widget _buildGradientOverlay() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.3),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withOpacity(0.85),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoInfo(double screenWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("@${widget.videoData['user']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        // Largeur limitée à 60% pour ne pas chevaucher les boutons de droite
        SizedBox(
          width: screenWidth * 0.60, 
          child: Text(
            widget.videoData['desc']!, 
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3), 
            maxLines: 3, 
            overflow: TextOverflow.ellipsis
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.music_note, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            SizedBox(
              width: screenWidth * 0.40,
              child: Text(
                widget.videoData['music']!, 
                style: const TextStyle(color: Colors.white, fontSize: 13), 
                maxLines: 1, 
                overflow: TextOverflow.ellipsis
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileAvatar() {
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 48, width: 48,
          decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1), shape: BoxShape.circle, color: Colors.grey.shade900),
          child: const Icon(Icons.person, color: Colors.white),
        ),
        Positioned(
          bottom: -8,
          child: Container(
            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            child: const Icon(Icons.add, color: Colors.white, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _sideButton(IconData icon, String label, {Color color = Colors.white, bool isShare = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          Transform(
            alignment: Alignment.center,
            transform: isShare ? Matrix4.rotationY(math.pi) : Matrix4.identity(),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildMusicDisc() {
    return AnimatedBuilder(
      animation: _musicAnimationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _musicAnimationController.value * 2 * math.pi,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: SweepGradient(colors: [Colors.grey.shade800, Colors.black, Colors.grey.shade800]),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white10, width: 4),
            ),
            child: const Icon(Icons.music_note, color: Colors.white, size: 18),
          ),
        );
      },
    );
  }
}
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  final List<Map<String, String>> lualabaVideos = [
    {
      "user": "@LualabaGouv",
      "desc": "Travaux de modernisation à Kolwezi. 🏗️",
      "url": "https://assets.mixkit.co/videos/preview/mixkit-city-traffic-at-night-vertical-shot-34547-small.mp4",
      "likes": "15K",
      "comments": "1.2K"
    }
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: lualabaVideos.length,
        itemBuilder: (context, index) {
          // On utilise une clé unique pour forcer la reconstruction propre
          return VideoItem(key: ValueKey(lualabaVideos[index]['url']), videoData: lualabaVideos[index]);
        },
      ),
    );
  }
}

class VideoItem extends StatefulWidget {
  final Map<String, String> videoData;
  const VideoItem({super.key, required this.videoData});

  @override
  State<VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<VideoItem> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoData['url']!));
      
      await _controller!.initialize();
      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });
      _controller!.setLooping(true);
      _controller!.setVolume(0); // Indispensable sur Web pour l'autoplay
      _controller!.play();
    } catch (e) {
      debugPrint("Erreur vidéo: $e");
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(child: Text("Erreur de chargement vidéo", style: TextStyle(color: Colors.white)));
    }

    return GestureDetector(
      onTap: () {
        if (_controller != null && _controller!.value.isInitialized) {
          setState(() {
            _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
          });
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          _isInitialized
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                )
              : const Center(child: CircularProgressIndicator(color: Colors.orange)),
          
          _buildGradientOverlay(),
          _buildContent(),
          if (_isInitialized && !_controller!.value.isPlaying)
            const Center(child: Icon(Icons.play_arrow, color: Colors.white70, size: 80)),
        ],
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.videoData['user']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 10),
                Text(widget.videoData['desc']!, style: const TextStyle(color: Colors.white, fontSize: 14)),
                const SizedBox(height: 110),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _sideButton(Icons.favorite, widget.videoData['likes']!),
              _sideButton(Icons.chat_bubble, widget.videoData['comments']!),
              const SizedBox(height: 110),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sideButton(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [Icon(icon, color: Colors.white, size: 30), Text(label, style: const TextStyle(color: Colors.white, fontSize: 10))],
      ),
    );
  }
}
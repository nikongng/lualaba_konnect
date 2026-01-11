import 'package:flutter/material.dart';

class CallPage extends StatefulWidget {
  final String name;
  final String avatarLetter;
  final bool isVideo;

  const CallPage({super.key, required this.name, required this.avatarLetter, this.isVideo = false});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  bool _muted = false;
  bool _speaker = true;
  late Stopwatch _stopwatch;
  late final Ticker _ticker;

  // format helper not required — we compute minutes/seconds directly in build

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _ticker = Ticker((_) {
      if (mounted) setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.stop();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _stopwatch.elapsed;
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: const Color(0xFF0B1418),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            CircleAvatar(radius: 64, backgroundColor: Colors.white10, child: Text(widget.avatarLetter, style: const TextStyle(color: Colors.white, fontSize: 44))),
            const SizedBox(height: 20),
            Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('$minutes:$seconds', style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 40),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _buildCircleButton(Icons.mic_off, _muted ? Colors.orange : Colors.white24, () => setState(() => _muted = !_muted)),
              _buildCircleButton(Icons.volume_up, _speaker ? Colors.orange : Colors.white24, () => setState(() => _speaker = !_speaker)),
              _buildCircleButton(widget.isVideo ? Icons.videocam : Icons.call_end, Colors.red, () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 30),
            Text(widget.isVideo ? 'Appel vidéo' : 'Appel audio', style: const TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton(IconData icon, Color bg, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: CircleAvatar(radius: 28, backgroundColor: bg, child: Icon(icon, color: Colors.white)),
    );
  }
}

// tiny Ticker implementation to avoid importing flutter/scheduler in multiple places
class Ticker {
  final void Function(Duration) _onTick;
  bool _running = false;
  Ticker(this._onTick);
  void start() {
    _running = true;
    _tick();
  }
  void _tick() async {
    while (_running) {
      await Future.delayed(const Duration(seconds: 1));
      _onTick(Duration.zero);
    }
  }
  void stop() { _running = false; }
}

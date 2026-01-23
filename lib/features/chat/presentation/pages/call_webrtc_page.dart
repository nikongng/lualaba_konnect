import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_webrtc_logic.dart';
import 'package:lualaba_konnect/core/notification_service.dart';

class CallWebRTCPage extends StatefulWidget {
  final String name;
  final String avatarLetter;
  final bool isVideo;
  final String otherId;
  final String callId;
  final bool isCaller;

  const CallWebRTCPage({
    super.key,
    required this.name,
    required this.avatarLetter,
    required this.otherId,
    required this.callId,
    this.isVideo = false,
    this.isCaller = false,
  });

  @override
  State<CallWebRTCPage> createState() => _CallWebRTCPageState();
}

class _CallWebRTCPageState extends State<CallWebRTCPage> with SingleTickerProviderStateMixin {
  late CallWebRTCLogic _logic;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _muted = false;
  bool _speaker = true;
  bool _camera = true;
  bool _isConnected = false;
  bool _isRinging = false;

  late Stopwatch _stopwatch;
  late Timer _timer;

  // Animation for button taps
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150), lowerBound: 0.0, upperBound: 0.1);
    _initRenderers();
    _initLogic();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _initLogic() {
    _logic = CallWebRTCLogic(
      callId: widget.callId,
      otherId: widget.otherId,
      isCaller: widget.isCaller,
      onLocalStream: (s) => _localRenderer.srcObject = s,
      onRemoteStream: (s) => _remoteRenderer.srcObject = s,
      onStateChanged: (st) {
        setState(() {
          _isConnected = st == 'connected';
          _isRinging = st == 'ringing';
        });
        if (_isConnected && !_stopwatch.isRunning) _stopwatch.start();
        if (!_isConnected && _stopwatch.isRunning) _stopwatch.stop();
        _updateRingtone();
      },
      onLog: (m) => debugPrint('[call] $m'),
    );

    _startCallFlow();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  Future<void> _startCallFlow() async {
    await _logic.openUserMedia(video: widget.isVideo);
    if (widget.isCaller) {
      await _logic.startAsCaller();
    } else {
      await _logic.startAsCallee();
    }
  }

  void _updateRingtone() {
    if (_isRinging) {
      NotificationService.playRingtone();
    } else {
      NotificationService.stopRingtone();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _stopwatch.stop();
    _logic.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _animController.dispose();
    super.dispose();
  }

  String _formatElapsed() {
    final elapsed = _stopwatch.elapsed;
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _animatedButton({required IconData icon, required VoidCallback onTap, required Color color, double size = 64}) {
    return GestureDetector(
      onTapDown: (_) => _animController.forward(),
      onTapUp: (_) => _animController.reverse(),
      onTapCancel: () => _animController.reverse(),
      onTap: onTap,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          double scale = 1 - _animController.value;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0,4))],
          ),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote Video
            Positioned.fill(
              child: _remoteRenderer.srcObject != null
                  ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Container(
                      color: Colors.black87,
                      alignment: Alignment.center,
                      child: Text(
                        'En attente de connexion...',
                        style: TextStyle(color: Colors.white54, fontSize: 18),
                      ),
                    ),
            ),
            // Top Info
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.blueAccent,
                    child: Text(widget.avatarLetter, style: TextStyle(fontSize: 28, color: Colors.white)),
                  ),
                  SizedBox(height: 12),
                  Text(widget.name, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text(
                    _isConnected ? _formatElapsed() : (_isRinging ? 'Ça sonne...' : 'En attente'),
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
            // Local Video Preview
            Positioned(
              right: 20,
              top: 180,
              width: 140,
              height: 180,
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: 300),
                child: _localRenderer.srcObject != null
                    ? Container(
                        key: ValueKey('localVideo'),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white54, width: 2),
                        ),
                        child: RTCVideoView(_localRenderer, mirror: true),
                      )
                    : Container(
                        key: ValueKey('noLocalVideo'),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white54, width: 2),
                          color: Colors.black45,
                        ),
                        child: Icon(Icons.videocam_off, color: Colors.white54, size: 40),
                      ),
              ),
            ),
            // Bottom Controls
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _animatedButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    color: _muted ? Colors.redAccent : Colors.blueAccent,
                    onTap: () => setState(() => _muted = !_muted),
                  ),
                  _animatedButton(
                    icon: _camera ? Icons.videocam : Icons.videocam_off,
                    color: _camera ? Colors.blueAccent : Colors.grey,
                    onTap: () => setState(() => _camera = !_camera),
                  ),
                  _animatedButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    size: 72,
                    onTap: () async {
                      await _logic.hangup();
                      if (mounted) Navigator.pop(context);
                    },
                  ),
                  _animatedButton(
                    icon: _speaker ? Icons.volume_up : Icons.headset_off,
                    color: _speaker ? Colors.blueAccent : Colors.grey,
                    onTap: () => setState(() => _speaker = !_speaker),
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

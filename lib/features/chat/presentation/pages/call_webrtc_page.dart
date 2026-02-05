import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
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

  // États de l'appel
  bool _muted = false;
  bool _camera = true;
  bool _isSpeakerOn = false;
  bool _isConnected = false;
  bool _isRinging = false;
  
  // États PiP (Picture-in-Picture)
  bool _isMinimized = false;
  Offset _pipOffset = const Offset(20, 60);

  // Monitoring & Animations
  late Stopwatch _stopwatch;
  late Timer _timer;
  late AnimationController _pulseController;
  final String _networkQuality = 'Stable';
  final Color _networkColor = Colors.greenAccent;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    if (widget.isVideo) {
      _isSpeakerOn = true;
      Helper.setSpeakerphoneOn(true);
    }
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _initLogic();
  }

  void _initLogic() {
    _logic = CallWebRTCLogic(
      callId: widget.callId,
      otherId: widget.otherId,
      isCaller: widget.isCaller,
      onLocalStream: (s) {
        if (!mounted) return;
        try {
          setState(() {
            _localRenderer.srcObject = s;
          });
        } catch (e) {
          debugPrint('safe onLocalStream assign error: $e');
        }
      },
      onRemoteStream: (s) {
        if (!mounted) return;
        try {
          setState(() {
            _remoteRenderer.srcObject = s;
          });
        } catch (e) {
          debugPrint('safe onRemoteStream assign error: $e');
        }
      },
      onStateChanged: (st) {
        if (!mounted) return;
        setState(() {
          _isConnected = st == 'connected';
          _isRinging = st == 'ringing';
        });

        if (_isConnected) {
          if (!_stopwatch.isRunning) _stopwatch.start();
          _pulseController.stop();
          NotificationService.stopRingtone();
        }

        if (st == 'ended' || st == 'failed') {
          _stopwatch.stop();
          NotificationService.stopRingtone();
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
      },
      onLog: (m) => debugPrint('[WebRTC_UI] $m'),
    );
    _startCallFlow();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  Future<void> _startCallFlow() async {
    try {
      final statuses = await [Permission.camera, Permission.microphone].request();

      // Check camera permission when video is requested
      if (widget.isVideo) {
        final camStatus = statuses[Permission.camera];
        if (camStatus == null || !camStatus.isGranted) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission caméra requise pour appeler en vidéo')));
          // If permanently denied, open app settings
          if (camStatus != null && camStatus.isPermanentlyDenied) {
            openAppSettings();
          }
          return;
        }
      }

      // Check microphone permission
      final micStatus = statuses[Permission.microphone];
      if (micStatus == null || !micStatus.isGranted) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission microphone requise')));
        if (micStatus != null && micStatus.isPermanentlyDenied) openAppSettings();
        return;
      }

      await _logic.openUserMedia(video: widget.isVideo);
      widget.isCaller ? await _logic.startAsCaller() : await _logic.startAsCallee();
    } catch (e) {
      debugPrint("Erreur Media: $e");
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _stopwatch.stop();
    _pulseController.dispose();
    _logic.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  // --- ACTIONS ---
  void _toggleMute() {
    _muted = !_muted;
    _localRenderer.srcObject?.getAudioTracks().forEach((t) => t.enabled = !_muted);
    setState(() {});
  }

  void _toggleCamera() {
    _camera = !_camera;
    _localRenderer.srcObject?.getVideoTracks().forEach((t) => t.enabled = _camera);
    setState(() {});
  }

  void _toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    Helper.setSpeakerphoneOn(_isSpeakerOn);
    setState(() {});
  }

  void _switchCamera() {
    _localRenderer.srcObject?.getVideoTracks().forEach((track) => Helper.switchCamera(track));
  }

  String _formatElapsed() {
    final d = _stopwatch.elapsed;
    return '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Important pour le PiP
      body: Stack(
        children: [
          // Widget Principal (Plein écran ou PiP déplaçable)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            top: _isMinimized ? _pipOffset.dy : 0,
            left: _isMinimized ? _pipOffset.dx : 0,
            child: GestureDetector(
              onPanUpdate: _isMinimized ? (d) => setState(() => _pipOffset += d.delta) : null,
              onTap: _isMinimized ? () => setState(() => _isMinimized = false) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _isMinimized ? 130 : MediaQuery.of(context).size.width,
                height: _isMinimized ? 200 : MediaQuery.of(context).size.height,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(_isMinimized ? 20 : 0),
                  boxShadow: [if (_isMinimized) const BoxShadow(color: Colors.black54, blurRadius: 15)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_isMinimized ? 20 : 0),
                  child: _isMinimized ? _buildPiPContent() : _buildFullContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- VUE RÉDUITE (PiP) ---
  Widget _buildPiPContent() {
    return Stack(
      children: [
        _remoteRenderer.srcObject != null
            ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            : Container(color: Colors.blueGrey, child: Center(child: Text(widget.avatarLetter))),
        Container(color: Colors.black26),
        const Positioned(top: 5, right: 5, child: Icon(Icons.open_in_full, size: 16, color: Colors.white70)),
      ],
    );
  }

  // --- VUE COMPLÈTE ---
  Widget _buildFullContent() {
    return Stack(
      children: [
        _buildGlassBackground(),
        // Vidéo Distante
        Positioned.fill(
          child: _remoteRenderer.srcObject != null
              ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : const SizedBox.shrink(),
        ),
        _buildGradientOverlay(),

        // Bouton Réduire (PiP)
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 15,
          child: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 35),
            onPressed: () => setState(() => _isMinimized = true),
          ),
        ),

        // Infos Caller
        Positioned(
          top: MediaQuery.of(context).padding.top + 30,
          left: 0, right: 0,
          child: Column(
            children: [
              _buildAnimatedAvatar(),
              const SizedBox(height: 15),
              Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildStatusChip(),
            ],
          ),
        ),

        // Vidéo Locale
        if (_camera && _localRenderer.srcObject != null)
          Positioned(right: 20, bottom: 160, width: 110, height: 160, child: _buildLocalPreview()),

        // Barre de commande
        Positioned(bottom: 40, left: 15, right: 15, child: _buildControlBar()),
      ],
    );
  }

  // --- COMPOSANTS UI DÉTAILLÉS ---

  Widget _buildGlassBackground() {
    return Stack(children: [
      Container(color: Colors.blueGrey.shade900),
      Center(child: Text(widget.avatarLetter, style: TextStyle(fontSize: 180, color: Colors.white.withOpacity(0.05)))),
      BackdropFilter(filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), child: Container(color: Colors.transparent)),
    ]);
  }

  Widget _buildGradientOverlay() => Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.7), Colors.transparent, Colors.black.withOpacity(0.9)])));

  Widget _buildAnimatedAvatar() => ScaleTransition(
    scale: Tween(begin: 1.0, end: 1.1).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)),
    child: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
      child: CircleAvatar(radius: 45, backgroundColor: Colors.blueAccent.shade700, child: Text(widget.avatarLetter, style: const TextStyle(fontSize: 32, color: Colors.white))),
    ),
  );

  Widget _buildStatusChip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
    child: Text(_isConnected ? _formatElapsed() : (_isRinging ? 'SONNERIE...' : 'CONNEXION...'), style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
  );

  Widget _buildLocalPreview() => Container(
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)),
    child: ClipRRect(borderRadius: BorderRadius.circular(15), child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
  );

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(40), border: Border.all(color: Colors.white10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleBtn(icon: _muted ? Icons.mic_off : Icons.mic, color: _muted ? Colors.redAccent : Colors.white10, onTap: _toggleMute),
          _circleBtn(icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down, color: _isSpeakerOn ? Colors.blueAccent : Colors.white10, onTap: _toggleSpeaker),
          _circleBtn(icon: Icons.call_end, color: Colors.red, size: 65, onTap: () => _logic.hangup()),
          if (widget.isVideo) ...[
            _circleBtn(icon: _camera ? Icons.videocam : Icons.videocam_off, color: _camera ? Colors.white10 : Colors.grey, onTap: _toggleCamera),
            if (_camera) _circleBtn(icon: Icons.flip_camera_ios, color: Colors.white10, onTap: _switchCamera),
          ],
        ],
      ),
    );
  }

  Widget _circleBtn({required IconData icon, required Color color, required VoidCallback onTap, double size = 50}) => Material(
    color: Colors.transparent,
    child: InkWell(onTap: onTap, customBorder: const CircleBorder(), child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: size * 0.5))),
  );
}
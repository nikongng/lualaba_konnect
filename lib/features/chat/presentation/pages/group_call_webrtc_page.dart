import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'group_call_webrtc_logic.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:lualaba_konnect/core/ongoing_call_service.dart';

class GroupCallWebRTCPage extends StatefulWidget {
  final String callId;
  final String name; // group name or title
  final bool isVideo;
  final bool isCaller;
  final bool startMuted;
  final bool publishAudio;

  const GroupCallWebRTCPage({
    super.key,
    required this.callId,
    required this.name,
    this.isVideo = false,
    this.isCaller = false,
    this.startMuted = false,
    this.publishAudio = true,
  });

  @override
  State<GroupCallWebRTCPage> createState() => _GroupCallWebRTCPageState();
}

class _GroupCallWebRTCPageState extends State<GroupCallWebRTCPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  GroupCallWebRTCLogic? _logic;

  bool _muted = false;
  bool _camera = true;
  bool _isSpeakerOn = false;
  bool _isConnected = false;
  bool _videoPausedByBackground = false;
  bool _isLiveMode = false;
  bool _isLeavingPage = false;
  bool _isDisposing = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callMetaSub;
  final TextEditingController _liveChatCtrl = TextEditingController();
  bool _sendingLiveChat = false;

  late Stopwatch _stopwatch;
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stopwatch = Stopwatch();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _muted = widget.startMuted || !widget.publishAudio;

    OngoingCallService.start(
      title: widget.name.isNotEmpty ? widget.name : 'Appel de groupe',
      subtitle: widget.isVideo
          ? 'Appel vidéo (audio en arrière-plan)'
          : 'Appel audio en cours',
    );

    if (widget.isVideo || !widget.publishAudio) {
      _isSpeakerOn = true;
      Helper.setSpeakerphoneOn(true);
    }

    _init();

    // detect "Live" mode to show chat overlay
    try {
      _callMetaSub = FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .snapshots()
          .listen((snap) {
            final data = snap.data() ?? <String, dynamic>{};
            final kind = (data['kind'] ?? '').toString().trim().toLowerCase();
            final mode = (data['mode'] ?? '').toString().trim().toLowerCase();
            final live = kind == 'live' || mode == 'broadcast';
            if (mounted && live != _isLiveMode) {
              setState(() => _isLiveMode = live);
            }
          });
    } catch (_) {}
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    if (!mounted || _isDisposing) return;
    await _initLogicAndStart();
    if (!mounted || _isDisposing) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_isDisposing) setState(() {});
    });
  }

  Future<void> _initLogicAndStart() async {
    final uid = await _currentUid();
    if (uid == null || uid.trim().isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final logic = GroupCallWebRTCLogic(
      callId: widget.callId,
      selfId: uid,
      isCaller: widget.isCaller,
      onLocalStream: (s) {
        if (!mounted || _isDisposing) return;
        try {
          s?.getAudioTracks().forEach((t) => t.enabled = !_muted);
        } catch (_) {}
        setState(() => _localRenderer.srcObject = s);
      },
      onRemoteStream: (remoteId, stream) async {
        if (!mounted || _isDisposing) return;
        if (stream == null) {
          final r = _remoteRenderers.remove(remoteId);
          try {
            await r?.dispose();
          } catch (_) {}
          setState(() {});
          return;
        }
        final renderer = _remoteRenderers.putIfAbsent(
          remoteId,
          () => RTCVideoRenderer(),
        );
        if (renderer.textureId == null) {
          await renderer.initialize();
        }
        renderer.srcObject = stream;
        setState(() {});
      },
      onStateChanged: (st) {
        if (!mounted || _isDisposing) return;
        if (st == 'connected') {
          _isConnected = true;
          if (!_stopwatch.isRunning) _stopwatch.start();
          _pulseController.stop();
          NotificationService.stopRingtone();
        }
        if (st == 'ended' || st == 'failed') {
          _stopwatch.stop();
          NotificationService.stopRingtone();
          _scheduleLeaveAfterEnd();
        }
        if (mounted && !_isDisposing) setState(() {});
      },
      onLog: (m) => debugPrint('[GroupWebRTC_UI] $m'),
    );
    _logic = logic;

    await _requestPermissions();
    if (_isDisposing || !mounted) return;
    await logic.openUserMedia(
      video: widget.isVideo,
      audio: widget.publishAudio,
    );
    if (_isDisposing || !mounted) return;
    await logic.start(
      isVideo: widget.isVideo,
      audioEnabled: widget.publishAudio,
    );
  }

  Future<String?> _currentUid() async {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      if (widget.publishAudio) Permission.microphone,
      if (widget.isVideo) Permission.camera,
    ].request();
    if (widget.isVideo) {
      final cam = statuses[Permission.camera];
      if (cam == null || !cam.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission caméra requise')),
          );
        }
      }
    }
    if (widget.publishAudio) {
      final mic = statuses[Permission.microphone];
      if (mic == null || !mic.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission microphone requise')),
          );
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _isDisposing) return;
    if (!widget.isVideo) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_camera) {
        _videoPausedByBackground = true;
        _localRenderer.srcObject?.getVideoTracks().forEach(
          (t) => t.enabled = false,
        );
        if (mounted && !_isDisposing) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_videoPausedByBackground) {
        _videoPausedByBackground = false;
        if (_camera) {
          _localRenderer.srcObject?.getVideoTracks().forEach(
            (t) => t.enabled = true,
          );
        }
        if (mounted && !_isDisposing) setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this);
    try {
      _callMetaSub?.cancel();
    } catch (_) {}
    _callMetaSub = null;
    _liveChatCtrl.dispose();
    OngoingCallService.stop();
    _timer?.cancel();
    _stopwatch.stop();
    _pulseController.dispose();
    final logic = _logic;
    _logic = null;
    if (logic != null) {
      logic.onLocalStream = null;
      logic.onRemoteStream = null;
      logic.onStateChanged = null;
      logic.onLog = null;
      logic.dispose();
    }
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) {
      try {
        r.dispose();
      } catch (_) {}
    }
    _remoteRenderers.clear();
    super.dispose();
  }

  void _scheduleLeaveAfterEnd() {
    if (_isLeavingPage || _isDisposing) return;
    _isLeavingPage = true;
    Future.delayed(const Duration(milliseconds: 350), () {
      _popIfPossible();
    });
  }

  Future<void> _leaveCallFromUi() async {
    if (_isLeavingPage || _isDisposing) return;
    _isLeavingPage = true;
    try {
      await _logic?.hangup(endForAll: widget.isCaller);
    } catch (_) {}
    _popIfPossible();
  }

  void _popIfPossible() {
    if (!mounted || _isDisposing) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  Future<void> _sendLiveChat() async {
    if (_sendingLiveChat) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final text = _liveChatCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sendingLiveChat = true);
    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .collection('live_comments')
          .add({
            'uid': user.uid,
            'name': (user.displayName ?? '').toString(),
            'text': text,
            'createdAt': FieldValue.serverTimestamp(),
            'createdAtMs': DateTime.now().millisecondsSinceEpoch,
          });
      _liveChatCtrl.clear();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _sendingLiveChat = false);
    }
  }

  void _toggleMute() {
    if (!widget.publishAudio) return;
    _muted = !_muted;
    _localRenderer.srcObject?.getAudioTracks().forEach(
      (t) => t.enabled = !_muted,
    );
    // Best-effort: reflect state in participants doc
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('calls')
            .doc(widget.callId)
            .collection('participants')
            .doc(uid)
            .set({'audio': !_muted}, SetOptions(merge: true));
      }
    } catch (_) {}
    setState(() {});
  }

  void _toggleCamera() {
    _camera = !_camera;
    _localRenderer.srcObject?.getVideoTracks().forEach(
      (t) => t.enabled = _camera,
    );
    setState(() {});
  }

  void _toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    Helper.setSpeakerphoneOn(_isSpeakerOn);
    setState(() {});
  }

  void _switchCamera() {
    _localRenderer.srcObject?.getVideoTracks().forEach(
      (t) => Helper.switchCamera(t),
    );
  }

  String _formatElapsed() {
    final d = _stopwatch.elapsed;
    return '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildRemoteGrid()),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.65),
                    Colors.transparent,
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 14,
            right: 14,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _leaveCallFromUi,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name.isNotEmpty
                            ? widget.name
                            : 'Appel de groupe',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isConnected ? _formatElapsed() : 'Connexion...',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.people,
                        size: 16,
                        color: Colors.white.withOpacity(0.85),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_remoteRenderers.length + 1}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (widget.isVideo && _camera && _localRenderer.srcObject != null)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 76,
              width: 110,
              height: 160,
              child: _buildLocalPreview(),
            ),
          if (_isLiveMode)
            Positioned(
              left: 14,
              right: 14,
              bottom: 110,
              child: _buildLiveChatOverlay(),
            ),
          Positioned(
            bottom: 34,
            left: 14,
            right: 14,
            child: _buildControlBar(isDark: isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveChatOverlay() {
    final chatRef = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .collection('live_comments');
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 120,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: chatRef
                      .orderBy('createdAtMs', descending: true)
                      .limit(30)
                      .snapshots(),
                  builder: (context, snap) {
                    final docs = snap.data?.docs ?? const [];
                    if (docs.isEmpty) {
                      return const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Soyez le premier à commenter...',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      itemCount: docs.length,
                      itemBuilder: (c, i) {
                        final d = docs[docs.length - 1 - i].data();
                        final name = (d['name'] ?? '').toString().trim();
                        final uid = (d['uid'] ?? '').toString();
                        final text = (d['text'] ?? '').toString();
                        final who = name.isNotEmpty
                            ? name
                            : (uid.isNotEmpty
                                  ? uid.substring(
                                      0,
                                      uid.length < 6 ? uid.length : 6,
                                    )
                                  : '?');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '$who: ',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: text,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _liveChatCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Commenter...',
                        hintStyle: TextStyle(color: Colors.white54),
                        isDense: true,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _sendLiveChat(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sendingLiveChat ? null : _sendLiveChat,
                    icon: Icon(
                      Icons.send,
                      color: _sendingLiveChat ? Colors.white30 : Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteGrid() {
    final ids =
        _remoteRenderers.entries
            .where(
              (e) => (e.value.srcObject?.getVideoTracks().isNotEmpty ?? false),
            )
            .map((e) => e.key)
            .toList()
          ..sort();

    if (ids.isNotEmpty) {
      final count = ids.length;
      final crossAxisCount = count <= 1 ? 1 : (count <= 4 ? 2 : 3);
      return GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: ids.length,
        itemBuilder: (c, i) {
          final r = _remoteRenderers[ids[i]]!;
          return Container(
            color: Colors.black,
            child: RTCVideoView(
              r,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          );
        },
      );
    }

    return Stack(
      children: [
        Container(color: Colors.black),
        Center(
          child: ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.07).animate(
              CurvedAnimation(
                parent: _pulseController,
                curve: Curves.easeInOut,
              ),
            ),
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
                color: Colors.white10,
              ),
              child: const Icon(Icons.people, color: Colors.white70, size: 56),
            ),
          ),
        ),
        Positioned(
          bottom: 120,
          left: 0,
          right: 0,
          child: Text(
            'En attente des participants...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalPreview() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 10),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: RTCVideoView(
          _localRenderer,
          mirror: true,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      ),
    );
  }

  Widget _buildControlBar({required bool isDark}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (widget.publishAudio)
                _circleBtn(
                  icon: _muted ? Icons.mic_off : Icons.mic,
                  color: _muted ? Colors.redAccent : Colors.white10,
                  onTap: _toggleMute,
                )
              else
                const SizedBox(width: 50, height: 50),
              _circleBtn(
                icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                color: _isSpeakerOn ? Colors.blueAccent : Colors.white10,
                onTap: _toggleSpeaker,
              ),
              _circleBtn(
                icon: Icons.call_end,
                color: Colors.red,
                size: 65,
                onTap: _leaveCallFromUi,
              ),
              if (widget.isVideo) ...[
                _circleBtn(
                  icon: _camera ? Icons.videocam : Icons.videocam_off,
                  color: _camera ? Colors.white10 : Colors.grey,
                  onTap: _toggleCamera,
                ),
                if (_camera)
                  _circleBtn(
                    icon: Icons.flip_camera_ios,
                    color: Colors.white10,
                    onTap: _switchCamera,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 50,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    ),
  );
}

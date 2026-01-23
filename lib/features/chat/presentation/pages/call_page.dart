import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lualaba_konnect/core/notification_service.dart';

class CallPage extends StatefulWidget {
  final String name;
  final String avatarLetter;
  final bool isVideo;
  final String? otherId; // remote user's uid (optional)
  final String? callId; // firestore call document id (optional)
  final bool isCaller;

  const CallPage({
    super.key,
    required this.name,
    required this.avatarLetter,
    this.isVideo = false,
    this.otherId,
    this.callId,
    this.isCaller = false,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  bool _muted = false;
  bool _speaker = true;
  bool _camera = true;
  late Stopwatch _stopwatch;
  late final _Ticker _ticker;

  StreamSubscription<DocumentSnapshot>? _presenceSub;
  StreamSubscription<DocumentSnapshot>? _callSub;
  bool? _remoteOnline;
  bool _isRinging = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch();
    _ticker = _Ticker((_) {
      if (mounted) setState(() {});
    })..start();

    // subscribe to remote presence if provided
    if (widget.otherId != null) {
      _presenceSub = FirebaseFirestore.instance.collection('users').doc(widget.otherId).snapshots().listen((snap) {
        if (!mounted) return;
        final data = (snap.data() is Map) ? Map<String, dynamic>.from((snap.data() as Map<String, dynamic>?) ?? {}) : <String, dynamic>{};
        final online = data['isOnline'] == true;
        setState(() {
          _remoteOnline = online;
        });
        _evaluateRingingState();
      });
    }

    // subscribe to call doc if available to react to status changes
    if (widget.callId != null) {
      _callSub = FirebaseFirestore.instance.collection('calls').doc(widget.callId).snapshots().listen((snap) {
        if (!mounted || !snap.exists) return;
        final raw = snap.data();
        final data = raw is Map ? Map<String, dynamic>.from((raw as Map<String, dynamic>?) ?? {}) : <String, dynamic>{};
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (['accepted', 'answered', 'in_progress', 'connected', 'ongoing'].contains(status)) {
          if (!_isConnected) {
            setState(() {
              _isConnected = true;
              _isRinging = false;
            });
            NotificationService.stopRingtone();
            if (!_stopwatch.isRunning) _stopwatch.start();
          }
        } else if (['ringing'].contains(status)) {
          if (!_isConnected) {
            setState(() {
              _isRinging = true;
            });
            _evaluateRingingState();
          }
        } else if (['ended', 'rejected', 'no_answer', 'busy'].contains(status)) {
          // stop all
          setState(() {
            _isRinging = false;
            _isConnected = false;
          });
          NotificationService.stopRingtone();
          if (_stopwatch.isRunning) _stopwatch.stop();
        }
      });
    }
  }

  @override
  void dispose() {
    _ticker.stop();
    _stopwatch.stop();
    _presenceSub?.cancel();
    _callSub?.cancel();
    super.dispose();
  }

  String _formatElapsed() {
    final elapsed = _stopwatch.elapsed;
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _evaluateRingingState() {
    if (!_isRinging) {
      NotificationService.stopRingtone();
      return;
    }
    // Caller: only ring if remote appears online
    if (widget.isCaller) {
      if (_remoteOnline == false) {
        NotificationService.stopRingtone();
      } else {
        NotificationService.playRingtone();
      }
    } else {
      // Callee: play ringtone while ringing
      NotificationService.playRingtone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            // Background gradient and subtle blur
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
                ),
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(color: Colors.black.withOpacity(0.15)),
              ),
            ),

            // Main content
            Column(
              children: [
                const SizedBox(height: 24),
                // Top bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                            const SizedBox(height: 4),
                            Text(widget.isVideo ? 'Appel vidéo' : 'Appel audio', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                        child: Row(children: [const Icon(Icons.signal_cellular_alt, color: Colors.white70, size: 16), const SizedBox(width: 6), Text(_formatElapsed(), style: const TextStyle(color: Colors.white70))]),
                      )
                    ],
                  ),
                ),

                const Spacer(),

                // Avatar with glowing ring
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(colors: [Color(0xFF00CBA9), Color(0xFF764ba2)]),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 20, spreadRadius: 2)],
                    ),
                    child: CircleAvatar(
                      radius: 72,
                      backgroundColor: Colors.white,
                      child: Text(widget.avatarLetter, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: Color(0xFF203A43))),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Small info row
                Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  _isConnected
                      ? _formatElapsed()
                      : (_isRinging ? 'Ça sonne...' : (_remoteOnline == false ? 'Indisponible' : 'En attente')),
                  style: TextStyle(color: Colors.white.withOpacity(0.8)),
                ),

                const Spacer(),

                // Controls (responsive)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _controlButton(
                          icon: _muted ? Icons.mic_off : Icons.mic,
                          label: _muted ? 'Muet' : 'Micro',
                          color: _muted ? Colors.deepOrangeAccent : const Color(0xFF7C4DFF),
                          onTap: () => setState(() => _muted = !_muted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _controlButton(
                          icon: _camera ? Icons.videocam : Icons.videocam_off,
                          label: _camera ? 'Activer vidéo' : 'Désactiver',
                          color: _camera ? const Color(0xFF7C4DFF) : Colors.white12,
                          onTap: () => setState(() => _camera = !_camera),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // End call central big button
                      GestureDetector(
                        onTap: () async {
                          // hangup: stop sounds and timers, update call doc if available
                          NotificationService.stopRingtone();
                          if (_stopwatch.isRunning) _stopwatch.stop();
                          try {
                            if (widget.callId != null) {
                              await FirebaseFirestore.instance.collection('calls').doc(widget.callId).update({'status': 'ended', 'endedAt': FieldValue.serverTimestamp()});
                            }
                          } catch (_) {}
                          if (mounted) Navigator.pop(context);
                        },
                        child: Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.45), blurRadius: 16, spreadRadius: 3)]),
                          alignment: Alignment.center,
                          child: const Icon(Icons.call_end, color: Colors.white, size: 38),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _controlButton(
                          icon: _speaker ? Icons.volume_up : Icons.headset_off,
                          label: _speaker ? 'Haut-parleur' : 'Son',
                          color: _speaker ? const Color(0xFF7C4DFF) : Colors.white12,
                          onTap: () => setState(() => _speaker = !_speaker),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _controlButton(icon: Icons.more_horiz, label: 'Muet', color: Colors.white12, onTap: () {}),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: Offset(0,4))],
            ),
            width: 64,
            height: 64,
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 86,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// Simple Ticker used by the page
class _Ticker {
  final void Function(Duration) _onTick;
  bool _running = false;
  _Ticker(this._onTick);
  void start() {
    _running = true;
    _loop();
  }

  void _loop() async {
    while (_running) {
      await Future.delayed(const Duration(seconds: 1));
      _onTick(Duration.zero);
    }
  }

  void stop() { _running = false; }
}

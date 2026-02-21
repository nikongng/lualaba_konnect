import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'call_webrtc_logic.dart';
import 'group_call_webrtc_page.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:lualaba_konnect/core/ongoing_call_service.dart';
import 'package:lualaba_konnect/core/config.dart';

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

class _CallWebRTCPageState extends State<CallWebRTCPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CallWebRTCLogic? _logic;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _endingHandled = false;
  bool _navigatingUpgrade = false;
  bool _isClosingPage = false;
  bool _isDisposing = false;

  // États de l'appel
  bool _muted = false;
  bool _camera = true;
  bool _isSpeakerOn = false;
  bool _isConnected = false;
  bool _isRinging = false;
  bool _videoPausedByBackground = false;

  // États PiP (Picture-in-Picture)
  bool _isMinimized = false;
  Offset _pipOffset = const Offset(20, 60);

  // Monitoring & Animations
  late Stopwatch _stopwatch;
  Timer? _timer;
  late AnimationController _pulseController;
  final String _networkQuality = 'Stable';
  final Color _networkColor = Colors.greenAccent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stopwatch = Stopwatch();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Keep audio reliable when app goes background (Android): show a foreground-service notification.
    // Video is handled separately (we disable camera when backgrounded).
    OngoingCallService.start(
      title: widget.name.isNotEmpty ? widget.name : 'Appel en cours',
      subtitle: widget.isVideo
          ? 'Appel vidéo (audio en arrière-plan)'
          : 'Appel audio en cours',
    );

    if (widget.isVideo) {
      _isSpeakerOn = true;
      Helper.setSpeakerphoneOn(true);
    }
    _initRenderers();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _isDisposing) return;
    // Most realistic behavior: when app goes background, keep audio but pause video capture.
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
        // Restore only if user didn't manually disable camera during the pause.
        if (_camera) {
          _localRenderer.srcObject?.getVideoTracks().forEach(
            (t) => t.enabled = true,
          );
        }
        if (mounted && !_isDisposing) setState(() {});
      }
    }
  }

  Future<void> _initRenderers() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      if (!mounted || _isDisposing) return;
      _initLogic();
    } catch (e) {
      debugPrint('init renderers error: $e');
    }
  }

  void _initLogic() {
    final logic = CallWebRTCLogic(
      callId: widget.callId,
      otherId: widget.otherId,
      isCaller: widget.isCaller,
      onLocalStream: (s) {
        if (!mounted || _isDisposing) return;
        try {
          setState(() {
            _localRenderer.srcObject = s;
          });
        } catch (e) {
          debugPrint('safe onLocalStream assign error: $e');
        }
      },
      onRemoteStream: (s) {
        if (!mounted || _isDisposing) return;
        try {
          setState(() {
            _remoteRenderer.srcObject = s;
          });
        } catch (e) {
          debugPrint('safe onRemoteStream assign error: $e');
        }
      },
      onStateChanged: (st) {
        if (!mounted || _isDisposing) return;
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
          _handleEndedOrUpgrade();
        }
      },
      onLog: (m) => debugPrint('[WebRTC_UI] $m'),
    );
    _logic = logic;
    _startCallFlow();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_isDisposing) setState(() {});
    });
  }

  Future<void> _startCallFlow() async {
    try {
      final logic = _logic;
      if (logic == null || _isDisposing) return;
      final statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      // Check camera permission when video is requested
      if (widget.isVideo) {
        final camStatus = statuses[Permission.camera];
        if (camStatus == null || !camStatus.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Permission caméra requise pour appeler en vidéo',
                ),
              ),
            );
          }
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permission microphone requise')),
          );
        }
        if (micStatus != null && micStatus.isPermanentlyDenied) {
          openAppSettings();
        }
        return;
      }

      await logic.openUserMedia(video: widget.isVideo);
      widget.isCaller
          ? await logic.startAsCaller()
          : await logic.startAsCallee();
    } catch (e) {
      debugPrint("Erreur Media: $e");
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this);
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
    _remoteRenderer.dispose();
    super.dispose();
  }

  // --- ACTIONS ---
  void _toggleMute() {
    _muted = !_muted;
    _localRenderer.srcObject?.getAudioTracks().forEach(
      (t) => t.enabled = !_muted,
    );
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
      (track) => Helper.switchCamera(track),
    );
  }

  Future<void> _handleEndedOrUpgrade() async {
    if (_navigatingUpgrade || _endingHandled || _isClosingPage || _isDisposing) {
      return;
    }
    _endingHandled = true;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      final upgradeTo = (data['upgradeToCallId'] ?? '').toString();
      if (upgradeTo.isNotEmpty) {
        _navigatingUpgrade = true;
        final bool isVideo = (data['upgradeIsVideo'] == true) || widget.isVideo;
        final String title = (data['upgradeTitle'] ?? widget.name).toString();
        if (!mounted || _isDisposing) return;
        _isClosingPage = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GroupCallWebRTCPage(
              callId: upgradeTo,
              name: title,
              isVideo: isVideo,
              isCaller: widget.isCaller,
            ),
          ),
        );
        return;
      }
    } catch (_) {
      // Best-effort only.
    }

    Future.delayed(const Duration(milliseconds: 500), () {
      _popIfPossible();
    });
  }

  Future<void> _endCallFromUi() async {
    if (_isClosingPage || _isDisposing) return;
    _endingHandled = true;
    try {
      await _logic?.hangup();
    } catch (_) {}
    _popIfPossible();
  }

  void _popIfPossible() {
    if (!mounted || _isDisposing || _isClosingPage) return;
    final nav = Navigator.of(context);
    if (!nav.canPop()) return;
    _isClosingPage = true;
    nav.pop();
  }

  Future<void> _showAddParticipantSheet() async {
    try {
      final self = FirebaseAuth.instance.currentUser;
      if (self == null) return;
      if (!_isConnected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Attendez la connexion avant d’ajouter une personne',
              ),
            ),
          );
        }
        return;
      }

      final picked = await _pickContactUid();
      if (picked == null || picked.trim().isEmpty) return;
      if (picked == widget.otherId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cette personne est déjà dans l’appel'),
            ),
          );
        }
        return;
      }
      await _upgradeToGroupCall(addUid: picked.trim());
    } catch (e) {
      debugPrint('add participant error: $e');
    }
  }

  Future<String?> _pickContactUid() async {
    final self = FirebaseAuth.instance.currentUser;
    if (self == null) return null;
    final blocked = <String>{self.uid, widget.otherId};
    try {
      final callSnap = await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .get();
      final data = callSnap.data() ?? <String, dynamic>{};
      final participants = (data['participants'] is List)
          ? List<String>.from(
              (data['participants'] as List).map((e) => e.toString()),
            )
          : const <String>[];
      blocked.addAll(participants.where((e) => e.trim().isNotEmpty));
    } catch (_) {}

    final Map<String, Map<String, String>> byUid = {};
    void addCandidate({
      required String uid,
      required String name,
      required String phone,
    }) {
      final id = uid.trim();
      if (id.isEmpty || blocked.contains(id)) return;
      final existing = byUid[id];
      if (existing != null) {
        if ((existing['name'] ?? '').trim().isEmpty && name.trim().isNotEmpty) {
          existing['name'] = name.trim();
        }
        if ((existing['phone'] ?? '').trim().isEmpty &&
            phone.trim().isNotEmpty) {
          existing['phone'] = phone.trim();
        }
        return;
      }
      byUid[id] = {'uid': id, 'name': name.trim(), 'phone': phone.trim()};
    }

    try {
      final profileCols = [
        'classic_users',
        'enterprise_users',
        'pro_users',
        'users',
      ];
      DocumentReference<Map<String, dynamic>>? baseRef;
      for (final c in profileCols) {
        try {
          final ref = FirebaseFirestore.instance.collection(c).doc(self.uid);
          final snap = await ref.get();
          if (snap.exists) {
            baseRef = ref;
            break;
          }
        } catch (_) {}
      }
      if (baseRef != null) {
        final contactsSnap = await baseRef.collection('contacts').get();
        for (final d in contactsSnap.docs) {
          final data = d.data();
          final name =
              (data['displayName'] ?? data['name'] ?? data['username'] ?? '')
                  .toString();
          final phone = (data['phone'] ?? data['phoneNumber'] ?? '').toString();
          addCandidate(
            uid: d.id,
            name: name.isNotEmpty ? name : d.id,
            phone: phone,
          );
        }
      }
    } catch (_) {}

    try {
      final chats = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: self.uid)
          .get();
      final fromChats = <String>{};
      for (final chat in chats.docs) {
        final data = chat.data();
        final participants = (data['participants'] is List)
            ? List<String>.from(
                (data['participants'] as List).map((e) => e.toString()),
              )
            : const <String>[];
        for (final p in participants) {
          if (p.trim().isNotEmpty && !blocked.contains(p)) fromChats.add(p);
        }
      }
      for (final uid in fromChats) {
        if (byUid.containsKey(uid)) continue;
        for (final col in [
          'classic_users',
          'pro_users',
          'enterprise_users',
          'users',
        ]) {
          try {
            final doc = await FirebaseFirestore.instance
                .collection(col)
                .doc(uid)
                .get();
            if (!doc.exists) continue;
            final data = doc.data() ?? <String, dynamic>{};
            final display =
                (data['displayName'] ??
                        data['display_name'] ??
                        data['name'] ??
                        '${(data['firstName'] ?? '').toString()} ${(data['lastName'] ?? '').toString()}')
                    .toString()
                    .trim();
            addCandidate(
              uid: uid,
              name: display.isNotEmpty ? display : uid,
              phone: (data['phone'] ?? data['phoneNumber'] ?? '').toString(),
            );
            break;
          } catch (_) {}
        }
      }
    } catch (_) {}

    final cols = ['classic_users', 'pro_users', 'enterprise_users', 'users'];
    for (final col in cols) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection(col)
            .limit(400)
            .get();
        for (final doc in snap.docs) {
          final d = doc.data();
          final display =
              (d['displayName'] ??
                      d['display_name'] ??
                      d['name'] ??
                      '${(d['firstName'] ?? '').toString()} ${(d['lastName'] ?? '').toString()}')
                  .toString()
                  .trim();
          addCandidate(
            uid: doc.id,
            name: display.isNotEmpty ? display : doc.id,
            phone: (d['phone'] ?? d['phoneNumber'] ?? '').toString(),
          );
        }
      } catch (_) {}
    }

    if (!mounted) return null;
    final searchCtrl = TextEditingController();
    String search = '';
    final items = byUid.values.toList()
      ..sort(
        (a, b) => (a['name'] ?? '').toLowerCase().compareTo(
          (b['name'] ?? '').toLowerCase(),
        ),
      );

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF17212B) : Colors.white;
        final fg = isDark ? Colors.white : Colors.black87;
        final sub = isDark ? Colors.white70 : Colors.black54;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = items.where((m) {
              if (search.trim().isEmpty) return true;
              final q = search.toLowerCase();
              final hay =
                  '${m['name'] ?? ''} ${m['phone'] ?? ''} ${m['uid'] ?? ''}'
                      .toLowerCase();
              return hay.contains(q);
            }).toList();
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.75,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : Colors.black12,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Ajouter une personne',
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl,
                    style: TextStyle(color: fg),
                    onChanged: (v) => setModalState(() => search = v),
                    decoration: InputDecoration(
                      hintText: 'Rechercher utilisateur...',
                      hintStyle: TextStyle(color: sub),
                      prefixIcon: Icon(Icons.search, color: sub),
                      filled: true,
                      fillColor: isDark ? Colors.white10 : Colors.black12,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Aucun utilisateur',
                              style: TextStyle(color: sub),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Divider(
                              color: isDark ? Colors.white10 : Colors.black12,
                            ),
                            itemBuilder: (c, i) {
                              final it = filtered[i];
                              final uid = (it['uid'] ?? '').toString();
                              final name = (it['name'] ?? '').toString();
                              final phone = (it['phone'] ?? '').toString();
                              final letter = (name.isNotEmpty ? name[0] : '?')
                                  .toUpperCase();
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.white10,
                                  child: Text(
                                    letter,
                                    style: TextStyle(color: fg),
                                  ),
                                ),
                                title: Text(
                                  name.isNotEmpty ? name : uid,
                                  style: TextStyle(color: fg),
                                ),
                                subtitle: phone.isNotEmpty
                                    ? Text(phone, style: TextStyle(color: sub))
                                    : null,
                                onTap: () => Navigator.pop(c, uid),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    searchCtrl.dispose();
    return selected;
  }

  Future<void> _upgradeToGroupCall({required String addUid}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_navigatingUpgrade) return;

    Map<String, dynamic> oldCall = <String, dynamic>{};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .get();
      oldCall = snap.data() ?? <String, dynamic>{};
    } catch (_) {}
    final String hostId =
        (oldCall['caller'] ?? (widget.isCaller ? user.uid : widget.otherId))
            .toString();
    final String hostName = (oldCall['callerName'] ?? '').toString();
    final bool amHost = hostId == user.uid;

    final participants = <String>{
      user.uid,
      widget.otherId,
      addUid,
    }.where((e) => e.trim().isNotEmpty).toList();
    if (participants.length < 3) return;

    final String title = widget.name.isNotEmpty
        ? widget.name
        : 'Appel de groupe';
    final groupCallRef = await FirebaseFirestore.instance
        .collection('calls')
        .add({
          'isGroup': true,
          'caller': hostId,
          'callerName': hostName.isNotEmpty
              ? hostName
              : (user.displayName ?? ''),
          'upgradedBy': user.uid,
          'participants': participants,
          'invited': [addUid],
          'status': 'ringing',
          'type': widget.isVideo ? 'video' : 'audio',
          'createdAt': FieldValue.serverTimestamp(),
          'groupName': title,
          'chatName': title,
          'upgradedFrom': widget.callId,
        });

    // Notify the added person (and also the current other participant as a fallback).
    try {
      await _sendIncomingGroupCallPush(
        calleeIds: [addUid],
        callId: groupCallRef.id,
        isVideo: widget.isVideo,
        title: title,
        callerId: hostId,
        callerName: hostName.isNotEmpty ? hostName : (user.displayName ?? ''),
      );
    } catch (_) {}

    _navigatingUpgrade = true;
    _endingHandled = true;

    // Mark current 1:1 call as upgrading so both participants switch automatically.
    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .set({
            'upgradeToCallId': groupCallRef.id,
            'upgradeIsVideo': widget.isVideo,
            'upgradeTitle': title,
            'upgradedAt': FieldValue.serverTimestamp(),
            'status': 'ended',
          }, SetOptions(merge: true));
    } catch (_) {}

    try {
      await _logic?.hangup(setFireStoreEnded: false);
    } catch (_) {}

    if (!mounted || _isDisposing) return;
    _isClosingPage = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GroupCallWebRTCPage(
          callId: groupCallRef.id,
          name: title,
          isVideo: widget.isVideo,
          isCaller: amHost,
        ),
      ),
    );
  }

  Future<void> _sendIncomingGroupCallPush({
    required List<String> calleeIds,
    required String callId,
    required bool isVideo,
    required String title,
    required String callerId,
    required String callerName,
  }) async {
    final ids = calleeIds.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final idToken = await user.getIdToken();
    final url = Uri.parse(kNotifierUrl);

    await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'recipients': ids,
        'title': title,
        'body': isVideo ? 'Appel vidéo de groupe' : 'Appel audio de groupe',
        'existing_android_channel_id': 'lualaba_channel_v2',
        'android_sound': 'lualaba_pop',
        'data': {
          'type': 'incoming_call',
          'isGroup': true,
          'callId': callId,
          'isVideo': isVideo,
          'groupName': title,
          'chatName': title,
          'caller': callerId,
          'callerName': callerName,
        },
      }),
    );
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
              onPanUpdate: _isMinimized
                  ? (d) => setState(() => _pipOffset += d.delta)
                  : null,
              onTap: _isMinimized
                  ? () => setState(() => _isMinimized = false)
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _isMinimized ? 130 : MediaQuery.of(context).size.width,
                height: _isMinimized ? 200 : MediaQuery.of(context).size.height,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(_isMinimized ? 20 : 0),
                  boxShadow: [
                    if (_isMinimized)
                      const BoxShadow(color: Colors.black54, blurRadius: 15),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_isMinimized ? 20 : 0),
                  child: _isMinimized
                      ? _buildPiPContent()
                      : _buildFullContent(),
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
            ? RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : Container(
                color: Colors.blueGrey,
                child: Center(child: Text(widget.avatarLetter)),
              ),
        Container(color: Colors.black26),
        const Positioned(
          top: 5,
          right: 5,
          child: Icon(Icons.open_in_full, size: 16, color: Colors.white70),
        ),
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
              ? RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              : const SizedBox.shrink(),
        ),
        _buildGradientOverlay(),

        // Bouton Réduire (PiP)
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 15,
          child: IconButton(
            icon: const Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white,
              size: 35,
            ),
            onPressed: () => setState(() => _isMinimized = true),
          ),
        ),

        // Infos Caller
        Positioned(
          top: MediaQuery.of(context).padding.top + 30,
          left: 0,
          right: 0,
          child: Column(
            children: [
              _buildAnimatedAvatar(),
              const SizedBox(height: 15),
              Text(
                widget.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildStatusChip(),
            ],
          ),
        ),

        // Vidéo Locale
        if (_camera && _localRenderer.srcObject != null)
          Positioned(
            right: 20,
            bottom: 160,
            width: 110,
            height: 160,
            child: _buildLocalPreview(),
          ),

        // Barre de commande
        Positioned(bottom: 40, left: 15, right: 15, child: _buildControlBar()),
      ],
    );
  }

  // --- COMPOSANTS UI DÉTAILLÉS ---

  Widget _buildGlassBackground() {
    return Stack(
      children: [
        Container(color: Colors.blueGrey.shade900),
        Center(
          child: Text(
            widget.avatarLetter,
            style: TextStyle(
              fontSize: 180,
              color: Colors.white.withOpacity(0.05),
            ),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(color: Colors.transparent),
        ),
      ],
    );
  }

  Widget _buildGradientOverlay() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withOpacity(0.7),
          Colors.transparent,
          Colors.black.withOpacity(0.9),
        ],
      ),
    ),
  );

  Widget _buildAnimatedAvatar() => ScaleTransition(
    scale: Tween(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    ),
    child: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: CircleAvatar(
        radius: 45,
        backgroundColor: Colors.blueAccent.shade700,
        child: Text(
          widget.avatarLetter,
          style: const TextStyle(fontSize: 32, color: Colors.white),
        ),
      ),
    ),
  );

  Widget _buildStatusChip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      _isConnected
          ? _formatElapsed()
          : (_isRinging ? 'SONNERIE...' : 'CONNEXION...'),
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _buildLocalPreview() => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: Colors.white24),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: RTCVideoView(
        _localRenderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    ),
  );

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleBtn(
            icon: _muted ? Icons.mic_off : Icons.mic,
            color: _muted ? Colors.redAccent : Colors.white10,
            onTap: _toggleMute,
          ),
          _circleBtn(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            color: _isSpeakerOn ? Colors.blueAccent : Colors.white10,
            onTap: _toggleSpeaker,
          ),
          _circleBtn(
            icon: Icons.call_end,
            color: Colors.red,
            size: 65,
            onTap: _endCallFromUi,
          ),
          _circleBtn(
            icon: Icons.person_add_alt_1,
            color: Colors.white10,
            onTap: _showAddParticipantSheet,
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

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallWebRTCPage extends StatefulWidget {
  final String callId;
  final String otherId; // other participant uid
  final bool isCaller;
  final String name;

  const CallWebRTCPage({super.key, required this.callId, required this.otherId, required this.isCaller, required this.name});

  @override
  State<CallWebRTCPage> createState() => _CallWebRTCPageState();
}

class _CallWebRTCPageState extends State<CallWebRTCPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final _remoteRenderer = RTCVideoRenderer();
  final _localRenderer = RTCVideoRenderer();

  bool _muted = false;
  bool _videoEnabled = false;
  bool _speakerOn = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _start();
  }

  Future<void> _initRenderers() async {
    await _remoteRenderer.initialize();
    await _localRenderer.initialize();
  }

  Future<void> _start() async {
    await _openUserMedia(video: _videoEnabled);
    if (widget.isCaller) {
      await _createPeerConnectionAsCaller();
    } else {
      await _createPeerConnectionAsCallee();
    }
  }

  Future<void> _openUserMedia({bool video = false}) async {
    final Map<String, dynamic> mediaConstraints = {'audio': true, 'video': video};
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
    } catch (e) {
      debugPrint('openUserMedia error: $e');
    }
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    try {
      if (_localStream != null) {
        for (var t in _localStream!.getAudioTracks()) {
          t.enabled = !_muted;
        }
      }
    } catch (e) {
      debugPrint('toggleMute error: $e');
    }
  }

  Future<void> _toggleVideo() async {
    try {
      if (!_videoEnabled) {
        final media = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': true});
        final videoTracks = media.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          if (_localStream != null) {
            try {
              _localStream!.addTrack(videoTracks[0]);
            } catch (_) {}
          } else {
            _localStream = media;
          }
          _localRenderer.srcObject = _localStream;
          if (_pc != null) {
            try {
              await _pc!.addTrack(videoTracks[0], _localStream!);
            } catch (_) {}
          }
        }
        setState(() => _videoEnabled = true);
      } else {
        if (_localStream != null) {
          for (var t in List<MediaStreamTrack>.from(_localStream!.getVideoTracks())) {
            try {
              t.stop();
              _localStream!.removeTrack(t);
            } catch (_) {}
          }
          _localRenderer.srcObject = _localStream;
        }
        setState(() => _videoEnabled = false);
      }
    } catch (e) {
      debugPrint('toggleVideo error: $e');
    }
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_speakerOn ? 'Haut‑parleur activé (placeholder)' : 'Haut‑parleur désactivé (placeholder)')));
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final configuration = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };
    final pc = await createPeerConnection(configuration);
    if (_localStream != null) {
      _localStream!.getTracks().forEach((t) => pc.addTrack(t, _localStream!));
    }
    pc.onIceCandidate = (RTCIceCandidate c) async {
      if (c.candidate == null) return;
      final coll = widget.isCaller ? 'callerCandidates' : 'calleeCandidates';
      await _db.collection('calls').doc(widget.callId).collection(coll).add({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) _remoteRenderer.srcObject = event.streams[0];
    };
    return pc;
  }

  Future<void> _createPeerConnectionAsCaller() async {
    _pc = await _createPeerConnection();
    final callDoc = _db.collection('calls').doc(widget.callId);
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    await callDoc.set({'caller': _auth.currentUser?.uid, 'callee': widget.otherId, 'offer': {'sdp': offer.sdp, 'type': offer.type}, 'createdAt': FieldValue.serverTimestamp()});

    // listen for answer
    callDoc.snapshots().listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data();
      if (data != null && data['answer'] != null) {
        final ans = data['answer'] as Map<String, dynamic>;
        final rtc = RTCSessionDescription(ans['sdp'], ans['type']);
        await _pc!.setRemoteDescription(rtc);
      }
    });

    // listen for callee ICE
    _db.collection('calls').doc(widget.callId).collection('calleeCandidates').snapshots().listen((snap) {
      for (var doc in snap.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data()!;
          _pc!.addCandidate(RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        }
      }
    });
  }

  Future<void> _createPeerConnectionAsCallee() async {
    _pc = await _createPeerConnection();
    final callDoc = _db.collection('calls').doc(widget.callId);
    final snap = await callDoc.get();
    if (!snap.exists) return;
    final data = snap.data()!;
    final offer = data['offer'] as Map<String, dynamic>;
    final rtcOffer = RTCSessionDescription(offer['sdp'], offer['type']);
    await _pc!.setRemoteDescription(rtcOffer);
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await callDoc.update({'answer': {'sdp': answer.sdp, 'type': answer.type}});

    // listen for caller ICE
    _db.collection('calls').doc(widget.callId).collection('callerCandidates').snapshots().listen((snap) {
      for (var doc in snap.docChanges) {
        if (doc.type == DocumentChangeType.added) {
          final data = doc.doc.data()!;
          _pc!.addCandidate(RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        }
      }
    });
  }

  Future<void> _hangUp() async {
    await _pc?.close();
    _localStream?.getTracks().forEach((t) => t.stop());
    // delete call doc and subcollections
    final callRef = _db.collection('calls').doc(widget.callId);
    final callerCol = await callRef.collection('callerCandidates').get();
    for (var d in callerCol.docs) await d.reference.delete();
    final calleeCol = await callRef.collection('calleeCandidates').get();
    for (var d in calleeCol.docs) await d.reference.delete();
    await callRef.delete();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _remoteRenderer.dispose();
    _localRenderer.dispose();
    _pc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1418),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(radius: 56, backgroundColor: Colors.white10, child: Text(widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 36))),
            const SizedBox(height: 16),
            Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(height: 160, width: 160, child: RTCVideoView(_localRenderer, mirror: true)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              // Haut-parleur (placeholder)
              Column(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.purple.shade300,
                    child: IconButton(
                      icon: Icon(_speakerOn ? Icons.volume_up : Icons.volume_off, color: Colors.white),
                      onPressed: _toggleSpeaker,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Haut‑parleur', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),

              // Activer vidéo
              Column(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white10,
                    child: IconButton(
                      icon: Icon(_videoEnabled ? Icons.videocam : Icons.videocam_off, color: Colors.white),
                      onPressed: _toggleVideo,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Activer vidéo', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),

              // Raccrocher
              Column(
                children: [
                  FloatingActionButton(backgroundColor: Colors.red, child: const Icon(Icons.call_end), onPressed: _hangUp),
                  const SizedBox(height: 6),
                  const Text('Raccrocher', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),

              // Muet
              Column(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white10,
                    child: IconButton(
                      icon: Icon(_muted ? Icons.mic_off : Icons.mic, color: Colors.white),
                      onPressed: _toggleMute,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Muet', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ])
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

class GroupCallWebRTCLogic {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final String callId;
  final String selfId;
  final bool isCaller;

  void Function(MediaStream? local)? onLocalStream;
  void Function(String remoteId, MediaStream? remote)? onRemoteStream;
  void Function(String state)? onStateChanged;
  void Function(String msg)? onLog;

  MediaStream? _localStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _participantsSub;

  final Map<String, RTCPeerConnection> _pcs = {};
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _pairDocSubs = {};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _candidateSubs = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  bool _sessionStarted = false;
  bool _broadcastMode = false;
  String? _hostUid;

  GroupCallWebRTCLogic({
    required this.callId,
    required this.selfId,
    required this.isCaller,
    this.onLocalStream,
    this.onRemoteStream,
    this.onStateChanged,
    this.onLog,
  });

  void _log(String s) {
    try {
      onLog?.call(s);
    } catch (_) {}
  }

  String _pairId(String a, String b) => (a.compareTo(b) <= 0) ? '${a}_$b' : '${b}_$a';
  bool _isOfferer(String remoteId) => selfId.compareTo(remoteId) < 0;

  Future<Map<String, dynamic>> _getIceConfig() async {
    try {
      _log('Récupération de la config TURN depuis Render...');
      final response = await http
          .get(Uri.parse('https://lualaba-konnect.onrender.com/webrtc-config'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _log('Config TURN chargée avec succès');
        return {
          'iceServers': data['iceServers'],
          'iceTransportPolicy': 'all',
          'iceCandidatePoolSize': 10,
        };
      }
    } catch (e) {
      _log('Erreur config TURN, utilisation STUN secours: $e');
    }
    return {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'iceTransportPolicy': 'all',
    };
  }

  Future<void> openUserMedia({bool video = false, bool audio = true}) async {
    try {
      if (!audio && !video) {
        _localStream = await createLocalMediaStream('local_$selfId');
        onLocalStream?.call(_localStream);
        return;
      }

      final Map<String, dynamic> constraints = {
        'audio': audio,
        'video': video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      };
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      onLocalStream?.call(_localStream);
    } catch (e) {
      _log('Erreur media: $e');
      rethrow;
    }
  }

  Future<void> start({required bool isVideo, bool audioEnabled = true}) async {
    if (_sessionStarted) return;
    _sessionStarted = true;

    _listenForEnd();
    await _prefetchCallMode();
    await _joinParticipants(isVideo: isVideo, audioEnabled: audioEnabled);
    await _listenParticipants();
  }

  Future<void> _prefetchCallMode() async {
    try {
      final snap = await _db.collection('calls').doc(callId).get();
      if (!snap.exists) return;
      final data = snap.data() ?? <String, dynamic>{};
      final mode = (data['mode'] ?? '').toString().trim().toLowerCase();
      _broadcastMode = (mode == 'broadcast');
      final hu = (data['hostUid'] ?? data['hostId'] ?? data['caller'] ?? '').toString().trim();
      if (hu.isNotEmpty) _hostUid = hu;
    } catch (_) {}
  }

  void _listenForEnd() {
    _callDocSub?.cancel();
    _callDocSub = _db.collection('calls').doc(callId).snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data() ?? <String, dynamic>{};
      final status = (data['status'] ?? '').toString();
      final mode = (data['mode'] ?? '').toString().trim().toLowerCase();
      _broadcastMode = (mode == 'broadcast');
      final hu = (data['hostUid'] ?? data['hostId'] ?? data['caller'] ?? '').toString().trim();
      if (hu.isNotEmpty) _hostUid = hu;
      if (status == 'ended') {
        _log('Call ended via Firestore');
        hangup(endForAll: false);
      }
    });
  }

  Future<void> _joinParticipants({required bool isVideo, required bool audioEnabled}) async {
    try {
      final callRef = _db.collection('calls').doc(callId);
      final snap = await callRef.get();
      if (!snap.exists) {
        await callRef.set({
          'isGroup': true,
          'status': 'ringing',
        }, SetOptions(merge: true));
      } else {
        await callRef.set({
          'isGroup': true,
        }, SetOptions(merge: true));
      }
    } catch (_) {}

    try {
      await _db.collection('calls').doc(callId).collection('participants').doc(selfId).set({
        'uid': selfId,
        'joinedAt': FieldValue.serverTimestamp(),
        'leftAt': null,
        'video': isVideo,
        'audio': audioEnabled,
        'role': isCaller ? 'host' : 'viewer',
      }, SetOptions(merge: true));
    } catch (e) {
      _log('Join participant error: $e');
    }
  }

  bool _shouldConnectTo(String remoteId, Map<String, dynamic> remoteData) {
    if (!_broadcastMode) return true;
    if (isCaller) return true; // host connects to everyone
    final role = (remoteData['role'] ?? '').toString().trim().toLowerCase();
    if (role == 'host') return true;
    if (_hostUid != null && _hostUid!.isNotEmpty && remoteId == _hostUid) return true;
    return false;
  }

  Future<void> _listenParticipants() async {
    _participantsSub?.cancel();
    _participantsSub = _db.collection('calls').doc(callId).collection('participants').snapshots().listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final d = change.doc.data();
          if (d == null) continue;
          final uid = (d['uid'] ?? change.doc.id).toString();
          if (uid.isEmpty || uid == selfId) continue;
          final leftAt = d['leftAt'];
          if (leftAt != null) {
            await _closePeer(uid);
            continue;
          }
          final remote = Map<String, dynamic>.from(d);
          if (_shouldConnectTo(uid, remote)) {
            await _ensurePeer(uid);
          } else {
            await _closePeer(uid);
          }
        } else if (change.type == DocumentChangeType.removed) {
          final uid = change.doc.id;
          if (uid.isNotEmpty) await _closePeer(uid);
        }
      }
    });
  }

  Future<void> _ensurePeer(String remoteId) async {
    final id = _pairId(selfId, remoteId);
    if (_pcs.containsKey(id)) return;
    if (_localStream == null) {
      _log('Local stream not ready yet, cannot create peer connection.');
      return;
    }

    final config = await _getIceConfig();
    final pc = await createPeerConnection(config);

    for (final t in _localStream!.getTracks()) {
      await pc.addTrack(t, _localStream!);
    }

    pc.onIceCandidate = (RTCIceCandidate? c) async {
      if (c == null) return;
      try {
        await _db
            .collection('calls')
            .doc(callId)
            .collection('pairs')
            .doc(id)
            .collection('candidates_$selfId')
            .add({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        _log('Erreur envoi candidat: $e');
      }
    };

    pc.onTrack = (RTCTrackEvent event) async {
      try {
        if (event.streams.isNotEmpty) {
          onRemoteStream?.call(remoteId, event.streams[0]);
          return;
        }
        final ms = await createLocalMediaStream('remote_${remoteId}_${DateTime.now().millisecondsSinceEpoch}');
        await ms.addTrack(event.track);
        onRemoteStream?.call(remoteId, ms);
      } catch (e) {
        _log('onTrack error: $e');
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      _log('pc[$remoteId] connectionState=${state.name}');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onStateChanged?.call('connected');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        onStateChanged?.call('failed');
      }
    };

    _pcs[id] = pc;

    await _subscribeCandidates(remoteId);
    await _subscribePairDoc(remoteId);
  }

  Future<void> _subscribeCandidates(String remoteId) async {
    final id = _pairId(selfId, remoteId);
    final key = '$id|cand';
    if (_candidateSubs.containsKey(key)) return;

    _candidateSubs[key]?.cancel();
    _candidateSubs[key] = _db
        .collection('calls')
        .doc(callId)
        .collection('pairs')
        .doc(id)
        .collection('candidates_$remoteId')
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final d = change.doc.data();
        if (d == null) continue;
        final cand = d['candidate'];
        final sdpMid = d['sdpMid'];
        final sdpMLineIndexRaw = d['sdpMLineIndex'];
        final int? sdpMLineIndex = (sdpMLineIndexRaw is num) ? sdpMLineIndexRaw.toInt() : null;
        if (cand is! String) continue;
        final ice = RTCIceCandidate(cand, sdpMid, sdpMLineIndex);

        final pc = _pcs[id];
        if (pc == null) continue;
        try {
          final hasRemote = await pc.getRemoteDescription() != null;
          if (hasRemote) {
            await pc.addCandidate(ice);
          } else {
            _pendingCandidates.putIfAbsent(id, () => []).add(ice);
          }
        } catch (e) {
          _log('addCandidate error: $e');
        }
      }
    });
  }

  Future<void> _flushPendingCandidates(String remoteId) async {
    final id = _pairId(selfId, remoteId);
    final pc = _pcs[id];
    if (pc == null) return;
    final q = _pendingCandidates[id];
    if (q == null || q.isEmpty) return;
    for (final c in List<RTCIceCandidate>.from(q)) {
      try {
        await pc.addCandidate(c);
      } catch (e) {
        _log('pending candidate error: $e');
      }
    }
    _pendingCandidates.remove(id);
  }

  Future<void> _subscribePairDoc(String remoteId) async {
    final id = _pairId(selfId, remoteId);
    if (_pairDocSubs.containsKey(id)) return;

    final docRef = _db.collection('calls').doc(callId).collection('pairs').doc(id);
    _pairDocSubs[id] = docRef.snapshots().listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data() ?? <String, dynamic>{};
      final pc = _pcs[id];
      if (pc == null) return;

      final offer = data['offer'];
      final answer = data['answer'];

      try {
        if (_isOfferer(remoteId)) {
          // Create offer if not present yet.
          if (offer == null && (await pc.getLocalDescription()) == null) {
            final created = await pc.createOffer();
            await pc.setLocalDescription(created);
            await docRef.set({
              'a': selfId.compareTo(remoteId) <= 0 ? selfId : remoteId,
              'b': selfId.compareTo(remoteId) <= 0 ? remoteId : selfId,
              'offerer': selfId,
              'offer': {'sdp': created.sdp, 'type': created.type},
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
          if (answer != null && (await pc.getRemoteDescription()) == null) {
            await pc.setRemoteDescription(RTCSessionDescription(answer['sdp'], answer['type']));
            await _flushPendingCandidates(remoteId);
          }
        } else {
          // Answerer.
          if (offer != null && (await pc.getRemoteDescription()) == null) {
            await pc.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
            await _flushPendingCandidates(remoteId);
            final created = await pc.createAnswer();
            await pc.setLocalDescription(created);
            await docRef.set({
              'answerer': selfId,
              'answer': {'sdp': created.sdp, 'type': created.type},
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      } catch (e) {
        _log('pair doc handling error[$remoteId]: $e');
      }
    });
  }

  Future<void> _closePeer(String remoteId) async {
    final id = _pairId(selfId, remoteId);
    try {
      await _pcs[id]?.close();
    } catch (_) {}
    _pcs.remove(id);

    try {
      await _pairDocSubs[id]?.cancel();
    } catch (_) {}
    _pairDocSubs.remove(id);

    final candKey = '$id|cand';
    try {
      await _candidateSubs[candKey]?.cancel();
    } catch (_) {}
    _candidateSubs.remove(candKey);

    _pendingCandidates.remove(id);
    try {
      onRemoteStream?.call(remoteId, null);
    } catch (_) {}
  }

  Future<void> hangup({required bool endForAll}) async {
    try {
      if (!_sessionStarted) return;
      _sessionStarted = false;

      try {
        await _db.collection('calls').doc(callId).collection('participants').doc(selfId).set({
          'leftAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}

      if (endForAll && isCaller) {
        try {
          await _db.collection('calls').doc(callId).update({'status': 'ended'});
        } catch (_) {}
      }

      _localStream?.getTracks().forEach((t) => t.stop());
      for (final remoteId in _pcs.keys.toList()) {
        // remoteId here is pair id; close in loop below.
        try {
          await _pcs[remoteId]?.close();
        } catch (_) {}
      }
    } catch (e) {
      _log('hangup error: $e');
    } finally {
      _localStream = null;
      try {
        await _callDocSub?.cancel();
      } catch (_) {}
      _callDocSub = null;

      try {
        await _participantsSub?.cancel();
      } catch (_) {}
      _participantsSub = null;

      for (final s in _pairDocSubs.values) {
        try {
          await s.cancel();
        } catch (_) {}
      }
      _pairDocSubs.clear();

      for (final s in _candidateSubs.values) {
        try {
          await s.cancel();
        } catch (_) {}
      }
      _candidateSubs.clear();

      for (final pc in _pcs.values) {
        try {
          await pc.close();
        } catch (_) {}
      }
      _pcs.clear();
      _pendingCandidates.clear();
      onStateChanged?.call('ended');
    }
  }

  Future<void> dispose() async {
    await hangup(endForAll: false);
  }
}

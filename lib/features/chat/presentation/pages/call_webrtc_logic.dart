// call_webrtc_logic.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallWebRTCLogic {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String callId;
  final String otherId;
  final bool isCaller;

  // Callbacks
  void Function(MediaStream? local)? onLocalStream;
  void Function(MediaStream? remote)? onRemoteStream;
  void Function(String state)? onStateChanged;
  void Function(String msg)? onLog;

  // Internal
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _otherCandidatesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _myCandidatesSub;
  bool _sessionStarted = false;

  CallWebRTCLogic({
    required this.callId,
    required this.otherId,
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

  Future<void> openUserMedia({bool video = false}) async {
    final Map<String, dynamic> constraints = {'audio': true, 'video': video};
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      _log(
          'openUserMedia: local stream acquired (audio:${_localStream?.getAudioTracks().length}, video:${_localStream?.getVideoTracks().length})');
      onLocalStream?.call(_localStream);
    } catch (e) {
      _log('openUserMedia error: $e');
      rethrow;
    }
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final config = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    final pc = await createPeerConnection(config);

    // add local tracks if present
    if (_localStream != null) {
      for (var t in _localStream!.getTracks()) {
        try {
          await pc.addTrack(t, _localStream!);
          _log('addTrack: id=${t.id} kind=${t.kind}');
        } catch (e) {
          _log('addTrack error: $e');
        }
      }
    }

    pc.onIceCandidate = (RTCIceCandidate? c) async {
      if (c == null) return;
      final coll = isCaller ? 'callerCandidates' : 'calleeCandidates';
      try {
        await _db.collection('calls').doc(callId).collection(coll).add({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
          'createdAt': FieldValue.serverTimestamp(),
        });
        _log('onIceCandidate -> pushed to $coll');
      } catch (e) {
        _log('onIceCandidate push error: $e');
      }
    };

    pc.onTrack = (RTCTrackEvent event) {
      try {
        if (event.streams.isNotEmpty) {
          final s = event.streams[0];
          _log(
              'onTrack: remote stream id=${s.id} audio=${s.getAudioTracks().length} video=${s.getVideoTracks().length}');
          onRemoteStream?.call(s);
        } else if (event.track != null) {
          createLocalMediaStream('remote-${event.track!.id}').then((ms) {
            try {
              ms.addTrack(event.track!);
            } catch (_) {}
            _log('onTrack: wrapped single track into stream id=${ms.id}');
            onRemoteStream?.call(ms);
          }).catchError((e) => _log('onTrack wrap error: $e'));
        } else {
          _log('onTrack: no streams and no track');
        }
      } catch (e) {
        _log('onTrack handler error: $e');
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      _log('pc connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onStateChanged?.call('connected');
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        onStateChanged?.call('failed');
      }
    };

    return pc;
  }

  Future<void> _subscribeToRemoteCandidates(
      {required bool listeningForCallee}) async {
    final coll = listeningForCallee ? 'calleeCandidates' : 'callerCandidates';
    _otherCandidatesSub?.cancel();
    _otherCandidatesSub = _db
        .collection('calls')
        .doc(callId)
        .collection(coll)
        .snapshots()
        .listen((snap) async {
      for (var change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data();
          if (d == null) continue;
          try {
            final cand = d['candidate'];
            final sdpMid = d['sdpMid'];
            final sdpMLineIndexRaw = d['sdpMLineIndex'];
            int? sdpMLineIndex;
            if (sdpMLineIndexRaw is int) sdpMLineIndex = sdpMLineIndexRaw;
            else if (sdpMLineIndexRaw is num)
              sdpMLineIndex = sdpMLineIndexRaw.toInt();
            if (cand != null && cand is String) {
              await _pc?.addCandidate(
                  RTCIceCandidate(cand, sdpMid, sdpMLineIndex));
              _log('Added remote candidate from $coll');
            }
          } catch (e) {
            _log('addCandidate error: $e');
          }
        }
      }
    }, onError: (e) => _log('remoteCandidatesSub error: $e'));
  }

  Future<void> _safeCallDocUpdate(Map<String, dynamic> data) async {
    try {
      final ref = _db.collection('calls').doc(callId);
      final snap = await ref.get();
      if (!snap.exists) {
        _log('_safeCallDocUpdate: doc not exists, skip -> $data');
        return;
      }
      await ref.update(data);
    } catch (e) {
      _log('_safeCallDocUpdate error: $e data=$data');
    }
  }

  Future<void> startAsCaller() async {
    if (_sessionStarted) return;
    _sessionStarted = true;
    try {
      _pc = await _createPeerConnection();
      await _subscribeToRemoteCandidates(listeningForCallee: true);

      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      _log('startAsCaller: created offer sdpLen=${offer.sdp?.length ?? 0}');

      final callRef = _db.collection('calls').doc(callId); // correct
      final snap = await callRef.get();
      if (snap.exists) {
        await callRef.update({'offer': {'sdp': offer.sdp, 'type': offer.type}});
        _log('startAsCaller: offer saved to Firestore');
      }

      callRef.snapshots().listen((snap) async {
        if (!snap.exists) return;
        final data = snap.data();
        final ansRaw = data?['answer'];
        if (ansRaw == null) return;
        final ans = ansRaw is Map ? Map<String, dynamic>.from(ansRaw) : null;
        if (ans == null) return;
        final sdp = ans['sdp'];
        final type = ans['type'];
        if (sdp is String && type is String) {
          await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
          _log('startAsCaller: remote answer set');
        }
      }, onError: (e) => _log('startAsCaller callRef snapshot error: $e'));
    } catch (e) {
      _log('startAsCaller error: $e');
      rethrow;
    }
  }

  Future<void> startAsCallee() async {
    if (_sessionStarted) return;
    _sessionStarted = true;
    try {
      _pc = await _createPeerConnection();
      await _subscribeToRemoteCandidates(listeningForCallee: false);

      final callRef = _db.collection('calls').doc(callId);
      final snap = await callRef.get();
      if (!snap.exists) return;

      final data = snap.data();
      final offer = data?['offer'] as Map<String, dynamic>?;
      if (offer == null || offer['sdp'] == null || offer['type'] == null) return;

      final rtcOffer = RTCSessionDescription(offer['sdp'], offer['type']);
      await _pc!.setRemoteDescription(rtcOffer);
      _log('startAsCallee: remote offer set');

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await _safeCallDocUpdate({'answer': {'sdp': answer.sdp, 'type': answer.type}});
      _log('startAsCallee: answer saved');
    } catch (e) {
      _log('startAsCallee error: $e');
      rethrow;
    }
  }

  Future<void> acceptCall() async {
    try {
      final callRef = _db.collection('calls').doc(callId);
      final snap = await callRef.get();
      if (!snap.exists) return;
      await callRef.update({'status': 'accepted', 'acceptedAt': FieldValue.serverTimestamp()});
      onStateChanged?.call('accepted');
      _log('acceptCall: status=accepted written');
    } catch (e) {
      _log('acceptCall error: $e');
    }
  }

  Future<void> hangup({bool setFireStoreEnded = true}) async {
    try {
      await _pc?.close();
    } catch (_) {}
    try {
      _localStream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}

    try {
      final callRef = _db.collection('calls').doc(callId);
      final callerColl = await callRef.collection('callerCandidates').get();
      for (var d in callerColl.docs) {
        await d.reference.delete();
      }
      final calleeColl = await callRef.collection('calleeCandidates').get();
      for (var d in calleeColl.docs) {
        await d.reference.delete();
      }
      if (setFireStoreEnded) {
        await _safeCallDocUpdate({'status': 'ended', 'endedAt': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      _log('hangup cleanup error: $e');
    }

    _pc = null;
    _localStream = null;
    onLocalStream?.call(null);
    onRemoteStream?.call(null);
    onStateChanged?.call('ended');
    _log('hangup: finished');
  }

  Future<void> dispose() async {
    try {
      await hangup(setFireStoreEnded: false);
    } catch (_) {}
    await _otherCandidatesSub?.cancel();
    await _myCandidatesSub?.cancel();
    _otherCandidatesSub = null;
    _myCandidatesSub = null;
  }

  // Getter pour exposer local stream si besoin
  MediaStream? get localStream => _localStream;
}

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
  // ignore: unused_field
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _myCandidatesSub;
  bool _sessionStarted = false;

  // --- NOUVEAU : File d'attente pour les candidats arrivant trop tôt ---
  final List<RTCIceCandidate> _remoteCandidatesQueue = [];

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
      _log('openUserMedia: local stream acquired');
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
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]
    };

    final pc = await createPeerConnection(config);

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
      if (event.streams.isNotEmpty) {
        _log('onTrack: remote stream id=${event.streams[0].id}');
        onRemoteStream?.call(event.streams[0]);
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      _log('pc connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onStateChanged?.call('connected');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        onStateChanged?.call('failed');
      }
    };

    return pc;
  }

  // --- MISE À JOUR : Gestion intelligente des candidats ---
  Future<void> _subscribeToRemoteCandidates({required bool listeningForCallee}) async {
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

          final cand = d['candidate'];
          final sdpMid = d['sdpMid'];
          final sdpMLineIndexRaw = d['sdpMLineIndex'];
          int? sdpMLineIndex = (sdpMLineIndexRaw is num) ? sdpMLineIndexRaw.toInt() : null;

          if (cand != null && cand is String) {
            RTCIceCandidate iceCandidate = RTCIceCandidate(cand, sdpMid, sdpMLineIndex);
            
            // Vérification : peut-on ajouter le candidat maintenant ?
            if (_pc != null && await _pc!.getRemoteDescription() != null) {
              await _pc!.addCandidate(iceCandidate);
              _log('Candidate added immediately');
            } else {
              _remoteCandidatesQueue.add(iceCandidate);
              _log('Candidate queued (RemoteDescription null)');
            }
          }
        }
      }
    });
  }

  // Fonction pour injecter les candidats en attente
  Future<void> _processPendingCandidates() async {
    if (_remoteCandidatesQueue.isEmpty) return;
    _log('Processing ${_remoteCandidatesQueue.length} queued candidates');
    for (var cand in _remoteCandidatesQueue) {
      try {
        await _pc?.addCandidate(cand);
      } catch (e) {
        _log('Error adding queued candidate: $e');
      }
    }
    _remoteCandidatesQueue.clear();
  }

  Future<void> startAsCaller() async {
    if (_sessionStarted) return;
    _sessionStarted = true;
    try {
      _pc = await _createPeerConnection();
      await _subscribeToRemoteCandidates(listeningForCallee: true);

      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);

      await _db.collection('calls').doc(callId).update({
        'offer': {'sdp': offer.sdp, 'type': offer.type}
      });

      _db.collection('calls').doc(callId).snapshots().listen((snap) async {
        final data = snap.data();
        final ans = data?['answer'];
        if (ans != null && _pc != null && await _pc!.getRemoteDescription() == null) {
          await _pc!.setRemoteDescription(RTCSessionDescription(ans['sdp'], ans['type']));
          _log('startAsCaller: remote answer set');
          await _processPendingCandidates(); // On débloque les candidats
        }
      });
    } catch (e) {
      _log('startAsCaller error: $e');
    }
  }

  Future<void> startAsCallee() async {
    if (_sessionStarted) return;
    _sessionStarted = true;
    try {
      _pc = await _createPeerConnection();
      await _subscribeToRemoteCandidates(listeningForCallee: false);

      final snap = await _db.collection('calls').doc(callId).get();
      final offer = snap.data()?['offer'];

      if (offer != null) {
        await _pc!.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
        _log('startAsCallee: remote offer set');
        await _processPendingCandidates(); // On débloque les candidats

        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        await _db.collection('calls').doc(callId).update({
          'answer': {'sdp': answer.sdp, 'type': answer.type}
        });
      }
    } catch (e) {
      _log('startAsCallee error: $e');
    }
  }

  Future<void> hangup({bool setFireStoreEnded = true}) async {
    try {
      await _pc?.close();
      _localStream?.getTracks().forEach((t) => t.stop());
      if (setFireStoreEnded) {
        await _db.collection('calls').doc(callId).update({'status': 'ended'});
      }
    } catch (e) {
      _log('hangup error: $e');
    }

    _pc = null;
    _localStream = null;
    _remoteCandidatesQueue.clear();
    onStateChanged?.call('ended');
    _log('hangup: finished');
  }

  Future<void> dispose() async {
    await hangup(setFireStoreEnded: false);
    await _otherCandidatesSub?.cancel();
  }
}
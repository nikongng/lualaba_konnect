// call_webrtc_logic.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallWebRTCLogic {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String callId;
  final String otherId;
  final bool isCaller;

  // Callbacks pour l'UI
  void Function(MediaStream? local)? onLocalStream;
  void Function(MediaStream? remote)? onRemoteStream;
  void Function(String state)? onStateChanged;
  void Function(String msg)? onLog;

  // Objets WebRTC internes
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _otherCandidatesSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callDocSub; 
  bool _sessionStarted = false;

  // File d'attente pour les candidats ICE
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

  // 1. Récupération de la configuration ICE (STUN + TURN Metered)
  Future<Map<String, dynamic>> _getIceConfig() async {
    try {
      _log('Récupération de la config TURN depuis Render...');
      // REMPLACE CETTE URL PAR TON URL RENDER
      final response = await http.get(
        Uri.parse('https://lualaba-konnect.onrender.com/webrtc-config')
      ).timeout(const Duration(seconds: 5));

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

  // 2. Écouteur pour fermer l'appel si l'autre raccroche
  void _listenForHangup() {
    _callDocSub?.cancel();
    _callDocSub = _db.collection('calls').doc(callId).snapshots().listen((snap) {
      if (snap.exists) {
        final data = snap.data();
        final status = data?['status'];
        if (status == 'ended' || status == 'rejected') {
          _log('Déconnexion détectée via Firestore');
          hangup(setFireStoreEnded: false);
        }
      }
    });
  }

  // 3. Accès caméra/micro
  Future<void> openUserMedia({bool video = false}) async {
    final Map<String, dynamic> constraints = {
      'audio': true, 
      'video': video ? {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
      } : false
    };
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      onLocalStream?.call(_localStream);
    } catch (e) {
      _log('Erreur media: $e');
      rethrow;
    }
  }

  // 4. Création de la connexion WebRTC
  Future<RTCPeerConnection> _createPeerConnection() async {
    final config = await _getIceConfig();
    final pc = await createPeerConnection(config);

    if (_localStream != null) {
      for (var t in _localStream!.getTracks()) {
        await pc.addTrack(t, _localStream!);
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
      } catch (e) {
        _log('Erreur envoi candidat: $e');
      }
    };

    pc.onTrack = (RTCTrackEvent event) async {
      try {
        if (event.streams.isNotEmpty) {
          _log('onTrack: received stream with id=${event.streams[0].id}');
          onRemoteStream?.call(event.streams[0]);
          return;
        }

        // Fallback: some platforms deliver track without streams — wrap track in a MediaStream
        if (event.track != null) {
          _log('onTrack: received track id=${event.track?.id}, creating MediaStream fallback');
          try {
            final ms = await createLocalMediaStream('remote_${event.track?.id ?? DateTime.now().millisecondsSinceEpoch}');
            await ms.addTrack(event.track!);
            onRemoteStream?.call(ms);
            return;
          } catch (e) {
            _log('onTrack fallback failed: $e');
          }
        }
      } catch (e) {
        _log('onTrack handler error: $e');
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      _log('Etat de la connexion: ${state.name}');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onStateChanged?.call('connected');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        onStateChanged?.call('failed');
      }
    };

    return pc;
  }

  // 5. Gestion des candidats ICE distants (Firestore -> App)
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
            
            if (_pc != null && await _pc!.getRemoteDescription() != null) {
              await _pc!.addCandidate(iceCandidate);
            } else {
              _remoteCandidatesQueue.add(iceCandidate);
            }
          }
        }
      }
    });
  }

  // 6. Traitement de la file d'attente des candidats
  Future<void> _processPendingCandidates() async {
    if (_remoteCandidatesQueue.isEmpty) return;
    _log('Traitement de ${_remoteCandidatesQueue.length} candidats en attente');
    for (var cand in _remoteCandidatesQueue) {
      try {
        await _pc?.addCandidate(cand);
      } catch (e) {
        _log('Erreur candidat en attente: $e');
      }
    }
    _remoteCandidatesQueue.clear();
  }

  // 7. Démarrage de l'appelant
  Future<void> startAsCaller() async {
    if (_sessionStarted) return;
    _sessionStarted = true;
    _listenForHangup();

    try {
      _pc = await _createPeerConnection();
      await _subscribeToRemoteCandidates(listeningForCallee: true);

      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);

      await _db.collection('calls').doc(callId).set({
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'status': 'ringing',
      }, SetOptions(merge: true));

      _db.collection('calls').doc(callId).snapshots().listen((snap) async {
        if (!snap.exists) return;
        final data = snap.data();
        final ans = data?['answer'];
        if (ans != null && _pc != null && await _pc!.getRemoteDescription() == null) {
          await _pc!.setRemoteDescription(RTCSessionDescription(ans['sdp'], ans['type']));
          await _processPendingCandidates();
        }
      });
    } catch (e) {
      _log('Erreur startAsCaller: $e');
    }
  }

  // 8. Démarrage du receveur
  Future<void> startAsCallee() async {
    if (_sessionStarted) return;
    _sessionStarted = true;
    _listenForHangup();

    try {
      _pc = await _createPeerConnection();
      await _subscribeToRemoteCandidates(listeningForCallee: false);

      final snap = await _db.collection('calls').doc(callId).get();
      final offer = snap.data()?['offer'];

      if (offer != null) {
        await _pc!.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
        await _processPendingCandidates();

        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        await _db.collection('calls').doc(callId).update({
          'answer': {'sdp': answer.sdp, 'type': answer.type},
          'status': 'connected',
        });
      }
    } catch (e) {
      _log('Erreur startAsCallee: $e');
    }
  }

  // 9. Raccrocher
  Future<void> hangup({bool setFireStoreEnded = true}) async {
    try {
      if (setFireStoreEnded) {
        await _db.collection('calls').doc(callId).update({'status': 'ended'});
      }
      _localStream?.getTracks().forEach((t) => t.stop());
      await _pc?.close();
    } catch (e) {
      _log('Erreur hangup: $e');
    } finally {
      _pc = null;
      _localStream = null;
      _remoteCandidatesQueue.clear();
      onStateChanged?.call('ended');
    }
  }

  Future<void> dispose() async {
    await _callDocSub?.cancel();
    await _otherCandidatesSub?.cancel();
    await hangup(setFireStoreEnded: false);
  }
}
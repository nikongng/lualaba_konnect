import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lualaba_konnect/core/app_navigator.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/call_webrtc_page.dart';

/// Listens to Firestore `calls` and shows an incoming call UI globally.
///
/// This complements push notifications:
/// - When the app is open (any page), incoming calls still pop the accept/decline sheet.
/// - When the app is closed, push notifications handle it.
class CallInviteListener {
  static StreamSubscription<QuerySnapshot>? _sub;
  static bool _showingIncoming = false;
  static String? _uid;

  static void start(String uid) {
    if (uid.trim().isEmpty) return;
    if (_uid == uid && _sub != null) return;
    stop();
    _uid = uid;

    _sub = FirebaseFirestore.instance
        .collection('calls')
        .where('callee', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        _handleIncoming(change.doc);
      }
    });
  }

  static void stop() {
    _uid = null;
    _showingIncoming = false;
    _sub?.cancel();
    _sub = null;
  }

  static Future<void> _handleIncoming(DocumentSnapshot doc) async {
    if (_showingIncoming) return;

    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return; // no UI context available

    final data = (doc.data() is Map) ? Map<String, dynamic>.from(doc.data() as Map) : <String, dynamic>{};
    final callerId = (data['caller'] ?? '').toString();
    final callerName = (data['callerName'] ?? 'Appel entrant').toString();
    final bool isVideo = (data['type'] ?? '').toString() == 'video';

    _showingIncoming = true;
    NotificationService.playRingtone();

    // We use the root navigator to avoid "no Scaffold" issues when called from anywhere.
    // ignore: use_build_context_synchronously
    showModalBottomSheet(
      context: ctx,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (mCtx) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFF17212B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                callerName,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(isVideo ? 'Appel vidéo entrant' : 'Appel entrant', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await FirebaseFirestore.instance.collection('calls').doc(doc.id).update({'status': 'rejected'});
                      } catch (_) {}
                      NotificationService.stopRingtone();
                      Navigator.pop(mCtx);
                      _showingIncoming = false;
                    },
                    icon: const Icon(Icons.call_end),
                    label: const Text('Refuser'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await FirebaseFirestore.instance.collection('calls').doc(doc.id).update({'status': 'accepted'});
                      } catch (_) {}
                      NotificationService.stopRingtone();
                      Navigator.pop(mCtx);
                      appNavigatorKey.currentState?.push(
                        MaterialPageRoute(
                          builder: (_) => CallWebRTCPage(
                            callId: doc.id,
                            otherId: callerId,
                            isCaller: false,
                            name: callerName,
                            avatarLetter: callerName.isNotEmpty ? callerName[0].toUpperCase() : '?',
                            isVideo: isVideo,
                          ),
                        ),
                      );
                      _showingIncoming = false;
                    },
                    icon: const Icon(Icons.call),
                    label: const Text('Accepter'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      // Safety: if user dismisses via system back (rare, but possible), stop ringtone.
      try {
        NotificationService.stopRingtone();
      } catch (_) {}
      _showingIncoming = false;
    });
  }
}


import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lualaba_konnect/core/app_navigator.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/call_webrtc_page.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/group_call_webrtc_page.dart';

/// Listens to Firestore `calls` and shows an incoming call UI globally.
///
/// This complements push notifications:
/// - When the app is open (any page), incoming calls still pop the accept/decline sheet.
/// - When the app is closed, push notifications handle it.
class CallInviteListener {
  static StreamSubscription<QuerySnapshot>? _sub;
  static StreamSubscription<QuerySnapshot>? _groupSub;
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

    // Group calls: we listen on participants array (best-effort, may require Firestore index).
    try {
      _groupSub = FirebaseFirestore.instance
          .collection('calls')
          .where('participants', arrayContains: uid)
          .snapshots()
          .listen((snap) {
        for (final change in snap.docChanges) {
          if (change.type != DocumentChangeType.added && change.type != DocumentChangeType.modified) continue;
          final data = (change.doc.data() is Map)
              ? Map<String, dynamic>.from(change.doc.data() as Map)
              : <String, dynamic>{};
          final status = (data['status'] ?? '').toString();
          final isGroup = data['isGroup'] == true;
          if (!isGroup) continue;
          if (status != 'ringing') continue;
          // If the call has an explicit invited list, only show for invited users.
          if (data['invited'] is List) {
            final invited = (data['invited'] as List).map((e) => e.toString()).toSet();
            if (_uid != null && !invited.contains(_uid)) continue;
          }
          // If user already handled the invite, don't show again.
          if (_uid != null && _uid!.isNotEmpty) {
            if (data['acceptedBy'] is List) {
              final a = (data['acceptedBy'] as List).map((e) => e.toString()).toSet();
              if (a.contains(_uid)) continue;
            }
            if (data['declinedBy'] is List) {
              final d = (data['declinedBy'] as List).map((e) => e.toString()).toSet();
              if (d.contains(_uid)) continue;
            }
          }
          _handleIncoming(change.doc);
        }
      });
    } catch (_) {}
  }

  static void stop() {
    _uid = null;
    _showingIncoming = false;
    _sub?.cancel();
    _sub = null;
    _groupSub?.cancel();
    _groupSub = null;
  }

  static Future<void> showIncomingCallById(String callId, {String? uid}) async {
    if (callId.trim().isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('calls').doc(callId.trim()).get();
      if (!snap.exists) return;
      await _handleIncoming(snap, selfUidOverride: uid);
    } catch (_) {}
  }

  static Future<void> _handleIncoming(DocumentSnapshot doc, {String? selfUidOverride}) async {
    if (_showingIncoming) return;

    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return; // no UI context available

    final data = (doc.data() is Map) ? Map<String, dynamic>.from(doc.data() as Map) : <String, dynamic>{};
    final callerId = (data['caller'] ?? '').toString();
    final callerName = (data['callerName'] ?? 'Appel entrant').toString();
    final bool isVideo = (data['type'] ?? '').toString() == 'video';
    final bool isGroup = data['isGroup'] == true || (data['participants'] is List);
    final selfUid = (selfUidOverride ?? _uid)?.toString();
    if (isGroup && selfUid != null && selfUid.isNotEmpty && callerId == selfUid) {
      // Don't show an incoming sheet to the caller of a group call.
      return;
    }
    final displayTitle =
        isGroup ? (data['groupName'] ?? data['chatName'] ?? 'Appel de groupe').toString() : callerName;

    _showingIncoming = true;
    NotificationService.playRingtone();

    bool closed = false;
    StreamSubscription<DocumentSnapshot>? callSub;

    void closeSheet(BuildContext mCtx) {
      if (closed) return;
      closed = true;
      try { NotificationService.stopRingtone(); } catch (_) {}
      try { Navigator.pop(mCtx); } catch (_) {}
      _showingIncoming = false;
      callSub?.cancel();
    }

    // We use the root navigator to avoid "no Scaffold" issues when called from anywhere.
    // ignore: use_build_context_synchronously
    showModalBottomSheet(
      context: ctx,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (mCtx) {
        // Close the incoming sheet if another device accepted/rejected.
        callSub ??= FirebaseFirestore.instance.collection('calls').doc(doc.id).snapshots().listen((snap) {
          if (!snap.exists) {
            closeSheet(mCtx);
            return;
          }
          final d = (snap.data() is Map) ? Map<String, dynamic>.from(snap.data() as Map) : <String, dynamic>{};
          final status = (d['status'] ?? '').toString();
          if (status.isNotEmpty && status != 'ringing') {
            closeSheet(mCtx);
            return;
          }
          if (selfUid != null && selfUid.isNotEmpty) {
            if (d['acceptedBy'] is List) {
              final a = (d['acceptedBy'] as List).map((e) => e.toString()).toSet();
              if (a.contains(selfUid)) {
                closeSheet(mCtx);
                return;
              }
            } else if (!isGroup && d['acceptedBy'] != null && d['acceptedBy'].toString().isNotEmpty) {
              final accepted = d['acceptedBy'].toString();
              if (accepted != selfUid) {
                closeSheet(mCtx);
                return;
              }
            }
            if (d['declinedBy'] is List) {
              final r = (d['declinedBy'] as List).map((e) => e.toString()).toSet();
              if (r.contains(selfUid)) {
                closeSheet(mCtx);
                return;
              }
            }
          }
        });

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
                displayTitle,
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
                        if (isGroup && selfUid != null && selfUid.isNotEmpty) {
                          await FirebaseFirestore.instance.collection('calls').doc(doc.id).set({
                            'declinedBy': FieldValue.arrayUnion([selfUid]),
                          }, SetOptions(merge: true));
                        } else {
                          await FirebaseFirestore.instance.collection('calls').doc(doc.id).update({'status': 'rejected'});
                        }
                      } catch (_) {}
                      closeSheet(mCtx);
                    },
                    icon: const Icon(Icons.call_end),
                    label: const Text('Refuser'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        if (isGroup && selfUid != null && selfUid.isNotEmpty) {
                          await FirebaseFirestore.instance.collection('calls').doc(doc.id).set({
                            'acceptedBy': FieldValue.arrayUnion([selfUid]),
                          }, SetOptions(merge: true));
                        } else {
                          await FirebaseFirestore.instance.runTransaction((tx) async {
                            final ref = FirebaseFirestore.instance.collection('calls').doc(doc.id);
                            final snap = await tx.get(ref);
                            if (!snap.exists) return;
                            final d = (snap.data() is Map) ? Map<String, dynamic>.from(snap.data() as Map) : <String, dynamic>{};
                            final status = (d['status'] ?? '').toString();
                            if (status.isNotEmpty && status != 'ringing') return;
                            tx.update(ref, {
                              'status': 'accepted',
                              'acceptedBy': selfUid ?? '',
                              'acceptedAt': FieldValue.serverTimestamp(),
                            });
                          });
                        }
                      } catch (_) {}
                      closeSheet(mCtx);
                      if (isGroup) {
                        AppNavigator.pushWhenReady(
                          MaterialPageRoute(
                            builder: (_) => GroupCallWebRTCPage(
                              callId: doc.id,
                              name: displayTitle,
                              isVideo: isVideo,
                              isCaller: false,
                            ),
                          ),
                        );
                      } else {
                        AppNavigator.pushWhenReady(
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
                      }
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
      try { NotificationService.stopRingtone(); } catch (_) {}
      _showingIncoming = false;
      callSub?.cancel();
    });
  }
}

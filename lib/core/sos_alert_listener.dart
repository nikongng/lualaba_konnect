import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lualaba_konnect/core/app_navigator.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/chat_detail_page.dart';

/// Listens to Firestore SOS alerts and shows a full-screen emergency UI.
class SosAlertListener {
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  static Timer? _vibrationTimer;
  static String? _uid;
  static bool _showingAlert = false;
  static String? _activeAlertId;
  static final Set<String> _mutedAlertIds = <String>{};

  static void start(String uid) {
    if (uid.trim().isEmpty) return;
    if (_uid == uid && _sub != null) return;
    stop();
    _uid = uid;

    _sub = FirebaseFirestore.instance
        .collection('user_alerts')
        .doc(uid)
        .collection('pending')
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
    _showingAlert = false;
    _activeAlertId = null;
    _mutedAlertIds.clear();
    _stopFeedback();
    _sub?.cancel();
    _sub = null;
  }

  static Future<void> acknowledgeAlert({
    String? alertId,
    bool deletePending = true,
  }) async {
    final normalizedAlertId = alertId?.trim();
    if (normalizedAlertId != null && normalizedAlertId.isNotEmpty) {
      _mutedAlertIds.add(normalizedAlertId);
      if (deletePending) {
        await _deletePendingAlert(normalizedAlertId);
      }
    } else if (_activeAlertId != null) {
      _mutedAlertIds.add(_activeAlertId!);
      if (deletePending) {
        await _deletePendingAlert(_activeAlertId!);
      }
    }

    _stopFeedback();

    if (!_showingAlert) return;
    final navigator = appNavigatorKey.currentState;
    if (navigator == null || !navigator.canPop()) return;
    navigator.pop('external_open');
  }

  static Future<void> _handleIncoming(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final alertId = doc.id;
    if (_showingAlert || _mutedAlertIds.contains(alertId)) return;

    if (!doc.exists) return;
    final data = doc.data() ?? <String, dynamic>{};
    final chatId = (data['chatId'] ?? '').toString().trim();
    if (chatId.isEmpty) return;

    await _waitForContext();
    final rootContext = appNavigatorKey.currentContext;
    if (rootContext == null ||
        _showingAlert ||
        _mutedAlertIds.contains(alertId)) {
      return;
    }

    final fromName = (data['fromName'] ?? data['chatName'] ?? 'SOS')
        .toString()
        .trim();
    final chatName = (data['chatName'] ?? data['fromName'] ?? 'SOS')
        .toString()
        .trim();
    final hasLocation = data['location'] is Map;

    _showingAlert = true;
    _activeAlertId = alertId;
    _startFeedback();

    final result = await showGeneralDialog<String>(
      context: rootContext,
      barrierDismissible: false,
      barrierLabel: 'SOS',
      barrierColor: Colors.black.withValues(alpha: 0.78),
      useRootNavigator: true,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _SosIncomingAlertScreen(
          fromName: fromName.isEmpty ? 'Un proche' : fromName,
          hasLocation: hasLocation,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );

    _stopFeedback();
    _showingAlert = false;
    _activeAlertId = null;

    if (result == 'external_open') {
      return;
    }

    if (result == 'later') {
      _mutedAlertIds.add(alertId);
      await _showNextPendingIfAny();
      return;
    }

    if (result == 'open') {
      _mutedAlertIds.add(alertId);
      await _deletePendingAlert(alertId);
      _stopFeedback();
      await AppNavigator.pushWhenReady(
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            chatId: chatId,
            chatName: chatName.isEmpty ? fromName : chatName,
          ),
        ),
      );
      return;
    }

    await _showNextPendingIfAny();
  }

  static Future<void> _showNextPendingIfAny() async {
    if (_showingAlert || _uid == null || _uid!.trim().isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('user_alerts')
          .doc(_uid)
          .collection('pending')
          .get();
      for (final doc in snap.docs) {
        if (doc.id == _activeAlertId) continue;
        if (_mutedAlertIds.contains(doc.id)) continue;
        await _handleIncoming(doc);
        return;
      }
    } catch (_) {}
  }

  static Future<void> _deletePendingAlert(String alertId) async {
    final uid = _uid;
    if (uid == null || uid.trim().isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('user_alerts')
          .doc(uid)
          .collection('pending')
          .doc(alertId)
          .delete();
    } catch (_) {}
  }

  static Future<void> _waitForContext({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final context = appNavigatorKey.currentContext;
      if (context != null) return;
      await Future.delayed(const Duration(milliseconds: 80));
    }
  }

  static void _startFeedback() {
    try {
      NotificationService.playRingtone();
    } catch (_) {}

    try {
      HapticFeedback.heavyImpact();
      HapticFeedback.vibrate();
    } catch (_) {}

    _vibrationTimer?.cancel();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      try {
        HapticFeedback.heavyImpact();
        HapticFeedback.vibrate();
      } catch (_) {}
    });
  }

  static void _stopFeedback() {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    try {
      NotificationService.stopRingtone();
    } catch (_) {}
  }
}

class _SosIncomingAlertScreen extends StatefulWidget {
  final String fromName;
  final bool hasLocation;

  const _SosIncomingAlertScreen({
    required this.fromName,
    required this.hasLocation,
  });

  @override
  State<_SosIncomingAlertScreen> createState() =>
      _SosIncomingAlertScreenState();
}

class _SosIncomingAlertScreenState extends State<_SosIncomingAlertScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashCtrl;

  @override
  void initState() {
    super.initState();
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AnimatedBuilder(
        animation: _flashCtrl,
        builder: (context, _) {
          final background = Color.lerp(
            const Color(0xFF5A0000),
            const Color(0xFFFF1F1F),
            Curves.easeInOut.transform(_flashCtrl.value),
          )!;

          return Scaffold(
            backgroundColor: background,
            body: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: 1.1,
                      colors: [
                        Colors.white.withValues(alpha: 0.16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                  child: const SizedBox.expand(),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.22),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.sos_rounded,
                            color: Colors.white,
                            size: 72,
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'ALERTE D URGENCE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '${widget.fromName} a envoyé un SOS.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.hasLocation
                              ? 'Ouvre immédiatement le chat pour voir le message et la position partagée.'
                              : 'Ouvre immédiatement le chat pour voir le message d urgence.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                          child: Text(
                            widget.hasLocation
                                ? 'Position partagée'
                                : 'Message prioritaire',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 34),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.of(
                              context,
                              rootNavigator: true,
                            ).pop('open'),
                            icon: const Icon(Icons.mark_chat_read_rounded),
                            label: const Text('Ouvrir'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFFB00020),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.of(
                            context,
                            rootNavigator: true,
                          ).pop('later'),
                          child: const Text(
                            'Plus tard',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

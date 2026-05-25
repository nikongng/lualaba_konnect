import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lualaba_konnect/core/app_navigator.dart';
import 'package:lualaba_konnect/core/sos_alert_listener.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/chat_detail_page.dart';

class SosLaunchService {
  static const MethodChannel _channel = MethodChannel(
    'lualaba_konnect/sos_launch',
  );

  static bool _initialized = false;
  static bool _navigating = false;
  static Map<String, dynamic>? _pendingLaunch;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onPendingSosLaunch') return;
      final args = call.arguments;
      if (args is Map) {
        _pendingLaunch = Map<String, dynamic>.from(args);
        await processPendingLaunch();
      }
    });

    await _hydratePendingLaunchFromPlatform();
  }

  static Future<void> processPendingLaunch() async {
    if (_navigating) return;
    if (_pendingLaunch == null) {
      await _hydratePendingLaunchFromPlatform();
    }
    final launch = _pendingLaunch;
    if (launch == null) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    final chatId = (launch['chatId'] ?? '').toString().trim();
    if (chatId.isEmpty) return;

    final chatName = (launch['chatName'] ?? launch['fromName'] ?? 'Alerte SOS')
        .toString()
        .trim();
    final alertId = (launch['alertId'] ?? '').toString().trim();

    _pendingLaunch = null;
    _navigating = true;
    try {
      await SosAlertListener.acknowledgeAlert(
        alertId: alertId.isEmpty ? null : alertId,
      );
      await AppNavigator.pushWhenReady(
        MaterialPageRoute(
          builder: (_) => ChatDetailPage(
            chatId: chatId,
            chatName: chatName.isEmpty ? 'Alerte SOS' : chatName,
          ),
        ),
      );
    } finally {
      _navigating = false;
    }
  }

  static Future<void> _hydratePendingLaunchFromPlatform() async {
    try {
      final initial = await _channel.invokeMethod<dynamic>(
        'consumePendingSosLaunch',
      );
      if (initial is Map) {
        _pendingLaunch = Map<String, dynamic>.from(initial);
      }
    } catch (_) {}
  }
}

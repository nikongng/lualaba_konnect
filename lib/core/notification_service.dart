import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      onDidReceiveLocalNotification: (id, title, body, payload) {},
    );

    final InitializationSettings initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _fln.initialize(initSettings, onDidReceiveNotificationResponse: (resp) {});

    // FCM handlers
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title ?? 'Nouvelle notification';
      final body = message.notification?.body ?? '';
      showNotification(title, body);
    });

    _initialized = true;
  }

  static Future<void> showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'lualaba_channel', 'Lualaba Notifications',
      importance: Importance.max, priority: Priority.high, playSound: true);
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
    const NotificationDetails platform = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _fln.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, platform);
  }

  static void playRingtone() {
    if (kIsWeb) return;
    try {
      final player = FlutterRingtonePlayer();
      // try custom asset first
      try {
        player.play(fromAsset: 'assets/sounds/ringtone.mp3', looping: true, asAlarm: false, volume: 1.0);
        return;
      } catch (e) {
        debugPrint('playRingtone: asset play failed: $e');
      }
      // fallback: default ringtone method
      try {
        player.playRingtone(looping: true);
        return;
      } catch (e) {
        debugPrint('playRingtone: playRingtone failed: $e');
      }
      // last resort
      try {
        player.play(looping: true);
      } catch (e) {
        debugPrint('playRingtone: final play failed: $e');
      }
    } catch (e, st) {
      debugPrint('playRingtone: unexpected error: $e');
      debugPrint('$st');
    }
  }

  static void stopRingtone() {
    if (!kIsWeb) {
      final player = FlutterRingtonePlayer();
      player.stop();
    }
  }
}

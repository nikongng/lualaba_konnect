import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:lualaba_konnect/core/app_navigator.dart';
import 'package:lualaba_konnect/firebase_options.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/call_webrtc_page.dart';

// Must be a top-level function for background handling
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    // already initialized in some contexts
  }

  final notification = message.notification;
  final data = message.data;

  final fln = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await fln.initialize(initSettings);

  if (notification != null) {
    final androidDetails = AndroidNotificationDetails('lualaba_channel', 'Lualaba Notifications', importance: Importance.max, priority: Priority.high, playSound: true);
    final platform = NotificationDetails(android: androidDetails);
    await fln.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, notification.title, notification.body, platform, payload: data.toString());
  }
}

class FcmHandlers {
  static void init() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // App in foreground
      final notif = message.notification;
      final data = message.data;
      if (notif != null) NotificationService.showNotification(notif.title ?? 'Notification', notif.body ?? '');

      if (data['type'] == 'call') {
        // Play ringtone and show incoming UI if possible
        NotificationService.playRingtone();
        final callId = data['callId'] ?? data['chatId'] ?? '';
        final callerName = data['callerName'] ?? 'Appel entrant';
        // show a simple dialog using navigatorKey
        final ctx = appNavigatorKey.currentContext;
        if (ctx != null) {
          showModalBottomSheet(
            context: ctx,
            isDismissible: false,
            enableDrag: false,
            backgroundColor: Colors.transparent,
            builder: (c) => Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF17212B), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(callerName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Appel entrant', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  ElevatedButton.icon(onPressed: () async {
                    try { await FirebaseMessaging.instance.deleteToken(); } catch (_) {}
                    NotificationService.stopRingtone();
                    Navigator.pop(c);
                  }, icon: const Icon(Icons.call_end), label: const Text('Refuser'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red)),
                  ElevatedButton.icon(onPressed: () async {
                    NotificationService.stopRingtone();
                    Navigator.pop(c);
                    appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => CallWebRTCPage(callId: callId, otherId: data['caller'] ?? '', isCaller: false, name: callerName)));
                  }, icon: const Icon(Icons.call), label: const Text('Accepter'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green)),
                ])
              ]),
            ),
          );
        }
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final data = message.data;
      if (data['type'] == 'call') {
        final callId = data['callId'] ?? data['chatId'] ?? '';
        final caller = data['caller'] ?? '';
        final callerName = data['callerName'] ?? 'Appel entrant';
        appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => CallWebRTCPage(callId: callId, otherId: caller, isCaller: false, name: callerName)));
      } else if (data['type'] == 'message') {
        // navigate to chat list or chat detail if desired
      }
    });

    // handle initialMessage when app is started from terminated state by a notification
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        final data = message.data;
        if (data['type'] == 'call') {
          final callId = data['callId'] ?? data['chatId'] ?? '';
          final caller = data['caller'] ?? '';
          final callerName = data['callerName'] ?? 'Appel entrant';
          // need to wait for navigator to be ready
          WidgetsBinding.instance.addPostFrameCallback((_) {
            appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => CallWebRTCPage(callId: callId, otherId: caller, isCaller: false, name: callerName)));
          });
        }
      }
    });
  }
}

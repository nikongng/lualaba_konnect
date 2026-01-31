import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lualaba_konnect/core/app_navigator.dart';
import 'package:lualaba_konnect/firebase_options.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/call_webrtc_page.dart';
import 'package:lualaba_konnect/features/marketplace/orders_page.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (e) {
    debugPrint("Erreur init Firebase background: $e");
  }

  final data = message.data;
  // On récupère le titre/corps soit de la notification, soit de la DATA (pour le chat)
  String? title = message.notification?.title ?? data['title'] ?? data['senderName'];
  String? body = message.notification?.body ?? data['body'] ?? data['messageText'];

  if (title != null || body != null) {
    final fln = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await fln.initialize(const InitializationSettings(android: androidInit));

    const androidDetails = AndroidNotificationDetails(
      'lualaba_channel',
      'Lualaba Notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    // Extraction du payload pour la navigation
    final payload = data['orderId'] ?? data['chatId'] ?? data['type'];

    await fln.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: payload != null ? 'nav:$payload' : null,
    );
  }
}

class FcmHandlers {
  static void init() {
    // 1. Gestion Foreground (App ouverte)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notif = message.notification;
      final data = message.data;
      
      if (notif != null) {
        final payload = data['orderId'] ?? data['order_id'] ?? data['order'];
        NotificationService.showNotification(
          notif.title ?? 'Notification', 
          notif.body ?? '', 
          payload: payload != null ? 'order:$payload' : null
        );
      }

      // Gestion des appels entrants
      if (data['type'] == 'call') {
        _handleIncomingCall(data);
      }

      // Marketplace notifications
      if (data['type'] == 'market_order' || data['type'] == 'market_order_confirm') {
        _handleNavigation(data);
      }
    });

    // 2. Sauvegarde du token FCM
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      try {
        if (user == null) return;
        final token = await FirebaseMessaging.instance.getToken();
        if (token == null) return;
        
        final cols = ['classic_users', 'pro_users', 'enterprise_users'];
        for (final col in cols) {
          try {
            final ref = FirebaseFirestore.instance.collection(col).doc(user.uid);
            final doc = await ref.get();
            if (doc.exists) {
              // Save token as a document in subcollection fcm_tokens (doc id = token)
              final tokenRef = ref.collection('fcm_tokens').doc(token);
              await tokenRef.set({
                'token': token,
                'platform': Platform.operatingSystem,
                'lastSeen': FieldValue.serverTimestamp(),
                'appVersion': 'unknown'
              }, SetOptions(merge: true));
              break;
            }
          } catch (_) {}
        }
      } catch (e) { debugPrint('Save token error: $e'); }
    });

    // 2b. Gérer le rafraîchissement du token FCM
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;
        final cols = ['classic_users', 'pro_users', 'enterprise_users'];
        for (final col in cols) {
          try {
            final ref = FirebaseFirestore.instance.collection(col).doc(user.uid);
            final doc = await ref.get();
            if (doc.exists) {
              final tokenRef = ref.collection('fcm_tokens').doc(newToken);
              await tokenRef.set({
                'token': newToken,
                'platform': Platform.operatingSystem,
                'lastSeen': FieldValue.serverTimestamp(),
                'appVersion': 'unknown'
              }, SetOptions(merge: true));
              break;
            }
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('Token refresh save error: $e');
      }
    });

    // 3. Clic sur notification (Arrière-plan)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNavigation(message.data);
    });

    // 4. Lancement via notification (App fermée)
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNavigation(message.data);
        });
      }
    });
  }

  static void _handleIncomingCall(Map<String, dynamic> data) {
    NotificationService.playRingtone();
    final callId = data['callId'] ?? data['chatId'] ?? '';
    final callerName = data['callerName'] ?? 'Appel entrant';
    
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) {
      showModalBottomSheet(
        context: ctx,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (c) => Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFF17212B), 
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(callerName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Appel entrant', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              ElevatedButton.icon(
                onPressed: () {
                  NotificationService.stopRingtone();
                  Navigator.pop(c);
                }, 
                icon: const Icon(Icons.call_end), 
                label: const Text('Refuser'), 
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red)
              ),
              ElevatedButton.icon(
                onPressed: () {
                  NotificationService.stopRingtone();
                  Navigator.pop(c);
                  appNavigatorKey.currentState?.push(
                    MaterialPageRoute(
                      builder: (_) => CallWebRTCPage(
                        callId: callId,
                        otherId: data['caller'] ?? '',
                        isCaller: false,
                        name: callerName,
                        avatarLetter: callerName.isNotEmpty ? callerName[0].toUpperCase() : '?',
                      ),
                    ),
                  );
                }, 
                icon: const Icon(Icons.call), 
                label: const Text('Accepter'), 
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green)
              ),
            ])
          ]),
        ),
      );
    }
  }

  static void _handleNavigation(Map<String, dynamic> data) {
    debugPrint('FCM navigation data: $data');
    if (data['type'] == 'call') {
      final callId = data['callId'] ?? data['chatId'] ?? '';
      final callerName = data['callerName'] ?? 'Appel entrant';
      appNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => CallWebRTCPage(
            callId: callId,
            otherId: data['caller'] ?? '',
            isCaller: false,
            name: callerName,
            avatarLetter: callerName.isNotEmpty ? callerName[0].toUpperCase() : '?',
          ),
        ),
      );
    }
    
    if (data['type'] == 'market_order' || data['type'] == 'market_order_confirm') {
      final orderId = data['orderId'] ?? data['order_id'] ?? data['order'];
      appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => OrdersPage(orderId: orderId)));
    }
  }
}
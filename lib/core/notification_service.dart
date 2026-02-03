// Firebase Messaging removed — using OneSignal as push provider
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Avoid importing `dart:io` directly (breaks web builds). Use Flutter's
// platform constants instead.

class NotificationService {
  static final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // --- CONFIGURATION DU CANAL (ID UNIQUE) ---
  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'lualaba_channel', // DOIT correspondre à l'ID dans le Manifest
    'Lualaba Notifications',
    description: 'Notifications pour le chat et le marketplace',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> init() async {
    if (_initialized) return;

    // 2. Créer officiellement le canal sur le système Android
    // C'est l'étape qui manquait pour l'affichage en arrière-plan
    await _fln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 3. Configuration de l'initialisation
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    final DarwinInitializationSettings iosInit = DarwinInitializationSettings();

    final InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _fln.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Logique de navigation au clic sur la notification
        debugPrint("Notification cliquée avec payload: ${response.payload}");
      },
    );

    // 3b. OneSignal initialization (optional)
    const String oneSignalAppId = String.fromEnvironment('ONESIGNAL_APP_ID', defaultValue: 'ac19fdcc-16e7-4775-8806-8cde03d1fadb');
    if (!kIsWeb && oneSignalAppId.isNotEmpty) {
      try {
        // Use dynamic invocation to support different versions of the plugin
        final dynamic os = OneSignal();
        try {
          await os.setAppId(oneSignalAppId);
        } catch (_) {
          try {
            await os.init(oneSignalAppId);
          } catch (_) {
            try {
              await os.initWithAppId(oneSignalAppId);
            } catch (e) {
              debugPrint('OneSignal: could not call init/setAppId: $e');
            }
          }
        }

        // retrieve player id (plugin method name should exist at runtime)
        dynamic ds;
        try {
          ds = await os.getDeviceState();
        } catch (e) {
          debugPrint('OneSignal getDeviceState failed: $e');
        }
        final playerId = ds?.userId;
        if (playerId != null) {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final cols = ['classic_users', 'pro_users', 'enterprise_users'];
            for (final col in cols) {
              try {
                final ref = FirebaseFirestore.instance.collection(col).doc(user.uid);
                final doc = await ref.get();
                if (doc.exists) {
                  await ref.collection('notification_players').doc(playerId).set({
                    'playerId': playerId,
                    'platform': _platformName(),
                    'lastSeen': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                  break;
                }
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        debugPrint('OneSignal init error: $e');
      }
    }

    // Register OneSignal handlers (multiple API names supported) to show local notifications
    try {
      final dynamic os = OneSignal();

      // Helper to process incoming notification object
      Future<void> handleIncoming(dynamic n) async {
        try {
          final String title = (n?.title ?? n?.heading ?? n?.notification?.title ?? '')?.toString() ?? 'Lualaba Konnect';
          final String body = (n?.body ?? n?.content ?? n?.notification?.body ?? '')?.toString() ?? '';
          dynamic data = n?.additionalData ?? n?.data ?? n?.notification?.additionalData ?? {};
          if (data == null) data = {};

          // Build a payload string type if present
          String? type;
          try { type = (data['type'] ?? data['notificationType'])?.toString(); } catch (_) { type = null; }

          // show local banner and play short pop sound
          showNotification(title, body, payload: type);
          try {
            FlutterRingtonePlayer().play(fromAsset: 'assets/sounds/pop.mp3', looping: false, volume: 1.0);
          } catch (_) {}
        } catch (e) {
          debugPrint('handleIncoming error: $e');
        }
      }

      // Modern handler name
      try {
        if (os.setNotificationWillShowInForegroundHandler != null) {
          os.setNotificationWillShowInForegroundHandler((event) async {
            await handleIncoming(event?.notification ?? event);
            try { event.complete(event.notification); } catch (_) {}
          });
        }
      } catch (_) {}

      // Older/alternative handler names
      try {
        if (os.setNotificationReceivedHandler != null) {
          os.setNotificationReceivedHandler((event) async {
            await handleIncoming(event);
          });
        }
      } catch (_) {}

      try {
        if (os.setNotificationOpenedHandler != null) {
          os.setNotificationOpenedHandler((opened) async {
            await handleIncoming(opened?.notification ?? opened);
          });
        }
      } catch (_) {}

    } catch (e) {
      debugPrint('OneSignal handler registration failed: $e');
    }

    // Foreground handling: OneSignal plugin initializes separately.
    // If you want to display local banners for custom events, call `showNotification(...)` where appropriate.

    _initialized = true;
    debugPrint("✅ NotificationService initialisé avec succès");
  }

  // --- FONCTION POUR AFFICHER LA NOTIFICATION ---
  static Future<void> showNotification(String title, String body, {String? payload}) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/launcher_icon',
    );

    final NotificationDetails platform = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    await _fln.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      platform,
      payload: payload,
    );
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
      default:
        return 'unknown';
    }
  }

  // --- GESTION DU SON (APPELS / CHAT) ---
  static void playRingtone() {
    if (kIsWeb) return;
    try {
      FlutterRingtonePlayer().play(
        fromAsset: 'assets/sounds/ringtone.mp3',
        looping: true,
        volume: 1.0,
      );
    } catch (e) {
      FlutterRingtonePlayer().playRingtone(looping: true);
    }
  }

  static void stopRingtone() {
    if (!kIsWeb) {
      FlutterRingtonePlayer().stop();
    }
  }
}
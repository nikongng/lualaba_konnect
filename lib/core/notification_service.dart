import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io' show Platform;

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

    // 1. Demander les permissions (Indispensable Android 13+ et iOS)
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

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
        OneSignal.shared.setAppId(oneSignalAppId);
        // retrieve player id and store in Firestore under user doc if logged in
        final ds = await OneSignal.shared.getDeviceState();
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
                    'platform': Platform.operatingSystem,
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

    // 4. Ecouter les messages en FOREGROUND (App ouverte)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title ?? message.data['title'] ?? 'Lualaba Konnect';
      final body = message.notification?.body ?? message.data['body'] ?? '';
      
      // On force l'affichage de la bannière car Firebase ne le fait pas auto en foreground
      showNotification(title, body, payload: message.data['type']);
    });

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
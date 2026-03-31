// Firebase Messaging removed — using OneSignal as push provider
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:lualaba_konnect/firebase_options.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
// Avoid importing `dart:io` directly (breaks web builds). Use Flutter's
// platform constants instead.

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  await NotificationService.handleNotificationResponse(response);
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _localInitialized = false;
  static bool _tzInitialized = false;

  static int _stableHash32(String input) {
    // FNV-1a 32-bit (stable across runs/platforms)
    int hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  static int notificationIdForChat(String chatId) => _stableHash32('chat:$chatId');
  static int stableIdForKey(String key) => _stableHash32(key);

  // --- CONFIGURATION DU CANAL (ID UNIQUE) ---
  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'lualaba_channel_v2', // New id => forces Android to (re)create with custom sound
    'Lualaba Notifications',
    description: 'Notifications pour le chat et le marketplace',
    importance: Importance.max,
    playSound: true,
    // Custom sound (Android: android/app/src/main/res/raw/lualaba_pop.mp3)
    sound: RawResourceAndroidNotificationSound('lualaba_pop'),
    enableVibration: true,
  );

  /// Local notifications + Android channel (sound is tied to the channel id).
  static Future<void> initLocalOnly() async {
    if (_localInitialized) return;
    await _initTimeZones();

    // Create officially the channel on Android (required for background display + custom sound).
    await _fln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    final DarwinInitializationSettings iosInit = DarwinInitializationSettings();

    final InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _fln.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        handleNotificationResponse(response);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    _localInitialized = true;
  }

  static Future<void> _initTimeZones() async {
    if (_tzInitialized || kIsWeb) return;
    try {
      tz.initializeTimeZones();
      String? name;
      try {
        final tzInfo = await FlutterTimezone.getLocalTimezone();
        name = tzInfo.identifier;
      } catch (_) {
        name = null;
      }
      if (name != null && name.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(name));
      }
      _tzInitialized = true;
    } catch (e) {
      debugPrint('Timezone init error: $e');
    }
  }

  static Future<void> init() async {
    if (_initialized) return;
    await initLocalOnly();

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
          data ??= {};

          // Build a payload string type if present
          String? type;
          try { type = (data['type'] ?? data['notificationType'])?.toString(); } catch (_) { type = null; }

          int? localId;
          try {
            final chatId = (data['chatId'] ?? data['chat_id'] ?? data['conversationId'] ?? data['conversation_id'])?.toString();
            if (chatId != null && chatId.isNotEmpty) localId = notificationIdForChat(chatId);
          } catch (_) {}

          final String? chatId = (data['chatId'] ?? data['chat_id'] ?? data['conversationId'] ?? data['conversation_id'])?.toString();
          final String? payload = chatId != null && chatId.isNotEmpty ? 'chat:$chatId' : type;
          // show local banner and play short pop sound
          showNotification(title, body, payload: payload, id: localId, chatId: chatId);
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
  static Future<void> showNotification(
    String title,
    String body, {
    String? payload,
    int? id,
    String? chatId,
  }) async {
    await initLocalOnly();
    final actions = <AndroidNotificationAction>[];
    if (chatId != null && chatId.trim().isNotEmpty) {
      actions.add(
        const AndroidNotificationAction(
          'reply',
          'RÃ©pondre',
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(label: 'Votre rÃ©ponse'),
          ],
          allowGeneratedReplies: true,
          showsUserInterface: false,
        ),
      );
    }
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('lualaba_pop'),
      icon: '@mipmap/launcher_icon',
      actions: actions.isNotEmpty ? actions : null,
    );

    final NotificationDetails platform = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    final String? finalPayload = (payload == null || payload.isEmpty)
        ? (chatId != null && chatId.trim().isNotEmpty ? 'chat:$chatId' : null)
        : payload;
    await _fln.show(
      id ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      title,
      body,
      platform,
      payload: finalPayload,
    );
  }

  static Future<void> handleNotificationResponse(NotificationResponse response) async {
    final actionId = response.actionId ?? '';
    final payload = response.payload ?? '';
    if (actionId == 'reply') {
      final text = (response.input ?? '').trim();
      final chatId = _chatIdFromPayload(payload);
      if (chatId.isNotEmpty && text.isNotEmpty) {
        await _sendQuickReply(chatId, text);
      }
      return;
    }
    debugPrint("Notification cliquÃ©e avec payload: $payload");
  }

  static String _chatIdFromPayload(String payload) {
    final p = payload.trim();
    if (p.startsWith('chat:')) return p.substring(5);
    if (p.startsWith('nav:chat:')) return p.substring(9);
    return '';
  }

  static Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  static Future<void> _sendQuickReply(String chatId, String text) async {
    try {
      await _ensureFirebaseInitialized();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
      final chatSnap = await chatRef.get();
      if (!chatSnap.exists) return;
      final chatData = chatSnap.data() ?? const <String, dynamic>{};
      final participants = (chatData['participants'] is List)
          ? List.from(chatData['participants'])
          : <dynamic>[];

      await chatRef.collection('messages').add({
        'senderId': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'delivered': false,
        'deliveredAt': null,
        'type': 'text',
        'text': text,
      });

      final updateData = <String, dynamic>{
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
      };
      for (final p in participants) {
        final pid = p.toString();
        if (pid.isEmpty) continue;
        updateData['hiddenFor.$pid'] = FieldValue.delete();
        if (pid != user.uid) {
          updateData['unreadCounts.$pid'] = FieldValue.increment(1);
        }
      }
      await chatRef.set(updateData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Quick reply error: $e');
    }
  }

  static Future<AndroidScheduleMode> _preferredAndroidScheduleMode() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }

    final androidPlugin =
        _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }

    try {
      final canExact = await androidPlugin.canScheduleExactNotifications();
      if (canExact == false) {
        return AndroidScheduleMode.inexactAllowWhileIdle;
      }
    } catch (e) {
      debugPrint('Exact alarm capability check failed: $e');
    }

    return AndroidScheduleMode.exactAllowWhileIdle;
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    String? payload,
  }) async {
    await initLocalOnly();
    if (kIsWeb) return;

    final tz.TZDateTime tzTime = tz.TZDateTime.from(scheduledAt, tz.local);
    if (tzTime.isBefore(tz.TZDateTime.now(tz.local))) return;

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('lualaba_pop'),
      icon: '@mipmap/launcher_icon',
    );

    final NotificationDetails platform = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );
    final scheduleMode = await _preferredAndroidScheduleMode();

    try {
      await _fln.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        platform,
        androidScheduleMode: scheduleMode,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } on PlatformException catch (e) {
      final details = '${e.code} ${e.message ?? ''} ${e.details ?? ''}'.toLowerCase();
      if (defaultTargetPlatform == TargetPlatform.android &&
          details.contains('exact') &&
          details.contains('alarm')) {
        debugPrint('Exact alarm not permitted, retrying with inexact scheduling.');
        await _fln.zonedSchedule(
          id,
          title,
          body,
          tzTime,
          platform,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
        return;
      }
      rethrow;
    }
  }

  static Future<void> cancelNotification(int id) async {
    try {
      await initLocalOnly();
      await _fln.cancel(id);
    } catch (_) {}
  }

  static Future<void> clearNotificationsForChat(String chatId, {bool clearPush = false}) async {
    try {
      await initLocalOnly();
      await _fln.cancel(notificationIdForChat(chatId));
    } catch (_) {}

    if (!clearPush || kIsWeb) return;

    // OneSignal: there is no reliable per-chat cancel; best effort is to clear app notifications.
    try {
      final dynamic os = OneSignal();
      try {
        await os.clearOneSignalNotifications();
        return;
      } catch (_) {}
      try {
        await os.Notifications.clearAll();
        return;
      } catch (_) {}
      try {
        await os.notifications.clearAll();
        return;
      } catch (_) {}
    } catch (e) {
      debugPrint('NotificationService.clearNotificationsForChat error: $e');
    }
  }

  // --- ACTIVER/DESACTIVER LES NOTIFICATIONS ---
  static Future<void> setEnabled(bool enabled) async {
    try {
      if (kIsWeb) return;
      final dynamic os = OneSignal();
      // Newer API
      try {
        await os.disablePush(!enabled);
        if (!enabled) {
          try { await _fln.cancelAll(); } catch (_) {}
        }
        return;
      } catch (_) {}
      // Older API
      try {
        await os.setSubscription(enabled);
        if (!enabled) {
          try { await _fln.cancelAll(); } catch (_) {}
        }
        return;
      } catch (_) {}
      // Consent based
      try {
        await os.consentGranted(enabled);
      } catch (_) {}
    } catch (e) {
      debugPrint('NotificationService.setEnabled error: $e');
    }
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


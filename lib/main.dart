import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart'; // Pour kIsWeb

// --- Tes imports personnalisés ---
import 'features/chat/presentation/pages/call_webrtc_page.dart';
import 'features/chat/presentation/pages/chat_detail_page.dart';
import 'firebase_options.dart';
import 'core/supabase_service.dart';
// Assure-toi que ce fichier existe et contient : final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
import 'core/app_navigator.dart'; 
import 'features/auth/presentation/pages/splash_screen.dart';
import 'features/auth/presentation/pages/AuthMainPage.dart';
import 'features/dashboard/presentation/pages/dashboard_page.dart';
import 'core/theme_controller.dart';
import 'core/call_invite_listener.dart';
import 'core/notification_service.dart';

// Keep OneSignal push subscription id synced to Firestore (Android can take a bit to provide it).
String? _oneSignalBoundUid;
bool _oneSignalObserverAttached = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialisation Firebase
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('❌ Erreur init Firebase: $e');
  }

  // 2. Configuration Firestore (Persistance & Cache)
  if (!kIsWeb) {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      debugPrint('ℹ️ Note persistence Firestore: $e');
    }
  }

  // 3. Chargement .env
  try {
    // `flutter_dotenv` throws if the file is missing/empty unless `isOptional: true`.
    // On CI (Codemagic), `.env` is usually generated at build time via `DOTENV_FILE`.
    await dotenv.load(fileName: ".env", isOptional: true);
  } catch (e) {
    // Never crash the app for a missing env file; just continue with defaults.
    dotenv.loadFromString(envString: '', isOptional: true);
    debugPrint("ℹ️ Note : Problème chargement .env (defaults). error=$e");
  }
  debugPrint('dotenv initialized=${dotenv.isInitialized} keys=${dotenv.env.length}');

  // 4. Initialisation Supabase (Optionnel selon ton projet)
  final String supabaseUrl = dotenv.maybeGet('SUPABASE_URL') ?? '';
  final String supabaseAnon = dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '';

  if (supabaseUrl.isNotEmpty && supabaseAnon.isNotEmpty) {
    try {
      await SupabaseService.init(url: supabaseUrl, anonKey: supabaseAnon);
    } catch (e) {
      debugPrint('❌ Erreur Supabase : $e');
    }
  }

  // 4b. Initialiser le canal Android des notifications (son personnalisé, vibration, etc.)
  // Important: sur Android 8+, le son est "verrouillé" au niveau du channel id.
  try { await NotificationService.initLocalOnly(); } catch (e) { debugPrint('NotificationService.initLocalOnly error: $e'); }

  // 5. CONFIGURATION ONESIGNAL (UNIQUEMENT MOBILE)
  // On ignore le Web pour se concentrer sur Android/iOS
  if (!kIsWeb) {
    final envAppId = dotenv.maybeGet('ONE_SIGNAL_APP_ID') 
        ?? dotenv.maybeGet('ONESIGNAL_APP_ID') 
        ?? 'TON_APP_ID_PAR_DEFAUT_ICI'; // Remplace par ton ID en dur au cas où

    if (envAppId.trim().isEmpty || envAppId == 'TON_APP_ID_PAR_DEFAUT_ICI') {
      debugPrint('ERROR: OneSignal AppId missing. Set ONE_SIGNAL_APP_ID in .env (or hardcode it).');
    }

    debugPrint('ℹ️ OneSignal AppId resolved -> $envAppId');

    try {
      // A. Logs pour le debug
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);

      // B. Init
      OneSignal.initialize(envAppId);
      
      // C. Demande de permission immédiate
      final accepted = await OneSignal.Notifications.requestPermission(true);
      debugPrint('OneSignal permission accepted=$accepted');

      // D. S'assurer que OneSignal considère l'utilisateur "opted-in" (pas seulement la permission OS).
      // Sinon OneSignal peut répondre: "unsubscribed subscriptions attached" pour l'external_user_id.
      try {
        await OneSignal.User.pushSubscription.optIn();
        debugPrint(
          'OneSignal push optedIn=${OneSignal.User.pushSubscription.optedIn} '
          'id=${OneSignal.User.pushSubscription.id} token=${OneSignal.User.pushSubscription.token}',
        );
      } catch (e) {
        debugPrint('OneSignal optIn error: $e');
      }

      // E. Gestion des clics sur notification (Appel entrant)
      OneSignal.Notifications.addClickListener((event) {
        final data = event.notification.additionalData;
        final actionId = event.result.actionId;

        debugPrint("🔔 Notification click : $data");

        if (data != null && data['type'] == 'incoming_call') {
          final callId = (data['callId'] ?? '').toString();

          if (actionId == 'decline') {
            // Best-effort: update Firestore so caller sees it as rejected.
            if (callId.isNotEmpty) {
              try {
                FirebaseFirestore.instance.collection('calls').doc(callId).update({'status': 'rejected'});
              } catch (_) {}
            }
            return;
          }
          // Si on clique sur "Répondre" ou sur la notif elle-même
          if (actionId == 'accept' || actionId == null) {
            if (callId.isNotEmpty) {
              try {
                FirebaseFirestore.instance.collection('calls').doc(callId).update({'status': 'accepted'});
              } catch (_) {}
            }
             appNavigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => CallWebRTCPage(
                  callId: data['callId'] ?? '',
                  otherId: data['sentBy'] ?? '', 
                  name: event.notification.title ?? 'Appel entrant',
                  avatarLetter: (event.notification.title ?? 'U')[0].toUpperCase(),
                  isVideo: data['isVideo'] == true,
                  isCaller: false, // C'est nous qui recevons
                ),
              ),
            );
          }
        } else if (data != null && data['type'] == 'chat_message') {
          final chatId = (data['chatId'] ?? '').toString();
          if (chatId.isEmpty) return;
          final chatName = (data['chatName'] ?? event.notification.title ?? 'Discussion').toString();
          appNavigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => ChatDetailPage(chatId: chatId, chatName: chatName)),
          );
        }
      });

    } catch (e) {
      debugPrint('❌ Erreur initialisation OneSignal: $e');
    }
  }

  // 6. ÉCOUTEUR D'AUTHENTIFICATION (Le déclencheur principal)
  // Dès que l'utilisateur se connecte, on met à jour son ID OneSignal
  FirebaseAuth.instance.authStateChanges().listen((User? user) {
    if (user != null) {
      _oneSignalBoundUid = user.uid;
      _attachOneSignalPushSubscriptionObserver();
      debugPrint('👤 User connecté : ${user.uid} -> Mise à jour OneSignal...');
      _updateUserOneSignalId(user.uid);
      CallInviteListener.start(user.uid);
    } else {
      _oneSignalBoundUid = null;
      CallInviteListener.stop();
    }
  });

  // 7. Charger le thème global
  await ThemeController.instance.load();

  runApp(const MyApp());
}

void _attachOneSignalPushSubscriptionObserver() {
  if (kIsWeb) return;
  if (_oneSignalObserverAttached) return;
  _oneSignalObserverAttached = true;

  try {
    OneSignal.User.pushSubscription.addObserver((state) {
      final uid = _oneSignalBoundUid;
      final playerId = state.current.id;
      if (uid == null || uid.trim().isEmpty) return;
      if (playerId == null || playerId.trim().isEmpty) return;

      // Best-effort: keep Firestore in sync so the notifier can target this device.
      _saveOneSignalIdToFirestore(uid: uid.trim(), onesignalId: playerId.trim());
    });
  } catch (e) {
    debugPrint('OneSignal addObserver error: $e');
  }
}

Future<void> _saveOneSignalIdToFirestore({
  required String uid,
  required String onesignalId,
}) async {
  if (kIsWeb) return;
  if (uid.trim().isEmpty || onesignalId.trim().isEmpty) return;

  final collections = ['classic_users', 'pro_users', 'enterprise_users'];
  bool userFound = false;

  for (final col in collections) {
    final docRef = FirebaseFirestore.instance.collection(col).doc(uid);
    final doc = await docRef.get();
    if (!doc.exists) continue;

    await docRef.update({
      'oneSignalPlayerId': onesignalId,
      'last_seen_device': DateTime.now().toIso8601String(),
      'device_platform': 'android_flutter',
    });

    // Keep a history of devices/subscriptions (server reads this as a fallback).
    await docRef.collection('notification_players').doc(onesignalId).set({
      'playerId': onesignalId,
      'platform': 'android_flutter',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    userFound = true;
    break;
  }

  if (!userFound) {
    final fallbackRef = FirebaseFirestore.instance.collection('classic_users').doc(uid);
    await fallbackRef.set({
      'oneSignalPlayerId': onesignalId,
      'uid': uid,
      'email': FirebaseAuth.instance.currentUser?.email ?? 'no-email',
      'createdAt': FieldValue.serverTimestamp(),
      'role': 'classic',
    }, SetOptions(merge: true));

    await fallbackRef.collection('notification_players').doc(onesignalId).set({
      'playerId': onesignalId,
      'platform': 'android_flutter',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// Fonction CRITIQUE pour lier l'utilisateur à son téléphone
Future<void> _updateUserOneSignalId(String uid) async {
  if (kIsWeb) return; // Sécurité anti-crash web

  try {
    // ÉTAPE 1 : IDENTIFICATION EXTERNE (C'est ça qui fait marcher le "WhatsApp style")
    // On dit à OneSignal : "Cet appareil appartient à l'utilisateur UID"
    OneSignal.login(uid);
    debugPrint('🔑 OneSignal Login effectué pour : $uid');

    // ÉTAPE 2 : Attendre que le Token soit prêt
    String? onesignalId;
    for (var i = 0; i < 6; i++) {
      onesignalId = OneSignal.User.pushSubscription.id;
      if (onesignalId != null && onesignalId.isNotEmpty) break;
      await Future.delayed(const Duration(seconds: 1));
    }

    if (onesignalId == null || onesignalId.isEmpty) {
      debugPrint('⚠️ Impossible de récupérer le Subscription ID OneSignal.');
      return;
    }
    debugPrint('🚀 OneSignal pushSubscription.id prêt : $onesignalId');
    debugPrint(
      'OneSignal state optedIn=${OneSignal.User.pushSubscription.optedIn} '
      'token=${OneSignal.User.pushSubscription.token}',
    );

    // ÉTAPE 3 : Sauvegarde dans Firestore pour que Render puisse le trouver
    await _saveOneSignalIdToFirestore(uid: uid, onesignalId: onesignalId);

  } catch (e) {
    debugPrint('❌ Erreur critique _updateUserOneSignalId : $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeCtrl = ThemeController.instance;
    return AnimatedBuilder(
      animation: themeCtrl,
      builder: (context, _) {
        final baseLight = ThemeData.light(useMaterial3: true);
        final baseDark = ThemeData.dark(useMaterial3: true);
        return MaterialApp(
          navigatorKey: appNavigatorKey, // Indispensable pour la navigation hors contexte
          title: 'Lualaba Konnect',
          debugShowCheckedModeBanner: false,
          theme: baseLight.copyWith(
            colorScheme: baseLight.colorScheme.copyWith(primary: Colors.orange),
            textTheme: GoogleFonts.notoSansTextTheme(baseLight.textTheme),
            fontFamily: 'Poppins',
          ),
          darkTheme: baseDark.copyWith(
            colorScheme: baseDark.colorScheme.copyWith(primary: Colors.orange),
            textTheme: GoogleFonts.notoSansTextTheme(baseDark.textTheme),
            fontFamily: 'Poppins',
          ),
          themeMode: themeCtrl.mode,
          home: const SplashScreen(),
          routes: {
            '/login': (context) => const AuthMainPage(),
            '/dashboard': (context) => const DashboardPage(),
          },
        );
      },
    );
  }
}

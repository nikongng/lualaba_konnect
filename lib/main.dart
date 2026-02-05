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
import 'firebase_options.dart';
import 'core/supabase_service.dart';
// Assure-toi que ce fichier existe et contient : final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
import 'core/app_navigator.dart'; 
import 'features/auth/presentation/pages/splash_screen.dart';
import 'features/auth/presentation/pages/AuthMainPage.dart';
import 'features/dashboard/presentation/pages/dashboard_page.dart';

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
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("ℹ️ Note : Fichier .env non trouvé (Utilisation des defaults)");
  }

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

  // 5. CONFIGURATION ONESIGNAL (UNIQUEMENT MOBILE)
  // On ignore le Web pour se concentrer sur Android/iOS
  if (!kIsWeb) {
    final envAppId = dotenv.maybeGet('ONE_SIGNAL_APP_ID') 
        ?? dotenv.maybeGet('ONESIGNAL_APP_ID') 
        ?? 'TON_APP_ID_PAR_DEFAUT_ICI'; // Remplace par ton ID en dur au cas où

    debugPrint('ℹ️ OneSignal AppId resolved -> $envAppId');

    try {
      // A. Logs pour le debug
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);

      // B. Init
      OneSignal.initialize(envAppId);
      
      // C. Demande de permission immédiate
      OneSignal.Notifications.requestPermission(true);

      // D. Gestion des clics sur notification (Appel entrant)
      OneSignal.Notifications.addClickListener((event) {
        final data = event.notification.additionalData;
        final actionId = event.result.actionId;

        debugPrint("🔔 Notification click : $data");

        if (data != null && data['type'] == 'incoming_call') {
          // Si on clique sur "Répondre" ou sur la notif elle-même
          if (actionId == 'accept' || actionId == null) {
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
      debugPrint('👤 User connecté : ${user.uid} -> Mise à jour OneSignal...');
      _updateUserOneSignalId(user.uid);
    }
  });

  runApp(const MyApp());
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
    debugPrint('🚀 ID OneSignal Device prêt : $onesignalId');

    // ÉTAPE 3 : Sauvegarde dans Firestore pour que Render puisse le trouver
    final collections = ['classic_users', 'pro_users', 'enterprise_users'];
    bool userFound = false;

    for (var col in collections) {
      final docRef = FirebaseFirestore.instance.collection(col).doc(uid);
      final doc = await docRef.get();

      if (doc.exists) {
        // On met à jour l'ID et on ajoute un timestamp
        await docRef.update({
          'oneSignalPlayerId': onesignalId,
          'last_seen_device': DateTime.now().toIso8601String(),
          'device_platform': 'android_flutter'
        });
        debugPrint('✅ ID OneSignal sauvegardé dans : $col');
        userFound = true;
        break;
      }
    }

    // ÉTAPE 4 : Filet de sécurité (Création de profil si inexistant)
    if (!userFound) {
      debugPrint('ℹ️ User introuvable, création profil de secours...');
      await FirebaseFirestore.instance.collection('classic_users').doc(uid).set({
        'oneSignalPlayerId': onesignalId,
        'uid': uid,
        'email': FirebaseAuth.instance.currentUser?.email ?? 'no-email',
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'classic',
      }, SetOptions(merge: true));
    }

  } catch (e) {
    debugPrint('❌ Erreur critique _updateUserOneSignalId : $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey, // Indispensable pour la navigation hors contexte
      title: 'Lualaba Konnect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        textTheme: GoogleFonts.notoSansTextTheme(),
        fontFamily: 'Poppins', 
        useMaterial3: true,
      ),
      home: const SplashScreen(), 
      routes: {
        '/login': (context) => const AuthMainPage(),
        '/dashboard': (context) => const DashboardPage(),
      },
    );
  }
}
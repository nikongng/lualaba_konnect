import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

// Tes imports personnalisés
import 'firebase_options.dart';
import 'core/notification_service.dart';
import 'core/fcm_handlers.dart'; // Contient firebaseMessagingBackgroundHandler
import 'core/supabase_service.dart';
import 'core/app_navigator.dart';
import 'features/auth/presentation/pages/splash_screen.dart';
import 'features/auth/presentation/pages/AuthMainPage.dart';
import 'features/dashboard/presentation/pages/dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialisation Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Configuration Firestore
  if (kIsWeb) {
    await FirebaseFirestore.instance.enablePersistence(
      const PersistenceSettings(synchronizeTabs: true)
    );
  } else {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint('✅ Firestore Offline Persistence activée');
    } catch (e) {
      debugPrint('❌ Erreur persistence Firestore: $e');
    }
  }

  // 3. Chargement .env
  try {
    await dotenv.load(fileName: ".env");
    debugPrint("✅ Fichier .env chargé");
  } catch (e) {
    debugPrint("ℹ️ Note : Fichier .env non trouvé");
  }

  // 4. Clés API
  final String supabaseUrl = dotenv.maybeGet('SUPABASE_URL') ?? const String.fromEnvironment('SUPABASE_URL');
  final String supabaseAnon = dotenv.maybeGet('SUPABASE_ANON_KEY') ?? const String.fromEnvironment('SUPABASE_ANON_KEY');

  // 5. Initialisation Supabase
  if (supabaseUrl.isNotEmpty && supabaseAnon.isNotEmpty) {
    try {
      await SupabaseService.init(url: supabaseUrl, anonKey: supabaseAnon);
      debugPrint('✅ Supabase initialisé');
    } catch (e) {
      debugPrint('❌ Erreur Supabase : $e');
    }
  }

  // 6. CONFIGURATION DES NOTIFICATIONS PUSH
  await NotificationService.init();

  // On enregistre le handler défini dans fcm_handlers.dart
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler); 

  // On initialise les écouteurs de messages (Une seule fois !)
  FcmHandlers.init();

  // Demander les permissions
  try {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      final token = await messaging.getToken();
      debugPrint('🚀 MON TOKEN FCM : $token');
    }
  } catch (e) {
    debugPrint('❌ Erreur FCM Init : $e');
  }

  runApp(const MyApp());
}

// Ta classe MyApp reste identique
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
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
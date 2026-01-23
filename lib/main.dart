import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Tes imports personnalisés
import 'firebase_options.dart';
import 'core/notification_service.dart';
import 'core/fcm_handlers.dart';
import 'core/supabase_service.dart';
import 'core/app_navigator.dart';
import 'features/auth/presentation/pages/splash_screen.dart';
import 'features/auth/presentation/pages/AuthMainPage.dart';
import 'features/dashboard/presentation/pages/dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Charger le fichier .env (Local)
  // On utilise un try/catch pour que l'app ne plante pas sur Codemagic si le .env est absent
  try {
    await dotenv.load(fileName: ".env");
    debugPrint("✅ Fichier .env chargé avec succès");
  } catch (e) {
    debugPrint("ℹ️ Note : Fichier .env non trouvé (Utilisation des variables système)");
  }

  // 2. Récupérer les clés (Priorité au .env, sinon Dart Define/Codemagic)
  final String supabaseUrl = dotenv.maybeGet('SUPABASE_URL') ?? 
                             const String.fromEnvironment('SUPABASE_URL');
  
  final String supabaseAnon = dotenv.maybeGet('SUPABASE_ANON_KEY') ?? 
                              const String.fromEnvironment('SUPABASE_ANON_KEY');
  
  final String geminiKey = dotenv.maybeGet('GEMINI_API_KEY') ?? 
                           const String.fromEnvironment('GEMINI_KEY');

  // 3. Initialisation Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 4. Configuration Firestore
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    debugPrint('✅ Firestore persistence enabled');
  } catch (e) {
    debugPrint('❌ Could not enable Firestore persistence: $e');
  }

  // 5. Initialisation Supabase
  if (supabaseUrl.isNotEmpty && supabaseAnon.isNotEmpty) {
    try {
      await SupabaseService.init(url: supabaseUrl, anonKey: supabaseAnon);
      debugPrint('✅ Supabase initialized');
    } catch (e) {
      debugPrint('❌ Supabase init error: $e');
    }
  } else {
    debugPrint('⚠️ Supabase keys not provided');
  }

  // 6. Configuration Notifications & FCM
  await NotificationService.init();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  try {
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('FCM token: $token');
  } catch (e) { 
    debugPrint('FCM init err: $e'); 
  }

  FcmHandlers.init();

  // Debug Gemini
  if (geminiKey.isNotEmpty) {
    debugPrint("✅ GEMINI_KEY est prête");
  } else {
    debugPrint("⚠️ GEMINI_KEY manquante");
  }

  runApp(const MyApp());
}

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
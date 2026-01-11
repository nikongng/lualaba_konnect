import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/notification_service.dart';
import 'core/fcm_handlers.dart';
import 'core/app_navigator.dart';
import 'features/auth/presentation/pages/splash_screen.dart';
import 'features/auth/presentation/pages/AuthMainPage.dart';
import 'features/dashboard/presentation/pages/dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialisation Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Notifications
  await NotificationService.init();
  // register background handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  try {
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('FCM token: $token');
  } catch (e) { debugPrint('FCM init err: $e'); }

  // init foreground/opened handlers
  FcmHandlers.init();

  // VÉRIFICATION DES CLÉS (Optionnel - pour le debug)
  // On vérifie si les clés injectées par Codemagic sont présentes
  const geminiKey = String.fromEnvironment('GEMINI_KEY');
  if (geminiKey.isEmpty) {
    debugPrint("⚠️ Note : GEMINI_KEY n'est pas définie via --dart-define");
  } else {
    debugPrint("✅ GEMINI_KEY est prête");
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
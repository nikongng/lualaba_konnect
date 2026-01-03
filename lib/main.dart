import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'features/auth/presentation/pages/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialisation Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
      title: 'Lualaba Konnect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        fontFamily: 'Poppins', 
        useMaterial3: true,
      ),
      home: const SplashScreen(), 
      routes: {
        '/login': (context) => const SplashScreen(),
      },
    );
  }
}
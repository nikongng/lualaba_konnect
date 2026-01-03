import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // AJOUTÉ
import 'firebase_options.dart'; // AJOUTÉ
import 'features/auth/presentation/pages/splash_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  // AJOUTÉ : Indispensable pour Firebase
  WidgetsFlutterBinding.ensureInitialized();
  
  // AJOUTÉ : Initialisation de la connexion Google/Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
 try {
    await dotenv.load(fileName: ".env");
    debugPrint("Fichier .env chargé avec succès");
  } catch (e) {
    debugPrint("⚠️ Attention : Le fichier .env est introuvable. L'IA utilisera la clé par défaut.");
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
        // On garde votre thème orange pour l'identité de Kolwezi
        primarySwatch: Colors.orange,
        fontFamily: 'Poppins', 
        useMaterial3: true,
      ),
      // On garde votre point d'entrée actuel
      home: const SplashScreen(), 
      
      routes: {
        '/login': (context) => const SplashScreen(),
        // Les autres routes resteront ici
      },
    );
  }
}
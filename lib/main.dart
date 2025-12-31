import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // AJOUTÉ
import 'firebase_options.dart'; // AJOUTÉ
import 'features/auth/presentation/pages/ModernDashboard.dart';
import 'features/auth/presentation/pages/AuthMainPage.dart';

void main() async {
  // AJOUTÉ : Indispensable pour Firebase
  WidgetsFlutterBinding.ensureInitialized();
  
  // AJOUTÉ : Initialisation de la connexion Google/Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
      home: const AuthMainPage(), 
      
      routes: {
        '/login': (context) => const AuthMainPage(),
        // Les autres routes resteront ici
      },
    );
  }
}
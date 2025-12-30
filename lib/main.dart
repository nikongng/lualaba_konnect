import 'package:flutter/material.dart';
import 'account_choice_page.dart';
import 'classic_account__page.dart';
import 'prefs_service.dart';
import 'AuthMainPage.dart';

void main() {
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
        fontFamily: 'Poppins', // Si vous utilisez une police spécifique
      ),
      // On définit AuthMainPage comme point d'entrée
      home: const AuthMainPage(), 
      
      // Optionnel : Configuration des routes pour naviguer plus tard
      routes: {
        '/login': (context) => const AuthMainPage(),
        // '/choice': (context) => const AccountTypePage(),
        // '/registration': (context) => const RegistrationFormPage(profileType: 1),
      },
    );
  }
}
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'features/chat/presentation/pages/call_webrtc_page.dart';
import 'firebase_options.dart';
import 'core/supabase_service.dart';
import 'core/app_navigator.dart';
import 'features/auth/presentation/pages/splash_screen.dart';
import 'features/auth/presentation/pages/AuthMainPage.dart';
import 'features/dashboard/presentation/pages/dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialisation Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Configuration Firestore (Persistance & Cache)
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
    } catch (e) {
      debugPrint('❌ Erreur persistence Firestore: $e');
    }
  }

  // 3. Chargement .env
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("ℹ️ Note : Fichier .env non trouvé (Utilisation des defaults)");
  }

  // 4. Initialisation Supabase
  final String supabaseUrl = dotenv.maybeGet('SUPABASE_URL') ?? const String.fromEnvironment('SUPABASE_URL');
  final String supabaseAnon = dotenv.maybeGet('SUPABASE_ANON_KEY') ?? const String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseUrl.isNotEmpty && supabaseAnon.isNotEmpty) {
    try {
      await SupabaseService.init(url: supabaseUrl, anonKey: supabaseAnon);
    } catch (e) {
      debugPrint('❌ Erreur Supabase : $e');
    }
  }

  // 5. CONFIGURATION ONESIGNAL
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  
  // Récupération de l'ID (Priorité : .env > --dart-define > Valeur par défaut)
  final envAppId = dotenv.maybeGet('ONE_SIGNAL_APP_ID') ?? 
      const String.fromEnvironment('ONE_SIGNAL_APP_ID', defaultValue: 'ac19fdcc-16e7-4775-8806-8cde03d1fadb');

  try {
    OneSignal.initialize(envAppId);
    
    // Ajout CRUCIAL : Écouteur pour capturer l'ID s'il arrive en retard
    OneSignal.User.pushSubscription.addObserver((state) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && state.current.id != null && state.current.id!.isNotEmpty) {
        debugPrint('🔔 OneSignal Observer : ID détecté, mise à jour...');
        _updateUserOneSignalId(user.uid);
      }
    });

  } catch (e) {
    debugPrint('❌ Erreur initialisation OneSignal: $e');
  }

  try {
    OneSignal.Notifications.requestPermission(true);
  } catch (_) {}
OneSignal.Notifications.addClickListener((event) {
  final data = event.notification.additionalData;
  final actionId = event.result.actionId;

  if (data != null && data['type'] == 'incoming_call') {
    if (actionId == 'accept') {
      // L'utilisateur a cliqué sur le bouton "Répondre" de la bannière
      appNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => CallWebRTCPage(
            callId: data['callId'] ?? '', // Récupéré de Firestore via Render
            otherId: data['sentBy'] ?? '', 
            name: event.notification.title ?? 'Appel entrant',
            avatarLetter: (event.notification.title ?? 'U')[0].toUpperCase(),
            isVideo: data['isVideo'] == true, // Si tu gères la différence
            isCaller: false, // Très important : celui qui reçoit n'est pas l'appelant
          ),
        ),
      );
    }
  }
});
  // 6. ÉCOUTEUR DE CONNEXION (Déclencheur principal)
  FirebaseAuth.instance.authStateChanges().listen((User? user) {
    if (user != null) {
      // On lance la mise à jour dès qu'on sait qui est connecté
      _updateUserOneSignalId(user.uid);
    }
  });

  runApp(const MyApp());
}

/// Fonction ROBUSTE pour enregistrer l'ID OneSignal
Future<void> _updateUserOneSignalId(String uid) async {
  try {
    // A. Tentative de récupération de l'ID (Boucle de 6 secondes)
    String? onesignalId;
    for (var i = 0; i < 6; i++) {
      onesignalId = OneSignal.User.pushSubscription.id;
      if (onesignalId != null && onesignalId.isNotEmpty) break;
      await Future.delayed(const Duration(seconds: 1));
    }

    if (onesignalId == null || onesignalId.isEmpty) {
      debugPrint('⚠️ ID OneSignal introuvable après les tentatives.');
      return;
    }

    debugPrint('🚀 ID OneSignal PRÊT : $onesignalId');

    // B. Recherche dans les collections existantes
    final collections = ['classic_users', 'pro_users', 'enterprise_users'];
    bool userFound = false;

    for (var col in collections) {
      final docRef = FirebaseFirestore.instance.collection(col).doc(uid);
      final doc = await docRef.get();

      if (doc.exists) {
        await docRef.update({
          'oneSignalPlayerId': onesignalId,
          'last_seen_device': DateTime.now().toIso8601String(),
        });
        debugPrint('✅ ID mis à jour dans la collection existante : $col');
        userFound = true;
        break;
      }
    }

    // C. LE FILET DE SÉCURITÉ (Si l'utilisateur n'est nulle part)
    // Cela force la création du document pour que l'ID soit sauvé quoi qu'il arrive
    if (!userFound) {
      debugPrint('ℹ️ Profil introuvable, création d\'un profil de secours dans classic_users...');
      await FirebaseFirestore.instance.collection('classic_users').doc(uid).set({
        'oneSignalPlayerId': onesignalId,
        'email': FirebaseAuth.instance.currentUser?.email ?? 'unknown',
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'classic', // Valeur par défaut
        'uid': uid,
      }, SetOptions(merge: true)); // Merge évite d'écraser des données si on s'est trompé
      debugPrint('✅ Profil créé et ID OneSignal sauvegardé !');
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
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math' as math;
import 'AuthMainPage.dart';
import 'ModernDashboard.dart';
import 'ModernDashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _dotsController;
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _opacity = 1.0);
    });

    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 4));
    final prefs = await SharedPreferences.getInstance();
    bool remember = prefs.getBool('remember_me') ?? false;

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, anim, _) => remember ? const ModernDashboard() : const AuthMainPage(),
          transitionsBuilder: (context, anim, _, child) => FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 1000),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF012E32), 
      body: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(seconds: 2),
        curve: Curves.easeIn,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 5),
              
              // --- LOGO IMAGE PNG ---
              ScaleTransition(
                scale: Tween(begin: 1.0, end: 1.05).animate(_pulseController),
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF26522).withOpacity(0.3),
                        blurRadius: 40,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/logo.png', 
                      width: 120, // Taille de ton logo orange
                      fit: BoxFit.contain,
                      // On retire le placeholderBuilder qui causait l'erreur
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 60),
              
              // --- LES DOTS ANIMÉS ---
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  return AnimatedBuilder(
                    animation: _dotsController,
                    builder: (context, child) {
                      double delay = index * 0.2;
                      double value = (_dotsController.value - delay);
                      if (value < 0) value += 1.0;
                      
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        height: 7,
                        width: 7,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF26522).withOpacity(
                            0.2 + (0.8 * math.sin(value * math.pi)),
                          ),
                          shape: BoxShape.circle,
                        ),
                        transform: Matrix4.translationValues(
                          0, 
                          -7 * math.sin(value * math.pi), 
                          0
                        ),
                      );
                    },
                  );
                }),
              ),
              const Spacer(flex: 4),
            ],
          ),
        ),
      ),
    );
  }
}
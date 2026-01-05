import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore ajouté
import 'dart:async';
import 'AuthMainPage.dart';
import 'package:flutter/services.dart';

class OTPVerificationPage extends StatefulWidget {
  final String verificationId;
  final String? phoneNumber;
  
  // --- NOUVEAUX CHAMPS POUR RECEVOIR LES DONNÉES ---
  final String firstName;
  final String lastName;
  final String email;
  final String password;
  final int profileType;
  final String bio;
  final String address;

  const OTPVerificationPage({
    super.key, 
    required this.verificationId, 
    this.phoneNumber,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
    required this.profileType,
    this.bio = "",
    this.address = "",
  });

  @override
  State<OTPVerificationPage> createState() => _OTPVerificationPageState();
}

class _OTPVerificationPageState extends State<OTPVerificationPage> {
  final List<TextEditingController> _controllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  
  bool _isLoading = false;
  bool _canResend = false;
  int _timerSeconds = 60;
  Timer? _timer;
  late String _currentVerificationId;

  @override
  void initState() {
    super.initState();
    _currentVerificationId = widget.verificationId;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _controllers) { controller.dispose(); }
    for (var node in _focusNodes) { node.dispose(); }
    super.dispose();
  }

  void _startTimer() {
    setState(() { _canResend = false; _timerSeconds = 60; });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerSeconds == 0) {
        setState(() => _canResend = true);
        timer.cancel();
      } else {
        setState(() => _timerSeconds--);
      }
    });
  }

  Future<void> _resendCode() async {
    if (widget.phoneNumber == null) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber!,
        verificationCompleted: (PhoneAuthCredential credential) {},
        verificationFailed: (e) => _showError("Erreur : ${e.message}"),
        codeSent: (String vid, int? resendToken) {
          setState(() { _currentVerificationId = vid; _isLoading = false; });
          _startTimer();
          _showSuccess("Nouveau code envoyé !");
        },
        codeAutoRetrievalTimeout: (vid) {},
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("Impossible de renvoyer le code.");
    }
  }

  Future<void> _verifyOTP() async {
    String otp = _controllers.map((c) => c.text).join();
    if (otp.length < 6) return;

    setState(() => _isLoading = true);

    try {
      // 1. Authentification avec le vrai code SMS
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _currentVerificationId, 
        smsCode: otp,
      );
      
      UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        // 2. Création du profil utilisateur dans Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'firstName': widget.firstName,
          'lastName': widget.lastName,
          'email': widget.email,
          'phone': widget.phoneNumber,
          'profileType': widget.profileType,
          'address': widget.address,
          'bio': widget.bio,
          'idKonnect': "LK-${user.uid.substring(0, 5).toUpperCase()}", // Génération de l'ID
          'isVerified': true,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          setState(() => _isLoading = false);
          _showFinalSummary(true); 
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (e is FirebaseAuthException && e.code == 'invalid-verification-code') {
         _showError("Code incorrect.");
      } else {
         _showError("Erreur : $e");
      }
    }
  }

  void _showFinalSummary(bool autoValidated) {
    HapticFeedback.vibrate();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
        backgroundColor: Colors.transparent,
        child: TweenAnimationBuilder(
          duration: const Duration(milliseconds: 900),
          tween: Tween<Offset>(begin: const Offset(0, 1.5), end: const Offset(0, 0)),
          curve: Curves.easeOutBack,
          builder: (context, Offset offset, child) {
            return FractionalTranslation(
              translation: offset,
              child: Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 30,
                      offset: const Offset(0, -10),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 90, width: 90,
                      decoration: BoxDecoration(
                        color: autoValidated ? Colors.green.shade50 : Colors.blue.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(autoValidated ? "🥰" : "😎", style: const TextStyle(fontSize: 50)),
                      ),
                    ),
                    const SizedBox(height: 25),
                    Text(
                      autoValidated ? "Certification lancée !" : "Dossier en route !",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFE65100)),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      autoValidated 
                        ? "Check terminé ! Tes documents sont validés. Nous finalisons ta certification maintenant."
                        : "Tes documents ont été envoyés avec succès. Nous vérifions tout ça tout de suite.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.4, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 35),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(context);
                        Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const AuthMainPage()),
                        (route) => false,
                      );
                      },
                      child: Container(
                        height: 60, width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFF57C00), Color(0xFFE65100)]),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Text("Se connecter", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating)
  );
  
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating)
  );

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF012E32); 

    return Scaffold(
      backgroundColor: primaryColor,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF012E32), Color(0xFF004D40)],
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.security_rounded, size: 60, color: Colors.orange)
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        "Vérification SMS",
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                          children: [
                            const TextSpan(text: "Entrez le code à 6 chiffres envoyé au\n"),
                            TextSpan(
                              text: widget.phoneNumber ?? "votre numéro",
                              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 50),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) => _buildOtpBox(index)),
                      ),
                      const SizedBox(height: 40),
                      _canResend
                          ? TextButton(
                              onPressed: _isLoading ? null : _resendCode,
                              child: const Text("Renvoyer le code", 
                                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16)),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.timer_outlined, color: Colors.white54, size: 18),
                                const SizedBox(width: 8),
                                Text("Renvoyer dans ${_timerSeconds}s", 
                                  style: const TextStyle(color: Colors.white54, fontSize: 15)),
                              ],
                            ),
                      const SizedBox(height: 40),
                      _isLoading 
                        ? const CircularProgressIndicator(color: Colors.orange)
                        : SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: ElevatedButton(
                              onPressed: _verifyOTP,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                elevation: 8,
                                shadowColor: Colors.orange.withOpacity(0.4),
                              ),
                              child: const Text("VÉRIFIER", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    return Container(
      width: 50,
      height: 65,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: const TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(counterText: "", border: InputBorder.none),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
          if (index == 5 && value.isNotEmpty) {
            FocusScope.of(context).unfocus();
            _verifyOTP();
          }
        },
      ),
    );
  }
}
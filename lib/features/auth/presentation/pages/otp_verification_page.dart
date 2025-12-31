import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:ui'; // Pour les effets de flou si besoin
import 'account_choice_page.dart';

class OTPVerificationPage extends StatefulWidget {
  final String verificationId;
  final String? phoneNumber;

  const OTPVerificationPage({super.key, required this.verificationId, this.phoneNumber});

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

  // --- LOGIQUE FIREBASE CONSERVÉE ---
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
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _currentVerificationId,
        smsCode: otp,
      );
      
      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AccountChoicePage()),
          (route) => false,
        );
      }
    } catch (e) {
      _showError("Code incorrect. Veuillez réessayer.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating)
  );
  
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating)
  );

  @override
  Widget build(BuildContext context) {
    // Thème cohérent avec le Dashboard
    const Color primaryColor = Color(0xFF012E32); 

    return Scaffold(
      backgroundColor: primaryColor,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            // Dégradé de fond subtil
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
                      // Icône stylisée
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
                      
                      // BOÎTES OTP MODERNES
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) => _buildOtpBox(index)),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // TIMER / RESEND
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
                      
                      // BOUTON DE VALIDATION
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
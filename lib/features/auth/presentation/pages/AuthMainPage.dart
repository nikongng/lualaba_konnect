import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Ajouté
import 'account_choice_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ModernDashboard.dart';

class AuthMainPage extends StatefulWidget {
  const AuthMainPage({super.key});

  @override
  State<AuthMainPage> createState() => _AuthMainPageState();
}

class _AuthMainPageState extends State<AuthMainPage> {
  bool isLoginMode = true;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false; // Ajouté pour le feedback visuel

  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRememberMe();
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    bool remember = prefs.getBool('remember_me') ?? false;
    String savedId = prefs.getString('saved_id') ?? "";

    if (remember && savedId.isNotEmpty) {
      _idController.text = savedId;
      setState(() {
        _rememberMe = remember;
      });
    }
  }

  Future<void> _handleRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool('remember_me', true);
      await prefs.setString('saved_id', _idController.text.trim());
    } else {
      await prefs.remove('remember_me');
      await prefs.remove('saved_id');
    }
  }

  void _navigateToDashboard() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const ModernDashboard()),
      (route) => false,
    );
  }

  // --- NOUVELLE LOGIQUE FIREBASE DANS TON DESIGN ---
  Future<void> _login() async {
    if (_idController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError("Veuillez remplir tous les champs");
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _idController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await _handleRememberMe();
      _navigateToDashboard();
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Erreur de connexion");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE65100), Color(0xFFF57C00)],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 60),
            _buildLogoHeader(),
            const SizedBox(height: 30),
            Expanded(
              child: _buildMainFormCard(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoHeader() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 25,
                spreadRadius: 2,
              )
            ],
          ),
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.transparent,
            child: ClipOval(
              child: Image.asset(
                'assets/logo.png',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.wifi_tethering, color: Colors.white, size: 50);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        const Text(
          "Lualaba Konnect",
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const Text(
          "La super-app de la province",
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildMainFormCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MediaQuery.of(context).size.width > 600
            ? BorderRadius.circular(40)
            : const BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(40),
              ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 25, left: 30, right: 30),
                child: _buildTabToggle(),
              ),
              Expanded(
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    switchInCurve: Curves.easeOutQuart,
                    switchOutCurve: Curves.easeInQuart,
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      final bool isEnteringAccountChoice = child.key == const ValueKey("account_choice_content");
                      final offsetTween = Tween<Offset>(
                        begin: isEnteringAccountChoice ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0),
                        end: Offset.zero,
                      );
                      return SlideTransition(
                        position: offsetTween.animate(animation),
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: isLoginMode
                        ? _buildLoginForm()
                        : const AccountChoicePage(key: ValueKey("account_choice_content")),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      height: 55,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F8),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Expanded(child: _buildTabItem("Connexion", isLoginMode)),
          Expanded(child: _buildTabItem("Inscription", !isLoginMode)),
        ],
      ),
    );
  }

  Widget _buildTabItem(String title, bool active) {
    return GestureDetector(
      onTap: () {
        if ((title == "Connexion" && !isLoginMode) || (title == "Inscription" && isLoginMode)) {
          HapticFeedback.lightImpact();
          setState(() => isLoginMode = (title == "Connexion"));
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)] : [],
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: active ? Colors.black : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return SingleChildScrollView(
      key: const ValueKey("login_form_content"),
      padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
      child: Column(
        children: [
          _buildProfileImage(),
          const SizedBox(height: 20),
          const Text(
            "Bon retour, Bienvenue !",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
          ),
          const Text("Connectez-vous pour continuer.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 30),
          _buildInputField(
            label: "IDENTIFIANT (EMAIL)",
            hint: "exemple@mail.com",
            icon: Icons.person_outline,
            controller: _idController,
          ),
          const SizedBox(height: 20),
          _buildInputField(
            label: "MOT DE PASSE",
            hint: "........",
            icon: Icons.lock_outline,
            isPassword: true,
            controller: _passwordController,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    activeColor: Colors.orange,
                    onChanged: (value) => setState(() => _rememberMe = value ?? false),
                  ),
                  const Text("Se souvenir", style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
              TextButton(
                onPressed: () {},
                child: const Text("Mot de passe oublié ?", style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildProfileImage() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.orange.shade100, width: 2),
      ),
      child: const CircleAvatar(
        radius: 40,
        backgroundColor: Color(0xFFF1F4F8),
        child: Icon(Icons.person, size: 40, color: Colors.grey),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword && _obscurePassword,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 20, color: Colors.grey),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  )
                : null,
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFFBFBFB),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.orange, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE65100),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        onPressed: _isLoading ? null : _login, // Appelle maintenant _login
        child: _isLoading 
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text("Se connecter", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
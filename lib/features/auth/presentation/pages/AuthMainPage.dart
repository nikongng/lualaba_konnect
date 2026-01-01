import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'account_choice_page.dart';
import 'ModernDashboard.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthMainPage extends StatefulWidget {
  const AuthMainPage({super.key});

  @override
  State<AuthMainPage> createState() => _AuthMainPageState();
}

class _AuthMainPageState extends State<AuthMainPage> {
  @override
void initState() {
  super.initState();
  _loadRememberMe();
}
  bool isLoginMode = true; 
  bool _obscurePassword = true;
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberMe = false; // <-- Ajouter cette ligne

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
    // Si l'utilisateur a coché "Se souvenir", on ne perd pas de temps
    // On le redirige directement au Dashboard
    _navigateToDashboard();
  } else {
    // Sinon, on reste sur la page et on pré-remplit juste l'ID s'il existe
    setState(() {
      _rememberMe = remember;
      _idController.text = savedId;
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
    MaterialPageRoute(builder: (context) => const ModernDashboard()), // Remplacez par le nom exact de votre classe Dashboard
    (route) => false,
  );
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // On utilise un Builder pour accéder au Scaffold de manière sûre,
      // ce qui est utile pour les SnackBar par exemple.
      body: Builder(
        builder: (context) {
          return Container(
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
                const SizedBox(height: 50),
                _buildLogoHeader(),
                const SizedBox(height: 30),
                Expanded(
                  child: _buildMainFormCard(context), // Passe le context pour MediaQuery.of
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  // --- HEADER : LOGO ET TITRE ---
  Widget _buildLogoHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.wifi_tethering, color: Colors.white, size: 45),
        ),
        const SizedBox(height: 15),
        const Text(
          "Lualaba Konnect",
          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const Text(
          "La super-app de la province",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  // --- CARTE PRINCIPALE RESPONSIVE AVEC ANIMATION DE GLISSEMENT ---
  Widget _buildMainFormCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MediaQuery.of(context).size.width > 600
            ? BorderRadius.circular(40) // Arrondi complet sur Web
            : const BorderRadius.only( // Uniquement en haut sur Mobile
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
              Expanded( // Utilisation de Expanded pour que le contenu puisse prendre toute la hauteur restante
                child: ClipRect( // Important pour que l'animation de glissement reste dans les limites
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    switchInCurve: Curves.easeOutQuart,
                    switchOutCurve: Curves.easeInQuart,
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      // Détecte si le widget qui entre est AccountChoicePage pour déterminer la direction
                      final bool isEnteringAccountChoice = child.key == const ValueKey("account_choice_content");
                      
                      // Définition du point de départ du glissement
                      final Tween<Offset> offsetTween = Tween<Offset>(
                        begin: isEnteringAccountChoice 
                            ? const Offset(1.0, 0.0) // AccountChoicePage entre par la droite
                            : const Offset(-1.0, 0.0), // LoginForm entre par la gauche
                        end: Offset.zero,
                      );

                      return SlideTransition(
                        position: offsetTween.animate(animation),
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      );
                    },
                    // Le widget enfant actuel à afficher
                    child: isLoginMode 
                      ? _buildLoginForm() 
                      : const AccountChoicePage(key: ValueKey("account_choice_content")), // La clé est cruciale ici
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- TOGGLE TAB (CONNEXION / INSCRIPTION) ---
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
        // Ne déclenche un setState que si le mode change réellement
        if ((title == "Connexion" && !isLoginMode) || (title == "Inscription" && isLoginMode)) {
          HapticFeedback.lightImpact();
          setState(() => isLoginMode = (title == "Connexion"));
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active 
            ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)] 
            : [],
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

  // --- FORMULAIRE DE CONNEXION ---
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
          label: "IDENTIFIANT",
          hint: "0999000000",
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
        
        // --- NOUVELLE SECTION : SE SOUVENIR DE MOI & MOT DE PASSE OUBLIÉ ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: _rememberMe,
                    activeColor: Colors.orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                    onChanged: (value) {
                      setState(() {
                        _rememberMe = value ?? false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Se souvenir",
                  style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            TextButton(
              onPressed: () { /* Logique mot de passe oublié */ },
              child: const Text(
                "Mot de passe oublié ?",
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        // ------------------------------------------------------------------
        
        const SizedBox(height: 20),
        _buildSubmitButton(),
        const SizedBox(height: 20),
      ],
    ),
  );
}

  // --- WIDGETS DE SOUTIEN ---
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
    bool isPassword = false
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
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                )
              : null,
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFFBFBFB),
            contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15), // Ajuster le padding interne
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
      onPressed: () async { // Ajout de async
        HapticFeedback.mediumImpact();
        
        String id = _idController.text.trim();
        String pass = _passwordController.text.trim();

        if (id.isNotEmpty && pass.isNotEmpty) {
          // --- SAUVEGARDE ICI ---
          await _handleRememberMe(); 

          // Logique de test ou réelle
          if (id.contains("857263544") && pass == "123456") {
            _navigateToDashboard();
          } else {
            _navigateToDashboard();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Veuillez remplir tous les champs")),
          );
        }
      },
      child: const Text(
        "Se connecter", 
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
      ),
    ),
  );
}
}
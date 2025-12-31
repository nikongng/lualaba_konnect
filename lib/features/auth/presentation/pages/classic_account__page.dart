import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  int selectedTab = 0; // 0 = Connexion, 1 = Inscription
  bool isPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Couleur de fond pour l'espace vide sur navigateur
      backgroundColor: Colors.grey.shade200, 
      body: Center(
        child: Container(
          // Limite la largeur pour simuler un téléphone sur PC
          constraints: const BoxConstraints(maxWidth: 450),
          decoration: BoxDecoration(
            color: Colors.orange.shade800,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 0),
              )
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 50),
              
              // --- SECTION HAUT (LOGO ET TITRE) ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // Icône style antenne/wifi
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.wifi_tethering, size: 50, color: Colors.white),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      "Lualaba Konnect",
                      style: TextStyle(
                        color: Colors.white, 
                        fontSize: 28, 
                        fontWeight: FontWeight.bold
                      ),
                    ),
                    const Text(
                      "La super-app de la province",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // --- SECTION BLANCHE ARRONDIE ---
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(40),
                      topRight: Radius.circular(40),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        // --- SÉLECTEUR D'ONGLETS ---
                        Container(
                          height: 50,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F4F8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Stack(
                            children: [
                              AnimatedAlign(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                alignment: selectedTab == 0 ? Alignment.centerLeft : Alignment.centerRight,
                                child: FractionallySizedBox(
                                  widthFactor: 0.5,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  _buildTabButton("Connexion", 0),
                                  _buildTabButton("Inscription", 1),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 30),

                        // --- FORMULAIRE DYNAMIQUE ---
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: selectedTab == 0 ? _buildLoginForm() : _buildRegisterForm(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Widget Bouton d'onglet
  Widget _buildTabButton(String text, int index) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedTab = index),
        child: Container(
          color: Colors.transparent,
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selectedTab == index ? FontWeight.bold : FontWeight.w500,
                color: selectedTab == index ? Colors.black : Colors.blueGrey.shade300,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Widget Formulaire de Connexion
  Widget _buildLoginForm() {
    return Column(
      key: const ValueKey(0),
      children: [
        const CircleAvatar(
          radius: 40,
          backgroundImage: NetworkImage('https://via.placeholder.com/150'), // Remplace par ton image
        ),
        const SizedBox(height: 15),
        const Text(
          "Bon retour, Bienvenu !",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Text("Connectez-vous pour continuer.", style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 25),
        
        _buildInputField("IDENTIFIANT", Icons.email_outlined, "0999000000"),
        const SizedBox(height: 20),
        _buildInputField("MOT DE PASSE", Icons.lock_outline, "••••••••", isPassword: true),
        
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {},
            child: const Text("Mot de passe oublié ?", style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 10),
        _buildSubmitButton("Se connecter"),
      ],
    );
  }

  // Widget Formulaire d'Inscription
  Widget _buildRegisterForm() {
    return Column(
      key: const ValueKey(1),
      children: [
        const Text("Créer un compte", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 25),
        _buildInputField("NOM COMPLET", Icons.person_outline, "Ex: Jean Mukendi"),
        const SizedBox(height: 15),
        _buildInputField("TÉLÉPHONE", Icons.phone_android, "0820000000"),
        const SizedBox(height: 15),
        _buildInputField("MOT DE PASSE", Icons.lock_outline, "••••••••", isPassword: true),
        const SizedBox(height: 30),
        _buildSubmitButton("S'inscrire"),
      ],
    );
  }

  // Widget Champ de saisie réutilisable
  Widget _buildInputField(String label, IconData icon, String hint, {bool isPassword = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 8),
        TextField(
          obscureText: isPassword && !isPasswordVisible,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.blueGrey.shade300, size: 20),
            suffixIcon: isPassword 
              ? IconButton(
                  icon: Icon(isPasswordVisible ? Icons.visibility : Icons.visibility_off, size: 20),
                  onPressed: () => setState(() => isPasswordVisible = !isPasswordVisible),
                ) 
              : null,
            hintText: hint,
            hintStyle: TextStyle(color: Colors.blueGrey.shade100, fontSize: 14),
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade100),
            ),
          ),
        ),
      ],
    );
  }

  // Widget Bouton de validation
  Widget _buildSubmitButton(String text) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF5B08F), // Couleur orange clair du modèle
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        onPressed: () {},
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
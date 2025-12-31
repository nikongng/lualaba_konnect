import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'registration_form_page.dart';

class AccountChoicePage extends StatefulWidget {
  const AccountChoicePage({super.key});

  @override
  State<AccountChoicePage> createState() => _AccountChoicePageState();
}

class _AccountChoicePageState extends State<AccountChoicePage> {
  // 0: Classique, 1: Pro, 2: Entreprise
  int selectedProfile = 0;

  @override
  Widget build(BuildContext context) {
    // Utilisation de SingleChildScrollView pour permettre le défilement interne
    return SingleChildScrollView(
      key: const ValueKey("account_choice_content"), // Clé pour l'AnimatedSwitcher
      padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- ENTÊTE DE L'ÉTAPE ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "ÉTAPE 1 / 4",
                style: TextStyle(
                  color: Color(0xFFE65100),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Profil", 
                  style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              "Quel est votre profil ?",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              ),
            ),
          ),
          const SizedBox(height: 25),

          // --- LISTE DES PROFILS ---
          _buildProfileCard(
            index: 0,
            title: "Compte Classique",
            subtitle: "Pour les citoyens et particuliers.",
            icon: Icons.account_circle_outlined,
            accentColor: Colors.blue.shade600,
          ),
          _buildProfileCard(
            index: 1,
            title: "Professionnel",
            subtitle: "Indépendants, experts, créateurs.",
            icon: Icons.business_center_outlined,
            accentColor: Colors.purple.shade600,
          ),
          _buildProfileCard(
            index: 2,
            title: "Entreprise",
            subtitle: "Sociétés, ONGs, Commerces.",
            icon: Icons.domain_outlined,
            accentColor: const Color(0xFFE65100),
          ),

          const SizedBox(height: 30),

          // --- BOUTON SUIVANT ---
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RegistrationFormPage(profileType: selectedProfile),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "CONTINUER", 
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.1)
                  ),
                  SizedBox(width: 12),
                  Icon(Icons.arrow_forward_ios, size: 18),
                ],
              ),
            ),
          ),

          const SizedBox(height: 25),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                "En continuant, vous acceptez la Politique de Confidentialité du Lualaba Konnect.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildProfileCard({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    bool isSelected = selectedProfile == index;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => selectedProfile = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withOpacity(0.02) : const Color(0xFFFBFBFB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFE65100) : Colors.grey.shade100,
            width: 2,
          ),
          boxShadow: isSelected 
            ? [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
            : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? accentColor.withOpacity(0.1) : Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isSelected ? accentColor : Colors.grey, size: 24),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle, 
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)
                  ),
                ],
              ),
            ),
            // Radio-button custom
            Container(
              height: 22,
              width: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFFE65100) : Colors.grey.shade300,
                  width: 2,
                ),
                color: isSelected ? const Color(0xFFE65100) : Colors.transparent,
              ),
              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
            ),
          ],
        ),
      ),
    );
  }
}
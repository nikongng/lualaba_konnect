import 'package:flutter/material.dart';

class TrialWelcomePage extends StatelessWidget {
  const TrialWelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Fond orange identique aux autres pages
      backgroundColor: const Color(0xFFE65100),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            // Largeur contrôlée pour ne pas prendre tout l'écran (surtout sur tablette/web)
            constraints: const BoxConstraints(maxWidth: 400),
            margin: const EdgeInsets.symmetric(horizontal: 25),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min, // S'adapte au contenu
              children: [
                // Icône Cadeau stylisée
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.card_giftcard_rounded,
                    size: 60,
                    color: Color(0xFFE65100),
                  ),
                ),
                const SizedBox(height: 25),

                // Titre
                const Text(
                  "Félicitations !",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE65100),
                  ),
                ),
                const SizedBox(height: 15),

                // Description
                const Text(
                  "Votre compte est prêt. Pour découvrir l'application, nous vous offrons :",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey, height: 1.4),
                ),
                const SizedBox(height: 25),

                // Badge vert (15 jours)
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded, color: Colors.green),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "15 JOURS D'ESSAI",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900,
                              ),
                            ),
                            const Text(
                              "Accès complet gratuit",
                              style: TextStyle(fontSize: 12, color: Colors.green),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 35),

                // Bouton Principal (Lancer l'app)
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () {
                      // Action : Vers le Dashboard
                      print("Vers le Dashboard");
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "PROFITER DE L'ESSAI",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // Bouton Secondaire (Payer)
                TextButton(
                  onPressed: () {
                    // Action : Flux de paiement
                    print("Payer maintenant");
                  },
                  child: const Text(
                    "Activer l'abonnement (10\$ / an)",
                    style: TextStyle(
                      color: Color(0xFFE65100),
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
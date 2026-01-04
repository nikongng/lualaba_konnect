import 'package:flutter/material.dart';

class RapidServicesPage extends StatelessWidget {
  const RapidServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // Fond gris très clair comme sur ton image
      appBar: AppBar(
        backgroundColor: const Color(0xFF2962FF), // Le bleu de ton catalogue
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Catalogue Services", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Bleu avec Barre de recherche
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF2962FF),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const TextField(
                  decoration: InputDecoration(
                    hintText: "Quel service cherchez-vous ?",
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                    icon: Icon(Icons.search, color: Colors.white),
                  ),
                ),
              ),
            ),
            
Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMainServiceCard("Freelance & Pros", "Plombier, Tech, Maçon...", Icons.person_search_rounded, const Color(0xFF0D1B2A)),
                  const SizedBox(height: 25),
                  
                  _buildSectionTitle("✨ MAISON & QUOTIDIEN"),
                  _buildServiceItem("Ménage & Aide", "Nounou, Jardinier, Vigile", Icons.auto_awesome_outlined, Colors.blue.shade100, Colors.blue),
                  _buildServiceItem("Repas", "Livraison Express", Icons.restaurant_rounded, Colors.orange.shade100, Colors.orange),
                  _buildServiceItem("Factures", "SNEL, Eau, TV, Net", Icons.account_balance_wallet_outlined, Colors.yellow.shade100, Colors.orangeAccent),
                  
                  const SizedBox(height: 25),
                  _buildSectionTitle("🚗 MOBILITÉ & AUTO"),
                  _buildServiceItem("Mobilité", "Taxi, Location, Auto", Icons.directions_car_filled_outlined, Colors.indigo.shade100, Colors.indigo),
                  _buildServiceItem("Dépannage & Auto", "Garage, Mécanicien, Pneus", Icons.build_circle_outlined, Colors.blueGrey.shade100, Colors.blueGrey),

                  // --- SECTION AJOUTÉE : LIFESTYLE & PRO ---
                  const SizedBox(height: 25),
                  _buildSectionTitle("💼 LIFESTYLE & PRO"),
                  _buildServiceItem("Formation", "Cours, Soutien, Pro", Icons.school_outlined, Colors.green.shade100, Colors.green),
                  _buildServiceItem("Événements", "DJ, Traiteur, Déco", Icons.music_note_outlined, Colors.pink.shade100, Colors.pink),
                  _buildServiceItem("Administration", "Documents, Taxes, RDV", Icons.account_balance_outlined, Colors.grey.shade200, Colors.blueGrey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15, left: 5),
      child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
    );
  }

  Widget _buildMainServiceCard(String title, String sub, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(sub, style: const TextStyle(color: Colors.grey)),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.black26),
        ],
      ),
    );
  }

  Widget _buildServiceItem(String title, String sub, IconData icon, Color bgColor, Color iconColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black12),
        ],
      ),
    );
  }
}
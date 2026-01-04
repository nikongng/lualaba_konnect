import 'package:flutter/material.dart';

class TipsPage extends StatelessWidget {
  const TipsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00A88E), // Le vert de ton bouton Santé
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Conseils Utiles", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // --- CARTE CONSEIL DU JOUR (HIGHLIGHT) ---
          _buildHighlightCard(),

          // --- FILTRES (CHIPS) ---
          _buildFilterChips(),

          // --- LISTE DES CONSEILS ---
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildTipCard(
                  category: "SÉCURITÉ",
                  title: "Poussière sur la route",
                  desc: "La route vers Musompo est très poussiéreuse en ce moment. Le port du masque est recommandé...",
                  icon: Icons.engineering_rounded,
                  iconBg: Colors.orange.shade50,
                  iconColor: Colors.orange,
                ),
                _buildTipCard(
                  category: "TECH",
                  title: "Économiser sa batterie",
                  desc: "En zone de faible réseau (H+), votre téléphone consomme 2x plus. Basculez en mode économie...",
                  icon: Icons.battery_charging_full_rounded,
                  iconBg: Colors.blue.shade50,
                  iconColor: Colors.blue,
                ),
                _buildTipCard(
                  category: "VIE PRATIQUE",
                  title: "Coupures d'eau",
                  desc: "Des travaux sont signalés sur le réseau REGIDESO quartier Joli Site. Pensez à faire des réserves...",
                  icon: Icons.water_drop_outlined,
                  iconBg: Colors.cyan.shade50,
                  iconColor: Colors.cyan,
                ),
                const SizedBox(height: 80), // Espace pour le bouton du bas
              ],
            ),
          ),
        ],
      ),
      // --- BOUTON PROPOSER UNE ASTUCE ---
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _buildProposeButton(),
    );
  }

  Widget _buildHighlightCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: const Color(0xFFE0F2F1), borderRadius: BorderRadius.circular(10)),
                child: const Text("CONSEIL DU JOUR", style: TextStyle(color: Color(0xFF00A88E), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const Icon(Icons.share_outlined, color: Colors.grey, size: 20),
            ],
          ),
          const SizedBox(height: 15),
          const Text("Pic de chaleur prévu", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            "Aujourd'hui, la température ressentie atteindra 32°C. Buvez au moins 2L d'eau et évitez l'exposition directe.",
            style: TextStyle(color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 15),
          const Row(
            children: [
              Icon(Icons.wb_sunny_outlined, size: 14, color: Colors.orange),
              Text(" Aujourd'hui • Météo", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ["Tout", "Santé", "Sécurité", "Tech", "Vie Pratique"];
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          bool isFirst = index == 0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Chip(
              backgroundColor: isFirst ? const Color(0xFF00A88E) : Colors.white,
              label: Text(filters[index], style: TextStyle(color: isFirst ? Colors.white : Colors.black54)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade200)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTipCard({required String category, required String title, required String desc, required IconData icon, required Color iconBg, required Color iconColor}) {
    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(category, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    const Icon(Icons.bookmark_border, size: 18, color: Colors.grey),
                  ],
                ),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProposeButton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF00A88E),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: Colors.white),
          const SizedBox(width: 10),
          const Expanded(
            child: Text("Vous avez une astuce ? Partagez-la avec la communauté", style: TextStyle(color: Colors.white, fontSize: 11)),
          ),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF00A88E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Proposer"),
          ),
        ],
      ),
    );
  }
}
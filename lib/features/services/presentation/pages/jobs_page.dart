import 'package:flutter/material.dart';

class JobsPage extends StatefulWidget {
  const JobsPage({super.key});

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF9D59FF), // Violet correspondant à ton image
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Emploi & Annonce", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // --- HEADER VIOLET ---
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF9D59FF),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
            ),
            child: Column(
              children: [
                // Barre de recherche
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                  child: const TextField(
                    decoration: InputDecoration(
                      hintText: "Job, terrain, vente...",
                      border: InputBorder.none,
                      icon: Icon(Icons.search, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Actions Rapides
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildQuickAction(Icons.description_outlined, "CV Express"),
                    _buildQuickAction(Icons.business_center_outlined, "Déposer Job"),
                    _buildQuickAction(Icons.campaign_outlined, "Publier Annonce"),
                  ],
                ),
              ],
            ),
          ),

          // --- ONGLET DE SÉLECTION (TABS) ---
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              height: 50,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(color: const Color(0xFF0D1B2A), borderRadius: BorderRadius.circular(25)),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                tabs: const [Tab(text: "Offres d'emploi"), Tab(text: "Petites Annonces")],
              ),
            ),
          ),

          // --- LISTE DES OFFRES ---
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildJobsList(),
                const Center(child: Text("Aucune annonce pour le moment")),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }

  Widget _buildJobsList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _buildJobCard("Vendeuse Boutique", "LUBUM MODE", "250\$", "Centre-Ville", "Temps plein", "Hier"),
        _buildJobCard("Chauffeur Privé", "PARTICULIER", "Sur devis", "Golf", "Temps partiel", "Aujourd'hui", isUrgent: true),
      ],
    );
  }

  Widget _buildJobCard(String title, String company, String salary, String location, String type, String date, {bool isUrgent = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isUrgent ? Colors.red.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(date, style: TextStyle(color: isUrgent ? Colors.red : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(Icons.business, size: 16, color: Color(0xFF9D59FF)),
              const SizedBox(width: 5),
              Text(company, style: const TextStyle(color: Color(0xFF9D59FF), fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
              Text(" $location  •  ", style: const TextStyle(color: Colors.grey)),
              Icon(Icons.access_time, size: 14, color: Colors.grey),
              Text(" $type", style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(salary, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D1B2A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Postuler", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
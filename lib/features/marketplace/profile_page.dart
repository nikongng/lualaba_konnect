import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'orders_page.dart';
import 'favorites_page.dart';

class ProfilePage extends StatefulWidget {
  final List<Map<String, dynamic>> allProducts;
  final Set<String> favoriteIds;

  const ProfilePage({
    super.key,
    required this.allProducts,
    required this.favoriteIds,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final user = FirebaseAuth.instance.currentUser;
  double _totalSales = 0;
  int _orderCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  /// Calcule les statistiques de vente en filtrant les commandes "Livrées"
  Future<void> _loadStats() async {
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('market_orders')
          .get();

      double total = 0;
      int count = 0;

      for (var doc in snap.docs) {
        final data = doc.data();
        final items = List.from(data['items'] ?? []);
        
        // On vérifie si l'utilisateur actuel est le vendeur d'au moins un article
        bool isSeller = items.any((it) => (it['owner'] ?? it['ownerUid']) == user!.uid);
        
        if (isSeller) {
          count++;
          // On ne compte dans le chiffre d'affaires que ce qui est payé/livré
          if (data['status'] == 'livré' || data['status'] == 'completed') {
            total += (data['total'] ?? 0).toDouble();
          }
        }
      }

      if (mounted) {
        setState(() {
          _totalSales = total;
          _orderCount = count;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erreur statistiques profil: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.orange.shade900,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Mon Profil", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildStatsRow(),
                  const SizedBox(height: 30),
                  
                  // MENU : MES COMMANDES
                  _buildMenuTile(
                    icon: Icons.receipt_long_rounded,
                    title: "Mes Commandes",
                    subtitle: "Suivi de mes achats et ventes",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OrdersPage()),
                    ),
                  ),

                  // MENU : MES FAVORIS
                  _buildMenuTile(
                    icon: Icons.favorite_rounded,
                    title: "Mes Favoris",
                    subtitle: "${widget.favoriteIds.length} articles enregistrés",
                    badgeCount: widget.favoriteIds.length,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FavoritesPage(
                          allProducts: widget.allProducts,
                          favoriteIds: widget.favoriteIds,
                        ),
                      ),
                    ),
                  ),

                  // MENU : PARAMÈTRES
                  _buildMenuTile(
                    icon: Icons.settings_rounded,
                    title: "Paramètres",
                    subtitle: "Compte, Sécurité, Notifications",
                    onTap: () {
                      // Action pour les paramètres
                    },
                  ),
                  
                  const SizedBox(height: 40),
                  const Text(
                    "Market Pro v1.0.2",
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(bottom: 30),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.orange.shade900,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          CircleAvatar(
            radius: 45,
            backgroundColor: Colors.white,
            child: Text(
              user?.email?.substring(0, 1).toUpperCase() ?? "U",
              style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            user?.email ?? "Utilisateur",
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "Vendeur Vérifié",
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCard("Revenus", "${_totalSales.toStringAsFixed(0)} FC", Colors.green),
        const SizedBox(width: 15),
        _buildStatCard("Activités", "$_orderCount", Colors.blue),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            if (_isLoading)
              SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
            else
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.orange.shade900, size: 22),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Text("$badgeCount", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
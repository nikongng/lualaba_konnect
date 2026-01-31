import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Historique'),
        backgroundColor: Colors.orange.shade800,
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Achats'), Tab(text: 'Ventes')]),
      ),
      body: TabBarView(controller: _tabController, children: [
        _buildPurchases(),
        _buildSales(),
      ]),
    );
  }

  Widget _buildPurchases() {
    if (user == null) return const Center(child: Text('Connectez-vous pour voir vos achats'));
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('market_orders').where('buyerUid', isEqualTo: user!.uid).orderBy('createdAt', descending: true).snapshots(),
      builder: (c, s) {
        if (s.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: Colors.orange));
        final docs = s.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('Aucun achat trouvé'));
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i].data() as Map<String, dynamic>;
            final created = (docs[i].get('createdAt') as Timestamp?)?.toDate();
            return ListTile(
              title: Text('Commande • ${doc['total'] ?? ''}'),
              subtitle: Text('Statut: ${doc['status'] ?? ''} • ${created != null ? created.toLocal().toString().split('.').first : ''}'),
            );
          },
        );
      },
    );
  }

  Widget _buildSales() {
    if (user == null) return const Center(child: Text('Connectez-vous pour voir vos ventes'));
    // Combine sold products from market_products and deleted items from orders
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('market_products').where('owner', isEqualTo: user!.uid).snapshots(),
      builder: (cProd, sProd) {
        if (sProd.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: Colors.orange));
        final prodDocs = sProd.data?.docs ?? [];

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('market_orders').orderBy('createdAt', descending: true).snapshots(),
          builder: (cOrd, sOrd) {
            if (sOrd.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: Colors.orange));
            final ordDocs = sOrd.data?.docs ?? [];

            // Sold products (from products collection)
            final soldProducts = prodDocs.where((p) {
              final d = p.data() as Map<String, dynamic>;
              return (d['sold'] ?? false) == true;
            }).toList();

            // Deleted items from orders where seller is current user
            final List<Map<String, dynamic>> deletedItems = [];
            for (final od in ordDocs) {
              try {
                final odData = od.data() as Map<String, dynamic>;
                final items = List.from(odData['items'] ?? []);
                for (final it in items) {
                  if ((it['owner'] ?? it['ownerUid']) == user!.uid && (it['deleted'] ?? false) == true) {
                    deletedItems.add({...Map<String, dynamic>.from(it), 'orderId': od.id, 'orderCreatedAt': odData['createdAt']});
                  }
                }
              } catch (_) {}
            }

            if (soldProducts.isEmpty && deletedItems.isEmpty) {
              // also check archived history collection
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('market_products_history').where('owner', isEqualTo: user!.uid).snapshots(),
                builder: (cHist, sHist) {
                  if (sHist.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: Colors.orange));
                  final histDocs = sHist.data?.docs ?? [];
                  if (histDocs.isEmpty) return const Center(child: Text('Aucun historique trouvé'));
                  final List<Widget> ch = [];
                  ch.add(Padding(padding: const EdgeInsets.all(16), child: Text('Historique archivés', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.grey.shade700))));
                  for (final h in histDocs) {
                    final d = h.data() as Map<String, dynamic>;
                    ch.add(ListTile(title: Text(d['name'] ?? ''), subtitle: Text('Statut: ${d['status'] ?? ''}')));
                  }
                  return ListView(children: ch);
                }
              );
            }

            final List<Widget> children = [];
            if (soldProducts.isNotEmpty) {
              children.add(Padding(padding: const EdgeInsets.all(16), child: Text('Produits vendus', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.orange.shade800))));
              for (final p in soldProducts) {
                final d = p.data() as Map<String, dynamic>;
                children.add(ListTile(
                  leading: d['images'] is List && (d['images'] as List).isNotEmpty ? Image.network(d['images'][0], width: 56, height: 56, fit: BoxFit.cover) : null,
                  title: Text(d['name'] ?? ''),
                  subtitle: Text('Statut: VENDU • ${d['category'] ?? ''}'),
                ));
              }
            }

            if (deletedItems.isNotEmpty) {
              children.add(Padding(padding: const EdgeInsets.all(16), child: Text('Produits supprimés', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.grey.shade700))));
              for (final it in deletedItems) {
                children.add(ListTile(
                  title: Text('${it['name'] ?? ''} (supprimé)'),
                  subtitle: Text('Commande: ${it['orderId'] ?? ''}'),
                ));
              }
            }

            return ListView(children: children);
          },
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'product_detail_page.dart';
import 'product_create_page.dart';
// import 'package:intl/intl.dart'; // Optionnel pour formater les dates (unused)

class OrdersPage extends StatefulWidget {
  final String? orderId;
  const OrdersPage({super.key, this.orderId}); // Utilisation du super parameter

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<QueryDocumentSnapshot> _orders = [];
  String? _uid;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('market_orders')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      if (mounted) {
        setState(() {
          _orders = snap.docs;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Erreur chargement commandes: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  // Détermine si l'utilisateur doit voir cette commande (soit il a acheté, soit il vend)
  bool _orderRelevant(QueryDocumentSnapshot doc) {
    if (_uid == null) return false;
    final data = doc.data() as Map<String, dynamic>;
    if ((data['buyerUid'] ?? '') == _uid) return true;
    final items = List.from(data['items'] ?? []);
    for (final it in items) {
      if ((it['owner'] ?? it['ownerUid']) == _uid) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text('Mes Commandes', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          tabs: const [Tab(text: 'Achats'), Tab(text: 'Ventes')],
        ),
      ),
        body: _loading
          ? Center(child: CircularProgressIndicator(color: Colors.orange))
          : TabBarView(controller: _tabController, children: [_buildPurchasesList(), _buildSalesList()]),
    );
  }

  Widget _buildPurchasesList() {
    final purchases = widget.orderId != null
        ? _orders.where((d) => d.id == widget.orderId && (d.data() as Map<String, dynamic>)['buyerUid'] == _uid).toList()
        : _orders.where((d) => (d.data() as Map<String, dynamic>)['buyerUid'] == _uid).toList();

    if (purchases.isEmpty) return _buildEmptyState();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: purchases.length,
      itemBuilder: (c, i) => _buildOrderCard(purchases[i]),
    );
  }

  Widget _buildSalesList() {
    // Affiche produits publiés ET ventes (commandes où l'utilisateur est vendeur)
    if (_uid == null) return _buildEmptyState();

    return StreamBuilder<QuerySnapshot>(
      // Avoid ordering here to prevent transient ordering/index issues while createdAt is null on client
      stream: FirebaseFirestore.instance.collection('market_products').where('owner', isEqualTo: _uid).snapshots(),
      builder: (cProd, sProd) {
        if (sProd.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: Colors.orange));
        final prodDocs = sProd.data?.docs ?? [];
        // Debug: log received product ids and owner values
        for (final pd in prodDocs) {
          try {
            final m = pd.data() as Map<String, dynamic>;
            debugPrint('product doc=${pd.id} owner=${m['owner']} createdAt=${m['createdAt']}');
          } catch (e) {
            debugPrint('product doc=${pd.id} cannot parse data: $e');
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('market_orders').orderBy('createdAt', descending: true).snapshots(),
          builder: (cOrd, sOrd) {
            if (sOrd.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: Colors.orange));
            final ordDocs = sOrd.data?.docs ?? [];

            // Filtrer les commandes où l'utilisateur est vendeur d'au moins un item
            final salesOrders = ordDocs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              final items = List.from(data['items'] ?? []);
              return items.any((it) => (it['owner'] ?? it['ownerUid']) == _uid);
            }).toList();

            if (prodDocs.isEmpty && salesOrders.isEmpty) return _buildEmptyState();

            // Construire une liste combinée (produits puis ventes)
            final List<Widget> children = [];
            // Build set of purchased product ids from orders
            final Set<String> purchasedIds = {};
            for (final od in ordDocs) {
              try {
                final data = od.data() as Map<String, dynamic>;
                final items = List.from(data['items'] ?? []);
                for (final it in items) {
                  final id = it['id'];
                  if (id != null) purchasedIds.add(id.toString());
                }
              } catch (_) {}
            }

            if (prodDocs.isNotEmpty) {
              children.add(Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Produits publiés', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.orange.shade800)),
              ));
              for (final doc in prodDocs) {
                final d = doc.data() as Map<String, dynamic>;
                // Skip products that are sold or already purchased
                if ((d['sold'] ?? false) == true) continue;
                if (purchasedIds.contains(doc.id)) continue;
                final images = d['images'] as List? ?? [];
                // Product tile with publication datetime and action buttons
                final created = d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null;
                final createdStr = created != null ? created.toLocal().toString().split('.').first : '—';

                children.add(Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: SizedBox(
                      width: 56,
                      height: 56,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: images.isNotEmpty
                                ? Image.network(images[0], width: 56, height: 56, fit: BoxFit.cover)
                                : Container(width: 56, height: 56, color: Colors.grey.shade200),
                          ),
                          // sold badge
                          if ((d['sold'] ?? false) == true || d['soldAt'] != null)
                            Positioned(
                              top: 2,
                              left: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(6)),
                                child: const Text('VENDU', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    title: Text(d['name'] ?? 'Produit', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Prix: ${d['price'] ?? ''} ${d['currency'] ?? 'FC'} • ${d['category'] ?? ''}'),
                        const SizedBox(height: 4),
                        Text('Publié: $createdStr', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Compact actions menu to prevent overflow
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20),
                          onSelected: (v) {
                            if (v == 'edit') Navigator.push(context, MaterialPageRoute(builder: (_) => ProductCreatePage(product: doc.data() as Map<String, dynamic>, docId: doc.id)));
                            if (v == 'delete') _confirmDeleteProduct(doc.id);
                            if (v == 'sold') _markProductSold(doc.id);
                            if (v == 'renew') _renewProduct(doc.id);
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                            const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                            const PopupMenuItem(value: 'sold', child: Text('Marquer vendu')),
                            const PopupMenuItem(value: 'renew', child: Text('Renouveller l\'annonce')),
                          ],
                        )
                      ],
                    ),
                    onTap: () {
                      final map = Map<String, dynamic>.from(d);
                      map['id'] = doc.id;
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: map)));
                    },
                  ),
                ));
                children.add(const Divider(height: 0));
              }
            }

            if (salesOrders.isNotEmpty) {
              children.add(Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text('Ventes (commandes)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.orange.shade800)),
              ));
              for (final doc in salesOrders) {
                children.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildOrderCard(doc)));
              }
            }

            return ListView(
              children: children,
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text("Aucune commande pour le moment", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildOrderCard(QueryDocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;
    final bool isBuyer = data['buyerUid'] == _uid;
    final String status = data['status'] ?? 'en attente';
    final List items = List.from(data['items'] ?? []);
    final double total = (data['total'] ?? 0).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showOrderDetails(d.id, data),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicateur Achat ou Vente
                  Row(
                    children: [
                      Icon(
                        isBuyer ? Icons.shopping_bag_outlined : Icons.sell_outlined,
                        size: 18,
                        color: isBuyer ? Colors.blue : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isBuyer ? "ACHAT" : "VENTE",
                        style: TextStyle(
                          fontSize: 12, 
                          fontWeight: FontWeight.w900, 
                          color: isBuyer ? Colors.blue : Colors.green
                        ),
                      ),
                    ],
                  ),
                  _buildStatusBadge(status),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Container(
                    height: 50, width: 50,
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.inventory_2_outlined, color: Colors.orange),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Commande #${d.id.substring(0, 8).toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text("${items.length} article(s)", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  Text("$total ${data['currency'] ?? 'FC'}", 
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    final s = (status ?? '').toLowerCase();
    Color color;
    switch (s) {
      case 'pending':
      case 'en attente':
        color = Colors.orange;
        break;
      case 'completed':
      case 'livré':
        color = Colors.green;
        break;
      case 'cancelled':
      case 'annulé':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    final display = (status ?? 'pending').toString().toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(
        display,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
void _showOrderDetails(String orderDocId, Map<String, dynamic> data) {
    final items = List.from(data['items'] ?? []);
    final String currentStatus = data['status'] ?? 'pending';
    
    // On vérifie si l'utilisateur actuel possède au moins un article dans cette commande
    bool isSellerOfAnyItem = items.any((it) => (it['owner'] ?? it['ownerUid']) == _uid);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Détails Commande", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      _buildStatusBadge(currentStatus),
                    ],
                  ),
                  const Divider(height: 32),

                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final it = items[i];
                        final bool itemSold = (it['sold'] ?? false) == true || it['soldAt'] != null;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Row(
                            children: [
                              Expanded(child: Text(it['name'] ?? 'Produit', style: const TextStyle(fontWeight: FontWeight.bold))),
                              if (itemSold)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(6)),
                                  child: const Text('VENDU', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          subtitle: Text("Qté: ${it['quantity'] ?? 1}"),
                          trailing: Text("${it['price']} ${data['currency']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
                  ),

                  // --- SECTION ACTIONS DU VENDEUR ---
                  if (isSellerOfAnyItem && (currentStatus == 'pending' || currentStatus == 'en attente')) ...[
                    const Text("Action Vendeur", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => _updateOrderStatus(orderDocId, 'annulé'),
                            child: const Text("ANNULER"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => _updateOrderStatus(orderDocId, 'livré'),
                            child: const Text("MARQUER LIVRÉ"),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("TOTAL", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                      Text("${data['total']} ${data['currency']}", 
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.orange.shade800)),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- LOGIQUE DE MISE À JOUR FIREBASE ---
  Future<void> _updateOrderStatus(String docId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('market_orders')
          .doc(docId)
          .update({'status': newStatus});
      
      if (mounted) {
        Navigator.pop(context); // Ferme le BottomSheet
        _load(); // Recharge la liste
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Statut mis à jour : $newStatus"), backgroundColor: Colors.teal)
        );
      }
    } catch (e) {
      debugPrint("Erreur update: $e");
    }
  }

  // --- PRODUITS: actions edit/delete/mark sold ---
  Future<void> _confirmDeleteProduct(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la publication'),
        content: const Text('Confirmer la suppression de cette annonce ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      try {
        // Read product data
        final prodRef = FirebaseFirestore.instance.collection('market_products').doc(docId);
        final prodSnap = await prodRef.get();
        final prodData = prodSnap.exists ? prodSnap.data() as Map<String, dynamic> : null;

        // Archive into history collection before deletion
        if (prodData != null) {
          final historyData = {
            'originalId': docId,
            'archivedAt': FieldValue.serverTimestamp(),
            'status': 'deleted',
            ...prodData,
          };
          await FirebaseFirestore.instance.collection('market_products_history').add(historyData);
        }

        // Delete from marketplace
        await prodRef.delete();

        // Propager la suppression dans les commandes: marquer l'item comme supprimé
        try {
          final ordersSnap = await FirebaseFirestore.instance.collection('market_orders').get();
          for (final od in ordersSnap.docs) {
            final odData = od.data();
            final items = List.from(odData['items'] ?? []);
            bool changed = false;
            final updatedItems = items.map((it) {
              try {
                if (it['id'] == docId) {
                  changed = true;
                  return {
                    ...Map<String, dynamic>.from(it),
                    'deleted': true,
                    'name': '${it['name'] ?? 'Produit'} (supprimé)'
                  };
                }
              } catch (_) {}
              return it;
            }).toList();

            if (changed) {
              await FirebaseFirestore.instance.collection('market_orders').doc(od.id).update({'items': updatedItems});
            }
          }
        } catch (e) {
          debugPrint('Erreur propagation suppression aux commandes: $e');
        }

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Publication supprimée'), backgroundColor: Colors.teal));
      } catch (e) {
        debugPrint('Erreur delete product: $e');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur suppression'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _markProductSold(String docId) async {
    try {
      await FirebaseFirestore.instance.collection('market_products').doc(docId).update({
        'sold': true,
        'soldAt': FieldValue.serverTimestamp(),
      });
      // Propager le statut 'vendu' dans les commandes contenant cet article
      try {
        final ordersSnap = await FirebaseFirestore.instance.collection('market_orders').get();
        for (final od in ordersSnap.docs) {
          final odData = od.data();
          final items = List.from(odData['items'] ?? []);
          bool changed = false;
          final updatedItems = items.map((it) {
            try {
              if (it['id'] == docId) {
                changed = true;
                return {
                  ...Map<String, dynamic>.from(it),
                  'sold': true,
                  'soldAt': Timestamp.now(),
                };
              }
            } catch (_) {}
            return it;
          }).toList();

          if (changed) {
            await FirebaseFirestore.instance.collection('market_orders').doc(od.id).update({'items': updatedItems});
          }
        }
      } catch (e) {
        debugPrint('Erreur propagation vendu aux commandes: $e');
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marqué comme vendu'), backgroundColor: Colors.teal));
    } catch (e) {
      debugPrint('Erreur mark sold: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur'), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _renewProduct(String docId) async {
    try {
      await FirebaseFirestore.instance.collection('market_products').doc(docId).update({
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Annonce renouvelée'), backgroundColor: Colors.teal));
    } catch (e) {
      debugPrint('Erreur renew product: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur'), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _editProductDialog(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final priceCtrl = TextEditingController(text: (data['price'] ?? '').toString());
    final stockCtrl = TextEditingController(text: (data['stock'] ?? '').toString());

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier la publication'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Titre')),
          TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Prix'), keyboardType: TextInputType.number),
          TextField(controller: stockCtrl, decoration: const InputDecoration(labelText: 'Stock'), keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
        ],
      ),
    );

    if (res == true) {
      try {
        await FirebaseFirestore.instance.collection('market_products').doc(doc.id).update({
          'name': nameCtrl.text.trim(),
          'price': double.tryParse(priceCtrl.text) ?? data['price'] ?? 0,
          'stock': int.tryParse(stockCtrl.text) ?? data['stock'] ?? 0,
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Publication modifiée'), backgroundColor: Colors.teal));
        
        // --- Mettre à jour les commandes contenant ce produit (propager les modifications)
        try {
          final ordersSnap = await FirebaseFirestore.instance.collection('market_orders').get();
          for (final od in ordersSnap.docs) {
            final odData = od.data();
            final items = List.from(odData['items'] ?? []);
            bool changed = false;
            final updatedItems = items.map((it) {
              try {
                if (it['id'] == doc.id) {
                  changed = true;
                  return {
                    ...Map<String, dynamic>.from(it),
                    'name': nameCtrl.text.trim(),
                    'price': double.tryParse(priceCtrl.text) ?? it['price'] ?? 0,
                    // update image if product has images
                    'image': (data['images'] is List && (data['images'] as List).isNotEmpty) ? (data['images'][0]) : it['image'],
                  };
                }
              } catch (_) {}
              return it;
            }).toList();

            if (changed) {
              await FirebaseFirestore.instance.collection('market_orders').doc(od.id).update({'items': updatedItems});
            }
          }
        } catch (e) {
          debugPrint('Erreur propagation modification aux commandes: $e');
        }
      } catch (e) {
        debugPrint('Erreur edit product: $e');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur modification'), backgroundColor: Colors.redAccent));
      }
    }
  }
}
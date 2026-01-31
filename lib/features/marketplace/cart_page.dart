import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cart_service.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _delivery = 'Retrait';
  String _payment = 'Orange';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _items = await CartService.instance.getItems();
    setState(() { _loading = false; });
  }

  Future<void> _changeQty(String id, int delta) async {
    await CartService.instance.changeItemQuantity(id, delta);
    await _load();
  }

  double get _total {
    double t = 0.0;
    for (var it in _items) {
      final priceRaw = (it['price'] ?? '').toString().replaceAll(RegExp(r'[^0-9\.]'), '');
      final price = double.tryParse(priceRaw) ?? 0.0;
      t += price * (it['quantity'] as int? ?? 1);
    }
    return t;
  }

  Widget _paymentChip(String name, Color color, {Color textColor = Colors.white}) {
    final selected = _payment == name;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _payment = name),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: selected ? color : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Text(name, style: TextStyle(color: selected ? textColor : Colors.black87)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: const Text('Mon Panier'), backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.black)),
      body: _loading ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)) : _items.isEmpty ? const Center(child: Text('Panier vide')) : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Items
              ..._items.map((it) => Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(width: 80, height: 80, child: CachedNetworkImage(imageUrl: it['image'] ?? '', fit: BoxFit.cover, placeholder: (c,s)=>Container(color:Colors.grey.shade200))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text(it['price'] ?? '', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 8),
                                  Row(children: [
                                    IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _changeQty(it['id'], -1)),
                                    Text('${it['quantity']}'),
                                    IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _changeQty(it['id'], 1)),
                                  ])
                              ],
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerLeft, child: Text('Discuter avec ${it['sellerName'] ?? 'le vendeur'}', style: TextStyle(color: Colors.black54))),
                    ],
                  ),
                ),
              )),

              const SizedBox(height: 8),

              // Delivery toggle
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _delivery = 'Retrait'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _delivery == 'Retrait' ? Colors.white : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [Icon(Icons.store), SizedBox(width: 8), Text('Retrait')],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _delivery = 'Livraison'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _delivery == 'Livraison' ? Colors.white : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [const Icon(Icons.local_shipping), const SizedBox(width: 8), const Text('Livraison (+5\$)')],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      const Text('MOYEN DE PAIEMENT', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(children: [
                        _paymentChip('Airtel', Colors.red.shade300),
                        const SizedBox(width: 8),
                        _paymentChip('Orange', Colors.orange.shade400),
                        const SizedBox(width: 8),
                        _paymentChip('M-Pesa', Colors.green.shade400),
                        const SizedBox(width: 8),
                        _paymentChip('Cash', Colors.grey.shade200, textColor: Colors.black87),
                      ])
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Sous-total'), Text('${_total.toStringAsFixed(0)} FC')]),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), Text('${_total.toStringAsFixed(0)} FC', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: _total <= 0 || _creatingOrder ? null : () async { await _createOrder(); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _creatingOrder ? CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary) : Text('Payer avec $_payment', style: const TextStyle(fontSize: 16)))),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  bool _creatingOrder = false;

  Future<void> _createOrder() async {
    setState(() { _creatingOrder = true; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez vous connecter pour acheter')));
        return;
      }

      // Refresh items to ensure latest quantities
      final items = await CartService.instance.getItems();
      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Panier vide')));
        return;
      }

      final firestore = FirebaseFirestore.instance;

      // Transaction: verify stock and decrement
      await firestore.runTransaction((tx) async {
        for (var it in items) {
          final id = it['id']?.toString();
          final qty = it['quantity'] as int? ?? 1;
          if (id == null || id.trim().isEmpty) continue; // skip non-store items
          final docRef = firestore.collection('market_products').doc(id);
          final snapshot = await tx.get(docRef);
          if (!snapshot.exists) throw Exception('Produit introuvable: ${it['name']}');
          final stock = (snapshot.data()?['stock'] is int) ? snapshot.data()!['stock'] as int : int.tryParse(snapshot.data()?['stock']?.toString() ?? '0') ?? 0;
          if (stock < qty) throw Exception('Stock insuffisant pour ${it['name']}');
          tx.update(docRef, {'stock': stock - qty});
        }
      });

      // Create order document
      final order = {
        'buyerUid': user.uid,
        'items': items.map((e) => {
          'id': e['id'], 'name': e['name'], 'price': e['price'], 'quantity': e['quantity'] ?? 1, 'image': e['image']
        }).toList(),
        'total': _total,
        'delivery': _delivery,
        'payment': _payment,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      };
      await firestore.collection('market_orders').add(order);

      // clear cart
      await CartService.instance.clear();
      await _load();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commande créée avec succès')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur commande: $e')));
    } finally {
      if (mounted) setState(() { _creatingOrder = false; });
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'health_user_context.dart';

class HealthPharmacyPage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthPharmacyPage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthPharmacyPage> createState() => _HealthPharmacyPageState();
}

class _HealthPharmacyPageState extends State<HealthPharmacyPage> {
  final Map<String, _CartItem> _cart = {};
  String _query = '';
  bool _loadingUser = true;
  bool _canAddProducts = false;
  String _sellerName = '';

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final snap = await widget.contextRef.userRef.get();
      final data = snap.data() ?? <String, dynamic>{};
      final profileType = data['profileType'] is int ? data['profileType'] as int : null;
      final first = (data['firstName'] ?? '').toString().trim();
      final last = (data['lastName'] ?? '').toString().trim();
      final full = ('$first $last').trim();
      _sellerName = full.isNotEmpty ? full : (data['name'] ?? '').toString().trim();
      _canAddProducts = profileType == 1 || profileType == 2;
    } catch (_) {}
    if (mounted) setState(() => _loadingUser = false);
  }

  CollectionReference<Map<String, dynamic>> get _productsRef =>
      FirebaseFirestore.instance.collection('pharmacy_products');

  void _addToCart(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final name = (data['name'] ?? '').toString();
    final price = (data['price'] is num) ? (data['price'] as num).toDouble() : double.tryParse('${data['price']}') ?? 0;
    final currency = (data['currency'] ?? 'USD').toString();
    if (_cart.containsKey(doc.id)) {
      _cart[doc.id] = _cart[doc.id]!.copyWith(qty: _cart[doc.id]!.qty + 1);
    } else {
      _cart[doc.id] = _CartItem(
        docId: doc.id,
        name: name,
        price: price,
        currency: currency,
        qty: 1,
      );
    }
    setState(() {});
  }

  void _removeFromCart(String id) {
    if (!_cart.containsKey(id)) return;
    final item = _cart[id]!;
    if (item.qty <= 1) {
      _cart.remove(id);
    } else {
      _cart[id] = item.copyWith(qty: item.qty - 1);
    }
    setState(() {});
  }

  double _cartTotal() {
    double total = 0;
    for (final item in _cart.values) {
      total += item.price * item.qty;
    }
    return total;
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final items = _cart.values
        .map((e) => {
              'productId': e.docId,
              'name': e.name,
              'price': e.price,
              'currency': e.currency,
              'qty': e.qty,
              'total': e.price * e.qty,
            })
        .toList();

    final total = _cartTotal();
    await FirebaseFirestore.instance.collection('pharmacy_orders').add({
      'buyerUid': widget.contextRef.userId,
      'buyerName': _sellerName,
      'items': items,
      'total': total,
      'currency': _cart.values.isNotEmpty ? _cart.values.first.currency : 'USD',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    final batch = FirebaseFirestore.instance.batch();
    for (final item in _cart.values) {
      final ref = _productsRef.doc(item.docId);
      batch.update(ref, {'stock': FieldValue.increment(-item.qty)});
    }
    await batch.commit();

    _cart.clear();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commande envoyee')));
      setState(() {});
    }
  }

  Future<void> _openCart() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Panier vide')));
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Panier', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 12),
              ..._cart.values.map(
                (item) => ListTile(
                  title: Text(item.name.isEmpty ? 'Produit' : item.name),
                  subtitle: Text('${item.qty} x ${item.price.toStringAsFixed(2)} ${item.currency}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(onPressed: () => _removeFromCart(item.docId), icon: const Icon(Icons.remove_circle)),
                      IconButton(onPressed: () => _addToCartById(item.docId), icon: const Icon(Icons.add_circle)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total'),
                  Text('${_cartTotal().toStringAsFixed(2)} ${_cart.values.first.currency}'),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _checkout,
                child: const Text('Commander'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _addToCartById(String id) {
    final item = _cart[id];
    if (item == null) return;
    _cart[id] = item.copyWith(qty: item.qty + 1);
    setState(() {});
  }

  Future<void> _openAddProduct() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final stockCtrl = TextEditingController(text: '1');
    final currencyCtrl = TextEditingController(text: 'USD');
    final imageCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ajouter un produit', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom')),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
                TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Prix')),
                TextField(controller: stockCtrl, decoration: const InputDecoration(labelText: 'Stock')),
                TextField(controller: currencyCtrl, decoration: const InputDecoration(labelText: 'Devise')),
                TextField(controller: imageCtrl, decoration: const InputDecoration(labelText: 'Image URL (optionnel)')),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;
                    final stock = int.tryParse(stockCtrl.text.trim()) ?? 0;
                    await _productsRef.add({
                      'name': name,
                      'desc': descCtrl.text.trim(),
                      'price': price,
                      'stock': stock,
                      'currency': currencyCtrl.text.trim().isEmpty ? 'USD' : currencyCtrl.text.trim(),
                      'image': imageCtrl.text.trim(),
                      'owner': widget.contextRef.userId,
                      'sellerName': _sellerName,
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                    if (mounted) Navigator.of(ctx).pop();
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pharmacie'),
        actions: [
          IconButton(onPressed: _openCart, icon: const Icon(Icons.shopping_cart)),
          if (_canAddProducts)
            IconButton(onPressed: _openAddProduct, icon: const Icon(Icons.add_circle_outline)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher un medicament',
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _productsRef.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData || _loadingUser) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                final filtered = docs.where((d) {
                  if (_query.isEmpty) return true;
                  final data = d.data();
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final desc = (data['desc'] ?? '').toString().toLowerCase();
                  return name.contains(_query) || desc.contains(_query);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('Aucun produit'));
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12),
                  itemBuilder: (ctx, i) {
                    final doc = filtered[i];
                    final data = doc.data();
                    final name = (data['name'] ?? '').toString();
                    final desc = (data['desc'] ?? '').toString();
                    final price = (data['price'] is num)
                        ? (data['price'] as num).toDouble()
                        : double.tryParse('${data['price']}') ?? 0;
                    final currency = (data['currency'] ?? 'USD').toString();
                    final stock = data['stock'] ?? 0;
                    final image = (data['image'] ?? '').toString();
                    return ListTile(
                      leading: image.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(image, width: 48, height: 48, fit: BoxFit.cover),
                            )
                          : Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.teal.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.local_pharmacy),
                            ),
                      title: Text(name.isEmpty ? 'Produit' : name),
                      subtitle: Text(_joinParts([desc, 'Stock: $stock'])),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${price.toStringAsFixed(2)} $currency'),
                          const SizedBox(height: 4),
                          ElevatedButton(
                            onPressed: () => _addToCart(doc),
                            child: const Text('Ajouter'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _joinParts(List<String> parts) {
    final out = parts.where((p) => p.trim().isNotEmpty).toList();
    return out.isEmpty ? '' : out.join(' / ');
  }
}

class _CartItem {
  final String docId;
  final String name;
  final double price;
  final String currency;
  final int qty;

  const _CartItem({
    required this.docId,
    required this.name,
    required this.price,
    required this.currency,
    required this.qty,
  });

  _CartItem copyWith({int? qty}) {
    return _CartItem(
      docId: docId,
      name: name,
      price: price,
      currency: currency,
      qty: qty ?? this.qty,
    );
  }
}

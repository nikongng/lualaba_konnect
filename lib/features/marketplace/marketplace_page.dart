import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shimmer/shimmer.dart'; 

import 'product_detail_page.dart';
import 'product_create_page.dart';
import 'cart_page.dart';
import 'cart_service.dart';
import 'history_page.dart';
import 'profile_page.dart';
import 'categories.dart';

class MarketplacePage extends StatefulWidget {
  final VoidCallback onBack;
  final bool isDark;
  const MarketplacePage({super.key, required this.onBack, this.isDark = false});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  List<Map<String, dynamic>> _products = [];
  String _query = '';
  bool _loading = true;
  final String _selectedCategory = 'Tout';
  String _selectedMainCategory = Categories.mainCategories().first;
  String? _selectedSubCategory;
  final Set<String> _favoriteIds = {}; 
  // Use centralized categories map
  List<String> get _mainCategories => Categories.mainCategories();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('market_products')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      
      _products = snap.docs.map<Map<String, dynamic>>((d) {
        final data = d.data();
        // determine sold status and whether to keep in marketplace
        final bool sold = data['sold'] == true;
        final soldAt = data['soldAt'] as Timestamp?;
        final bool soldRecent = sold && soldAt != null && DateTime.now().difference(soldAt.toDate()).inHours < 24;
        return {
          'id': d.id,
          'name': data['name'] ?? '',
          'price': data['price']?.toString() ?? '0',
          'currency': data['currency'] ?? 'FC',
          'image': (data['images'] != null && data['images'].isNotEmpty) ? data['images'][0] : null,
          'category': data['category'] ?? 'Autres',
          'location': data['location'] ?? 'Non spécifié',
          'sellerName': data['sellerName'] ?? 'Vendeur',
          // Normalize visibility values (backward compatibility with older French labels)
          'visibility': (() {
            final raw = data['visibility'] ?? data['visibilityLabel'] ?? 'public';
            final s = raw is String ? raw : raw.toString();
            if (s == 'public' || s == 'contacts') return s;
            if (s.toLowerCase() == 'tout le monde') return 'public';
            if (s.toLowerCase().contains('contact')) return 'contacts';
            return s;
          })(),
          'owner': data['owner'] ?? '',
          'sold': sold,
          'soldRecent': soldRecent,
          'etat': data['etat'] ?? 'occasion',
          'byLot': data['byLot'] ?? false,
          'lotSize': data['lotSize'] ?? 1,
          'desc': data['desc'] ?? '',
        };
      }).toList();
      // Remove sold products older than 1 day from the list
      _products = _products.where((p) => !(p['sold'] == true && (p['soldRecent'] as bool) == false)).toList().cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error loading products: $e');
    }
    
    if (mounted) setState(() => _loading = false);
    _applyVisibilityRules();
  }

  Future<void> _applyVisibilityRules() async {
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    final viewerEmail = FirebaseAuth.instance.currentUser?.email?.toString();
    final owners = <String>{};
    for (final p in _products) {
      if (p['visibility'] == 'contacts') owners.add(p['owner']);
    }
    final allowedOwners = <String>{};
    for (final owner in owners) {
      if (owner.isEmpty) continue;
      if (viewerUid != null && owner == viewerUid) { allowedOwners.add(owner); continue; }
      try {
        final q = await FirebaseFirestore.instance.collection('contacts').where('owner', isEqualTo: owner).get();
        var ok = false;
        for (var d in q.docs) {
          final data = d.data();
          if (viewerUid != null && data['uid'] == viewerUid) { ok = true; break; }
          if (viewerEmail != null && data['email']?.toString().toLowerCase() == viewerEmail.toLowerCase()) { ok = true; break; }
        }
        if (ok) allowedOwners.add(owner);
      } catch (e) {
        debugPrint('Error checking contacts for owner $owner: $e');
      }
    }
    final viewer = viewerUid ?? '';
    final filtered = _products.where((p) {
      if (p['visibility'] == 'public' || p['visibility'] == 'Tout le monde' || p['owner'] == viewer) {
        debugPrint('Product visible: ${p['name']} (public or owned by viewer)');
        return true;
      }
      if (p['visibility'] == 'contacts' && allowedOwners.contains(p['owner'])) {
        debugPrint('Product visible: ${p['name']} (contacts)');
        return true;
      }
      debugPrint('Product hidden: ${p['name']} (visibility: ${p['visibility']}, owner: ${p['owner']})');
      return false;
    }).toList();
    if (mounted) setState(() => _products = filtered);
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _products;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((p) => p['name'].toLowerCase().contains(q) || p['desc'].toLowerCase().contains(q)).toList();
    }
    // Filtering by category: if a subcategory is selected, filter by it; else if a main category selected filter by any of its subcategories or the main label
    if (_selectedSubCategory != null && _selectedSubCategory != 'Tout') {
      final sel = _selectedSubCategory!.toLowerCase();
      list = list.where((p) => (p['category'] ?? '').toLowerCase() == sel).toList();
    } else if (_selectedMainCategory != 'Tout') {
      final main = _selectedMainCategory;
      final subs = Categories.subCategories(main);
      final allowed = <String>{};
      allowed.add(main.toLowerCase());
      for (final s in subs) {
        allowed.add(s.toLowerCase());
      }
      list = list.where((p) => allowed.contains(((p['category'] ?? '')).toLowerCase())).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF0B1415) : const Color(0xFFF4F7FA);
    final cardBg = isDark ? const Color(0xFF122422) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bg,
      body: RefreshIndicator(
        onRefresh: _loadProducts,
        color: Colors.orange.shade800,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildModernAppBar(),
            SliverToBoxAdapter(child: _buildCategoryList()),
            if ((Categories.subCategories(_selectedMainCategory)).isNotEmpty)
              SliverToBoxAdapter(child: _buildSubCategoryList()),
            SliverToBoxAdapter(child: _buildPromoBanner()),
            _loading ? _buildShimmerGrid() : _buildProductGrid(),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
      floatingActionButton: _buildCartFAB(),
    );
  }

  Widget _buildModernAppBar() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 150,
      backgroundColor: widget.isDark ? const Color(0xFF071010) : Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
        onPressed: widget.onBack,
      ),
      title: Text("Market Pro", style: TextStyle(color: widget.isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w900, fontSize: 24)),
      actions: [
        IconButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductCreatePage())).then((_) => _loadProducts()), 
          icon: Icon(Icons.add_circle_outline, color: Colors.orange.shade800, size: 28)
        ),
        IconButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage())), 
          icon: const Icon(Icons.history_toggle_off, color: Colors.black54)
        ),
        IconButton(
          onPressed: () {
            // SÉCURITÉ : On garantit que les variables ne sont pas nulles
            final List<Map<String, dynamic>> currentProducts = List.from(_products);
            final Set<String> currentFavs = Set.from(_favoriteIds);

            Navigator.push(
              context, 
              MaterialPageRoute(
                builder: (_) => ProfilePage(
                  allProducts: currentProducts,
                  favoriteIds: currentFavs,
                )
              )
            );
          }, 
          icon: const Icon(Icons.account_circle_outlined, color: Colors.black87, size: 26)
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Padding(
          padding: const EdgeInsets.fromLTRB(20, 100, 20, 10),
          child: _buildSearchBar(),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF0E2323) : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: const InputDecoration(
          hintText: "Rechercher...",
          prefixIcon: Icon(Icons.search_rounded, color: Colors.orange),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.7,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24))),
          ),
          childCount: 6,
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_filtered.isEmpty) {
      return SliverFillRemaining(child: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 60, color: Colors.grey.shade300),
          const Text("Aucun article trouvé"),
        ],
      )));
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.7,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildProductCard(_filtered[index]),
          childCount: _filtered.length,
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final bool isFav = _favoriteIds.contains(product['id']);
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))),
      child: Container(
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF0E2422) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: CachedNetworkImage(
                      imageUrl: product['image'] ?? '',
                      width: double.infinity, height: double.infinity, fit: BoxFit.cover,
                      errorWidget: (c,u,e) => Container(color: Colors.grey.shade100, child: const Icon(Icons.broken_image)),
                    ),
                  ),
                  Positioned(top: 10, right: 10, child: _buildLikeButton(product['id'], isFav)),
                  Positioned(bottom: 8, left: 8, child: _buildBadge(product['etat'])),
                  if (product['sold'] == true)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(8)),
                        child: const Text('VENDU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: widget.isDark ? Colors.white : Colors.black)),
                  const SizedBox(height: 4),
                  Text("${product['price']} ${product['currency']}", style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.location_on, size: 12, color: widget.isDark ? Colors.white54 : Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(child: Text(product['location'], style: TextStyle(color: widget.isDark ? Colors.white60 : Colors.grey, fontSize: 10), maxLines: 1)),
                  ]),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildLikeButton(String id, bool isFav) {
    return GestureDetector(
      onTap: () => setState(() => isFav ? _favoriteIds.remove(id) : _favoriteIds.add(id)),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle),
        child: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.red : Colors.grey, size: 18),
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(10)),
      child: Text(text.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCategoryList() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _mainCategories.length,
        itemBuilder: (context, i) {
          final label = _mainCategories[i];
          final sel = _selectedMainCategory == label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: sel,
                onSelected: (v) => setState(() {
                _selectedMainCategory = label;
                _selectedSubCategory = (Categories.subCategories(label)).isNotEmpty ? Categories.subCategories(label).first : null;
              }),
              selectedColor: Colors.orange.shade800,
              labelStyle: TextStyle(color: sel ? Colors.white : Colors.black87),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubCategoryList() {
    final subs = Categories.subCategories(_selectedMainCategory);
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: subs.length,
        itemBuilder: (context, i) {
          final label = subs[i];
          final sel = _selectedSubCategory == label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: sel,
              onSelected: (v) => setState(() => _selectedSubCategory = label),
              selectedColor: Colors.orange.shade600,
              labelStyle: TextStyle(color: sel ? Colors.white : Colors.black87),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [Colors.orange.shade900, Colors.orange.shade600]),
      ),
      child: const Row(
        children: [
          Icon(Icons.stars, color: Colors.white),
          SizedBox(width: 10),
          Expanded(child: Text("Promo Lualaba : Livraison gratuite !", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildCartFAB() {
    return FloatingActionButton.extended(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())).then((_) => setState(() {})),
      backgroundColor: Colors.black,
      icon: const Icon(Icons.shopping_bag, color: Colors.white),
      label: FutureBuilder<int>(
        future: CartService.instance.getCount(),
        builder: (c, s) => Text("${s.data ?? 0} Articles", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
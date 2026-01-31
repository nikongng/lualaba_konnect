import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'product_detail_page.dart';
import 'cart_service.dart';

class FavoritesPage extends StatefulWidget {
  final List<Map<String, dynamic>> allProducts;
  final Set<String> favoriteIds;

  const FavoritesPage({
    super.key,
    required this.allProducts,
    required this.favoriteIds,
  });

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  // On crée une copie locale pour pouvoir retirer des éléments visuellement
  late List<Map<String, dynamic>> _favorites;

  @override
  void initState() {
    super.initState();
    _filterFavorites();
  }

  void _filterFavorites() {
    _favorites = widget.allProducts
        .where((p) => widget.favoriteIds.contains(p['id']))
        .toList();
  }

  void _removeFromFavorites(String id) {
    setState(() {
      widget.favoriteIds.remove(id);
      _filterFavorites();
    });
    // Optionnel : Ajouter ici une logique Firestore pour synchroniser
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text(
          "Mes Favoris",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _favorites.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: _favorites.length,
              itemBuilder: (context, index) => _buildFavoriteItem(_favorites[index]),
            ),
    );
  }

  Widget _buildFavoriteItem(Map<String, dynamic> p) {
    return Dismissible(
      key: Key(p['id'].toString()),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) => _removeFromFavorites(p['id']),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 30),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProductDetailPage(product: p)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: CachedNetworkImage(
                    imageUrl: p['image'] ?? '',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorWidget: (c, u, e) => Container(
                      color: Colors.grey.shade100,
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${p['price']} ${p['currency']}",
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                // BOUTON AJOUT PANIER (Utilise addItem de ton CartService)
                IconButton(
                  onPressed: () async {
                    await CartService.instance.addItem(p); // Nom corrigé ici
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("${p['name']} ajouté au panier"),
                          duration: const Duration(seconds: 1),
                          backgroundColor: Colors.teal,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.shopping_cart_outlined, color: Colors.orange.shade900, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border_rounded, size: 100, color: Colors.grey.shade300),
          const SizedBox(height: 20),
          const Text(
            "Aucun coup de cœur ?",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 10),
          const Text(
            "Parcourez la boutique pour ajouter\ndes articles à vos favoris.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';

class MarketplacePage extends StatelessWidget {
  final VoidCallback onBack;

  const MarketplacePage({super.key, required this.onBack});

  // Simulation de données avec des images réelles de produits
  final List<Map<String, String>> products = const [
    {
      "name": "iPhone 15 Pro",
      "price": "999 \$",
      "image": "https://images.unsplash.com/photo-1695048133142-1a20484d2569?q=80&w=500",
      "desc": "Titane naturel, puce A17 Pro."
    },
    {
      "name": "MacBook Air M2",
      "price": "1199 \$",
      "image": "https://images.unsplash.com/photo-1611186871348-b1ce696e52c9?q=80&w=500",
      "desc": "Ultra fin, écran Liquid Retina."
    },
    {
      "name": "Sony WH-1000XM5",
      "price": "349 \$",
      "image": "https://images.unsplash.com/photo-1505740420928-5e560c06d30e?q=80&w=500",
      "desc": "Réduction de bruit leader."
    },
    {
      "name": "Apple Watch Ultra",
      "price": "799 \$",
      "image": "https://images.unsplash.com/photo-1434494878577-86c23bdd0639?q=80&w=500",
      "desc": "Pour l'aventure et l'endurance."
    },
    {
      "name": "PS5 Console",
      "price": "499 \$",
      "image": "https://images.unsplash.com/photo-1606813907291-d86efa9b94db?q=80&w=500",
      "desc": "Expérience de jeu immersive."
    },
    {
      "name": "Nike Air Max",
      "price": "160 \$",
      "image": "https://images.unsplash.com/photo-1542291026-7eec264c27ff?q=80&w=500",
      "desc": "Confort et style iconique."
    },
  ];

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = 60.0 + MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [
          // HEADER
          SliverAppBar(
            pinned: true,
            floating: true,
            backgroundColor: Colors.orange.shade800,
            expandedHeight: 160.0,
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 22),
              onPressed: onBack,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 60, right: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Market Pro",
                            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          _buildCircleIcon(Icons.shopping_cart, true),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildSearchBar(),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(child: _buildCategoryList()),
          SliverToBoxAdapter(child: _buildPromoBanner()),

          // GRILLE DE PRODUITS AVEC IMAGES
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  // On boucle sur la liste products pour avoir du contenu varié
                  final product = products[index % products.length];
                  return _buildProductCard(product);
                },
                childCount: 12, // Affiche 12 produits
              ),
            ),
          ),

          SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, String> product) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // IMAGE DU PRODUIT
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Image.network(
                product['image']!,
                fit: BoxFit.cover,
                width: double.infinity,
                // Gestion du chargement
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                      color: Colors.orange,
                    ),
                  );
                },
                // Gestion de l'erreur (si l'URL est morte)
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['name']!,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  product['desc']!,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      product['price']!,
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                      child: const Icon(Icons.add, color: Colors.white, size: 18),
                    )
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- Reste des widgets utilitaires inchangés ---
  Widget _buildSearchBar() {
    return Container(
      height: 45,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: const TextField(
        decoration: InputDecoration(
          hintText: "Rechercher...",
          prefixIcon: Icon(Icons.search, size: 20, color: Colors.orange),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildCircleIcon(IconData icon, bool hasBadge) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  Widget _buildCategoryList() {
    final categories = ["Tout", "Phones", "Laptops", "Shoes", "Watch"];
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemBuilder: (context, index) => Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: index == 0 ? Colors.orange : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(categories[index], style: TextStyle(color: index == 0 ? Colors.white : Colors.black)),
        ),
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      margin: const EdgeInsets.all(15),
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(colors: [Colors.orange.shade700, Colors.orange.shade400]),
      ),
      child: const Center(
        child: Text("Promo Lualaba : -20% sur tout !", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
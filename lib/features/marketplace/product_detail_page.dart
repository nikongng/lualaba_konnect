import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'market_messages_page.dart';
import 'cart_service.dart';

class ProductDetailPage extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductDetailPage({super.key, required this.product});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  bool _adding = false;
  int _currentPage = 0;
  bool _isFavorite = false;
  final TextEditingController _messageController = TextEditingController(text: 'Cet article est-il toujours disponible ?');

  // --- LOGIQUE MISE À JOUR ---
  
  // Modification : prend maintenant les données en paramètre pour être à jour avec le Stream
  List<String> _getImages(Map<String, dynamic> data) {
    final imgs = data['images'];
    if (imgs is List && imgs.isNotEmpty) {
      try {
        final extracted = imgs.map((e) {
          if (e is String) return e;
          if (e is Map) {
            // Gestion de toutes les structures possibles
            if (e['url'] is String) return e['url'] as String;
            if (e['downloadUrl'] is String) return e['downloadUrl'] as String;
            if (e['path'] is String) return e['path'] as String;
            if (e.containsKey('storage') && e['storage'] is Map && e['storage']['url'] is String) return e['storage']['url'] as String;
            return e.values.firstWhere((v) => v is String, orElse: () => '').toString();
          }
          return e.toString();
        }).where((s) => s.isNotEmpty).cast<String>().toList();
        
        // Déduplication
        return extracted.toSet().toList();
      } catch (_) {
        return imgs.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    }
    
    // Cas chaîne séparée par virgules
    if (imgs is String && imgs.isNotEmpty) {
      final parts = imgs.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts;
    }
    
    // Fallback image unique
    final one = data['image'] ?? data['photo'] ?? data['photoUrl'];
    if (one is String && one.isNotEmpty) return [one];
    
    return [];
  }

  String _formatDateTime(dynamic ts) {
    if (ts == null) return 'Date inconnue';
    try {
      DateTime dt;
      if (ts is Timestamp) {
        dt = ts.toDate();
      } else if (ts is String) {
        dt = DateTime.parse(ts);
      } else if (ts is Map && ts.containsKey('_seconds')) {
        dt = DateTime.fromMillisecondsSinceEpoch(ts['_seconds'] * 1000);
      } else {
        return 'Format inconnu';
      }
      return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
    } catch (e) {
      return 'Erreur date';
    }
  }

  void _sendMessage(Map<String, dynamic> currentData) {
    final p = currentData;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    
    if (p['owner'] != null && p['owner'] == currentUid) {
      _notify(context, "Vous êtes le vendeur de cet article.");
      return;
    }
    
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      _notify(context, "Le message est vide.");
      return;
    }
    
    final ownerId = p['owner'];
    if (ownerId == null || ownerId.toString().isEmpty) {
      _notify(context, "Identifiant du vendeur introuvable.");
      return;
    }

    final imgs = _getImages(p);
    final msg = {
      'productId': p['id'],
      'productName': p['name'] ?? '',
      'productImage': imgs.isNotEmpty ? imgs.first : '',
      'content': text,
      'from': currentUid,
      'to': ownerId,
      'participants': [currentUid, ownerId],
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    };

    FirebaseFirestore.instance.collection('market_messages').add(msg).then((_) {
      _notify(context, "Message envoyé au vendeur.");
      _messageController.clear();
    }).catchError((e) {
      _notify(context, "Échec de l'envoi : $e");
    });
  }

  void _notify(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg), 
        behavior: SnackBarBehavior.floating, 
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
      )
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ID du produit passé depuis la page précédente
    final productId = widget.product['id'] ?? widget.product['objectID'];
    
    // Si pas d'ID, on affiche juste les données statiques (fallback)
    if (productId == null) return _buildPageContent(widget.product);

    // --- LE CŒUR DE LA CORRECTION : STREAMBUILDER ---
    // On écoute le document en temps réel pour avoir TOUS les champs (dont la date)
    return StreamBuilder<DocumentSnapshot>(
      // ⚠️ ASSUREZ-VOUS QUE 'products' EST BIEN LE NOM DE VOTRE COLLECTION DANS FIREBASE
      stream: FirebaseFirestore.instance.collection('market_products').doc(productId).snapshots(),
      builder: (context, snapshot) {
        
        // Données à afficher
        Map<String, dynamic> displayProduct = widget.product;

        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          // On fusionne : on prend les données fraîches de Firebase
          final freshData = snapshot.data!.data() as Map<String, dynamic>;
          displayProduct = {...widget.product, ...freshData};
          // On s'assure que l'ID est bien présent
          displayProduct['id'] = productId;
        }

        return _buildPageContent(displayProduct);
      },
    );
  }

  Widget _buildPageContent(Map<String, dynamic> p) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final images = _getImages(p);
    final isOwner = (p['owner'] != null && p['owner'] == currentUid);
    
    // Récupération intelligente de la date
    final dateValue = p['createdAt'] ?? p['created_at'] ?? p['date'] ?? p['timestamp'] ?? p['publishedAt'];

    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          child: CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.9),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: CircleAvatar(
              backgroundColor: Colors.white.withOpacity(0.9),
              child: IconButton(
                icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, 
                      color: _isFavorite ? Colors.redAccent : Colors.black, size: 20),
                onPressed: () => setState(() => _isFavorite = !_isFavorite),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // HEADER : SLIDER D'IMAGES
          Stack(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.45,
                child: PageView.builder(
                  itemCount: images.isEmpty ? 1 : images.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (ctx, i) {
                    return GestureDetector(
                      onTap: () {
                        if (images.isNotEmpty) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => FullscreenGallery(images: images, initialIndex: i)));
                        }
                      },
                      child: CachedNetworkImage(
                        imageUrl: images.isEmpty ? '' : images[i],
                        fit: BoxFit.cover,
                        placeholder: (c, s) => Container(color: Colors.grey.shade100, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                        errorWidget: (c, u, e) => Container(
                          color: Colors.grey.shade100, 
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_not_supported_outlined, size: 40, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text("Pas d'image", style: TextStyle(color: Colors.grey.shade500, fontSize: 12))
                            ],
                          )
                        ),
                      ),
                    );
                  },
                ),
              ),
              // VENDU badge
              if (p['sold'] == true || p['soldAt'] != null)
                Positioned(
                  top: 100,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.9), 
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]
                    ),
                    child: const Text('VENDU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 80,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.3)],
                    ),
                  ),
                ),
              ),
              if (images.length > 1)
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(images.length, (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 6,
                        width: _currentPage == index ? 20 : 6,
                        decoration: BoxDecoration(
                          color: _currentPage == index ? Colors.white : Colors.white.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),

          // CORPS DE LA PAGE
          Expanded(
            child: Container(
              width: double.infinity,
              transform: Matrix4.translationValues(0, -20, 0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p['category'] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          p['category'].toString().toUpperCase(),
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            p['name'] ?? 'Sans nom', 
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.1, color: Color(0xFF1A1A1A)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "${p['price']}",
                              style: TextStyle(color: Colors.orange.shade800, fontSize: 24, fontWeight: FontWeight.w900),
                            ),
                            Text(
                              p['currency'] ?? 'FC',
                              style: TextStyle(color: Colors.orange.shade800.withOpacity(0.6), fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _buildInfoChip(Icons.location_on, p['location'] ?? 'Inconnu', Colors.blue.shade50, Colors.blue.shade700),
                        _buildInfoChip(Icons.star_outline, p['etat']?.toString().toUpperCase() ?? 'OCCASION', Colors.orange.shade50, Colors.orange.shade800),
                        if (p['stock'] != null)
                          _buildInfoChip(Icons.inventory_2_outlined, "Stock: ${p['stock']}", Colors.green.shade50, Colors.green.shade700),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            height: 50, width: 50,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.orange.shade100, width: 2),
                            ),
                            child: const Icon(Icons.person, color: Colors.orange),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Vendu par", 
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11)
                                ),
                                Text(
                                  p['sellerName'] ?? 'Utilisateur', 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "Publié le", 
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 11)
                              ),
                              // ICI LA DATE S'AFFICHERA ENFIN
                              Text(
                                _formatDateTime(dateValue).split(' à ')[0],
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text("Description", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(
                      p['desc'] ?? 'Aucune description fournie pour cet article.', 
                      style: TextStyle(color: Colors.grey.shade700, height: 1.6, fontSize: 15),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(20, 15, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isOwner)
            Container(
              margin: const EdgeInsets.only(bottom: 15),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: "Écrire au vendeur...",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        isDense: true,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _sendMessage(p),
                    child: Container(
                      height: 40, width: 40,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade800, 
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketMessagesPage())),
                  child: Container(
                    height: 56, width: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.black87),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: isOwner
                      ? Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Center(
                            child: Text(
                              "C'est votre article", 
                              style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)
                            )
                          ),
                        )
                      : ElevatedButton(
                          onPressed: _adding ? null : () async {
                            setState(() => _adding = true);
                            await CartService.instance.addItem({
                              'id': p['id'] ?? p['name'], 
                              'name': p['name'], 
                              'price': p['price'], 
                              'image': images.isNotEmpty ? images.first : '',
                            });
                            if (mounted) {
                              setState(() => _adding = false);
                              _notify(context, "Ajouté au panier !");
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                            fixedSize: const Size.fromHeight(56),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          child: _adding 
                            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.shopping_bag_outlined),
                                  SizedBox(width: 10),
                                  Text("Ajouter au panier", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color bgColor, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label, 
            style: TextStyle(color: iconColor, fontSize: 12, fontWeight: FontWeight.w700)
          ),
        ],
      ),
    );
  }
}

// --- GALERIE FULLSCREEN ---
class FullscreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const FullscreenGallery({super.key, required this.images, this.initialIndex = 0});

  @override
  State<FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<FullscreenGallery> {
  late PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Text('${_index + 1}/${widget.images.length}', style: const TextStyle(color: Colors.white)),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (ctx, i) {
          return Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 1.0,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: widget.images[i],
                fit: BoxFit.contain,
                placeholder: (c, s) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                errorWidget: (c, u, e) => const Icon(Icons.broken_image, size: 80, color: Colors.white30),
              ),
            ),
          );
        },
      ),
    );
  }
}
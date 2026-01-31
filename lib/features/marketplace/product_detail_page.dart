import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  final TextEditingController _messageController = TextEditingController(text: 'Cet article est-il toujours disponible ? Je suis intéressé.');

  List<String> _getImages() {
    final imgs = widget.product['images'];
    if (imgs is List && imgs.isNotEmpty) return imgs.cast<String>();
    final one = widget.product['image'];
    if (one is String && one.isNotEmpty) return [one];
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final images = _getImages();

    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle),
            child: IconButton(
              icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, 
                   color: _isFavorite ? Colors.red : Colors.black),
              onPressed: () => setState(() => _isFavorite = !_isFavorite),
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
                        placeholder: (c, s) => Container(color: Colors.grey.shade100),
                        errorWidget: (c, u, e) => Container(
                          color: Colors.grey.shade100, 
                          child: const Icon(Icons.broken_image, size: 50, color: Colors.grey)
                        ),
                      ),
                    );
                  },
                ),
              ),
              // VENDU badge overlay
              if (p['sold'] == true || p['soldAt'] != null)
                Positioned(
                  top: 40,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(20)),
                    child: const Text('VENDU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              // INDICATEUR DE PAGES (DOTS)
              if (images.length > 1)
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(images.length, (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index ? Colors.orange.shade800 : Colors.white.withOpacity(0.5),
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
              transform: Matrix4.translationValues(0, -30, 0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // NOM ET PRIX
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(p['name'] ?? '', 
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                        ),
                        Text("${p['price']} ${p['currency'] ?? 'FC'}", 
                          style: TextStyle(color: Colors.orange.shade900, fontSize: 22, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    
                    // LOCALISATION ET ÉTAT
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.orange.shade800),
                        const SizedBox(width: 4),
                        Text(p['location'] ?? 'Lualaba', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 15),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Text(p['etat'].toString().toUpperCase(), 
                            style: TextStyle(color: Colors.orange.shade900, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),

                    // VENDEUR
                    const Text("Vendeur", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.orange.shade100,
                            child: const Icon(Icons.person, color: Colors.orange),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p['sellerName'] ?? 'Vendeur Pro', 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_formatDateTime(p['createdAt']), style: TextStyle(color: Colors.green.shade600, fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_right, color: Colors.grey)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),

                    // DESCRIPTION
                    const Text("Description", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text(p['desc'] ?? 'Aucune description fournie.', 
                      style: const TextStyle(color: Colors.black54, height: 1.5, fontSize: 15)),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      
      // BARRE D'ACTION BASSE
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // petite zone de texte + bouton envoyer au dessus du bouton panier
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                      maxLines: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(color: Colors.orange.shade700, borderRadius: BorderRadius.circular(12)),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: () => _sendMessage(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
            // BOUTON CHAT
            Container(
              height: 55, width: 55,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: Colors.black),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketMessagesPage())),
              ),
            ),
            const SizedBox(width: 15),
            // BOUTON PANIER: ne pas afficher pour les propres articles
            Expanded(
              child: (p['owner'] != null && p['owner'] == currentUid)
                  ? Container(
                      height: 55,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(child: Text("C'EST VOTRE ARTICLE", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold))),
                    )
                  : GestureDetector(
                      onTap: _adding ? null : () async {
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
                      child: Container(
                        height: 55,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [Colors.orange.shade900, Colors.orange.shade700]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
                        ),
                        child: Center(
                          child: _adding 
                            ? CircularProgressIndicator(color: Colors.white)
                            : const Text("AJOUTER AU PANIER", 
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
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

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final p = widget.product;
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

    final imgs = _getImages();
    final msg = {
      'productId': p['id'] ?? p['originalId'] ?? p['docId'] ?? '',
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
    }).catchError((e) {
      _notify(context, "Échec de l'envoi : $e");
    });
  }

  void _notify(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))
    );
  }

  String _formatDateTime(dynamic ts) {
    try {
      DateTime dt;
      if (ts == null) return 'Date inconnue';
      if (ts is Timestamp) {
        dt = ts.toDate();
      } else if (ts is DateTime) dt = ts;
      else if (ts is int) dt = DateTime.fromMillisecondsSinceEpoch(ts);
      else return 'Date inconnue';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Date inconnue';
    }
  }

}

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
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text('${_index + 1}/${widget.images.length}'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (ctx, i) {
          final url = widget.images[i];
          return Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 1.0,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (c, s) => Center(child: CircularProgressIndicator(color: Theme.of(c).colorScheme.primary)),
                errorWidget: (c, u, e) => const Icon(Icons.broken_image, size: 80, color: Colors.white30),
              ),
            ),
          );
        },
      ),
    );
  }
}
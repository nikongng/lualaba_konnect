import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'AuthMainPage.dart';
import 'dart:ui';
import '../../../chat/chat_list_page.dart';
import '../../../live/live_page.dart';

// ==========================================
// 0. DONNÉES CENTRALISÉES (10 ACTUALITÉS)
// ==========================================
final List<Map<String, dynamic>> lualabaNewsData = [
  {
    "source": "Lualaba Gouvernorat",
    "title": "Lancement officiel des travaux de réhabilitation de la route RN39.",
    "images": [
      'https://images.unsplash.com/photo-1503708928676-1cb796a0891e?auto=format&fit=crop&w=800&q=80'
    ]
  },
  {
    "source": "Radio Okapi",
    "title": "Inauguration du nouveau centre de négoce à Kolwezi.",
    "images": [
      'https://images.unsplash.com/photo-1541872703-74c5e443d1f9?auto=format&fit=crop&w=800&q=80'
    ]
  },
  {
    "source": "Lualaba TV",
    "title": "Production minière : les chiffres du cuivre en hausse.",
    "images": [
      'https://images.unsplash.com/photo-1581089781785-603411fa81e5?auto=format&fit=crop&w=800&q=80'
    ]
  },
  {
    "source": "Mikuba",
    "title": "Exportation : Premier convoi de lingots vers le port de Lobito.",
    "images": [
      'https://images.unsplash.com/photo-1587919968590-fbc98cea6c9a?auto=format&fit=crop&w=800&q=80'
    ]
  },
  {
    "source": "Urbanisme",
    "title": "Modernisation de la voirie urbaine.",
    "images": [
      'https://images.unsplash.com/photo-1676254540448-c3e29ca3c9bb?auto=format&fit=crop&w=800&q=80'
    ]
  },
  {
    "source": "Nature du Lualaba",
    "title": "Paysages verdoyants après la pluie.",
    "images": [
      'https://images.unsplash.com/photo-1685751528511-b5cb71733a03?auto=format&fit=crop&w=800&q=80'
    ]
  },
  {
    "source": "Climat",
    "title": "Coucher de soleil sur le fleuve Lualaba.",
    "images": [
      'https://images.unsplash.com/photo-1661643206053-ded2207d0c74?auto=format&fit=crop&w=800&q=80'
    ]
  },
  {
    "source": "Sport",
    "title": "Interclub : Stade Manika plein.",
    "images": [
      'https://images.unsplash.com/photo-1563581595415-db9b7775a3c5?auto=format&fit=crop&w=800&q=80'
    ]
  }
];

// ==========================================
// 1. PAGE FIL D'ACTUALITÉ (DÉFILEMENT VERTICAL MIS À JOUR)
// ==========================================
class NewsFeedPage extends StatefulWidget {
  const NewsFeedPage({super.key});

  @override
  State<NewsFeedPage> createState() => _NewsFeedPageState();
}

class _NewsFeedPageState extends State<NewsFeedPage> {
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Fil d'actualité", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: lualabaNewsData.length,
              itemBuilder: (context, index) {
                final item = lualabaNewsData[index];
                return Column(
                  children: [
                    if (index == 0) ...[
                      _buildCreatePostArea(),
                      const SizedBox(height: 20),
                    ],
                    VerticalNewsPost(
                      source: item['source'],
                      title: item['title'],
                      images: List<String>.from(item['images']),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    List<String> categories = ["Tout", "Infos Officielles", "Communauté", "Alertes"];
    return Container(
      height: 60, color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(right: 8, top: 12, bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: i == 0 ? Colors.orange : const Color(0xFFF2F4F5),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Text(categories[i], style: TextStyle(color: i == 0 ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  Widget _buildCreatePostArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const CircleAvatar(backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=3')),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFFF2F4F5), borderRadius: BorderRadius.circular(25)),
              child: const Text("Quoi de neuf à Kolwezi ?", style: TextStyle(color: Colors.black54)),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.image_outlined, color: Colors.orange, size: 28),
        ],
      ),
    );
  }
}

class VerticalNewsPost extends StatefulWidget {
  final String source;
  final String title;
  final List<String> images;
  const VerticalNewsPost({super.key, required this.source, required this.title, required this.images});
  @override
  State<VerticalNewsPost> createState() => _VerticalNewsPostState();
}

class _VerticalNewsPostState extends State<VerticalNewsPost> {
  bool isLiked = false;
  int likes = 124;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const CircleAvatar(backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11')),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Text(widget.source, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 4), const Icon(Icons.check_circle, color: Colors.blue, size: 14)]),
              const Text("Il y a 2h • INFO", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
            const Icon(Icons.more_horiz, color: Colors.grey),
          ]),
          const SizedBox(height: 12),
          Text(widget.title, style: const TextStyle(fontSize: 14, height: 1.4)),
          const SizedBox(height: 12),
          _buildImageGrid(widget.images),
          const SizedBox(height: 15),
          Row(children: [
            GestureDetector(
              onTap: () => setState(() { isLiked = !isLiked; isLiked ? likes++ : likes--; }),
              child: Row(children: [Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.red : Colors.grey), const SizedBox(width: 5), Text("$likes")]),
            ),
            const SizedBox(width: 25),
            const Icon(Icons.chat_bubble_outline, color: Colors.grey),
            const SizedBox(width: 5), const Text("45"),
            const Spacer(),
            const Icon(Icons.share_outlined, color: Colors.grey),
          ])
        ],
      ),
    );
  }

  // Image grid plus robuste : loading + error fallback
  Widget _buildImageGrid(List<String> imgs) {
    if (imgs.isEmpty) return const SizedBox.shrink();
    Widget placeholderBox = Container(color: Colors.black12, child: const Center(child: Icon(Icons.broken_image_outlined, size: 40)));
    if (imgs.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          imgs[0],
          fit: BoxFit.cover,
          width: double.infinity,
          height: 200,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator()));
          },
          errorBuilder: (context, error, stackTrace) => placeholderBox,
        ),
      );
    }
    return SizedBox(
      height: 250,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(children: [
          Expanded(
            child: Image.network(
              imgs[0],
              fit: BoxFit.cover,
              height: double.infinity,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator()));
              },
              errorBuilder: (context, error, stackTrace) => placeholderBox,
            ),
          ),
          const SizedBox(width: 4),
          if (imgs.length > 1)
            Expanded(
              child: Column(children: [
                Expanded(
                  child: Image.network(
                    imgs[1],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator()));
                    },
                    errorBuilder: (context, error, stackTrace) => placeholderBox,
                  ),
                ),
                if (imgs.length > 2) ...[
                  const SizedBox(height: 4),
                  Expanded(
                    child: Image.network(
                      imgs[2],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator()));
                      },
                      errorBuilder: (context, error, stackTrace) => placeholderBox,
                    ),
                  ),
                ],
              ]),
            ),
        ]),
      ),
    );
  }
}
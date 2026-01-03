import 'package:flutter/material.dart';

// ==========================================
// 0. DONNÉES CENTRALISÉES (10 ACTUALITÉS)
// ==========================================
final List<Map<String, dynamic>> lualabaNewsData = [
  {
    "source": "Gouvernorat Lualaba",
    "title": "Lancement officiel des travaux de réhabilitation de la route RN39.",
    "images": [
      'https://images.unsplash.com/photo-1515162305285-0293e4767cc2?q=80&w=800&auto=format&fit=crop'
    ]
  },
  {
    "source": "Radio Okapi",
    "title": "Inauguration du nouveau centre de négoce à Kolwezi.",
    "images": [
      'https://images.unsplash.com/photo-1542601906990-b4d3fb778b09?q=80&w=800&auto=format&fit=crop'
    ]
  },
  {
    "source": "Lualaba TV",
    "title": "Production minière : les chiffres du cuivre en hausse.",
    "images": [
      'https://images.unsplash.com/photo-1533106497176-45ae19e68ba2?q=80&w=800&auto=format&fit=crop'
    ]
  },
  {
    "source": "Mikuba",
    "title": "Exportation : Premier convoi de lingots vers le port de Lobito.",
    "images": [
      'https://images.unsplash.com/photo-1580674285054-bed31e145f59?q=80&w=800&auto=format&fit=crop'
    ]
  },
  {
    "source": "Urbanisme",
    "title": "Modernisation de la voirie urbaine.",
    "images": [
      'https://images.unsplash.com/photo-1449824913935-59a10b8d2000?q=80&w=800&auto=format&fit=crop'
    ]
  },
  {
    "source": "Nature du Lualaba",
    "title": "Paysages verdoyants après la pluie.",
    "images": [
      'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?q=80&w=800&auto=format&fit=crop'
    ]
  },
  {
    "source": "Climat",
    "title": "Coucher de soleil sur le fleuve Lualaba.",
    "images": [
      'https://images.unsplash.com/photo-1472214103451-9374bd1c798e?q=80&w=800&auto=format&fit=crop'
    ]
  },
  {
    "source": "Sport",
    "title": "Interclub : Stade Manika plein.",
    "images": [
      'https://images.unsplash.com/photo-1574629810360-7efbbe195018?q=80&w=800&auto=format&fit=crop'
    ]
  }
];

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
        title: const Text(
          "Fil d'actualité",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
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
      height: 60,
      color: Colors.white,
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
            child: Text(
              categories[i],
              style: TextStyle(
                color: i == 0 ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreatePostArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=3'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F5),
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Text(
                "Quoi de neuf à Kolwezi ?",
                style: TextStyle(color: Colors.black54),
              ),
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
  const VerticalNewsPost({
    super.key,
    required this.source,
    required this.title,
    required this.images,
  });
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.source,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.check_circle, color: Colors.blue, size: 14),
                      ],
                    ),
                    const Text(
                      "Il y a 2h • INFO",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          _buildImageGrid(widget.images),
          const SizedBox(height: 15),
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  isLiked = !isLiked;
                  isLiked ? likes++ : likes--;
                }),
                child: Row(
                  children: [
                    Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? Colors.red : Colors.grey,
                    ),
                    const SizedBox(width: 5),
                    Text("$likes"),
                  ],
                ),
              ),
              const SizedBox(width: 25),
              const Icon(Icons.chat_bubble_outline, color: Colors.grey),
              const SizedBox(width: 5),
              const Text("45"),
              const Spacer(),
              const Icon(Icons.share_outlined, color: Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid(List<String> imgs) {
    if (imgs.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        imgs[0],
        fit: BoxFit.cover,
        width: double.infinity,
        height: 200,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            height: 200,
            color: Colors.grey.shade100,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: 200,
            width: double.infinity,
            color: Colors.grey.shade200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image_outlined, color: Colors.grey.shade400, size: 40),
                const SizedBox(height: 8),
                const Text("Image non disponible", style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        },
      ),
    );
  }
}
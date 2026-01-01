import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'AuthMainPage.dart';
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

// ==========================================
// 2. DASHBOARD PRINCIPAL (MIS À JOUR)
// ==========================================
class ModernDashboard extends StatefulWidget {
  const ModernDashboard({super.key});
  @override
  State<ModernDashboard> createState() => _ModernDashboardState();
}

class _ModernDashboardState extends State<ModernDashboard> {
  int _selectedIndex = 0;
  bool _isDarkMode = true;

  Future<void> _makeCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir l'application de téléphone")));
      }
    }
  }

  void _showSOSMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Row(children: [Icon(Icons.warning_rounded, color: Colors.red, size: 30), SizedBox(width: 10), Text("URGENCE", style: TextStyle(color: Colors.red, fontSize: 22, fontWeight: FontWeight.w900))]),
              IconButton(onPressed: () => Navigator.pop(context), icon: const CircleAvatar(backgroundColor: Color(0xFFF5F5F5), child: Icon(Icons.close, color: Colors.black54))),
            ]),
            const SizedBox(height: 25),
            _buildSOSItem("Police", "Intervention rapide", "112", const Color(0xFF2962FF), Icons.shield),
            const SizedBox(height: 15),
            _buildSOSItem("Ambulance", "Secours médical", "118", const Color(0xFFEF5350), Icons.medical_services),
            const SizedBox(height: 15),
            _buildSOSItem("Pompiers", "Incendie & Sauvetage", "119", const Color(0xFFFF9100), Icons.local_fire_department),
            const SizedBox(height: 30),
            Container(
              width: double.infinity, height: 60,
              decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFFCDD2))),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.location_on_outlined, color: Colors.red), SizedBox(width: 10), Text("Envoyer ma position GPS", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))]),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSOSItem(String title, String sub, String number, Color color, IconData icon) {
    return InkWell(
      onTap: () => _makeCall(number),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 28)),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)), Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12))])),
          Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
        ]), 
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = _isDarkMode;
    final Color bgColor = isDark ? const Color(0xFF012E32) : const Color(0xFFF2F4F5);
    final Color textColor = isDark ? Colors.white : const Color(0xFF012E32);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 414),
          child: Stack(
            children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              _buildHomePage(isDark, textColor), // Index 0
              ChatListPage(isDark: isDark),       // Index 1 (Ton fichier chat)
              const LivePage(),                  // Index 2 (Ton nouveau fichier live)
              const Center(child: Text("Market")),
              _buildProfilePage(isDark, textColor),
            ],
          ),
              _buildFloatingBottomNav(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomePage(bool isDark, Color textColor) {
    final Color cardBg = isDark ? const Color(0xFF1E3E3B).withOpacity(0.8) : Colors.white;
    final Color subTextColor = isDark ? Colors.white70 : Colors.black54;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            _buildHeader(isDark, textColor),
            const SizedBox(height: 25),
            _buildWeatherCard(cardBg, textColor, subTextColor, isDark),
            const SizedBox(height: 25),
            _buildMastaCard(),
            const SizedBox(height: 25),
            _buildSearchBar(isDark),
            const SizedBox(height: 30),
            _buildCopperCard(cardBg, textColor, subTextColor),
            const SizedBox(height: 30),
            _buildNewsSection(textColor, isDark),
            const SizedBox(height: 30),
            _buildServicesSection(),
            const SizedBox(height: 130),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color textColor) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [
        const CircleAvatar(radius: 28, backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=3')),
        const SizedBox(width: 15),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("LUALABACONNECT", style: TextStyle(color: Color(0xFF00CBA9), fontSize: 10, fontWeight: FontWeight.w900)),
          Text("Bonjour, Ir Punga", style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.bold)),
          Text("Jeudi 01 Janvier", style: TextStyle(color: isDark ? Colors.white60 : Colors.black45, fontSize: 13)),
        ]),
      ]),
      GestureDetector(onTap: _showSOSMenu, child: const CircleAvatar(backgroundColor: Color(0xFFD32F2F), radius: 25, child: Text("sos", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
    ]);
  }

  Widget _buildWeatherCard(Color bg, Color text, Color sub, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(32)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Lubumbashi", style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.bold)),
            Text("22°", style: TextStyle(color: text, fontSize: 55, fontWeight: FontWeight.w200)),
          ]),
          Icon(Icons.cloudy_snowing, color: isDark ? Colors.white70 : Colors.orange, size: 45),
        ]),
        Divider(color: isDark ? Colors.white10 : Colors.black12, height: 30),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: ["MAINT.", "13 H", "14 H", "15 H", "16 H"].map((t) => Column(children: [
          Text(t, style: TextStyle(color: sub, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Icon(Icons.cloud_queue, color: text, size: 18),
          Text("22°", style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.bold)),
        ])).toList()),
      ]),
    );
  }

  Widget _buildMastaCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7F00FF), Color(0xFFE100FF)]), borderRadius: BorderRadius.circular(32)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [CircleAvatar(backgroundColor: Colors.white, radius: 18, child: Icon(Icons.face, color: Color(0xFF7F00FF))), SizedBox(width: 12), Text("Masta", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)), Spacer(), Text("Bêta", style: TextStyle(color: Colors.white70, fontSize: 10))]),
        const SizedBox(height: 10),
        const Text("Pose moi une question, je suis ton assistant personnel", style: TextStyle(color: Colors.white, fontSize: 13)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Container(height: 50, decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(15)), padding: const EdgeInsets.symmetric(horizontal: 15), alignment: Alignment.centerLeft, child: const Text("Posez votre question...", style: TextStyle(color: Colors.white60)))),
          const SizedBox(width: 10),
          Container(height: 50, width: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF7F00FF))),
        ]),
      ]),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      height: 55, decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(30), border: isDark ? null : Border.all(color: Colors.black12)),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Row(children: [Icon(Icons.search, color: Colors.grey), SizedBox(width: 10), Text("Rechercher un service, un produit...", style: TextStyle(color: Colors.grey, fontSize: 14))]),
    );
  }

  Widget _buildCopperCard(Color bg, Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(32)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("COURS DU CUIVRE (LME)", style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.bold)), const Text("\$9,840.50", style: TextStyle(color: Color(0xFF00E676), fontSize: 28, fontWeight: FontWeight.w900)), const Text("+1.2% aujourd'hui", style: TextStyle(color: Color(0xFF00E676), fontSize: 11))]),
        const Icon(Icons.auto_graph, color: Color(0xFF00E676), size: 35),
      ]),
    );
  }

  Widget _buildNewsSection(Color text, bool isDark) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text("Actu", style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.bold)),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NewsFeedPage())),
          child: const Text("Tout voir", style: TextStyle(color: Colors.orange, fontSize: 13))
        )
      ]),
      const SizedBox(height: 15),
      SizedBox(
        height: 280,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: lualabaNewsData.length,
          itemBuilder: (context, index) {
            final item = lualabaNewsData[index];
            return _newsCard(
              item['source'],
              item['title'],
              isDark,
              item['images'][0]
            );
          },
        )
      ),
    ]);
  }

  Widget _newsCard(String source, String title, bool isDark, String img) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E3E3B) : Colors.white,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- HEADER ----
          Row(
            children: [
              const CircleAvatar(
                radius: 12,
                backgroundColor: Colors.black,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ---- IMAGE ----
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.network(
                img,
                fit: BoxFit.cover,
                width: double.infinity,

                // 🔄 Loader
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.black12,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },

                // ❌ Fallback si image cassée / 404
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.black12,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 40,
                        color: Colors.grey,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ---- TITLE ----
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }


  Widget _buildServicesSection() {
    return Column(children: [
      _serviceTile("Services Rapides", "Food, Ménage, Auto & plus...", [const Color(0xFF448AFF), const Color(0xFF2962FF)], Icons.grid_view_rounded, "NOUVEAU"),
      const SizedBox(height: 16),
      _serviceTile("Emploi & Annonce", "Recrutement, Freelance, Annonces", [const Color(0xFFD500F9), const Color(0xFFAA00FF)], Icons.work_outline, "OPPORTUNITÉS"),
      const SizedBox(height: 16),
      _serviceTile("Conseil du jour", "Hydratez-vous régulièrement aujourd'hui.", [const Color(0xFF00CBA9), const Color(0xFF00A88E)], Icons.lightbulb_outline, "SANTÉ"),
    ]);
  }

  Widget _serviceTile(String title, String sub, List<Color> colors, IconData icon, String tag) {
    return Container(
      padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(28)),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: Colors.white, size: 28)),
        const SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tag, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)), Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)), Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 11))])),
        const CircleAvatar(backgroundColor: Colors.white, radius: 18, child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black)),
      ]),
    );
  }

  Widget _buildProfilePage(bool isDark, Color textColor) {
    final Color cardBg = isDark ? const Color(0xFF1E3E3B) : Colors.white;
    final Color subText = isDark ? Colors.white60 : Colors.black54;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildActionTile("Ma Santé", "Dossier médical, RDV, IA Santé", Icons.favorite_border, const Color(0xFF00CBA9)),
            const SizedBox(height: 12),
            _buildActionTile("Espace Adultes (+18)", "Rencontres, Jeux & Fun", Icons.whatshot, Colors.redAccent),
            const SizedBox(height: 25),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF0F171A), borderRadius: BorderRadius.circular(24)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Row(children: [
                      Icon(Icons.wifi, color: Colors.greenAccent, size: 20),
                      SizedBox(width: 8),
                      Text("Lualaba Premium", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ]),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8)), child: const Text("Actif", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                  ]),
                  const SizedBox(height: 15),
                  const Text("Data LAN Utilisée : 45GB / Illimité", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: 0.45, backgroundColor: Colors.white10, color: Colors.orange.withOpacity(0.8), minHeight: 6),
                  const SizedBox(height: 15),
                  const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text("Accès prioritaire activé", style: TextStyle(color: Colors.white38, fontSize: 11)),
                    Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 12),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 30),
            _sectionTitle("COMPTE", subText),
            _settingsTile(Icons.person_outline, "Informations personnelles", cardBg, textColor),
            _settingsTile(Icons.account_balance_wallet_outlined, "Portefeuille & Factures", cardBg, textColor, trailing: "3.50 \$"),
            const SizedBox(height: 20),
            _sectionTitle("PRÉFÉRENCES", subText),
            _settingsSwitchTile(Icons.notifications_none, "Notifications", true, cardBg, textColor),
            _settingsSwitchTile(Icons.dark_mode_outlined, "Mode Sombre", _isDarkMode, cardBg, textColor, (v) => setState(() => _isDarkMode = v)),
            const SizedBox(height: 20),
            _sectionTitle("SUPPORT", subText),
            _settingsTile(Icons.help_outline, "Centre d'aide", cardBg, textColor),
            const SizedBox(height: 30),
            Center(
              child: TextButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                label: const Text("Se déconnecter", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(String title, String sub, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.5), width: 1.5)),
      child: Row(children: [
        CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
        const SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ])),
        const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      ]),
    );
  }

  Widget _sectionTitle(String title, Color color) {
    return Padding(padding: const EdgeInsets.only(left: 8, bottom: 12), child: Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)));
  }

  Widget _settingsTile(IconData icon, String title, Color bg, Color text, {String? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: Icon(icon, color: text.withOpacity(0.7)),
        title: Text(title, style: TextStyle(color: text, fontSize: 15)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (trailing != null) Text(trailing, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          const SizedBox(width: 5),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        ]),
      ),
    );
  }

  Widget _settingsSwitchTile(IconData icon, String title, bool value, Color bg, Color text, [Function(bool)? onChanged]) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: Icon(icon, color: text.withOpacity(0.7)),
        title: Text(title, style: TextStyle(color: text, fontSize: 15)),
        trailing: CupertinoSwitch(value: value, activeColor: Colors.orange, onChanged: onChanged ?? (v){}),
      ),
    );
  }

Widget _buildFloatingBottomNav(bool isDark) {
  return Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 30),
      height: 75,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2C38) : Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 0. ACCUEIL
          IconButton(
            icon: Icon(Icons.home_filled, 
              color: _selectedIndex == 0 ? Colors.orange : Colors.grey, size: 28),
            onPressed: () => setState(() => _selectedIndex = 0),
          ),
          
          // 1. CHAT (Liaison avec ton nouveau fichier)
          IconButton(
            icon: Icon(Icons.chat_bubble_outline, 
              color: _selectedIndex == 1 ? Colors.orange : Colors.grey, size: 28),
            onPressed: () => setState(() => _selectedIndex = 1), // Index 1
          ),

          // 2. LUALABA TV (Centre)
          GestureDetector(
            onTap: () => setState(() => _selectedIndex = 2),
            child: Container(
              height: 58, width: 58,
              decoration: const BoxDecoration(color: Color(0xFF012E32), shape: BoxShape.circle),
              child: Icon(
                Icons.subscriptions_rounded,
                color: _selectedIndex == 2 ? Colors.orange : Colors.white,
                size: 26
              ),
            ),
          ),

          // 3. MARKET
          IconButton(
            icon: Icon(Icons.shopping_bag_outlined, 
              color: _selectedIndex == 3 ? Colors.orange : Colors.grey, size: 28),
            onPressed: () => setState(() => _selectedIndex = 3), // Index 3
          ),

          // 4. PROFIL
          IconButton(
            icon: Icon(Icons.person_outline, 
              color: _selectedIndex == 4 ? Colors.orange : Colors.grey, size: 28),
            onPressed: () => setState(() => _selectedIndex = 4), // Index 4
          ),
        ],
      ),
    ),
  );
}
}

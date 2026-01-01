import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'AuthMainPage.dart';

// ==========================================
// 1. PAGE FIL D'ACTUALITÉ (DÉFILEMENT VERTICAL)
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
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCreatePostArea(),
                const SizedBox(height: 20),
                // Exemple avec 3 images
                const VerticalNewsPost(
                  source: "Lualaba Gouvernorat",
                  title: "Lancement officiel des travaux de réhabilitation de la route RN39. Une avancée majeure pour fluidifier le transport.",
                  images: [
                    'https://images.unsplash.com/photo-1541872703-74c5e443d1f9',
                    'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b',
                    'https://images.unsplash.com/photo-1518173946687-a4c8a98039f5',
                  ],
                ),
                // Exemple avec 1 image
                const VerticalNewsPost(
                  source: "Radio Okapi",
                  title: "Inauguration du nouveau centre de négoce à Kolwezi.",
                  images: ['https://images.unsplash.com/photo-1581094288338-2314dddb7bc3'],
                ),
              ],
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

  Widget _buildImageGrid(List<String> imgs) {
    if (imgs.isEmpty) return const SizedBox.shrink();
    if (imgs.length == 1) {
      return ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(imgs[0], fit: BoxFit.cover, width: double.infinity, height: 200));
    }
    return SizedBox(
      height: 250,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(children: [
          Expanded(child: Image.network(imgs[0], fit: BoxFit.cover, height: double.infinity)),
          const SizedBox(width: 4),
          if (imgs.length > 1) Expanded(child: Column(children: [
            Expanded(child: Image.network(imgs[1], fit: BoxFit.cover, width: double.infinity)),
            if (imgs.length > 2) ...[const SizedBox(height: 4), Expanded(child: Image.network(imgs[2], fit: BoxFit.cover, width: double.infinity))],
          ])),
        ]),
      ),
    );
  }
}

// ==========================================
// 2. DASHBOARD PRINCIPAL (TON CODE ORIGINAL RESTAURÉ)
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
    if (await canLaunchUrl(launchUri)) { await launchUrl(launchUri); }
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
                index: _selectedIndex == 4 ? 1 : 0,
                children: [_buildHomePage(isDark, textColor), _buildProfilePage(isDark, textColor)],
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
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Actu", style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.bold)), GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NewsFeedPage())), child: const Text("Tout voir", style: TextStyle(color: Colors.orange, fontSize: 13)))]),
      const SizedBox(height: 15),
      SizedBox(height: 280, child: ListView(scrollDirection: Axis.horizontal, children: [ 
        _newsCard("Lualaba Gouvernorat", "Lancement des travaux RN39.", isDark, 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b'), 
        _newsCard("Radio Okapi", "Nouveau centre de négoce.", isDark, 'https://images.unsplash.com/photo-1541872703-74c5e443d1f9'),
        _newsCard("Lualaba TV", "Les mines.", isDark, 'https://images.unsplash.com/photo-1581089781785-603411fa81e5'),
        _newsCard("Mikuba", "Lingots de métal.", isDark, 'https://images.unsplash.com/photo-1533038590840-1cde6e668a91'),
        _newsCard("Urbanisme", "Route en construction.", isDark, 'https://images.unsplash.com/photo-1541872703-74c5e443d1f9'),
        _newsCard("Nature et Paysages du Lualaba", "Savane / Verdure.", isDark, 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b'),
        _newsCard("Climat", "Coucher de soleil africain.", isDark, 'https://images.unsplash.com/photo-1523805081446-ed9a7bb1401d'),
        _newsCard("Sport", "Interclub est de retour.", isDark, 'https://images.unsplash.com/photo-1574629810360-7efbbe195018'),
        _newsCard("Radio Okapi", "Nouveau centre de négoce.", isDark, 'https://images.unsplash.com/photo-1541872703-74c5e443d1f9'),
      _newsCard("Sport", "Le derby arrive !.", isDark, 'https://images.unsplash.com/photo-1541872703-74c5e443d1f9') 
      ])),

    ]);
  }

  Widget _newsCard(String source, String title, bool isDark, String img) {
    return Container(
      width: 260, margin: const EdgeInsets.only(right: 15), padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1E3E3B) : Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const CircleAvatar(radius: 12, backgroundColor: Colors.black), const SizedBox(width: 8), Text(source, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))]),
        const SizedBox(height: 12),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(img, fit: BoxFit.cover, width: double.infinity))),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2),
      ]),
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
    return SafeArea(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Paramètres", style: TextStyle(color: textColor, fontSize: 28, fontWeight: FontWeight.bold)),
      const SizedBox(height: 25),
      ListTile(leading: const Icon(Icons.dark_mode_outlined), title: const Text("Mode Sombre"), trailing: CupertinoSwitch(value: _isDarkMode, onChanged: (v) => setState(() => _isDarkMode = v))),
      const Spacer(),
      Center(child: TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text("Se déconnecter", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)))),
      const SizedBox(height: 100),
    ])));
  }

  Widget _buildFloatingBottomNav(bool isDark) {
    return Align(alignment: Alignment.bottomCenter, child: Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 30), height: 75,
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1A2C38) : Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)]),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        IconButton(icon: Icon(Icons.home_filled, color: _selectedIndex == 0 ? Colors.orange : Colors.grey, size: 28), onPressed: () => setState(() => _selectedIndex = 0)),
        const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 28),
        Container(height: 58, width: 58, decoration: const BoxDecoration(color: Color(0xFF012E32), shape: BoxShape.circle), child: const Icon(Icons.subscriptions_rounded, color: Colors.white, size: 26)),
        const Icon(Icons.shopping_bag_outlined, color: Colors.grey, size: 28),
        IconButton(icon: Icon(Icons.person_outline, color: _selectedIndex == 4 ? Colors.orange : Colors.grey, size: 28), onPressed: () => setState(() => _selectedIndex = 4)),
      ]),
    ));
  }
}
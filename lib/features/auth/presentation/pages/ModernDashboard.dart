import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'AuthMainPage.dart';
import '../../../chat/chat_list_page.dart';import 'dart:ui';

import '../../../live/live_page.dart';
import 'news_feed_page.dart';
import 'home_page_widgets.dart';
import 'profile_page_widgets.dart';
import '../widgets/floating_nav_bar.dart';

// ==========================================
// 2. DASHBOARD PRINCIPAL (MODULARISÉ)
// ==========================================
class ModernDashboard extends StatefulWidget {
  const ModernDashboard({super.key});
  @override
  State<ModernDashboard> createState() => _ModernDashboardState();
}

class _ModernDashboardState extends State<ModernDashboard> {
  final GlobalKey<ChatListPageState> _chatKey = GlobalKey<ChatListPageState>();
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
              ChatListPage(key: _chatKey, isDark: isDark),       // Index 1 (Ton fichier chat)
              const LivePage(),                  // Index 2 (Ton nouveau fichier live)
              const Center(child: Text("Market")),
              _buildProfilePage(isDark, textColor),
            ],
          ),
              FloatingNavBar(
                isDark: isDark,
                selectedIndex: _selectedIndex,
                onIndexChanged: (index) => setState(() => _selectedIndex = index),
                chatKey: _chatKey,
              ),
            ],
          ),
        ),
      ),
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
            ProfilePageWidgets.buildActionTile("Ma Santé", "Dossier médical, RDV, IA Santé", Icons.favorite_border, const Color(0xFF00CBA9)),
            const SizedBox(height: 12),
            ProfilePageWidgets.buildActionTile("Espace Adultes (+18)", "Rencontres, Jeux & Fun", Icons.whatshot, Colors.redAccent),
            const SizedBox(height: 25),
            ProfilePageWidgets.buildPremiumCard(),
            const SizedBox(height: 30),
            ProfilePageWidgets.sectionTitle("COMPTE", subText),
            ProfilePageWidgets.settingsTile(Icons.person_outline, "Informations personnelles", cardBg, textColor),
            ProfilePageWidgets.settingsTile(Icons.account_balance_wallet_outlined, "Portefeuille & Factures", cardBg, textColor, trailing: "3.50 \$"),
            const SizedBox(height: 20),
            ProfilePageWidgets.sectionTitle("PRÉFÉRENCES", subText),
            ProfilePageWidgets.settingsSwitchTile(Icons.notifications_none, "Notifications", true, cardBg, textColor),
            ProfilePageWidgets.settingsSwitchTile(Icons.dark_mode_outlined, "Mode Sombre", _isDarkMode, cardBg, textColor, (v) => setState(() => _isDarkMode = v)),
            const SizedBox(height: 20),
            ProfilePageWidgets.sectionTitle("SUPPORT", subText),
            ProfilePageWidgets.settingsTile(Icons.help_outline, "Centre d'aide", cardBg, textColor),
            const SizedBox(height: 30),
            ProfilePageWidgets.logoutButton(),
            const SizedBox(height: 120),
          ],
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
        trailing: CupertinoSwitch(value: value, activeTrackColor: Colors.orange, onChanged: onChanged ?? (v){}),
      ),
    );
  }

Widget _buildFloatingBottomNav(bool isDark) {
  return Positioned(
    bottom: 30,
    left: 24,
    right: 24,
    child: ClipRRect( // Pour que le flou ne dépasse pas des arrondis
      borderRadius: BorderRadius.circular(35),
      child: BackdropFilter( // Effet de flou sous la barre
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 75,
          decoration: BoxDecoration(
            color: isDark 
                ? const Color(0xFF1E3E3B).withOpacity(0.85) // Plus de transparence pour le style
                : Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(35),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _navItem(Icons.home_filled, 0, isDark),
              _navItem(Icons.chat_bubble_rounded, 1, isDark),
              _navItem(Icons.live_tv_rounded, 2, isDark),
              _navItem(Icons.shopping_bag_outlined, 3, isDark),
              _navItem(Icons.person_outline, 4, isDark),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _navItem(IconData icon, int index, bool isDark) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        // --- LOGIQUE DE VERROUILLAGE ---
        // Si on clique sur Chat (index 1) et qu'on vient d'un autre onglet
        if (index == 1 && _selectedIndex != 1) {
          // On déclenche le verrouillage dans le fichier chat_list_page.dart
          _chatKey.currentState?.lockChat();
        }

        setState(() {
          _selectedIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Icon(
          icon,
          color: isSelected ? const Color(0xFF00CBA9) : (isDark ? Colors.white38 : Colors.black26),
          size: 28,
        ),
      ),
    );
  }
}

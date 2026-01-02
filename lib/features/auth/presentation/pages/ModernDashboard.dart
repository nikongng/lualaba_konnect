import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';

import '../../../chat/chat_list_page.dart';
import '../../../live/live_page.dart';
import 'news_feed_page.dart';
import 'profile_page_widgets.dart';
import '../widgets/floating_nav_bar.dart';
// Import du nouveau widget météo
import '../widgets/weather_widget.dart'; 
import '../widgets/header_widget.dart'; 
import '../widgets/masta_card.dart';
import '../widgets/copper_card.dart';

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
              ChatListPage(key: _chatKey, isDark: isDark),       // Index 1
              const LivePage(),                  // Index 2
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
            ProfilePageWidgets.sectionTitle("MON COMPTE COMPTE", subText),
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
          
          // 1. NOUVEAU HEADER EXTERNE DYNAMIQUE
          HeaderWidget(
            isDark: isDark,
            textColor: textColor,
            onSOSPressed: _showSOSMenu, // Assurez-vous que cette fonction existe toujours
          ),
          
          const SizedBox(height: 25),

          // 2. WIDGET MÉTÉO (KOLWEZI)
          WeatherWidget(
            isDark: isDark,
            bg: cardBg,
            text: textColor,
            sub: subTextColor,
          ),
          
          const SizedBox(height: 25),

          // 3. CARTE MASTA CHAT
          MastaCard(
            onChatSubmit: (question) {
              print("Question reçue : $question");
              // C'est ici que vous gérerez la réponse de l'assistant
            },
          ),

          const SizedBox(height: 25),

          // 4. BARRE DE RECHERCHE
          _buildSearchBar(isDark),

          const SizedBox(height: 30),

          // 5. COURS DU CUIVRE (BOURSE LUALABA)
          const CopperCard(),

          const SizedBox(height: 30),

          // 6. ACTUALITÉS
          _buildNewsSection(textColor, isDark),

          const SizedBox(height: 30),

          // 7. SERVICES RAPIDES
          _buildServicesSection(),

          const SizedBox(height: 130), // Espace pour la barre de navigation
        ],
      ),
    ),
  );
}
  Widget _buildSearchBar(bool isDark) {
    return Container(
      height: 55, decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(30), border: isDark ? null : Border.all(color: Colors.black12)),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Row(children: [Icon(Icons.search, color: Colors.grey), SizedBox(width: 10), Text("Rechercher un service, un produit...", style: TextStyle(color: Colors.grey, fontSize: 14))]),
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
          Row(
            children: [
              const CircleAvatar(radius: 12, backgroundColor: Colors.black),
              const SizedBox(width: 8),
              Expanded(child: Text(source, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.network(
                img,
                fit: BoxFit.cover,
                width: double.infinity,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(color: Colors.black12, child: const Center(child: Icon(Icons.broken_image_outlined, size: 40, color: Colors.grey)));
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
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

  // Les autres widgets utilitaires (_settingsTile, etc.) restent inchangés...
}
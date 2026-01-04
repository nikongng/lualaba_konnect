import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';

// Tes imports originaux
import '../widgets/services/services_tiles/rapid_services_tile.dart';
import '../widgets/services/services_tiles/job_announcement_tile.dart';
import '../widgets/services/services_tiles/daily_tip_tile.dart';
import '../../../chat/chat_list_page.dart';
import '../../../live/live_page.dart';
import '../../../marketplace/marketplace_page.dart';
import 'news_feed_page.dart';
import 'profile_page_widgets.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/weather_widget.dart';
import '../widgets/header_widget.dart';
import '../widgets/masta_card.dart';
import '../widgets/copper_card.dart';

final List<Map<String, dynamic>> lualabaNewsData = [
  {'source': 'Lualaba News', 'title': 'Nouveau projet minier à Kolwezi', 'images': ['https://placeholder.com/150']},
  {'source': 'Info DRC', 'title': 'Météo : Fortes pluies prévues', 'images': ['https://placeholder.com/150']},
];

class ModernDashboard extends StatefulWidget {
  const ModernDashboard({super.key});
  @override
  State<ModernDashboard> createState() => _ModernDashboardState();
}

class _ModernDashboardState extends State<ModernDashboard> {
  final GlobalKey<ChatListPageState> _chatKey = GlobalKey<ChatListPageState>();
  int _selectedIndex = 0;
  bool _isDarkMode = true;

  // --- FONCTIONS SOS ---
  Future<void> _makeCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  Future<void> _sendGPSAlert() async {
    try {
      HapticFeedback.heavyImpact();
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final String message = "🚨 SOS URGENCE - Ir Punga 🚨\nPosition : https://www.google.com/maps?q=${position.latitude},${position.longitude}";
      final Uri smsUri = Uri(scheme: 'sms', path: '112', queryParameters: {'body': message});
      if (await canLaunchUrl(smsUri)) await launchUrl(smsUri);
    } catch (e) {
      debugPrint("Erreur GPS : $e");
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
            const SizedBox(height: 25),
            _buildSOSItem("Police", "Intervention rapide", "112", const Color(0xFF2962FF), Icons.shield),
            const SizedBox(height: 15),
            _buildSOSItem("Ambulance", "Secours médical", "118", const Color(0xFFEF5350), Icons.medical_services),
            const SizedBox(height: 15),
            _buildSOSItem("Pompiers", "Incendie & Sauvetage", "119", const Color(0xFFFF9100), Icons.local_fire_department),
            const SizedBox(height: 30),
            InkWell(
              onTap: () { Navigator.pop(context); _sendGPSAlert(); },
              child: Container(
                width: double.infinity, height: 60,
                decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFFCDD2))),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.location_on_outlined, color: Colors.red), SizedBox(width: 10), Text("Envoyer ma position GPS", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))]),
              ),
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

  void _showFilterMenu(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF012E32) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Filtrer la recherche", style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.location_on, color: Colors.orange),
              title: Text("Proximité (Kolwezi Centre)", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = _isDarkMode;
    final Color bgColor = isDark ? const Color(0xFF012E32) : const Color(0xFFF2F4F5);
    final Color textColor = isDark ? Colors.white : const Color(0xFF012E32);

    // CACHER LA NAVBAR SUR LIVE (2) ET MARKET (3)
    bool isNavBarVisible = _selectedIndex != 2 && _selectedIndex != 3;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
        else SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 414),
            child: Stack(
              children: [
                // TRANSITION DE LUXE (ZOOM + FADE)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  switchInCurve: Curves.easeInOutQuart,
                  switchOutCurve: Curves.easeInOutQuart,
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    final scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(animation);
                    final fadeAnimation = CurvedAnimation(parent: animation, curve: const Interval(0.5, 1.0));
                    return FadeTransition(opacity: fadeAnimation, child: ScaleTransition(scale: scaleAnimation, child: child));
                  },
                  child: _buildCurrentPage(isDark, textColor),
                ),

                // NAVBAR ANIMÉE
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.fastOutSlowIn,
                  left: 0, right: 0,
                  bottom: isNavBarVisible ? 0 : -120, // Disparaît complètement
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isNavBarVisible ? 1.0 : 0.0,
                    child: FloatingNavBar(
                      isDark: isDark,
                      selectedIndex: _selectedIndex,
                      onIndexChanged: (index) => setState(() => _selectedIndex = index),
                      chatKey: _chatKey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentPage(bool isDark, Color textColor) {
    switch (_selectedIndex) {
      case 0: return _buildHomePage(isDark, textColor, key: const ValueKey('home_ui'));
      case 1: return ChatListPage(key: _chatKey, isDark: isDark);
      case 2: return LivePage(key: const ValueKey('live_ui'), onBack: () => setState(() => _selectedIndex = 0));
      case 3: return MarketplacePage(key: const ValueKey('market_ui'), onBack: () => setState(() => _selectedIndex = 0));
      case 4: return _buildProfilePage(isDark, textColor, key: const ValueKey('profile_ui'));
      default: return _buildHomePage(isDark, textColor, key: const ValueKey('home_ui'));
    }
  }

  // --- SECTIONS DU DASHBOARD ---
  Widget _buildHomePage(bool isDark, Color textColor, {Key? key}) {
    final Color cardBg = isDark ? const Color(0xFF1E3E3B).withOpacity(0.8) : Colors.white;
    return SafeArea(
      key: key,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            HeaderWidget(isDark: isDark, textColor: textColor, onSOSPressed: _showSOSMenu),
            const SizedBox(height: 25),
            WeatherWidget(isDark: isDark, bg: cardBg, text: textColor, sub: isDark ? Colors.white70 : Colors.black54),
            const SizedBox(height: 25),
            MastaCard(onChatSubmit: (q) => debugPrint(q)),
            const SizedBox(height: 25),
            _buildSearchBar(isDark),
            const SizedBox(height: 30),
            const CopperCard(),
            const SizedBox(height: 30),
            _buildNewsSection(textColor, isDark),
            const SizedBox(height: 30),
            _buildServicesSection(isDark),
            const SizedBox(height: 130),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E3E3B).withOpacity(0.5) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: isDark ? Colors.white54 : Colors.grey, size: 22),
          const Expanded(child: TextField(decoration: InputDecoration(hintText: "Rechercher...", border: InputBorder.none))),
          IconButton(icon: const Icon(Icons.tune_rounded, color: Colors.orange), onPressed: () => _showFilterMenu(context, isDark)),
        ],
      ),
    );
  }

Widget _buildNewsSection(Color text, bool isDark) {
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text("Actu", 
        style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.bold)
      ),
      
      // On rend le "Tout voir" cliquable
      GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NewsFeedPage(), // Ouvre ta page existante
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: const Text(
            "Tout voir", 
            style: TextStyle(
              color: Colors.orange, 
              fontSize: 13, 
              fontWeight: FontWeight.bold
            )
          ),
        ),
      ),
    ]),
    const SizedBox(height: 16),
    SizedBox(
      height: 250, 
      child: ListView.builder(
        scrollDirection: Axis.horizontal, 
        itemCount: lualabaNewsData.length, 
        itemBuilder: (context, index) {
          final item = lualabaNewsData[index];
          return _newsCard(item['source'], item['title'], isDark, item['images'][0]);
        }
      )
    ),
  ]);
}

  Widget _newsCard(String source, String title, bool isDark, String imageUrl) {
    return Container(width: 220, margin: const EdgeInsets.only(right: 16), decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E1E) : Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), child: Image.network(imageUrl, height: 130, width: double.infinity, fit: BoxFit.cover)),
        Padding(padding: const EdgeInsets.all(12), child: Text(title, maxLines: 2, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold))),
      ]),
    );
  }

  Widget _buildServicesSection(bool isDark) {
    return Column(children: [RapidServicesTile(isDark: isDark), const SizedBox(height: 16), const JobAnnouncementTile(), const SizedBox(height: 16), const DailyTipTile()]);
  }

Widget _buildProfilePage(bool isDark, Color textColor, {Key? key}) {
  return SafeArea(
    key: key, 
    child: SingleChildScrollView(
      physics: const BouncingScrollPhysics(), 
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TES TUILES D'ACTION
          ProfilePageWidgets.buildActionTile("Ma Santé", "Dossier médical", Icons.favorite_border, const Color(0xFF00CBA9), isDark),
          const SizedBox(height: 12),
          ProfilePageWidgets.buildActionTile("Espace Adultes", "Rencontres", Icons.whatshot, Colors.redAccent, isDark),
          
          const SizedBox(height: 25),

          // 2. TA CARTE PREMIUM
          ProfilePageWidgets.buildPremiumCard(),
          
          const SizedBox(height: 25),

          // --- SECTION : MON COMPTE ---
          ProfilePageWidgets.sectionTitle("MON COMPTE", Colors.orange),
          ProfilePageWidgets.settingsTile(
            Icons.person_outline, "Profil", 
            isDark ? Colors.white.withOpacity(0.05) : Colors.white, textColor
          ),
          ProfilePageWidgets.settingsTile(
            Icons.account_balance_wallet_outlined, "Portefeuille", 
            isDark ? Colors.white.withOpacity(0.05) : Colors.white, textColor, trailing: "CDF"
          ),

          const SizedBox(height: 15),

          // --- SECTION : PRÉFÉRENCES ---
          ProfilePageWidgets.sectionTitle("PRÉFÉRENCES", Colors.orange),
          ProfilePageWidgets.settingsSwitchTile(
            Icons.notifications_none, "Notifications", true, 
            isDark ? Colors.white.withOpacity(0.05) : Colors.white, textColor, (val) {}
          ),
          ProfilePageWidgets.settingsTile(
            Icons.language, "Langue", 
            isDark ? Colors.white.withOpacity(0.05) : Colors.white, textColor, trailing: "Français"
          ),
          // RÉINTÉGRATION DU MODE SOMBRE ICI
          ProfilePageWidgets.settingsSwitchTile(
            Icons.dark_mode_outlined, 
            "Mode Sombre", 
            _isDarkMode, // Utilise ta variable d'état
            isDark ? Colors.white.withOpacity(0.05) : Colors.white, 
            textColor, 
            (val) => setState(() => _isDarkMode = val)
          ),

          const SizedBox(height: 15),

          // --- SECTION : SUPPORT ---
          ProfilePageWidgets.sectionTitle("SUPPORT", Colors.orange),
          ProfilePageWidgets.settingsTile(
            Icons.help_outline, "Centre d'aide", 
            isDark ? Colors.white.withOpacity(0.05) : Colors.white, textColor
          ),
          ProfilePageWidgets.settingsTile(
            Icons.info_outline, "À propos", 
            isDark ? Colors.white.withOpacity(0.05) : Colors.white, textColor
          ),

          const SizedBox(height: 30),

          // 3. TON BOUTON DÉCONNEXION
          ProfilePageWidgets.logoutButton(context),

          const SizedBox(height: 140), 
        ]
      )
    )
  );
}
}
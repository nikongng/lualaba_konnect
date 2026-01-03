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
// Voici la section et la carte optimisées pour un affichage parfait dans votre application

Widget _buildNewsSection(Color text, bool isDark) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start, 
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween, 
          children: [
            Text(
              "Actu", 
              style: TextStyle(
                color: text, 
                fontSize: 18, 
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              )
            ),
            GestureDetector(
              onTap: () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => const NewsFeedPage())
              ),
              child: const Text(
                "Tout voir", 
                style: TextStyle(
                  color: Colors.orange, 
                  fontSize: 13, 
                  fontWeight: FontWeight.w600
                )
              )
            )
          ]
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 250, // Hauteur légèrement augmentée pour éviter les coupures de texte
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 4, bottom: 10), // Padding pour l'ombre portée
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
    ]
  );
}

Widget _newsCard(String source, String title, bool isDark, String imageUrl) {
  return Container(
    width: 220, // Largeur optimisée pour la lisibilité
    margin: const EdgeInsets.only(right: 16),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        )
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Zone de l'image avec un ratio fixe
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Image.network(
            imageUrl,
            height: 130, 
            width: double.infinity,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                height: 130,
                color: isDark ? Colors.white10 : Colors.grey[100],
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              height: 130,
              width: double.infinity,
              color: isDark ? Colors.white10 : Colors.grey[200],
              child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
            ),
          ),
        ),
        // Zone de contenu textuel
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.orange, 
                        fontSize: 10, 
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
                // Petit indicateur de temps ou d'action (optionnel)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.access_time, 
                      size: 12, 
                      color: isDark ? Colors.white38 : Colors.black38
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "2h", 
                      style: TextStyle(
                        fontSize: 11, 
                        color: isDark ? Colors.white38 : Colors.black38
                      )
                    ),
                  ],
                )
              ],
            ),
          ),
        )
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
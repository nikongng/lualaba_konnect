import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

void main() {
  runApp(const MaterialApp(
    home: ModernDashboard(),
    debugShowCheckedModeBanner: false,
  ));
}

class ModernDashboard extends StatefulWidget {
  const ModernDashboard({super.key});

  @override
  State<ModernDashboard> createState() => _ModernDashboardState();
}

class _ModernDashboardState extends State<ModernDashboard> {
  int _selectedIndex = 0; 
  bool _isDarkMode = true;

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
              // Gestion des pages via IndexedStack
              IndexedStack(
                index: _selectedIndex == 4 ? 1 : 0,
                children: [
                  _buildHomePage(isDark, textColor),
                  _buildProfilePage(isDark, textColor),
                ],
              ),
              // Barre de navigation flottante
              _buildFloatingBottomNav(isDark),
            ],
          ),
        ),
      ),
    );
  }

  // --- 1. PAGE D'ACCUEIL ---
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

  // --- 2. PAGE PROFIL (PARAMÈTRES) ---
  Widget _buildProfilePage(bool isDark, Color textColor) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 30),
            Text("Paramètres", style: TextStyle(color: textColor, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 25),
            
            _buildSectionTitle("COMPTE"),
            _buildMenuTile(Icons.person_outline, "Informations personnelles", isDark),
            _buildMenuTile(Icons.shield_outlined, "Sécurité & Confidentialité", isDark),
            _buildMenuTile(Icons.account_balance_wallet_outlined, "Portefeuille & Factures", isDark, trailing: "3.50 \$"),
            
            const SizedBox(height: 25),
            _buildSectionTitle("PRÉFÉRENCES"),
            _buildMenuTile(Icons.notifications_none_outlined, "Notifications", isDark, isSwitch: true, switchValue: true),
            _buildMenuTile(Icons.phonelink_setup_outlined, "Économiseur de données", isDark, isSwitch: true, switchValue: false, sub: "Compresse les médias sur le LAN"),
            _buildMenuTile(Icons.dark_mode_outlined, "Mode Sombre", isDark, isSwitch: true, switchValue: _isDarkMode, onChanged: (v) => setState(() => _isDarkMode = v)),
            _buildMenuTile(Icons.language_outlined, "Langue", isDark, trailing: "Français"),

            const SizedBox(height: 25),
            _buildSectionTitle("SUPPORT"),
            _buildMenuTile(Icons.help_outline, "Centre d'aide", isDark),
            _buildMenuTile(Icons.system_update_alt_rounded, "Mises à jour", isDark, trailing: "v1.0.4"),

            const SizedBox(height: 40),
            const Center(child: Text("Se déconnecter", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16))),
            const SizedBox(height: 130),
          ],
        ),
      ),
    );
  }

  // --- COMPOSANTS INTERNES ---

  Widget _buildHeader(bool isDark, Color textColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const CircleAvatar(radius: 28, backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=3')),
            const SizedBox(width: 15),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("LUALABACONNECT", style: TextStyle(color: Color(0xFF00CBA9), fontSize: 10, fontWeight: FontWeight.w900)),
              Text("Bonjour, Richard", style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.bold)),
              Text("Samedi 27 Décembre", style: TextStyle(color: isDark ? Colors.white60 : Colors.black45, fontSize: 13)),
            ]),
          ],
        ),
        const CircleAvatar(backgroundColor: Color(0xFFD32F2F), radius: 25, child: Text("sos", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      ],
    );
  }

  Widget _buildWeatherCard(Color bg, Color text, Color sub, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(32)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Lubumbashi", style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.bold)),
                Text("22°", style: TextStyle(color: text, fontSize: 55, fontWeight: FontWeight.w200)),
              ]),
              Icon(Icons.cloudy_snowing, color: isDark ? Colors.white70 : Colors.orange, size: 45),
            ],
          ),
          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ["MAINT.", "13 H", "14 H", "15 H", "16 H"].map((t) => Column(
              children: [
                Text(t, style: TextStyle(color: sub, fontSize: 9, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Icon(Icons.cloud_queue, color: text, size: 18),
                Text("22°", style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMastaCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7F00FF), Color(0xFFE100FF)]), borderRadius: BorderRadius.circular(32)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(backgroundColor: Colors.white, radius: 18, child: Icon(Icons.face, color: Color(0xFF7F00FF))),
          const SizedBox(width: 12),
          const Text("Masta", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
          const Spacer(),
          const Text("Bêta", style: TextStyle(color: Colors.white70, fontSize: 10)),
        ]),
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
      height: 55,
      decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(30), border: isDark ? null : Border.all(color: Colors.black12)),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: const [Icon(Icons.search, color: Colors.grey), SizedBox(width: 10), Text("Rechercher un service, un produit...", style: TextStyle(color: Colors.grey, fontSize: 14))]),
    );
  }

  Widget _buildCopperCard(Color bg, Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(32)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("COURS DU CUIVRE (LME)", style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.bold)),
          const Text("\$9,840.50", style: TextStyle(color: Color(0xFF00E676), fontSize: 28, fontWeight: FontWeight.w900)),
          const Text("+1.2% aujourd'hui", style: TextStyle(color: Color(0xFF00E676), fontSize: 11)),
        ]),
        const Icon(Icons.auto_graph, color: Color(0xFF00E676), size: 35),
      ]),
    );
  }

  Widget _buildNewsSection(Color text, bool isDark) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Actu", style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.bold)), const Text("Tout voir", style: TextStyle(color: Colors.orange, fontSize: 13))]),
      const SizedBox(height: 15),
      SizedBox(
        height: 280,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [ _newsCard("Lualaba Gouvernorat", "Lancement des travaux de réhabilitation route RN39.", isDark), _newsCard("Radio Okapi", "Inauguration du nouveau centre de négoce.", isDark) ],
        ),
      ),
    ]);
  }

  Widget _newsCard(String source, String title, bool isDark) {
    return Container(
      width: 260, margin: const EdgeInsets.only(right: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: isDark ? const Color(0xFF1E3E3B) : Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [if(!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const CircleAvatar(radius: 12, backgroundColor: Colors.black), const SizedBox(width: 8), Text(source, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))]),
        const SizedBox(height: 12),
        Expanded(child: Container(decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(15)))),
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
      _serviceTile("Pic de chaleur prévu", "Hydratez-vous régulièrement aujourd'hui.", [const Color(0xFF00BFA5), const Color(0xFF00897B)], Icons.thermostat_rounded, "CONSEIL DU JOUR"),
    ]);
  }

  Widget _serviceTile(String title, String sub, List<Color> colors, IconData icon, String tag) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(28)),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: Colors.white, size: 28)),
        const SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tag, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ])),
        const CircleAvatar(backgroundColor: Colors.white, radius: 18, child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black)),
      ]),
    );
  }

  // --- COMPOSANTS NAVIGATION ---

  Widget _buildFloatingBottomNav(bool isDark) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 30),
        height: 75,
        decoration: BoxDecoration(color: isDark ? const Color(0xFF1A2C38) : Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)]),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _navIcon(Icons.home_filled, 0),
          _navIcon(Icons.chat_bubble_outline, 1),
          _videoButton(),
          _navIcon(Icons.shopping_bag_outlined, 3),
          _navIcon(Icons.person_outline, 4),
        ]),
      ),
    );
  }

  Widget _navIcon(IconData icon, int index) {
    return IconButton(
      icon: Icon(icon, color: _selectedIndex == index ? Colors.orange : Colors.grey, size: 28),
      onPressed: () => setState(() => _selectedIndex = index),
    );
  }

  Widget _videoButton() {
    return Container(
      height: 58, width: 58,
      decoration: const BoxDecoration(
        color: Color(0xFF012E32), 
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [Color(0xFF012E32), Color(0xFF004D40)]),
      ),
      child: const Icon(Icons.subscriptions_rounded, color: Colors.white, size: 26),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 12.0), child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)));
  }

  Widget _buildMenuTile(IconData icon, String title, bool isDark, {bool isSwitch = false, bool switchValue = false, String? trailing, String? sub, Function(bool)? onChanged}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        leading: Icon(icon, color: isDark ? Colors.white70 : Colors.black87),
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        subtitle: sub != null ? Text(sub, style: const TextStyle(fontSize: 11, color: Colors.grey)) : null,
        trailing: isSwitch 
          ? CupertinoSwitch(value: switchValue, activeColor: Colors.orange, onChanged: onChanged ?? (v){})
          : (trailing != null ? Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(trailing, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12))) : const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey)),
      ),
    );
  }
}
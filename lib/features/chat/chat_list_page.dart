import 'dart:ui'; // INDISPENSABLE pour le flou
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; // Pour les icônes modernes
import 'chat_detail_screen.dart';

class ChatListPage extends StatefulWidget {
  final bool isDark;
  const ChatListPage({super.key, required this.isDark});

  @override
  State<ChatListPage> createState() => ChatListPageState();
}

class ChatListPageState extends State<ChatListPage> with TickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // --- VARIABLES DE SÉCURITÉ ---
  String? _savedPin; 
  bool _isUnlocked = false;
  String _inputPin = ""; 
  
  // Couleur accent (Orange)
  final Color accentColor = const Color(0xFFFF8C00);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    _tabController.addListener(() {
      if (_tabController.indexIsChanging && _savedPin != null) {
        setState(() {
          _isUnlocked = false; 
          _inputPin = "";      
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void lockChat() {
    if (mounted) {
      setState(() {
        _isUnlocked = false;
        _inputPin = "";
      });
    }
  }

  // --- LOGIQUE DE DÉFINITION DU PIN ---
  void _showPinSetupDialog() {
    TextEditingController pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF162530) : Colors.white,
        title: Text("Définir un PIN", style: TextStyle(color: widget.isDark ? Colors.white : Colors.black)),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: "4 chiffres",
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() { _savedPin = null; _isUnlocked = false; });
              Navigator.pop(context);
            },
            child: const Text("DÉSACTIVER", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            onPressed: () {
              if (pinController.text.length == 4) {
                setState(() {
                  _savedPin = pinController.text;
                  _isUnlocked = true;
                });
                Navigator.pop(context);
              }
            },
            child: const Text("VALIDER"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isLocked = _savedPin != null && !_isUnlocked;

    return Scaffold(
      key: _scaffoldKey,
      // Drawer stylé avec largeur contrôlée
      drawer: _buildModernCarouselDrawer(),
      body: Stack(
        children: [
          // 1. LE CONTENU (Flouté si verrouillé)
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: isLocked ? 20 : 0, 
              sigmaY: isLocked ? 20 : 0,
            ),
            child: _buildChatContent(),
          ),

          // 2. L'INTERFACE DE SAISIE
          if (isLocked) 
            Container(
              color: Colors.black.withOpacity(0.5), 
              child: Center(
                child: _buildLockScreenOverlayUI(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatContent() {
    final bgColor = widget.isDark ? const Color(0xFF0F1D27) : Colors.white;
    final appBarColor = widget.isDark ? const Color(0xFF162530) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.bars),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ), 
        title: const Text("Chat", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_savedPin == null ? CupertinoIcons.lock : CupertinoIcons.lock_fill, 
                 color: _savedPin == null ? null : accentColor), 
            onPressed: _showPinSetupDialog
          ),
          IconButton(icon: const Icon(CupertinoIcons.search), onPressed: () {}),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(150),
          child: Column(
            children: [
              _buildStoriesSection(),
              _buildTabBar(),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatList(),
          const Center(child: Text("Messages Professionnels", style: TextStyle(color: Colors.grey))),
          const Center(child: Text("Messages Non Lus", style: TextStyle(color: Colors.grey))),
          const Center(child: Text("Favoris", style: TextStyle(color: Colors.grey))),
        ],
      ),
      floatingActionButton: _buildFloatingButtons(),
    );
  }

  // --- DRAWER MODERNE STYLE CAROUSEL TELEGRAM PREMIUM ---
  Widget _buildModernCarouselDrawer() {
    final double drawerWidth = MediaQuery.of(context).size.width * 0.75; // Largeur réduite

    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.transparent,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.scale(
            scale: 0.95 + (0.05 * value),
            child: Opacity(
              opacity: value,
              child: child,
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF162530) : Colors.white,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 5,
              )
            ],
          ),
          child: Column(
            children: [
              _buildDrawerHeader(),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  children: [
                    _buildCarouselItem("Nouveau groupe", CupertinoIcons.group, Colors.blueAccent),
                    _buildCarouselItem("Contacts", CupertinoIcons.person_2, Colors.orangeAccent),
                    _buildCarouselItem("Appels", CupertinoIcons.phone, Colors.greenAccent),
                    _buildCarouselItem("Messages enregistrés", CupertinoIcons.bookmark, Colors.purpleAccent),
                    _buildCarouselItem("Paramètres", CupertinoIcons.settings, Colors.blueGrey),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                      child: Divider(color: Colors.white10, thickness: 0.5),
                    ),
                    _buildCarouselItem("Inviter des amis", CupertinoIcons.person_add, Colors.cyan),
                    _buildCarouselItem("Aide Telegram", CupertinoIcons.question_circle, Colors.pinkAccent),
                  ],
                ),
              ),
              _buildDrawerFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withOpacity(0.8),
            accentColor,
          ],
        ),
        borderRadius: const BorderRadius.only(topRight: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: const CircleAvatar(
                  radius: 32,
                  backgroundImage: NetworkImage("https://i.pravatar.cc/150?u=me"),
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: Icon(
                  widget.isDark ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_fill,
                  color: Colors.white.withOpacity(0.9),
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Text(
            "Moshé Ismaël",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            "+243 999 000 000",
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselItem(String title, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        onTap: () => Navigator.pop(context),
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: widget.isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
          ),
        ),
        trailing: Icon(
          CupertinoIcons.chevron_right,
          size: 14,
          color: widget.isDark ? Colors.white24 : Colors.black12,
        ),
      ),
    );
  }

  Widget _buildDrawerFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.isDark ? Colors.black26 : Colors.grey.shade50,
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(30)),
      ),
      child: InkWell(
        onTap: () {},
        child: Row(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
              ).createShader(bounds),
              child: const Icon(CupertinoIcons.star_circle_fill, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 15),
            const Expanded(
              child: Text(
                "Telegram Premium",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 16, color: accentColor),
          ],
        ),
      ),
    );
  }

  // --- INTERFACE DE VERROUILLAGE ---
  Widget _buildLockScreenOverlayUI() {
    return SizedBox(
      width: 250, 
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withOpacity(0.1),
              border: Border.all(color: accentColor.withOpacity(0.2)),
            ),
            child: Icon(CupertinoIcons.lock_shield_fill, size: 35, color: accentColor),
          ),
          const SizedBox(height: 15),
          const Text(
            "ACCÈS SÉCURISÉ",
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _inputPin.length ? accentColor : Colors.white10,
                border: Border.all(color: Colors.white24),
              ),
            )),
          ),
          const SizedBox(height: 40),
          Column(
            children: [
              _buildKeyboardRow(["1", "2", "3"]),
              const SizedBox(height: 12),
              _buildKeyboardRow(["4", "5", "6"]),
              const SizedBox(height: 12),
              _buildKeyboardRow(["7", "8", "9"]),
              const SizedBox(height: 12),
              _buildKeyboardRow(["C", "0", "OK"]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboardRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) => SizedBox(
        width: 55, height: 55, 
        child: _buildKeypadButton(key),
      )).toList(),
    );
  }

  Widget _buildKeypadButton(String val) {
    return InkWell(
      onTap: () {
        setState(() {
          if (val == "C") {
            if (_inputPin.isNotEmpty) _inputPin = _inputPin.substring(0, _inputPin.length - 1);
          } else if (val == "OK") {
            if (_inputPin == _savedPin) { _isUnlocked = true; _inputPin = ""; } else { _inputPin = ""; }
          } else if (_inputPin.length < 4) {
            _inputPin += val;
            if (_inputPin == _savedPin) { _isUnlocked = true; _inputPin = ""; }
          }
        });
      },
      borderRadius: BorderRadius.circular(50),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.08),
          border: Border.all(color: Colors.white12),
        ),
        alignment: Alignment.center,
        child: Text(
          val,
          style: TextStyle(
            color: val == "OK" ? accentColor : (val == "C" ? Colors.redAccent : Colors.white),
            fontSize: (val == "OK" || val == "C") ? 14 : 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // --- SECTIONS STORIES / TABS / LISTES ---
  Widget _buildStoriesSection() {
    final List<Map<String, String>> stories = [
      {"name": "Ma story", "img": "https://i.pravatar.cc/150?u=a"},
      {"name": "Drc", "img": "https://i.pravatar.cc/150?u=b"},
      {"name": "AARON", "img": "https://i.pravatar.cc/150?u=c"},
      {"name": "Maman", "img": "https://i.pravatar.cc/150?u=d"},
      {"name": "Boss", "img": "https://i.pravatar.cc/150?u=e"},
    ];
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: stories.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: index == 0 ? null : LinearGradient(colors: [accentColor.withOpacity(0.5), accentColor]),
                    border: index == 0 ? Border.all(color: Colors.grey, width: 1) : null,
                  ),
                  child: CircleAvatar(radius: 28, backgroundImage: NetworkImage(stories[index]['img']!)),
                ),
                const SizedBox(height: 5),
                Text(stories[index]['name']!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      indicatorColor: accentColor,
      labelColor: accentColor,
      unselectedLabelColor: Colors.grey,
      tabs: [
        _tabItem("TOUS", "2"),
        _tabItem("PRO", "4"),
        _tabItem("NON LUS", "12"),
        _tabItem("PERSO", null),
      ],
    );
  }

  Widget _tabItem(String title, String? count) {
    return Tab(
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          if (count != null) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: accentColor.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
              child: Text(count, style: TextStyle(fontSize: 10, color: accentColor)),
            )
          ]
        ],
      ),
    );
  }

  Widget _buildChatList() {
    final List<Map<String, dynamic>> chats = [
      {"name": "Papa Jean", "msg": "On se voit demain au chantier ?", "time": "06:42 PM", "count": "2", "isPinned": true},
      {"name": "Microsoft Copilot", "msg": "En partageant votre téléphone...", "time": "05:47 PM", "isVerified": true},
      {"name": "Lualaba Mining Info", "msg": "Nouveaux prix du cuivre affichés.", "time": "04:47 PM", "count": "30", "isVerified": true},
    ];
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: chats.length,
      separatorBuilder: (context, index) => Divider(color: widget.isDark ? Colors.white10 : Colors.black12, indent: 80),
      itemBuilder: (context, index) {
        final chat = chats[index];
        return ListTile(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => ChatDetailScreen(name: chat['name'], isDark: widget.isDark, isVerified: chat['isVerified'] ?? false)));
          },
          leading: CircleAvatar(radius: 28, backgroundImage: NetworkImage("https://i.pravatar.cc/150?u=${chat['name']}")),
          title: Text(chat['name'], style: TextStyle(fontWeight: FontWeight.bold, color: widget.isDark ? Colors.white : Colors.black)),
          subtitle: Text(chat['msg'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
          trailing: Text(chat['time'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
        );
      },
    );
  }

  Widget _buildFloatingButtons() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(mini: true, heroTag: "btn1", backgroundColor: const Color(0xFF1D2C39), onPressed: () {}, child: const Icon(Icons.edit, color: Colors.white, size: 20)),
        const SizedBox(height: 10),
        FloatingActionButton(heroTag: "btn2", backgroundColor: accentColor, onPressed: () {}, child: const Icon(Icons.camera_alt, color: Colors.white)),
        const SizedBox(height: 80), 
      ],
    );
  }
}
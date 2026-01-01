import 'dart:ui'; // INDISPENSABLE pour le flou
import 'package:flutter/material.dart';
import 'chat_detail_screen.dart';

class ChatListPage extends StatefulWidget {
  final bool isDark;
  const ChatListPage({super.key, required this.isDark});

  @override
  State<ChatListPage> createState() => ChatListPageState();
}

class ChatListPageState extends State<ChatListPage> with TickerProviderStateMixin {
  late TabController _tabController;
  
  // --- VARIABLES DE SÉCURITÉ ---
  String? _savedPin; 
  bool _isUnlocked = false;
  String _inputPin = ""; 

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
          decoration: const InputDecoration(hintText: "4 chiffres"),
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
      body: Stack(
        children: [
          // 1. LE CONTENU (Flouté séparément via ImageFiltered)
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: isLocked ? 20 : 0, 
              sigmaY: isLocked ? 20 : 0,
            ),
            child: _buildChatContent(),
          ),

          // 2. L'INTERFACE DE SAISIE (Nette et centrée)
          if (isLocked) 
            Container(
              color: Colors.black.withOpacity(0.5), // Voile pour faire ressortir le clavier
              child: Center(
                child: _buildLockScreenOverlayUI(),
              ),
            ),
        ],
      ),
    );
  }

  // --- TON CONTENU ORIGINAL (SANS TOUCHE) ---
  Widget _buildChatContent() {
    final bgColor = widget.isDark ? const Color(0xFF0F1D27) : Colors.white;
    final appBarColor = widget.isDark ? const Color(0xFF162530) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: const Icon(Icons.menu),
        title: const Text("Chat", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_savedPin == null ? Icons.lock_outline : Icons.lock, 
                 color: _savedPin == null ? null : const Color(0xFF00CBA9)), 
            onPressed: _showPinSetupDialog
          ),
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
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

  // --- INTERFACE DE VERROUILLAGE RÉDUITE ---
  Widget _buildLockScreenOverlayUI() {
    return Container(
      width: 250, // Taille centrée et réduite
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00CBA9).withOpacity(0.1),
              border: Border.all(color: const Color(0xFF00CBA9).withOpacity(0.2)),
            ),
            child: const Icon(Icons.lock_rounded, size: 35, color: Color(0xFF00CBA9)),
          ),
          const SizedBox(height: 15),
          const Text(
            "ACCÈS SÉCURISÉ",
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
          const SizedBox(height: 30),

          // Indicateurs PIN
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _inputPin.length ? const Color(0xFF00CBA9) : Colors.white10,
                border: Border.all(color: Colors.white24),
              ),
            )),
          ),
          const SizedBox(height: 40),

          // Pavé numérique réduit
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
        width: 55, height: 55, // Touches plus petites
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
            color: val == "OK" ? const Color(0xFF00CBA9) : (val == "C" ? Colors.redAccent : Colors.white),
            fontSize: (val == "OK" || val == "C") ? 14 : 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // --- TES MÉTHODES DE DESIGN ORIGINALES ---
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
                    gradient: index == 0 ? null : const LinearGradient(colors: [Colors.purple, Colors.blue, Colors.green]),
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
      indicatorColor: Colors.blue,
      labelColor: Colors.blue,
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
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
              child: Text(count, style: const TextStyle(fontSize: 10, color: Colors.blue)),
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
        FloatingActionButton(heroTag: "btn2", backgroundColor: const Color(0xFF4BA3E3), onPressed: () {}, child: const Icon(Icons.camera_alt, color: Colors.white)),
        const SizedBox(height: 80), 
      ],
    );
  }
}
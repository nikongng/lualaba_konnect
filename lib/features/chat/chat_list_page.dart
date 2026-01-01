import 'package:flutter/material.dart';
import 'chat_detail_screen.dart'; // Assure-toi que ce fichier existe

class ChatListPage extends StatefulWidget {
  final bool isDark;
  const ChatListPage({super.key, required this.isDark});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Initialisation des 4 onglets : TOUS, PRO, NON LUS, PERSO
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          IconButton(icon: const Icon(Icons.lock_outline), onPressed: () {}),
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
          _buildChatList(), // Contenu pour l'onglet "TOUS"
          const Center(child: Text("Messages Professionnels", style: TextStyle(color: Colors.grey))),
          const Center(child: Text("Messages Non Lus", style: TextStyle(color: Colors.grey))),
          const Center(child: Text("Favoris", style: TextStyle(color: Colors.grey))),
        ],
      ),
      floatingActionButton: _buildFloatingButtons(),
    );
  }

  // --- 1. SECTION STORIES ---
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
                    gradient: index == 0 
                        ? null 
                        : const LinearGradient(colors: [Colors.purple, Colors.blue, Colors.green]),
                    border: index == 0 ? Border.all(color: Colors.grey, width: 1) : null,
                  ),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(stories[index]['img']!),
                  ),
                ),
                const SizedBox(height: 5),
                Text(stories[index]['name']!, 
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- 2. BARRE D'ONGLETS ---
  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      indicatorColor: Colors.blue,
      indicatorWeight: 3,
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
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2), 
                borderRadius: BorderRadius.circular(10)
              ),
              child: Text(count, style: const TextStyle(fontSize: 10, color: Colors.blue)),
            )
          ]
        ],
      ),
    );
  }

  // --- 3. LISTE DES MESSAGES (LOGIQUE DYNAMIQUE) ---
  Widget _buildChatList() {
    final List<Map<String, dynamic>> chats = [
      {"name": "Papa Jean", "msg": "On se voit demain au chantier ?", "time": "06:42 PM", "count": "2", "isPinned": true},
      {"name": "Microsoft Copilot", "msg": "En partageant votre téléphone...", "time": "05:47 PM", "isVerified": true},
      {"name": "Lualaba Mining Info", "msg": "Nouveaux prix du cuivre affichés.", "time": "04:47 PM", "count": "30", "isVerified": true},
      {"name": "Sarah", "msg": "Le design est incroyable ! 🔥", "time": "12:10 PM", "count": null},
      {"name": "Archives", "msg": "Dossiers compressés reçus", "time": "Hier", "count": "149", "isArchive": true},
    ];

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: chats.length,
      separatorBuilder: (context, index) => Divider(
        color: widget.isDark ? Colors.white10 : Colors.black12, 
        height: 1, 
        indent: 80
      ),
      itemBuilder: (context, index) {
        final chat = chats[index];
        return ListTile(
          onTap: () {
            // NAVIGATION VERS LE DÉTAIL
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatDetailScreen(
                  name: chat['name'],
                  isDark: widget.isDark,
                  isVerified: chat['isVerified'] ?? false,
                ),
              ),
            );
          },
leading: Stack(
            children: [
              // L'avatar du contact
              CircleAvatar(
                radius: 28,
                backgroundColor: chat['isArchive'] == true ? Colors.grey[800] : Colors.blueGrey,
                backgroundImage: chat['isArchive'] == true 
                    ? null 
                    : NetworkImage("https://i.pravatar.cc/150?u=${chat['name']}"),
                child: chat['isArchive'] == true 
                    ? const Icon(Icons.archive_outlined, color: Colors.white) 
                    : null,
              ),
              // Le point vert (Indicateur en ligne)
              // On ne l'affiche pas pour les archives
              if (chat['isArchive'] != true)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    height: 14,
                    width: 14,
                    decoration: BoxDecoration(
                      color: Colors.green, // Couleur "En ligne"
                      shape: BoxShape.circle,
                      // Bordure pour détacher le point de l'avatar (effet propre)
                      border: Border.all(
                        color: widget.isDark ? const Color(0xFF0F1D27) : Colors.white,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          title: Row(
            children: [
              Text(chat['name'], 
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    color: widget.isDark ? Colors.white : Colors.black
                  )),
              if (chat['isVerified'] == true) const SizedBox(width: 5),
              if (chat['isVerified'] == true) 
                const Icon(Icons.check_circle, color: Colors.blue, size: 16),
            ],
          ),
          subtitle: Text(chat['msg'], 
              maxLines: 1, 
              overflow: TextOverflow.ellipsis, 
              style: const TextStyle(color: Colors.grey)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(chat['time'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
              if (chat['count'] != null) ...[
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: chat['isArchive'] == true ? Colors.grey : Colors.blue, 
                    borderRadius: BorderRadius.circular(10)
                  ),
                  child: Text(chat['count'], 
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                )
              ]
            ],
          ),
        );
      },
    );
  }

  // --- 4. BOUTONS FLOTTANTS (CRAYON + CAMÉRA) ---
  Widget _buildFloatingButtons() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(
          mini: true,
          heroTag: "btn1",
          backgroundColor: const Color(0xFF1D2C39),
          onPressed: () {},
          child: const Icon(Icons.edit, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 10),
        FloatingActionButton(
          heroTag: "btn2",
          backgroundColor: const Color(0xFF4BA3E3),
          onPressed: () {},
          child: const Icon(Icons.camera_alt, color: Colors.white),
        ),
        const SizedBox(height: 80), // Espace pour la barre de navigation du dashboard
      ],
    );
  }
}
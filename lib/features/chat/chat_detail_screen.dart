import 'package:flutter/material.dart';

class ChatDetailScreen extends StatefulWidget {
  final String name;
  final bool isDark;
  final bool isVerified;

  const ChatDetailScreen({
    super.key,
    required this.name,
    required this.isDark,
    this.isVerified = false,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [
    {"text": "Salut ! Comment se passe le projet au Lualaba ?", "isMe": false, "time": "10:45"},
    {"text": "Ça avance très bien, on termine la phase de design.", "isMe": true, "time": "10:46"},
    {"text": "Super ! Envoie-moi les captures dès que possible.", "isMe": false, "time": "10:47"},
  ];

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _messages.add({
        "text": _controller.text,
        "isMe": true,
        "time": "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
      });
    });
    _controller.clear();
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF0F1D27) : const Color(0xFFE5DDD5);
    final appBarColor = widget.isDark ? const Color(0xFF162530) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 1,
        foregroundColor: widget.isDark ? Colors.white : Colors.black,
        leadingWidth: 70,
        leading: InkWell(
          onTap: () => Navigator.pop(context),
          child: Row(
            children: [
              const SizedBox(width: 5),
              const Icon(Icons.arrow_back, size: 24),
              const SizedBox(width: 5),
              const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 20)),
            ],
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (widget.isVerified) const SizedBox(width: 5),
                if (widget.isVerified) const Icon(Icons.check_circle, color: Colors.blue, size: 14),
              ],
            ),
            const Text("en ligne", style: TextStyle(fontSize: 12, color: Colors.blue)),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.more_vert), onPressed: () {})],
      ),
      body: Stack(
        children: [
          // --- COUCHE 1 : LE FOND AVEC DESSINS (Wallpaper) ---
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: bgColor,
              image: const DecorationImage(
                image: NetworkImage("https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png"),
                opacity: 0.06, // Très léger pour l'élégance
                repeat: ImageRepeat.repeat,
              ),
            ),
          ),
          
          // --- COUCHE 2 : LES MESSAGES ET L'INPUT ---
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(15),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
                ),
              ),
              _buildInputBar(appBarColor),
            ],
          ),
        ],
      ),
    );
  }

Widget _buildMessageBubble(Map<String, dynamic> msg) {
  bool isMe = msg['isMe'];
  
  // 1. DÉGRADÉ NÉON POUR "MOI" (Rose vers Violet)
  final LinearGradient myGradient = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE91E63), // Rose vif
      Color(0xFF9C27B0), // Violet profond
    ],
  );

  // 2. DÉGRADÉ POUR "L'AUTRE" (Gris bleuté ou Sombre)
  final LinearGradient otherGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: widget.isDark 
      ? [const Color(0xFF243447), const Color(0xFF1B2836)] 
      : [const Color(0xFFF5F7FB), const Color(0xFFE8EEF5)],
  );

  Color textColor = isMe ? Colors.white : (widget.isDark ? Colors.white : Colors.black87);

  return Align(
    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: isMe ? myGradient : otherGradient,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(isMe ? 22 : 6),
          bottomRight: Radius.circular(isMe ? 6 : 22),
        ),
        boxShadow: [
          BoxShadow(
            color: isMe 
              ? const Color(0xFF9C27B0).withOpacity(0.3) // Ombre colorée pour l'effet néon
              : Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 50, bottom: 4),
            child: Text(
              msg['text'],
              style: TextStyle(
                color: textColor, 
                fontSize: 16,
                fontWeight: isMe ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg['time'],
                  style: TextStyle(
                    color: textColor.withOpacity(0.7), 
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.done_all, 
                    size: 15, 
                    color: Color(0xFF00E5FF), // Cyan brillant pour le "vu" sur le violet
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildInputBar(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: color,
      child: SafeArea(
        child: Row(
          children: [
            const Icon(Icons.attach_file, color: Colors.grey),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: widget.isDark ? Colors.black : Colors.grey[100],
                  borderRadius: BorderRadius.circular(25),
                ),
                child: TextField(
                  controller: _controller,
                  // Couleur du texte adaptée au mode
                  style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
                  decoration: const InputDecoration(
                    hintText: "Message", 
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            GestureDetector(
              onTap: _sendMessage,
              child: const CircleAvatar(
                backgroundColor: Color(0xFF4BA3E3),
                child: Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

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
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;

  late final GenerativeModel _model;
  late final ChatSession _chat;

  @override
  void initState() {
    super.initState();
    _initGemini();
  }

  void _initGemini() {
    // On récupère la clé depuis le .env (géré par Codemagic en prod)
    const String apiKey = String.fromEnvironment('GEMINI_KEY'); 

    _model = GenerativeModel(
      model: 'gemini-2.5-flash', // Modèle stable et gratuit
      apiKey: apiKey,
      systemInstruction: Content.system(
        "Tu es un congolais cool, sage et juste. "
        "Tu t'adresses à ton ami avec affection. "
        "Tu es actuellement au Lualaba. "
        "Ton ton est encourageant, tu donnes souvent des conseils de vie et tu insistes sur l'importance du travail et de la famille. "
        "Tu réponds de manière concise, comme sur WhatsApp, et tu utilises parfois des expressions chaleureuses du pays."
      ),
    );

    _chat = _model.startChat();

    _messages.add({
      "text": "Bonjour ! Comment puis-je t'aider ?",
      "isMe": false,
      "time": _getTime(),
    });
  }

  String _getTime() {
    final now = DateTime.now();
    return "${now.hour}:${now.minute.toString().padLeft(2, '0')}";
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCirc,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final userText = _controller.text.trim();
    if (userText.isEmpty) return;

    setState(() {
      _messages.add({"text": userText, "isMe": true, "time": _getTime()});
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final response = await _chat.sendMessage(Content.text(userText));
      
      setState(() {
        _isTyping = false;
        if (response.text != null) {
          _messages.add({
            "text": response.text!,
            "isMe": false,
            "time": _getTime()
          });
        }
      });
    } catch (e) {
      setState(() => _isTyping = false);
      debugPrint("ERREUR TECHNIQUE GEMINI : $e");
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Détail de l'erreur : $e"),
            backgroundColor: Colors.redAccent,
          ), 
        );
      }
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF0F2027) : const Color(0xFFE5DDD5);
    final appBarColor = widget.isDark ? const Color(0xFF162530) : Colors.white;

    return Scaffold(
      extendBody: true,
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 1,
        foregroundColor: widget.isDark ? Colors.white : Colors.black,
        leadingWidth: 70,
        leading: InkWell(
          onTap: () => Navigator.pop(context),
          child: const Row(
            children: [
              SizedBox(width: 8),
              Icon(Icons.arrow_back),
              SizedBox(width: 4),
              CircleAvatar(radius: 16, child: Icon(Icons.person, size: 20)),
            ],
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (widget.isVerified) ...[
                  const SizedBox(width: 5),
                  const Icon(Icons.check_circle, color: Colors.blue, size: 14),
                ],
              ],
            ),
            Text(
              _isTyping ? "en train d'écrire..." : "en ligne",
              style: TextStyle(fontSize: 12, color: _isTyping ? Colors.green : Colors.blue),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: widget.isDark ? 0.05 : 0.08,
              child: Image.network(
                "https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png",
                repeat: ImageRepeat.repeat,
                scale: 2,
              ),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 100),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
                ),
              ),
              _buildGlassInputBar(appBarColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    bool isMe = msg['isMe'];
    return PulseBubble(
      key: UniqueKey(),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: isMe 
                ? const LinearGradient(colors: [Color(0xFFE91E63), Color(0xFF9C27B0)])
                : null,
            color: isMe ? null : (widget.isDark ? const Color(0xFF1D2C39) : Colors.white),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isMe ? 20 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                msg['text'],
                style: TextStyle(
                  color: isMe || widget.isDark ? Colors.white : Colors.black87, 
                  fontSize: 16
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    msg['time'], 
                    style: TextStyle(
                      color: (isMe || widget.isDark ? Colors.white : Colors.black54).withOpacity(0.5), 
                      fontSize: 10
                    )
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4), 
                    const Icon(Icons.done_all, size: 14, color: Color(0xFF00E5FF))
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassInputBar(Color color) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.8),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
          ),
          child: SafeArea(
            child: Row(
              children: [
                const Icon(Icons.emoji_emotions_outlined, color: Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: widget.isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
                      decoration: const InputDecoration(
                        hintText: "Écrire un message...", 
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _handleSend,
                  child: const CircleAvatar(
                    backgroundColor: Color(0xFF4BA3E3),
                    child: Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PulseBubble extends StatefulWidget {
  final Widget child;
  const PulseBubble({super.key, required this.child});
  @override
  State<PulseBubble> createState() => _PulseBubbleState();
}

class _PulseBubbleState extends State<PulseBubble> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 400), vsync: this);
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack)
    );
    _controller.forward();
  }
  @override
  void dispose() { 
    _controller.dispose(); 
    super.dispose(); 
  }
  @override
  Widget build(BuildContext context) { 
    return FadeTransition(
      opacity: _controller, 
      child: ScaleTransition(scale: _scale, child: widget.child)
    ); 
  }
}
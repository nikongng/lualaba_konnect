import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';


class MastaCard extends StatefulWidget {
  final Function(String) onChatSubmit;

  const MastaCard({super.key, required this.onChatSubmit});

  @override
  State<MastaCard> createState() => _MastaCardState();
}

class _MastaCardState extends State<MastaCard> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  bool _isExpanded = false; 
  bool _isTyping = false;
  List<Map<String, String>> _messages = []; 
  
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late GenerativeModel _model;

  @override
  void initState() {
    super.initState();
final String apiKey ='AIzaSyC1HAM3Poy6oQYR_Y0pT0duyv_Hxib4knU';
_model = GenerativeModel(
  model: 'gemini-2.5-flash', // Modèle Gemini
  apiKey: apiKey,

  systemInstruction: Content.system(
   "Tu es Masta, un ami bienveillant, sage et protecteur. "
      "Tu t'adresses à l'utilisateur avec une affection fraternelle (utilise des mots comme 'mon ami', 'ma famille'). "
      "Tu es actuellement au Lualaba pour superviser un projet important dans les mines. "
      "Ton ton est encourageant, tu donnes souvent des conseils de vie et tu insistes sur l'importance du travail. "
      "Tu réponds de manière concise, comme sur WhatsApp, et tu utilises parfois des expressions chaleureuses du pays."
  ),
);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    setState(() {
      _isExpanded = true;
      _messages.add({"role": "user", "text": text});
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      // Prompt personnalisé pour donner l'identité "Masta"
      final content = [Content.text("Tu es Masta, l'IA assistante de LualabaConnect. Sois bref, utile et expert du Lualaba. Question : $text")];
      final response = await _model.generateContent(content);
      
      setState(() {
        _isTyping = false;
        _messages.add({"role": "masta", "text": response.text ?? "Je n'ai pas pu formuler de réponse."});
      });
    } catch (e) {
      setState(() {
        _isTyping = false;
        _messages.add({"role": "masta", "text": "Désolé, j'ai un problème de connexion."});
      });
    }
    _scrollToBottom();
    widget.onChatSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.fastOutSlowIn,
      width: double.infinity,
      height: _isExpanded ? 420 : 165,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7F00FF), Color(0xFFE100FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7F00FF).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: const CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 14,
                  child: Icon(Icons.face, color: Color(0xFF7F00FF), size: 16),
                ),
              ),
              const SizedBox(width: 10),
              const Text("Masta", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
              const Spacer(),
              if (_isExpanded)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: () => setState(() => _isExpanded = false),
                )
              else
                const Text("Bêta", style: TextStyle(color: Colors.white70, fontSize: 9)),
            ],
          ),
          
          if (!_isExpanded) ...[
            const SizedBox(height: 8),
            const Text("Pose moi une question, je suis ton assistant", style: TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(height: 15),
          ],
          
          // Zone de Chat
          if (_isExpanded)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text("Masta réfléchit...", style: TextStyle(color: Colors.white54, fontSize: 11, fontStyle: FontStyle.italic)),
                      );
                    }
                    bool isMasta = _messages[index]["role"] == "masta";
                    return Align(
                      alignment: isMasta ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isMasta ? Colors.white24 : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _messages[index]["text"]!,
                          style: TextStyle(color: isMasta ? Colors.white : const Color(0xFF7F00FF), fontSize: 12),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Barre de saisie
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: "Écris ici...",
                      hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _handleSend,
                child: Container(
                  height: 42, width: 42,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Icon(_isTyping ? Icons.hourglass_top : Icons.send_rounded, size: 16, color: const Color(0xFF7F00FF)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
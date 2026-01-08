import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StoryViewerPage extends StatefulWidget {
  final List<DocumentSnapshot> stories;
  final int initialIndex;

  const StoryViewerPage({
    super.key,
    required this.stories,
    required this.initialIndex,
  });

  @override
  StoryViewerPageState createState() => StoryViewerPageState();
}

class StoryViewerPageState extends State<StoryViewerPage> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    // Contrôleur pour la barre de progression (5 secondes par story)
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _loadStory(index: _currentIndex);

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });
  }

  void _loadStory({required int index, bool animatePage = true}) {
    _animController.stop();
    _animController.reset();
    _animController.forward();
    
    if (animatePage) {
      _pageController.jumpToPage(index);
    }
  }

  void _nextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _loadStory(index: _currentIndex);
    } else {
      // Si c'est la dernière story, on ferme l'afficheur
      Navigator.of(context).pop();
    }
  }

  void _prevStory() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _loadStory(index: _currentIndex);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Pause au maintien, reprise au relâchement
        onLongPressStart: (_) => _animController.stop(),
        onLongPressEnd: (_) => _animController.forward(),
        
        onTapUp: (details) {
          final double screenWidth = MediaQuery.of(context).size.width;
          final double dx = details.globalPosition.dx;
          
          if (dx < screenWidth / 3) {
            _prevStory(); // Clic zone gauche
          } else {
            _nextStory(); // Clic zone droite
          }
        },
        child: Stack(
          children: [
            // Affichage de l'image
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // On gère via le clic
              itemCount: widget.stories.length,
              itemBuilder: (context, index) {
                final story = widget.stories[index].data() as Map<String, dynamic>;
                return Image.network(
                  story['imageUrl'],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  },
                );
              },
            ),

            // Barres de progression
            Positioned(
              top: 50,
              left: 10,
              right: 10,
              child: Row(
                children: widget.stories.asMap().entries.map((entry) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AnimatedBuilder(
                        animation: _animController,
                        builder: (context, child) {
                          double val = 0.0;
                          if (entry.key < _currentIndex) {
                            val = 1.0;
                          } else if (entry.key == _currentIndex) {
                            val = _animController.value;
                          }
                          return LinearProgressIndicator(
                            value: val,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            minHeight: 3,
                          );
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Infos (Nom + Bouton fermer)
            Positioned(
              top: 65,
              left: 15,
              right: 15,
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    (widget.stories[_currentIndex].data() as Map<String, dynamic>)['userName'] ?? 'Utilisateur',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
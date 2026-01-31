import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart'; // Ajout pour des icônes style Apple
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../chat/presentation/pages/chat_list_page.dart'; 

class FloatingNavBar extends StatefulWidget {
  final bool isDark;
  final int selectedIndex;
  final Function(int) onIndexChanged;
  final GlobalKey<ChatListPageState> chatKey;

  const FloatingNavBar({
    super.key,
    required this.isDark,
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.chatKey,
  });

  @override
  State<FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<FloatingNavBar> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTap(int index) {
    _pulseController.forward().then((_) => _pulseController.reverse());
    HapticFeedback.mediumImpact(); 
    
    if (index == 1 && widget.selectedIndex != 1) {

    }
    
    widget.onIndexChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: LayoutBuilder(
          builder: (context, constraints) {
            final double totalWidth = constraints.maxWidth;
            final double itemWidth = totalWidth / 5;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              height: 65,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: widget.isDark 
                        ? Colors.black.withOpacity(0.5) 
                        : const Color(0xFF00CBA9).withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? const Color(0xFF1E3E3B).withOpacity(0.8)
                          : Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(
                        color: widget.isDark 
                            ? Colors.white.withOpacity(0.15) 
                            : const Color(0xFF00CBA9).withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // CAPSULE DE FOCUS ARRIÈRE (Glow doux)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutExpo,
                          left: (itemWidth * widget.selectedIndex) + (itemWidth * 0.15),
                          top: 12,
                          bottom: 12,
                          child: Container(
                            width: itemWidth * 0.7,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00CBA9).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),

                        // POINT INDICATEUR
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.elasticOut,
                          left: (itemWidth * widget.selectedIndex) + (itemWidth / 2) - 3,
                          bottom: 10,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00CBA9),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),

                        // LES BOUTONS AVEC ICÔNES MODERNES
                        Row(
                          children: List.generate(5, (index) => _buildNavItem(index)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
  }

  Widget _buildNavItem(int index) {
    final bool isSelected = widget.selectedIndex == index;
    
    // --- SET D'ICÔNES MODERNES (Combinaison Material/Cupertino) ---
    final List<IconData> icons = [
      isSelected ? Icons.home_filled : Icons.home_outlined, // Accueil
      isSelected ? CupertinoIcons.chat_bubble_2_fill : CupertinoIcons.chat_bubble_2, // Chat
      isSelected ? CupertinoIcons.compass_fill : CupertinoIcons.compass, // Découverte
      isSelected ? Icons.shopping_bag : Icons.shopping_bag_outlined, // Boutique
      isSelected ? CupertinoIcons.person_fill : CupertinoIcons.person, // Profil
    ];

    return Expanded(
      child: GestureDetector(
        onTap: () => _handleTap(index),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            scale: isSelected ? 1.25 : 1.0,
            child: Builder(builder: (context) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              // For the market button (index 3), show unread market messages count
              if (index == 3 && uid != null) {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('market_messages')
                      .where('to', isEqualTo: uid)
                      .where('read', isEqualTo: false)
                      .snapshots(),
                  builder: (ctx, snap) {
                    final count = snap.data?.docs.length ?? 0;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          icons[index],
                          size: 24,
                          color: isSelected
                              ? const Color(0xFF00CBA9)
                              : (widget.isDark ? Colors.white38 : Colors.black38),
                        ),
                        if (index == 1 && (widget.chatKey.currentState?.unreadTotal ?? 0) > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: const Color(0xFF64B5F6), shape: BoxShape.circle, border: Border.all(color: widget.isDark ? Colors.black : Colors.white, width: 1.5)),
                              child: Text('${widget.chatKey.currentState?.unreadTotal ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                        ),
                        if (count > 0)
                          Positioned(
                            right: -8,
                            top: -8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(12), border: Border.all(color: widget.isDark ? Colors.black : Colors.white, width: 1.5)),
                              child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    );
                  },
                );
              }

              // Default icon stack (including chat badge)
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icons[index],
                    size: 24, // Taille légèrement réduite pour plus d'élégance
                    color: isSelected 
                        ? const Color(0xFF00CBA9) 
                        : (widget.isDark ? Colors.white38 : Colors.black38),
                  ),
                  if (index == 1 && (widget.chatKey.currentState?.unreadTotal ?? 0) > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFF64B5F6), shape: BoxShape.circle, border: Border.all(color: widget.isDark ? Colors.black : Colors.white, width: 1.5)),
                        child: Text('${widget.chatKey.currentState?.unreadTotal ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
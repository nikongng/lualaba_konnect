import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../chat/presentation/pages/story_viewer_page.dart';

class StoryBar extends StatelessWidget {
  final String currentUserId;
  final VoidCallback onAddStoryTap;

  const StoryBar({
    super.key,
    required this.currentUserId,
    required this.onAddStoryTap,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: StreamBuilder<QuerySnapshot>(
        // On récupère les stories non expirées, triées par date
        stream: FirebaseFirestore.instance
            .collection('stories')
            .where('expiresAt', isGreaterThan: DateTime.now())
            .orderBy('expiresAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          final stories = snapshot.data?.docs ?? [];

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: stories.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                // Ta story (Bouton ajouter)
                return _buildMyStoryCircle(user);
              }

              // Stories des autres
              var doc = stories[index - 1];
              var data = doc.data() as Map<String, dynamic>;
              
              return _buildFriendStoryCircle(
                context,
                data['userName'] ?? "Utilisateur",
                data['imageUrl'],
                index - 1,
                stories,
              );
            },
          );
        },
      ),
    );
  }

  // --- CERCLE POUR L'UTILISATEUR ACTUEL (+) ---
  Widget _buildMyStoryCircle(User? user) {
    return GestureDetector(
      onTap: onAddStoryTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 15, right: 5),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey[900],
                    backgroundImage: (user?.photoURL != null)
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: (user?.photoURL == null)
                        ? const Icon(Icons.person, color: Colors.white54)
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              "Ma story",
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // --- CERCLE POUR LES STORIES DES AMIS ---
  Widget _buildFriendStoryCircle(
    BuildContext context,
    String name,
    String? url,
    int index,
    List<DocumentSnapshot> allStories,
  ) {
    return GestureDetector(
      onTap: () {
        // Ouvre l'afficheur de story en plein écran
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StoryViewerPage(
              stories: allStories,
              initialIndex: index,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 5),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFE57C00), // Bordure orange WhatsApp/Instagram
                  width: 2.5,
                ),
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey[800],
                backgroundImage: url != null ? NetworkImage(url) : null,
                child: url == null 
                    ? const Icon(Icons.person, color: Colors.white54) 
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 70,
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
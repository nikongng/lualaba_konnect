import 'package:flutter/material.dart';
import '../../../../../services/presentation/pages/tips_page.dart';

class DailyTipTile extends StatelessWidget {
  const DailyTipTile({super.key});

  @override
  Widget build(BuildContext context) {
    return _buildBaseTile(
      title: "Conseil du jour",
      sub: "Hydratez-vous régulièrement aujourd'hui.",
      colors: [const Color(0xFF00CBA9), const Color(0xFF00A88E)],
      icon: Icons.lightbulb_outline,
      tag: "SANTÉ",
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TipsPage()),
        );
      },
    );
  }

  Widget _buildBaseTile({
    required String title, 
    required String sub, 
    required List<Color> colors, 
    required IconData icon, 
    required String tag, 
    required VoidCallback onTap
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: colors.last.withOpacity(0.3), 
              blurRadius: 10, 
              offset: const Offset(0, 4)
            )
          ],
        ),
        child: Row(
          children: [
            // Conteneur de l'icône
            Container(
              padding: const EdgeInsets.all(12), 
              decoration: BoxDecoration(
                color: Colors.white24, 
                borderRadius: BorderRadius.circular(15)
              ), 
              child: Icon(icon, color: Colors.white, size: 28)
            ),
            const SizedBox(width: 15),
            // Textes centraux
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Text(
                    tag, 
                    style: const TextStyle(
                      color: Colors.white70, 
                      fontSize: 9, 
                      fontWeight: FontWeight.bold
                    )
                  ),
                  Text(
                    title, 
                    style: const TextStyle(
                      color: Colors.white, 
                      fontSize: 17, 
                      fontWeight: FontWeight.bold
                    )
                  ),
                  Text(
                    sub, 
                    style: const TextStyle(
                      color: Colors.white70, 
                      fontSize: 11
                    )
                  ),
                ]
              )
            ),
            // Flèche de direction
            const Icon(
              Icons.arrow_forward_ios_rounded, 
              size: 14, 
              color: Colors.white
            ),
          ],
        ),
      ),
    );
  }
}
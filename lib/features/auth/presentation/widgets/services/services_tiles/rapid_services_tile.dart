import 'package:flutter/material.dart';

import '../../../../../services/presentation/pages/rapid_services_page.dart';

class RapidServicesTile extends StatelessWidget {
  final bool isDark;
  const RapidServicesTile({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bool dark = isDark || Theme.of(context).brightness == Brightness.dark;
    final List<Color> colors = dark
        ? const [Color(0xFF1F2A33), Color(0xFF0B141A)]
        : const [Color(0xFFFF8A00), Color(0xFFFF5A1F)];
    final Color glow = dark ? const Color(0xFFFB8C00) : const Color(0xFFFF6D00);

    return _buildBaseTile(
      title: 'Services Rapides',
      sub: 'Food, Menage, Auto & plus...',
      colors: colors,
      icon: Icons.grid_view_rounded,
      tag: 'CATALOGUE',
      glow: glow,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RapidServicesPage()),
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
    required Color glow,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 16, offset: const Offset(0, 10)),
            BoxShadow(color: glow.withOpacity(0.22), blurRadius: 22, offset: const Offset(0, 12)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withOpacity(0.22)),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tag, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  const SizedBox(height: 2),
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.2)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';
import '../../../../../services/presentation/pages/rapid_services_page.dart';

class RapidServicesTile extends StatelessWidget {
  final bool isDark;
  const RapidServicesTile({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _buildBaseTile(
      title: "Services Rapides",
      sub: "Food, Ménage, Auto & plus...",
      colors: [const Color(0xFF448AFF), const Color(0xFF2962FF)],
      icon: Icons.grid_view_rounded,
      tag: "NOUVEAU",
      onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const RapidServicesPage()),
  );
},
    );
  }

  Widget _buildBaseTile({required String title, required String sub, required List<Color> colors, required IconData icon, required String tag, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: colors.last.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: Colors.white, size: 28)),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tag, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white),
        ]),
      ),
    );
  }
}
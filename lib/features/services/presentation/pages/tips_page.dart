import 'package:flutter/material.dart';

class TipsPage extends StatelessWidget {
  const TipsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;
    const accent = Color(0xFF00A88E);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Conseils utiles', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          _HighlightCard(card: card, text: text, sub: sub, divider: divider),
          _FilterChips(card: card, sub: sub, divider: divider),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _TipCard(
                  card: card,
                  text: text,
                  sub: sub,
                  category: 'SECURITE',
                  title: 'Poussiere sur la route',
                  desc: 'La route vers Musompo est tres poussiereuse en ce moment. Le port du masque est recommande...',
                  icon: Icons.engineering_rounded,
                  iconBg: Colors.orange,
                ),
                _TipCard(
                  card: card,
                  text: text,
                  sub: sub,
                  category: 'TECH',
                  title: 'Economiser sa batterie',
                  desc: 'En zone de faible reseau (H+), votre telephone consomme 2x plus. Basculez en mode economie...',
                  icon: Icons.battery_charging_full_rounded,
                  iconBg: const Color(0xFF64B5F6),
                ),
                _TipCard(
                  card: card,
                  text: text,
                  sub: sub,
                  category: 'VIE PRATIQUE',
                  title: "Coupures d'eau",
                  desc: "Des travaux sont signales sur le reseau REGIDESO quartier Joli Site. Pensez a faire des reserves...",
                  icon: Icons.water_drop_outlined,
                  iconBg: Colors.cyan,
                ),
                const SizedBox(height: 90),
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _ProposeBar(card: card, sub: sub, divider: divider),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.card,
    required this.text,
    required this.sub,
    required this.divider,
  });

  final Color card;
  final Color text;
  final Color sub;
  final Color divider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.30 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A88E).withOpacity(isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF00A88E).withOpacity(0.25)),
                ),
                child: const Text(
                  'CONSEIL DU JOUR',
                  style: TextStyle(color: Color(0xFF00A88E), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
              ),
              Icon(Icons.share_outlined, color: sub, size: 20),
            ],
          ),
          const SizedBox(height: 14),
          Text('Pic de chaleur prevu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: text, letterSpacing: -0.2)),
          const SizedBox(height: 8),
          Text(
            "Aujourd'hui, la temperature ressentie atteindra 32°C. Buvez au moins 2L d'eau et evitez l'exposition directe.",
            style: TextStyle(color: sub, height: 1.35, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined, size: 14, color: Colors.orange),
              Text(' Aujourd\'hui • Meteo', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.card,
    required this.sub,
    required this.divider,
  });

  final Color card;
  final Color sub;
  final Color divider;

  @override
  Widget build(BuildContext context) {
    final filters = const ['Tout', 'Sante', 'Securite', 'Tech', 'Vie pratique'];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final selected = index == 0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Chip(
              backgroundColor: selected ? const Color(0xFF00A88E) : card,
              label: Text(filters[index], style: TextStyle(color: selected ? Colors.white : sub, fontWeight: FontWeight.w700)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: selected ? Colors.transparent : divider)),
              shadowColor: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
              elevation: selected ? 8 : 0,
            ),
          );
        },
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.card,
    required this.text,
    required this.sub,
    required this.category,
    required this.title,
    required this.desc,
    required this.icon,
    required this.iconBg,
  });

  final Color card;
  final Color text;
  final Color sub;
  final String category;
  final String title;
  final String desc;
  final IconData icon;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.28 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg.withOpacity(isDark ? 0.22 : 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: iconBg.withOpacity(0.25)),
            ),
            child: Icon(icon, color: iconBg, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(category, style: TextStyle(color: sub, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                    Icon(Icons.bookmark_border, size: 18, color: sub),
                  ],
                ),
                const SizedBox(height: 2),
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: text, letterSpacing: -0.2)),
                const SizedBox(height: 6),
                Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub, fontSize: 13, height: 1.25, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProposeBar extends StatelessWidget {
  const _ProposeBar({required this.card, required this.sub, required this.divider});

  final Color card;
  final Color sub;
  final Color divider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF00A88E);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.30 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withOpacity(0.25)),
            ),
            child: const Icon(Icons.lightbulb_outline, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Vous avez une astuce ? Partagez-la avec la communaute',
              style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w700, height: 1.1),
            ),
          ),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Proposer', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}


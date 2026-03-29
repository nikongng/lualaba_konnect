import 'package:flutter/material.dart';

import 'home_services_page.dart';
import 'food_services_page.dart';
import 'freelance_pros_page.dart';
import 'mobility_services_page.dart';
import 'real_estate_role_picker_page.dart';
import 'training_services_page.dart';

class RapidServicesPage extends StatefulWidget {
  const RapidServicesPage({super.key});

  @override
  State<RapidServicesPage> createState() => _RapidServicesPageState();
}

class _RapidServicesPageState extends State<RapidServicesPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openServiceSheet(ServiceItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.55 : 0.12), blurRadius: 26, offset: const Offset(0, 14))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: item.color.withOpacity(isDark ? 0.22 : 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: item.color.withOpacity(0.25)),
                    ),
                    child: Icon(item.icon, color: item.color),
                  ),
                  title: Text(item.title, style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                  subtitle: Text(item.sub, style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
                ),
                Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
                ListTile(
                  leading: Icon(Icons.arrow_outward_rounded, color: item.color),
                  title: Text('Ouvrir', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  subtitle: Text('Cette section arrive bientot.', style: TextStyle(color: sub)),
                  onTap: () => Navigator.pop(ctx),
                ),
                Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
                ListTile(
                  leading: Icon(Icons.bookmark_add_outlined, color: sub),
                  title: Text('Ajouter aux favoris', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openService(ServiceItem item) {
    final key = item.title.toLowerCase();
    if (key.contains('mobilite')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MobilityServicesPage()),
      );
      return;
    }
    if (key.contains('formation')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TrainingServicesPage()),
      );
      return;
    }
    if (key.contains('freelance') || key.contains('pros')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FreelanceProsPage()),
      );
      return;
    }
    if (key.contains('gestion immo')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RealEstateRolePickerPage()),
      );
      return;
    }
    if (key.contains('menage')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const HomeServicesPage(initialFilterKey: 'menage'),
        ),
      );
      return;
    }
    if (key.contains('repas')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FoodServicesPage()),
      );
      return;
    }
    _openServiceSheet(item);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;
    const accent = Color(0xFFFB8C00);

    final sections = _sections();
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? sections
        : sections
            .map((s) => s.copyWith(
                  items: s.items.where((it) {
                    return it.title.toLowerCase().contains(q) || it.sub.toLowerCase().contains(q) || s.title.toLowerCase().contains(q);
                  }).toList(),
                ))
            .where((s) => s.items.isNotEmpty)
            .toList();

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: bg,
            foregroundColor: text,
            elevation: 0,
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            title: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 6))],
                    ),
                    child: Icon(Icons.arrow_back, color: text),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Services',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.2, color: text),
                  ),
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(70),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: divider),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 10))],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: sub),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _q = v),
                          style: TextStyle(color: text, fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            hintText: 'Quel service cherchez-vous ?',
                            hintStyle: TextStyle(color: sub),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_q.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _q = '');
                          },
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: accent.withOpacity(isDark ? 0.18 : 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: accent.withOpacity(0.25)),
                            ),
                            child: const Icon(Icons.close, size: 18, color: accent),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                [
                  _HeroCard(
                    isDark: isDark,
                    title: 'Freelance & Pros',
                    sub: 'Plombier, Tech, Macon...',
                    icon: Icons.person_search_rounded,
                    colors: isDark
                        ? const [Color(0xFF202C33), Color(0xFF111B21)]
                        : const [Color(0xFF111827), Color(0xFF0B141A)],
                    onTap: () => _openService(
                      const ServiceItem(
                        title: 'Freelance & Pros',
                        sub: 'Plombier, Tech, Macon...',
                        icon: Icons.person_search_rounded,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final s in filtered) ...[
                    _SectionTitle(title: s.title, isDark: isDark),
                    const SizedBox(height: 10),
                    for (int i = 0; i < s.items.length; i++) ...[
                      _ServiceRow(
                        isDark: isDark,
                        card: card,
                        text: text,
                        sub: sub,
                        divider: divider,
                        item: s.items[i],
                        index: i,
                        onTap: () => _openService(s.items[i]),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 18),
                  ],
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text('Aucun service trouve', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<ServiceSection> _sections() {
    return const [
      ServiceSection(
        title: 'MAISON & QUOTIDIEN',
        items: [
          ServiceItem(title: 'Gestion Immo', sub: 'Locataire, Proprietaire, Commissionnaire', icon: Icons.apartment_outlined, color: Color(0xFF26A69A)),
          ServiceItem(title: 'Menage & Aide', sub: 'Nounou, Jardinier, Vigile', icon: Icons.auto_awesome_outlined, color: Color(0xFF64B5F6)),
          ServiceItem(title: 'Repas', sub: 'Livraison express', icon: Icons.restaurant_rounded, color: Color(0xFFFF8A00)),
          ServiceItem(title: 'Factures', sub: 'SNEL, Eau, TV, Net', icon: Icons.account_balance_wallet_outlined, color: Color(0xFFFFC107)),
        ],
      ),
      ServiceSection(
        title: 'MOBILITE & AUTO',
        items: [
          ServiceItem(title: 'Mobilite', sub: 'Taxi, Location, Auto', icon: Icons.directions_car_filled_outlined, color: Color(0xFF5C6BC0)),
          ServiceItem(title: 'Depannage & Auto', sub: 'Garage, Mecanicien, Pneus', icon: Icons.build_circle_outlined, color: Color(0xFF90A4AE)),
        ],
      ),
      ServiceSection(
        title: 'LIFESTYLE & PRO',
        items: [
          ServiceItem(title: 'Formation', sub: 'Cours, Soutien, Pro', icon: Icons.school_outlined, color: Color(0xFF2ECC71)),
          ServiceItem(title: 'Evenements', sub: 'DJ, Traiteur, Deco', icon: Icons.music_note_outlined, color: Color(0xFFE91E63)),
          ServiceItem(title: 'Administration', sub: 'Documents, Taxes, RDV', icon: Icons.account_balance_outlined, color: Color(0xFF607D8B)),
        ],
      ),
    ];
  }
}

class ServiceSection {
  final String title;
  final List<ServiceItem> items;
  const ServiceSection({required this.title, required this.items});

  ServiceSection copyWith({String? title, List<ServiceItem>? items}) => ServiceSection(title: title ?? this.title, items: items ?? this.items);
}

class ServiceItem {
  final String title;
  final String sub;
  final IconData icon;
  final Color color;
  const ServiceItem({required this.title, required this.sub, required this.icon, required this.color});
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.isDark});
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: const Color(0xFFFB8C00).withOpacity(isDark ? 0.85 : 0.9),
            borderRadius: BorderRadius.circular(99),
            boxShadow: [BoxShadow(color: const Color(0xFFFB8C00).withOpacity(0.25), blurRadius: 14, offset: const Offset(0, 6))],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(color: sub, fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 12),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.isDark,
    required this.title,
    required this.sub,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final bool isDark;
  final String title;
  final String sub;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(isDark ? 0.35 : 0.10), blurRadius: 20, offset: const Offset(0, 12)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.22)),
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.2)),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
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

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.isDark,
    required this.card,
    required this.text,
    required this.sub,
    required this.divider,
    required this.item,
    required this.index,
    required this.onTap,
  });

  final bool isDark;
  final Color card;
  final Color text;
  final Color sub;
  final Color divider;
  final ServiceItem item;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bgIcon = item.color.withOpacity(isDark ? 0.20 : 0.14);

    Widget tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: divider),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.28 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bgIcon,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: item.color.withOpacity(0.25)),
                ),
                child: Icon(item.icon, color: item.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: TextStyle(color: text, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
                    const SizedBox(height: 2),
                    Text(item.sub, style: TextStyle(color: sub, fontWeight: FontWeight.w600, height: 1.15)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: sub.withOpacity(0.9)),
            ],
          ),
        ),
      ),
    );

    tile = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + (index.clamp(0, 10) * 35)),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) {
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
        );
      },
      child: tile,
    );

    return tile;
  }
}

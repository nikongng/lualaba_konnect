import 'package:flutter/material.dart';

import 'real_estate_management_page.dart';

class RealEstateRolePickerPage extends StatelessWidget {
  const RealEstateRolePickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        title: const Text('Gestion Immo'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF26A69A), Color(0xFF4DD0E1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choisissez votre espace',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Nous ouvrons ensuite la gestion immo avec seulement les outils utiles a votre profil.',
                  style: TextStyle(
                    color: Colors.white,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _RoleChoiceCard(
            title: 'Locataire',
            subtitle: 'Maisons disponibles, suivi du bail, loyer et alertes',
            icon: Icons.person_outline,
            color: const Color(0xFF2D6BFF),
            card: card,
            text: text,
            sub: sub,
            divider: divider,
            onTap: () => _openRole(context, RealEstateViewMode.tenant),
          ),
          const SizedBox(height: 12),
          _RoleChoiceCard(
            title: 'Proprietaire',
            subtitle: 'Ajout de maisons, locataires, paiements et suivi de vos biens',
            icon: Icons.home_work_outlined,
            color: const Color(0xFFFB8C00),
            card: card,
            text: text,
            sub: sub,
            divider: divider,
            onTap: () => _openRole(context, RealEstateViewMode.owner),
          ),
          const SizedBox(height: 12),
          _RoleChoiceCard(
            title: 'Commissionnaire',
            subtitle: 'Publication d annonces et gestion des biens en intermediation',
            icon: Icons.apartment_outlined,
            color: const Color(0xFF26A69A),
            card: card,
            text: text,
            sub: sub,
            divider: divider,
            onTap: () => _openRole(context, RealEstateViewMode.commissioner),
          ),
        ],
      ),
    );
  }

  void _openRole(BuildContext context, RealEstateViewMode viewMode) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RealEstateManagementPage(viewMode: viewMode),
      ),
    );
  }
}

class _RoleChoiceCard extends StatelessWidget {
  const _RoleChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.card,
    required this.text,
    required this.sub,
    required this.divider,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color card;
  final Color text;
  final Color sub;
  final Color divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: sub,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward_rounded, color: sub),
            ],
          ),
        ),
      ),
    );
  }
}

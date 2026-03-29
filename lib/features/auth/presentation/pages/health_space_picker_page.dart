import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'health_profile_page.dart';

class HealthSpacePickerPage extends StatefulWidget {
  const HealthSpacePickerPage({super.key});

  @override
  State<HealthSpacePickerPage> createState() => _HealthSpacePickerPageState();
}

class _HealthSpacePickerPageState extends State<HealthSpacePickerPage> {
  String? _userCollection;
  bool _loadingAccount = true;

  @override
  void initState() {
    super.initState();
    _resolveUserCollection();
  }

  Future<void> _resolveUserCollection() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() => _loadingAccount = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final preferred = prefs.getString('user_collection')?.trim();
      final candidates = <String>[];
      if (preferred != null && preferred.isNotEmpty) {
        candidates.add(preferred);
      }
      for (final c in const ['classic_users', 'pro_users', 'enterprise_users', 'users']) {
        if (!candidates.contains(c)) candidates.add(c);
      }

      var found = candidates.first;
      for (final col in candidates) {
        try {
          final snap = await FirebaseFirestore.instance.collection(col).doc(user.uid).get();
          if (snap.exists) {
            found = col;
            break;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _userCollection = found;
        _loadingAccount = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAccount = false);
    }
  }

  bool get _hideOrganizationSpaces =>
      _userCollection == 'classic_users' || _userCollection == 'users';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF05191D) : const Color(0xFFF4F8F9);
    final text = isDark ? const Color(0xFFF3FCFB) : const Color(0xFF102127);
    final sub = isDark ? const Color(0xFF9FC0BE) : const Color(0xFF5F7278);
    final outline = isDark ? Colors.white10 : const Color(0xFFD9E6E8);

    final items = <_HealthChoiceConfig>[
      _HealthChoiceConfig(
        title: 'Personne',
        subtitle: 'Suivi personnel, dossier medical, rendez-vous et documents.',
        eyebrow: 'Mon espace',
        icon: Icons.favorite_outline,
        accent: Color(0xFF00BFA5),
        gradientStart: Color(0xFF0BCEB2),
        gradientEnd: Color(0xFF00796B),
        bullets: ['Dossier medical', 'Rappels intelligents', 'QR sante'],
      ),
      if (!_hideOrganizationSpaces) ...[
        _HealthChoiceConfig(
          title: 'Hopital',
          subtitle: 'Patients, teleconsultation, alertes critiques et pilotage medical.',
          eyebrow: 'Structure',
          icon: Icons.local_hospital_outlined,
          accent: Color(0xFF2D6BFF),
          gradientStart: Color(0xFF4E86FF),
          gradientEnd: Color(0xFF2146C7),
          bullets: ['Patients', 'Alertes critiques', 'Exports PDF'],
        ),
        _HealthChoiceConfig(
          title: 'Pharmacies',
          subtitle: 'Stocks visibles, recherche rapide et pharmacies proches.',
          eyebrow: 'Reseau local',
          icon: Icons.local_pharmacy_outlined,
          accent: Color(0xFFFF8A1F),
          gradientStart: Color(0xFFFFAA3B),
          gradientEnd: Color(0xFFE46A00),
          bullets: ['Recherche medicaments', 'Import/Export', 'Geolocalisation'],
        ),
      ],
    ];

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned(
            top: -110,
            right: -70,
            child: _GlowOrb(
              color: const Color(0xFF00CBA9).withOpacity(isDark ? 0.18 : 0.12),
              size: 260,
            ),
          ),
          Positioned(
            top: 180,
            left: -90,
            child: _GlowOrb(
              color: const Color(0xFF2D6BFF).withOpacity(isDark ? 0.15 : 0.10),
              size: 220,
            ),
          ),
          Positioned(
            bottom: -90,
            right: -40,
            child: _GlowOrb(
              color: const Color(0xFFFF8A1F).withOpacity(isDark ? 0.15 : 0.10),
              size: 210,
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                Row(
                  children: [
                    _TopButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).pop(),
                      isDark: isDark,
                    ),
                    const Spacer(),
                    _GlassTag(
                      label: 'Parcours sante',
                      icon: Icons.auto_awesome_outlined,
                      isDark: isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _HealthHeroCard(text: text, sub: sub, isDark: isDark),
                const SizedBox(height: 20),
                if (_loadingAccount)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 860;
                      final medium = constraints.maxWidth >= 620;
                      final cardWidth = wide
                          ? (constraints.maxWidth - 12) / 2
                          : medium
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth;

                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: items.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return SizedBox(
                            width: cardWidth,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: Duration(milliseconds: 280 + (index * 120)),
                              curve: Curves.easeOutCubic,
                              builder: (context, t, child) {
                                return Transform.translate(
                                  offset: Offset(0, (1 - t) * 18),
                                  child: Opacity(opacity: t, child: child),
                                );
                              },
                              child: _HealthChoiceCard(
                                item: item,
                                text: text,
                                sub: sub,
                                outline: outline,
                                isDark: isDark,
                                onTap: () => _openView(context, item.mode),
                              ),
                            ),
                          );
                        }).toList(growable: false),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openView(BuildContext context, HealthProfileViewMode viewMode) {
    final effectiveViewMode = _hideOrganizationSpaces &&
            (viewMode == HealthProfileViewMode.hospital ||
                viewMode == HealthProfileViewMode.pharmacy)
        ? HealthProfileViewMode.person
        : viewMode;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HealthProfilePage(viewMode: effectiveViewMode),
      ),
    );
  }
}

class _HealthHeroCard extends StatelessWidget {
  const _HealthHeroCard({
    required this.text,
    required this.sub,
    required this.isDark,
  });

  final Color text;
  final Color sub;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0BC3A3), Color(0xFF046C7A), Color(0xFF2D6BFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0BC3A3).withOpacity(isDark ? 0.22 : 0.16),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -24,
            right: -14,
            child: Container(
              width: 122,
              height: 122,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -38,
            left: -24,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.health_and_safety_outlined,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ma Sante',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.7,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Choisissez une experience ciblee et directe.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.84),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Un point d entree clair pour les personnes, les hopitaux et les pharmacies, avec une navigation plus rapide et plus elegante.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _HeroMetric(label: '3 espaces'),
                  _HeroMetric(label: 'Acces direct'),
                  _HeroMetric(label: 'Vue claire'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthChoiceCard extends StatelessWidget {
  const _HealthChoiceCard({
    required this.item,
    required this.text,
    required this.sub,
    required this.outline,
    required this.isDark,
    required this.onTap,
  });

  final _HealthChoiceConfig item;
  final Color text;
  final Color sub;
  final Color outline;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(item.accent, Colors.white, isDark ? 0.20 : 0.72)!,
                isDark ? const Color(0xFF0D181B) : Colors.white,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: outline),
            boxShadow: [
              BoxShadow(
                color: item.accent.withOpacity(isDark ? 0.16 : 0.10),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 14,
                right: 16,
                child: Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.22),
                        Colors.white.withOpacity(0.02),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _GlassTag(
                          label: item.eyebrow,
                          icon: item.icon,
                          isDark: isDark,
                          accent: item.accent,
                        ),
                        const Spacer(),
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [item.gradientStart, item.gradientEnd],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(item.icon, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      item.title,
                      style: TextStyle(
                        color: text,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        color: sub,
                        height: 1.42,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: item.bullets
                          .map(
                            (bullet) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: item.accent.withOpacity(isDark ? 0.16 : 0.10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                bullet,
                                style: TextStyle(
                                  color: text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(isDark ? 0.18 : 0.03),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'Entrer dans ${{'Personne': 'l espace personnel', 'Hopital': 'le portail medical', 'Pharmacies': 'le reseau pharmacie'}[item.title] ?? item.title.toLowerCase()}',
                              style: TextStyle(
                                color: sub,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [item.gradientStart, item.gradientEnd],
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: isDark ? Colors.white : const Color(0xFF102127)),
        ),
      ),
    );
  }
}

class _GlassTag extends StatelessWidget {
  const _GlassTag({
    required this.label,
    required this.icon,
    required this.isDark,
    this.accent,
  });

  final String label;
  final IconData icon;
  final bool isDark;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? const Color(0xFF00CBA9);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF102127),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: 100,
              spreadRadius: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthChoiceConfig {
  final String title;
  final String subtitle;
  final String eyebrow;
  final IconData icon;
  final Color accent;
  final Color gradientStart;
  final Color gradientEnd;
  final List<String> bullets;

  const _HealthChoiceConfig({
    required this.title,
    required this.subtitle,
    required this.eyebrow,
    required this.icon,
    required this.accent,
    required this.gradientStart,
    required this.gradientEnd,
    required this.bullets,
  });

  HealthProfileViewMode get mode {
    switch (title) {
      case 'Personne':
        return HealthProfileViewMode.person;
      case 'Hopital':
        return HealthProfileViewMode.hospital;
      case 'Pharmacies':
        return HealthProfileViewMode.pharmacy;
    }
    return HealthProfileViewMode.all;
  }
}

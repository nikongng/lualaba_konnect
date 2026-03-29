import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lualaba_konnect/core/supabase_service.dart';
import 'package:lualaba_konnect/features/auth/presentation/health/health_risk_utils.dart';
import 'health/health_ai_page.dart';
import 'health/health_appointments_page.dart';
import 'health/health_cycle_page.dart';
import 'health/health_documents_page.dart';
import 'health/health_medications_page.dart';
import 'health/health_metrics_page.dart';
import 'health/health_notifications_page.dart';
import 'health/health_patients_waiting_page.dart';
import 'health/health_pharmacy_page.dart';
import 'health/health_prevention_page.dart';
import 'health/health_profile_edit_page.dart';
import 'health/health_qr_page.dart';
import 'health/health_teleconsultation_page.dart';
import 'health/health_notification_scheduler.dart';
import 'health/health_user_context.dart';

enum HealthProfileViewMode { all, person, hospital, pharmacy }

class _HealthTabItem {
  final String label;

  const _HealthTabItem({
    required this.label,
  });
}

class _HealthModeStyle {
  final String navTitle;
  final String headline;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<Color> gradient;
  final List<String> highlights;

  const _HealthModeStyle({
    required this.navTitle,
    required this.headline,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.gradient,
    required this.highlights,
  });
}

class HealthProfilePage extends StatefulWidget {
  const HealthProfilePage({
    super.key,
    this.viewMode = HealthProfileViewMode.all,
  });

  final HealthProfileViewMode viewMode;

  @override
  State<HealthProfilePage> createState() => _HealthProfilePageState();
}

class _HealthProfilePageState extends State<HealthProfilePage> {
  static const List<double> _distanceRadiusOptionsKm = <double>[1, 5, 10, 50];

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  bool _initializing = true;
  String? _error;
  String? _userCollection;
  String? _userId;
  bool _notifPrimed = false;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _pharmacySearchCtrl = TextEditingController();
  final TextEditingController _healthAiPromptCtrl = TextEditingController();
  final TextEditingController _personHospitalSearchCtrl = TextEditingController();
  final TextEditingController _personPharmacySearchCtrl = TextEditingController();
  String _pharmacyQuery = '';
  String _personHospitalQuery = '';
  String _personPharmacyQuery = '';
  String _personPharmacyFilter = 'all';
  String _hospitalDirectoryFilter = 'all';
  double? _personHospitalRadiusKm;
  double? _personPharmacyRadiusKm;
  bool _addingHospital = false;
  bool _addingPharmacy = false;
  String _pharmacyManagerScope = 'mine';
  bool _locBusy = false;
  Position? _userPosition;
  bool _exportingPharmacies = false;
  bool _importingPharmacies = false;
  bool _healthAiSending = false;
  bool _showPharmacyHeader = true;
  final List<_HealthAiMessage> _healthAiMessages = <_HealthAiMessage>[
    const _HealthAiMessage(
      role: _HealthAiRole.assistant,
      text:
          'Bonjour. Je peux vous aider a comprendre vos mesures, vos traitements et votre routine sante du jour.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initStream();
    _pharmacySearchCtrl.addListener(() {
      final v = _pharmacySearchCtrl.text.trim().toLowerCase();
      if (v == _pharmacyQuery) return;
      if (!mounted) return;
      setState(() => _pharmacyQuery = v);
    });
    _personHospitalSearchCtrl.addListener(() {
      final v = _personHospitalSearchCtrl.text.trim().toLowerCase();
      if (v == _personHospitalQuery) return;
      if (!mounted) return;
      setState(() => _personHospitalQuery = v);
    });
    _personPharmacySearchCtrl.addListener(() {
      final v = _personPharmacySearchCtrl.text.trim().toLowerCase();
      if (v == _personPharmacyQuery) return;
      if (!mounted) return;
      setState(() => _personPharmacyQuery = v);
    });
  }

  @override
  void dispose() {
    _pharmacySearchCtrl.dispose();
    _healthAiPromptCtrl.dispose();
    _personHospitalSearchCtrl.dispose();
    _personPharmacySearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initStream() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _error = 'Utilisateur non connecté';
            _initializing = false;
          });
        }
        return;
      }
      _userId = user.uid;

      final prefs = await SharedPreferences.getInstance();
      final preferred = prefs.getString('user_collection')?.trim();
      final candidates = <String>[];
      if (preferred != null && preferred.isNotEmpty) {
        candidates.add(preferred);
      }
      for (final c in const ['classic_users', 'pro_users', 'enterprise_users', 'users']) {
        if (!candidates.contains(c)) candidates.add(c);
      }

      String found = candidates.first;
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
        _userStream = FirebaseFirestore.instance.collection(found).doc(user.uid).snapshots();
        _initializing = false;
        _error = null;
      });
      if (!_notifPrimed) {
        _notifPrimed = true;
        await HealthNotificationScheduler.refreshForUser(
          HealthUserContext(userId: user.uid, userCollection: found),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erreur chargement des données santé';
        _initializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF012E32) : const Color(0xFFF5F7F8);
    final cardBg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF0D1B2A);
    final sub = isDark ? Colors.white70 : Colors.black54;
    final pageStyle = _styleForMode(
      widget.viewMode == HealthProfileViewMode.all
          ? HealthProfileViewMode.person
          : widget.viewMode,
      isDark,
    );
    final accent = pageStyle.accent;

    final stream = _userStream;

    final tabs = <_HealthTabItem>[
      if (widget.viewMode == HealthProfileViewMode.all ||
          widget.viewMode == HealthProfileViewMode.person)
        const _HealthTabItem(label: 'Personne'),
      if (widget.viewMode == HealthProfileViewMode.all ||
          widget.viewMode == HealthProfileViewMode.hospital)
        const _HealthTabItem(label: 'Hopital'),
      if (widget.viewMode == HealthProfileViewMode.all ||
          widget.viewMode == HealthProfileViewMode.pharmacy)
        const _HealthTabItem(label: 'Pharmacies'),
    ];
    final showTabs = tabs.length > 1;

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          iconTheme: IconThemeData(color: text),
          title: Text(
            widget.viewMode == HealthProfileViewMode.all
                ? 'Ma Santé'
                : pageStyle.navTitle,
            style: TextStyle(color: text, fontWeight: FontWeight.bold),
          ),
          bottom: showTabs
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
                    child: _buildTabBar(isDark, accent, tabs),
                  ),
                )
              : null,
        ),
        body: _initializing
            ? const Center(child: CircularProgressIndicator())
            : (_error != null || stream == null)
                ? _buildMessage(text, sub, accent, _error ?? 'Flux utilisateur indisponible')
                : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: stream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || !snapshot.data!.exists) {
                        return _buildMessage(
                          text,
                          sub,
                          accent,
                          'Profil introuvable. Réessayez plus tard.',
                        );
                      }

                      final data = snapshot.data!.data() ?? <String, dynamic>{};

                      return Column(
                        children: [
                          Expanded(
                            child: showTabs
                                ? TabBarView(
                                    children: tabs
                                        .map(
                                          (tab) => _buildTabContent(
                                            label: tab.label,
                                            cardBg: cardBg,
                                            text: text,
                                            sub: sub,
                                            data: data,
                                            isDark: isDark,
                                            includeHero: false,
                                          ),
                                        )
                                        .toList(growable: false),
                                  )
                                : _singleHealthView(
                                    cardBg: cardBg,
                                    text: text,
                                    sub: sub,
                                    data: data,
                                    isDark: isDark,
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }

  Widget _buildMessage(Color text, Color sub, Color accent, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.health_and_safety, color: accent),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(color: text, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Vérifiez votre connexion ou réessayez.', style: TextStyle(color: sub)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _initStream,
              icon: const Icon(Icons.refresh),
              label: const Text('Recharger'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDark, Color accent, List<_HealthTabItem> tabs) {
    return TabBar(
      labelColor: isDark ? Colors.white : const Color(0xFF0D1B2A),
      unselectedLabelColor: isDark ? Colors.white54 : Colors.black45,
      indicator: BoxDecoration(
        color: accent.withOpacity(isDark ? 0.25 : 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.6), width: 1.2),
      ),
      indicatorPadding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      tabs: tabs.map((tab) => Tab(text: tab.label)).toList(growable: false),
    );
  }

  _HealthModeStyle _styleForMode(HealthProfileViewMode mode, bool isDark) {
    switch (mode) {
      case HealthProfileViewMode.hospital:
        return const _HealthModeStyle(
          navTitle: 'Espace Hopital',
          headline: 'Pilotage medical centralise',
          subtitle: 'Patients, priorites, teleconsultations et suivi critique dans une interface plus nette.',
          icon: Icons.local_hospital_outlined,
          accent: Color(0xFF2D6BFF),
          gradient: [Color(0xFF4E86FF), Color(0xFF233CC7)],
          highlights: ['Patients actifs', 'Alertes critiques', 'Exports PDF'],
        );
      case HealthProfileViewMode.pharmacy:
        return const _HealthModeStyle(
          navTitle: 'Espace Pharmacies',
          headline: 'Recherche, stocks et proximite',
          subtitle: 'Une vue plus directe pour trouver, gerer et publier les pharmacies et les medicaments.',
          icon: Icons.local_pharmacy_outlined,
          accent: Color(0xFFFF8A1F),
          gradient: [Color(0xFFFFAE42), Color(0xFFE56B00)],
          highlights: ['Medicaments', 'Import / Export', 'Pharmacies proches'],
        );
      case HealthProfileViewMode.person:
      case HealthProfileViewMode.all:
        return const _HealthModeStyle(
          navTitle: 'Espace Personne',
          headline: 'Votre tableau de bord sante',
          subtitle: 'Mesures, documents, rendez-vous et rappels dans une presentation plus vivante.',
          icon: Icons.favorite_outline,
          accent: Color(0xFF00BFA5),
          gradient: [Color(0xFF0BCDB2), Color(0xFF00796B)],
          highlights: ['Dossier medical', 'Suivi personnel', 'Rappels intelligents'],
        );
    }
  }

  _HealthModeStyle _styleForLabel(String label, bool isDark) {
    switch (label) {
      case 'Hopital':
        return _styleForMode(HealthProfileViewMode.hospital, isDark);
      case 'Pharmacies':
        return _styleForMode(HealthProfileViewMode.pharmacy, isDark);
      case 'Personne':
      default:
        return _styleForMode(HealthProfileViewMode.person, isDark);
    }
  }

  Widget _buildTabContent({
    required String label,
    required Color cardBg,
    required Color text,
    required Color sub,
    required Map<String, dynamic> data,
    required bool isDark,
    required bool includeHero,
  }) {
    final style = _styleForLabel(label, isDark);
    final hero = includeHero && label != 'Pharmacies'
        ? _buildModeHero(
            style: style,
            text: text,
            isDark: isDark,
          )
        : null;

    switch (label) {
      case 'Hopital':
        return _buildHospitalTab(
          cardBg,
          text,
          sub,
          style.accent,
          data,
          header: hero,
        );
      case 'Pharmacies':
        return _buildPharmacyTab(
          cardBg,
          text,
          sub,
          style.accent,
          data,
          showHero: includeHero,
        );
      case 'Personne':
      default:
        return _buildPersonTab(
          cardBg,
          text,
          sub,
          style.accent,
          data,
          header: hero,
        );
    }
  }

  Widget _buildModeHero({
    required _HealthModeStyle style,
    required Color text,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: style.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: style.accent.withOpacity(isDark ? 0.22 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -18,
            right: -4,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
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
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(style.icon, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      style.headline,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                style.subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  height: 1.42,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: style.highlights
                    .map(
                      (item) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withOpacity(0.16)),
                        ),
                        child: Text(
                          item,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPharmacyHero({
    required String displayName,
    required int totalPharmacies,
    required int totalProducts,
    required Color accent,
  }) {
    final heroTitle = displayName.isEmpty ? 'Profil pharmacie' : displayName;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFAE42), Color(0xFFE56B00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.16),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -18,
            right: -4,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
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
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.local_pharmacy_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Espace Pharmacies',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          heroTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '$totalPharmacies pharmacie(s) au total et $totalProducts produit(s) reference(s).',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  height: 1.42,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in <String>[
                    heroTitle,
                    '$totalPharmacies pharmacie(s)',
                    '$totalProducts produit(s)',
                  ])
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withOpacity(0.16)),
                      ),
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _handlePharmacyScrollNotification(
    ScrollNotification notification, {
    required bool canToggleHeader,
  }) {
    if (!canToggleHeader || !mounted || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification.metrics.pixels <= 0) {
      if (!_showPharmacyHeader) {
        setState(() => _showPharmacyHeader = true);
      }
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta > 6 && _showPharmacyHeader) {
        setState(() => _showPharmacyHeader = false);
      } else if (delta < -6 && !_showPharmacyHeader) {
        setState(() => _showPharmacyHeader = true);
      }
    }
    return false;
  }

  Widget _revealBlock(int index, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + (index * 120)),
      curve: Curves.easeOutCubic,
      builder: (context, t, builtChild) {
        return Transform.translate(
          offset: Offset(0, (1 - t) * 16),
          child: Opacity(opacity: t, child: builtChild),
        );
      },
      child: child,
    );
  }

  Widget _mergeHeaderWidgets(Widget? primary, Widget secondary) {
    if (primary == null) return secondary;
    return Column(
      children: [
        primary,
        const SizedBox(height: 12),
        secondary,
      ],
    );
  }

  HealthUserContext? _currentHealthUserContext() {
    if (_userId == null || _userCollection == null) return null;
    return HealthUserContext(userId: _userId!, userCollection: _userCollection!);
  }

  Future<void> _refreshHealthNotificationsIfAvailable() async {
    final userContext = _currentHealthUserContext();
    if (userContext == null) return;
    await HealthNotificationScheduler.refreshForUser(userContext);
  }

  Future<void> _sendHealthAiPrompt(Map<String, dynamic> data) async {
    final prompt = _healthAiPromptCtrl.text.trim();
    if (prompt.isEmpty || _healthAiSending) return;

    if (mounted) {
      setState(() {
        _healthAiMessages.add(_HealthAiMessage(role: _HealthAiRole.user, text: prompt));
        _healthAiPromptCtrl.clear();
        _healthAiSending = true;
      });
    }

    try {
      final apiKey = dotenv.maybeGet('GEMINI_API_KEY') ?? '';
      String reply;

      if (apiKey.isEmpty) {
        reply = _fallbackHealthAiReply(prompt, data);
      } else {
        final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
        final recentMessages = _healthAiMessages.length > 6
            ? _healthAiMessages.sublist(_healthAiMessages.length - 6)
            : _healthAiMessages;
        final history = recentMessages
            .map(
              (m) => '${m.role == _HealthAiRole.user ? 'Utilisateur' : 'Assistant'}: ${m.text}',
            )
            .join('\n');
        final content = [
          'Tu es un assistant sante integre dans une application mobile.',
          'Tu reponds en francais, de facon claire, breve, utile et rassurante.',
          'Ne fais pas de diagnostic certain et rappelle de consulter un professionnel si urgence ou aggravation.',
          'Contexte sante utilisateur:',
          _buildHealthAiContext(data),
          'Conversation recente:',
          history,
          'Reponds maintenant a la derniere question de l utilisateur en 5 a 8 lignes max.',
        ].join('\n');
        final response = await model.generateContent([Content.text(content)]);
        reply = response.text?.trim() ?? _fallbackHealthAiReply(prompt, data);
      }

      if (mounted) {
        setState(() {
          _healthAiMessages.add(_HealthAiMessage(role: _HealthAiRole.assistant, text: reply));
        });
      }
    } catch (_) {
      final fallback = _fallbackHealthAiReply(prompt, data);
      if (mounted) {
        setState(() {
          _healthAiMessages.add(_HealthAiMessage(role: _HealthAiRole.assistant, text: fallback));
        });
      }
    } finally {
      if (mounted) setState(() => _healthAiSending = false);
    }
  }

  String _buildHealthAiContext(Map<String, dynamic> data) {
    final health = (data['health'] is Map)
        ? Map<String, dynamic>.from(data['health'] as Map)
        : <String, dynamic>{};
    final weight = _toDouble(health['weight'] ?? health['weightKg'] ?? health['poids']);
    final height = _toDouble(health['height'] ?? health['heightCm'] ?? health['taille']);
    final bmi = _bmi(weight, height);
    final tension = _safeStr(health['bloodPressure'] ?? health['tension']);
    final glycemie = _safeStr(health['glucose'] ?? health['glycemie']);
    final heartRate = _safeStr(health['heartRate'] ?? health['frequenceCardiaque']);
    final medsToday = _medicationBullets(health['medicationsToday'] ?? health['todayMedications']);
    final appointments = _appointmentBullets(health['appointments']);
    final allergies = _stringList(health['allergies']);

    return [
      'poids: ${weight?.toStringAsFixed(1) ?? 'n/d'} kg',
      'taille: ${height?.toStringAsFixed(1) ?? 'n/d'} cm',
      'IMC: ${bmi?.toStringAsFixed(1) ?? 'n/d'}',
      'tension: ${tension.isEmpty ? 'n/d' : tension}',
      'glycemie: ${glycemie.isEmpty ? 'n/d' : glycemie}',
      'frequence cardiaque: ${heartRate.isEmpty ? 'n/d' : heartRate}',
      'allergies: ${allergies.isEmpty ? 'aucune donnee' : allergies.join(', ')}',
      'medicaments du jour: ${medsToday.isEmpty ? 'aucun' : medsToday.join(' ; ')}',
      'rendez-vous: ${appointments.isEmpty ? 'aucun' : appointments.join(' ; ')}',
    ].join('\n');
  }

  String _fallbackHealthAiReply(String prompt, Map<String, dynamic> data) {
    final health = (data['health'] is Map)
        ? Map<String, dynamic>.from(data['health'] as Map)
        : <String, dynamic>{};
    final weight = _toDouble(health['weight'] ?? health['weightKg'] ?? health['poids']);
    final height = _toDouble(health['height'] ?? health['heightCm'] ?? health['taille']);
    final bmi = _bmi(weight, height);
    final tension = _safeStr(health['bloodPressure'] ?? health['tension']);
    final glycemie = _safeStr(health['glucose'] ?? health['glycemie']);
    final medsToday = _medicationBullets(health['medicationsToday'] ?? health['todayMedications']);
    final appointments = _appointmentBullets(health['appointments']);
    final question = prompt.toLowerCase();

    final tips = <String>[];
    if (question.contains('tension') && tension.isNotEmpty) {
      tips.add('Votre tension enregistree est $tension. Comparez-la a vos habitudes et consultez si elle change fortement.');
    }
    if (question.contains('gly') && glycemie.isNotEmpty) {
      tips.add('Votre glycemie notee est $glycemie. Pensez au suivi habituel conseille par votre medecin.');
    }
    if (bmi != null) {
      tips.add('Votre IMC calcule est ${bmi.toStringAsFixed(1)}. Il doit etre interprete avec votre contexte medical global.');
    }
    if (medsToday.isNotEmpty) {
      tips.add('Traitements du jour: ${medsToday.take(2).join(' / ')}.');
    }
    if (appointments.isNotEmpty) {
      tips.add('Prochain suivi disponible: ${appointments.first}.');
    }
    if (tips.isEmpty) {
      tips.add('Je peux vous aider a relire vos mesures, vos rendez-vous et vos traitements du jour.');
      tips.add('Si vous voulez, demandez par exemple: "explique ma tension", "resume mon dossier" ou "que faire aujourd hui ?".');
    }

    return tips.take(4).join('\n');
  }

  List<_HospitalDirectoryItem> _hospitalDirectory(Map<String, dynamic> data) {
    final health = (data['health'] is Map)
        ? Map<String, dynamic>.from(data['health'] as Map)
        : <String, dynamic>{};
    final out = <_HospitalDirectoryItem>[];
    final seen = <String>{};

    void addHospital({
      required String name,
      required String location,
      String note = '',
      String phone = '',
      String email = '',
      String badge = 'Disponible',
      String status = '',
      bool isOpen = true,
      double? lat,
      double? lng,
      String image = '',
      List<String> services = const <String>[],
      List<String> doctors = const <String>[],
      List<_HospitalDoctorProfile> doctorProfiles = const <_HospitalDoctorProfile>[],
      bool isEmergency24h = false,
      bool isOpen24h = false,
      String ownerId = '',
      String sourceId = '',
    }) {
      final cleanName = _safeStr(name);
      final cleanLocation = _safeStr(location);
      if (cleanName.isEmpty || cleanLocation.isEmpty) return;
      final key = '${cleanName.toLowerCase()}|${cleanLocation.toLowerCase()}';
      if (seen.contains(key)) return;
      seen.add(key);
      out.add(
        _HospitalDirectoryItem(
          sourceId: sourceId,
          ownerId: _safeStr(ownerId),
          name: cleanName,
          location: cleanLocation,
          note: _safeStr(note),
          phone: _safeStr(phone),
          email: _safeStr(email),
          badge: badge,
          lat: lat,
          lng: lng,
          image: _safeStr(image),
          status: _safeStr(status),
          isOpen: isOpen,
          services: services.where((item) => _safeStr(item).isNotEmpty).map((item) => _safeStr(item)).toList(growable: false),
          doctors: (doctors.isNotEmpty
                  ? doctors
                  : doctorProfiles.map((item) => item.displayLabel).toList(growable: false))
              .where((item) => _safeStr(item).isNotEmpty)
              .map((item) => _safeStr(item))
              .toList(growable: false),
          doctorProfiles: doctorProfiles,
          isEmergency24h: isEmergency24h,
          isOpen24h: isOpen24h,
        ),
      );
    }

    final rawHospitals = health['availableHospitals'] ?? health['hospitals'] ?? data['availableHospitals'];
    if (rawHospitals is List) {
      for (final item in rawHospitals) {
        if (item is Map) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final doctorProfiles = _hospitalDoctorProfiles(
            map['doctorProfiles'] ?? map['doctors'] ?? map['medecins'] ?? map['doctor'] ?? map['medecin'],
          );
          final operationalStatus = _hospitalOperationalStatusFromMap(map);
          addHospital(
            name: _safeStr(map['name'] ?? map['hospital']),
            location: _joinParts([
              _safeStr(map['address'] ?? map['adresse']),
              _safeStr(map['location'] ?? map['quartier'] ?? map['city']),
            ]),
            note: _safeStr(map['services'] ?? map['speciality'] ?? map['note']),
            phone: _safeStr(map['phone'] ?? map['telephone']),
            email: _safeStr(map['email']),
            badge: _hospitalExtraBadge(_safeStr(map['badge'] ?? map['status'])),
            status: operationalStatus,
            isOpen: _isHospitalOpenFromMap(map),
            lat: _toDouble(map['lat'] ?? map['latitude']),
            lng: _toDouble(map['lng'] ?? map['longitude']),
            image: _safeStr(map['photo'] ?? map['image'] ?? map['photoUrl']),
            services: _stringList(map['services'] ?? map['specialities'] ?? map['specialties']),
            doctors: _doctorList(map['doctorProfiles'] ?? map['doctors'] ?? map['medecins'] ?? map['doctor'] ?? map['medecin']),
            doctorProfiles: doctorProfiles,
            isEmergency24h: _boolValue(map['emergency24h'] ?? map['emergency']) == true,
            isOpen24h: _boolValue(map['open24h'] ?? map['alwaysOpen']) == true,
          );
        } else {
          addHospital(name: _safeStr(item), location: 'Localisation a confirmer');
        }
      }
    }

    final appointments = health['appointments'];
    if (appointments is List) {
      for (final item in appointments) {
        if (item is Map) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final doctorProfiles = _hospitalDoctorProfiles(
            map['doctorProfiles'] ?? map['doctors'] ?? map['medecins'] ?? map['doctor'] ?? map['medecin'],
          );
          addHospital(
            name: _safeStr(map['hospital'] ?? map['lieu']),
            location: _joinParts([
              _safeStr(map['address'] ?? map['location']),
              _safeStr(map['city'] ?? map['quartier']),
            ]),
            note: _joinParts([
              _safeStr(map['doctor'] ?? map['medecin']),
              _safeStr(map['speciality'] ?? map['reason']),
            ]),
            phone: _safeStr(map['phone'] ?? map['telephone']),
            email: _safeStr(map['email']),
            badge: 'Recommande',
            status: _hospitalOperationalStatusFromMap(map),
            isOpen: _isHospitalOpenFromMap(map),
            lat: _toDouble(map['lat'] ?? map['latitude']),
            lng: _toDouble(map['lng'] ?? map['longitude']),
            services: _stringList(map['services'] ?? map['specialities'] ?? map['specialties']),
            doctors: _doctorList(map['doctorProfiles'] ?? map['doctors'] ?? map['medecins'] ?? map['doctor'] ?? map['medecin']),
            doctorProfiles: doctorProfiles,
          );
        }
      }
    }

    return out;
  }

  _HospitalDirectoryItem _hospitalItemFromMap(
    Map<String, dynamic> raw, {
    String sourceId = '',
  }) {
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    final services = _stringList(map['services'] ?? map['specialities'] ?? map['specialties']);
    final doctorProfiles = _hospitalDoctorProfiles(
      map['doctorProfiles'] ?? map['doctors'] ?? map['medecins'] ?? map['doctor'] ?? map['medecin'],
    );
    final doctors = doctorProfiles.map((item) => item.displayLabel).toList(growable: false);
    final rawBadge = _safeStr(map['badge'] ?? map['status']);
    final note = _safeStr(map['note'] ?? map['speciality'] ?? map['specialty'] ?? map['description']);
    final isOpen = _isHospitalOpenFromMap(map);
    final status = _hospitalOperationalStatusFromMap(map);

    return _HospitalDirectoryItem(
      sourceId: sourceId,
      ownerId: _safeStr(map['ownerId'] ?? map['owner']),
      name: _safeStr(map['name'] ?? map['hospital']),
      location: _joinParts([
        _safeStr(map['address'] ?? map['adresse']),
        _safeStr(map['location'] ?? map['localisation'] ?? map['quartier'] ?? map['city']),
      ]),
      note: note.isNotEmpty ? note : services.take(3).join(' / '),
      phone: _safeStr(map['phone'] ?? map['telephone']),
      email: _safeStr(map['email']),
      badge: _hospitalExtraBadge(rawBadge),
      lat: _toDouble(map['lat'] ?? map['latitude']),
      lng: _toDouble(map['lng'] ?? map['longitude']),
      image: _safeStr(map['photo'] ?? map['image'] ?? map['photoUrl']),
      status: status,
      isOpen: isOpen,
      services: services,
      doctors: doctors,
      doctorProfiles: doctorProfiles,
      isEmergency24h: _boolValue(map['emergency24h'] ?? map['emergency']) == true,
      isOpen24h: _boolValue(map['open24h'] ?? map['alwaysOpen']) == true,
    );
  }

  List<_HospitalDirectoryItem> _mergeHospitalItems(
    List<_HospitalDirectoryItem> primary,
    List<_HospitalDirectoryItem> secondary,
  ) {
    final out = <_HospitalDirectoryItem>[];
    final seen = <String>{};

    void push(_HospitalDirectoryItem item) {
      final name = _safeStr(item.name);
      final location = _safeStr(item.location);
      if (name.isEmpty || location.isEmpty) return;
      final key = '${name.toLowerCase()}|${location.toLowerCase()}';
      if (!seen.add(key)) return;
      out.add(item);
    }

    for (final item in primary) {
      push(item);
    }
    for (final item in secondary) {
      push(item);
    }
    return out;
  }

  Widget _buildPersonExperienceHeader({
    required bool isDark,
    required Color cardBg,
    required Color text,
    required Color sub,
    required Color accent,
    required Map<String, dynamic> data,
    required String displayName,
    required int? age,
    required String bloodType,
    required double? bmi,
    required String tension,
    required String glycemie,
    required String heartRate,
    required List<String> medsToday,
    required List<String> appointments,
    required List<_HealthDashboardShortcut> dashboardShortcuts,
    required HealthUserContext? ctx,
    required VoidCallback onOpenAi,
    required VoidCallback onScanPrescription,
    required VoidCallback onOpenAppointments,
    required VoidCallback onOpenProfile,
  }) {
    final hospitals = _hospitalDirectory(data);
    final fullName = displayName.isEmpty ? 'Profil sante' : displayName;
    final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};
    final profileImage = _safeStr(
      data['photo'] ?? data['image'] ?? data['photoUrl'] ?? data['avatar'] ?? data['avatarUrl'],
    );
    final healthRisk = _buildHealthRiskSummary(
      bmi: bmi,
      tension: tension,
      glycemie: glycemie,
      heartRate: heartRate,
      allergies: _stringList(health['allergies']),
      conditions: _stringList(health['chronicConditions'] ?? health['conditions'] ?? health['medicalConditions']),
      alerts: _stringList(health['alerts'] ?? health['importantAlerts'] ?? health['notifications']),
      aiAlerts: _stringList(health['aiAlerts'] ?? health['alertsAi']),
      treatmentsCount: medsToday.length,
    );

    return Column(
      children: [
        _revealBlock(
          0,
          _buildPersonSpotlightCard(
            isDark: isDark,
            cardBg: cardBg,
            text: text,
            sub: sub,
            accent: accent,
            displayName: fullName,
            profileImage: profileImage,
            age: age,
            bloodType: bloodType,
            appointmentsCount: appointments.length,
            treatmentsCount: medsToday.length,
            healthRisk: healthRisk,
            dashboardShortcuts: dashboardShortcuts,
          ),
        ),
        const SizedBox(height: 12),
        _revealBlock(
          1,
          _buildPersonVitalsStrip(
            text: text,
            sub: sub,
            accent: accent,
            cardBg: cardBg,
            bmi: bmi,
            tension: tension,
            glycemie: glycemie,
            heartRate: heartRate,
          ),
        ),
        const SizedBox(height: 12),
        _revealBlock(
          2,
          _buildPersonQuickActions(
            text: text,
            sub: sub,
            cardBg: cardBg,
            accent: accent,
            enabled: ctx != null,
            onOpenAi: onOpenAi,
            onOpenDocuments: onScanPrescription,
            onOpenAppointments: onOpenAppointments,
            onOpenProfile: onOpenProfile,
          ),
        ),
        const SizedBox(height: 12),
        _revealBlock(
          3,
          _buildPrescriptionScanPanel(
            isDark: isDark,
            text: text,
            sub: sub,
            cardBg: cardBg,
            accent: accent,
            enabled: ctx != null,
            onTap: onScanPrescription,
          ),
        ),
        const SizedBox(height: 12),
        _revealBlock(
          4,
          _buildPersonAiComposer(
            isDark: isDark,
            text: text,
            sub: sub,
            cardBg: cardBg,
            accent: accent,
            data: data,
            enabled: ctx != null,
            onOpenAi: onOpenAi,
          ),
        ),
        const SizedBox(height: 12),
        _revealBlock(
          5,
          _buildHospitalShowcase(
            text: text,
            sub: sub,
            cardBg: cardBg,
            accent: accent,
            items: hospitals,
            userContext: ctx,
          ),
        ),
        const SizedBox(height: 12),
        _revealBlock(
          6,
          _buildPersonPharmacyShowcase(
            text: text,
            sub: sub,
            cardBg: cardBg,
            accent: accent,
          ),
        ),
      ],
    );
  }

  Widget _buildPrescriptionScanPanel({
    required bool isDark,
    required Color text,
    required Color sub,
    required Color cardBg,
    required Color accent,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 460;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(cardBg, accent, isDark ? 0.14 : 0.18)!,
                Color.lerp(cardBg, Colors.blue, isDark ? 0.04 : 0.08)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withOpacity(0.14)),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(isDark ? 0.12 : 0.08),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent, Color.lerp(accent, Colors.blue, 0.45)!],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.document_scanner_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scan intelligent d ordonnance',
                          style: TextStyle(
                            color: text,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Prenez une photo ou importez un PDF pour centraliser vos prescriptions et relire les details plus vite.',
                          style: TextStyle(
                            color: sub,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _scanFeaturePill(accent: accent, text: text, label: 'Photo mobile'),
                  _scanFeaturePill(accent: accent, text: text, label: 'Import PDF'),
                  _scanFeaturePill(accent: accent, text: text, label: 'Lecture rapide'),
                ],
              ),
              const SizedBox(height: 16),
              if (compact) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: enabled ? onTap : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.center_focus_strong_outlined),
                    label: const Text(
                      'Scanner maintenant',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _scanSecurityBadge(accent: accent, text: text),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: enabled ? onTap : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.center_focus_strong_outlined),
                        label: const Text(
                          'Scanner maintenant',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _scanSecurityBadge(accent: accent, text: text),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _scanSecurityBadge({
    required Color accent,
    required Color text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(
            'Espace securise',
            style: TextStyle(
              color: text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanFeaturePill({
    required Color accent,
    required Color text,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPersonSpotlightCard({
    required bool isDark,
    required Color cardBg,
    required Color text,
    required Color sub,
    required Color accent,
    required String displayName,
    required String profileImage,
    required int? age,
    required String bloodType,
    required int appointmentsCount,
    required int treatmentsCount,
    required _HealthRiskSummary healthRisk,
    required List<_HealthDashboardShortcut> dashboardShortcuts,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withOpacity(isDark ? 0.95 : 0.88),
            Color.lerp(accent, const Color(0xFF2D6BFF), 0.45)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(isDark ? 0.22 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.24), width: 2),
                    ),
                    child: ClipOval(
                      child: profileImage.isNotEmpty
                          ? Image.network(
                              profileImage,
                              width: 62,
                              height: 62,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildSpotlightAvatarFallback(displayName),
                            )
                          : _buildSpotlightAvatarFallback(displayName),
                    ),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -2,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: accent.withOpacity(0.35)),
                      ),
                      child: Icon(
                        Icons.favorite_rounded,
                        color: accent,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bienvenue $displayName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Votre espace personnel est organise pour aller vite, rester lisible et agir au bon moment.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.90),
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (age != null) _heroChip('Age $age ans'),
              _heroChip(bloodType.isEmpty ? 'Groupe n/d' : 'Groupe $bloodType'),
              _heroChip('$appointmentsCount rendez-vous'),
              _heroChip('$treatmentsCount traitement(s)'),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scorePanel = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 84,
                            height: 84,
                            child: CircularProgressIndicator(
                              value: healthRisk.score / 100,
                              strokeWidth: 8,
                              backgroundColor: Colors.white.withOpacity(0.18),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${healthRisk.score}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                'Sante',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.86),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Niveau de sante ${healthRisk.label}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Risques principaux',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...healthRisk.risks.take(3).map(
                            (risk) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(top: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.92),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      risk,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.92),
                                        height: 1.35,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final menuPanel = PopupMenuButton<int>(
                  tooltip: 'Ouvrir les menus santé',
                  onSelected: (index) => dashboardShortcuts[index].onTap(),
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  itemBuilder: (ctx) {
                    return List<PopupMenuEntry<int>>.generate(dashboardShortcuts.length, (index) {
                      final shortcut = dashboardShortcuts[index];
                      return PopupMenuItem<int>(
                        value: index,
                        child: Row(
                          children: [
                            Icon(shortcut.icon, color: accent, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                shortcut.title,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      );
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'Menus',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white.withOpacity(0.90),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                );

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: scorePanel),
                    const SizedBox(width: 12),
                    menuPanel,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpotlightAvatarFallback(String displayName) {
    final initials = _profileInitials(displayName);
    return Container(
      color: Colors.white.withOpacity(0.12),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 20,
        ),
      ),
    );
  }

  Widget _buildPersonDashboardShortcutBar({
    required Color text,
    required Color sub,
    required Color cardBg,
    required Color accent,
    required List<_HealthDashboardShortcut> shortcuts,
  }) {
    if (shortcuts.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Menus du tableau de bord',
                      style: TextStyle(
                        color: text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ouvrez rapidement votre profil, les medicaments, le SOS, les notifications et la carte sante.',
                      style: TextStyle(
                        color: sub,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.dashboard_customize_outlined, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: shortcuts
                .map(
                  (shortcut) => _HealthDashboardShortcutTile(
                    item: shortcut,
                    cardBg: cardBg,
                    text: text,
                    sub: sub,
                    accent: accent,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _heroChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }

  String _profileInitials(String displayName) {
    final words = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return 'PS';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words.first.substring(0, 1)}${words.last.substring(0, 1)}'.toUpperCase();
  }

  Widget _buildPersonVitalsStrip({
    required Color text,
    required Color sub,
    required Color accent,
    required Color cardBg,
    required double? bmi,
    required String tension,
    required String glycemie,
    required String heartRate,
  }) {
    final items = <_MiniStatData>[
      _MiniStatData(
        label: 'IMC',
        value: bmi != null ? bmi.toStringAsFixed(1) : '--',
        icon: Icons.insights_outlined,
      ),
      _MiniStatData(
        label: 'Tension',
        value: tension.isEmpty ? '--' : tension,
        icon: Icons.favorite_border,
      ),
      _MiniStatData(
        label: 'Glycemie',
        value: glycemie.isEmpty ? '--' : glycemie,
        icon: Icons.water_drop_outlined,
      ),
      _MiniStatData(
        label: 'FC',
        value: heartRate.isEmpty ? '--' : heartRate,
        icon: Icons.monitor_heart_outlined,
      ),
    ];

    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          return SizedBox(
            width: 148,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 220 + (index * 60)),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color.lerp(cardBg, accent, 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accent.withOpacity(0.10)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(item.icon, color: accent, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    item.value,
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPersonQuickActions({
    required Color text,
    required Color sub,
    required Color cardBg,
    required Color accent,
    required bool enabled,
    required VoidCallback onOpenAi,
    required VoidCallback onOpenDocuments,
    required VoidCallback onOpenAppointments,
    required VoidCallback onOpenProfile,
  }) {
    final actions = <_QuickHealthActionData>[
      _QuickHealthActionData(
        title: 'Parler a l IA',
        subtitle: 'Question rapide, reponse directe',
        icon: Icons.auto_awesome_outlined,
        onTap: onOpenAi,
      ),
      _QuickHealthActionData(
        title: 'Scanner ordonnance',
        subtitle: 'Photo ou PDF avec analyse',
        icon: Icons.document_scanner_outlined,
        onTap: onOpenDocuments,
      ),
      _QuickHealthActionData(
        title: 'Mes rendez-vous',
        subtitle: 'Voir et organiser mes suivis',
        icon: Icons.event_available_outlined,
        onTap: onOpenAppointments,
      ),
      _QuickHealthActionData(
        title: 'Mon dossier',
        subtitle: 'Mettre a jour mes informations',
        icon: Icons.badge_outlined,
        onTap: onOpenProfile,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width < 430 ? 1 : 2;
        final itemWidth = columns == 1 ? width : (width - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: actions.map((action) {
            return SizedBox(
              width: itemWidth,
              child: _HealthQuickActionCard(
                title: action.title,
                subtitle: action.subtitle,
                icon: action.icon,
                cardBg: cardBg,
                text: text,
                sub: sub,
                accent: accent,
                enabled: enabled,
                onTap: enabled ? action.onTap : null,
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }

  Widget _buildPersonAiComposer({
    required bool isDark,
    required Color text,
    required Color sub,
    required Color cardBg,
    required Color accent,
    required Map<String, dynamic> data,
    required bool enabled,
    required VoidCallback onOpenAi,
  }) {
    final prompts = <String>[
      'Explique mes mesures',
      'Resume ma journee sante',
      'Que verifier aujourd hui ?',
    ];
    final visibleMessages = _healthAiMessages.length <= 4
        ? _healthAiMessages
        : _healthAiMessages.sublist(_healthAiMessages.length - 4);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(isDark ? 0.08 : 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, Color.lerp(accent, Colors.blue, 0.45)!],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.psychology_alt_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assistant IA sante',
                      style: TextStyle(
                        color: text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Posez une question et obtenez une reponse rapide a partir de vos donnees sante.',
                      style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: enabled ? onOpenAi : null,
                child: Text(
                  'Vue complete',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: prompts
                .map(
                  (item) => ActionChip(
                    label: Text(item),
                    backgroundColor: accent.withOpacity(0.08),
                    labelStyle: TextStyle(color: text, fontWeight: FontWeight.w700),
                    onPressed: (!enabled || _healthAiSending)
                        ? null
                        : () {
                            _healthAiPromptCtrl.text = item;
                            _sendHealthAiPrompt(data);
                          },
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Column(
              key: ValueKey('${visibleMessages.length}-${_healthAiSending ? 1 : 0}'),
              children: [
                ...visibleMessages.map(
                  (message) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _HealthAiBubble(
                      message: message,
                      accent: accent,
                      text: text,
                      sub: sub,
                    ),
                  ),
                ),
                if (_healthAiSending)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _healthAiPromptCtrl,
                  enabled: enabled && !_healthAiSending,
                  minLines: 1,
                  maxLines: 3,
                  style: TextStyle(color: text, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: enabled
                        ? 'Ecrivez a l assistant IA...'
                        : 'Connectez votre profil sante pour utiliser l IA',
                    hintStyle: TextStyle(color: sub),
                    filled: true,
                    fillColor: accent.withOpacity(0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: accent.withOpacity(0.12)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: accent.withOpacity(0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(color: accent.withOpacity(0.42)),
                    ),
                  ),
                  onSubmitted: (_) => _sendHealthAiPrompt(data),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, Color.lerp(accent, Colors.blue, 0.35)!],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: IconButton(
                  onPressed: (!enabled || _healthAiSending) ? null : () => _sendHealthAiPrompt(data),
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHospitalShowcase({
    required Color text,
    required Color sub,
    required Color cardBg,
    required Color accent,
    required List<_HospitalDirectoryItem> items,
    required HealthUserContext? userContext,
  }) {
    final query = _personHospitalQuery;
    final radiusKm = _personHospitalRadiusKm;
    final hospitalsRef = FirebaseFirestore.instance.collection('health_hospitals');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: hospitalsRef.orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        final liveItems = snap.hasData
            ? snap.data!.docs
                .map((doc) => _hospitalItemFromMap(doc.data(), sourceId: doc.id))
                .where((item) => item.name.isNotEmpty && item.location.isNotEmpty)
                .toList(growable: false)
            : const <_HospitalDirectoryItem>[];
        final directoryItems = _mergeHospitalItems(liveItems, items);
        final filteredItems = directoryItems.where((item) {
          final matchesQuery = query.isEmpty ||
              item.name.toLowerCase().contains(query) ||
              item.location.toLowerCase().contains(query) ||
              item.note.toLowerCase().contains(query) ||
              item.phone.toLowerCase().contains(query) ||
              item.email.toLowerCase().contains(query) ||
              item.doctors.any((doctor) => doctor.toLowerCase().contains(query)) ||
              item.services.any((service) => service.toLowerCase().contains(query));
          return matchesQuery &&
              _matchesDistanceFilter(
                lat: item.lat,
                lng: item.lng,
                radiusKm: radiusKm,
              );
        }).toList(growable: false);

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withOpacity(0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.local_hospital_outlined, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hopitaux et localisations',
                          style: TextStyle(
                            color: text,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Reperez rapidement les structures disponibles, les urgences 24/7 et les services utiles.',
                          style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!snap.hasData && directoryItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (directoryItems.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accent.withOpacity(0.10)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.location_off_outlined, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Aucun hopital avec localisation n est disponible pour le moment. Les cartes apparaitront ici des qu une donnee reelle sera enregistree.',
                          style: TextStyle(
                            color: sub,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: accent.withOpacity(0.10)),
                      ),
                      child: TextField(
                        controller: _personHospitalSearchCtrl,
                        style: TextStyle(color: text, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.search, color: accent),
                          hintText: 'Rechercher un hopital, une zone ou un service',
                          hintStyle: TextStyle(color: sub),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDistanceFilterWrap(
                      text: text,
                      sub: sub,
                      accent: accent,
                      selectedRadiusKm: radiusKm,
                      onSelected: (value) => _updateDistanceRadius(
                        radiusKm: value,
                        onApply: (selected) => _personHospitalRadiusKm = selected,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (filteredItems.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: accent.withOpacity(0.10)),
                        ),
                        child: Text(
                          radiusKm != null
                              ? 'Aucun hopital ne correspond dans un rayon de ${_radiusLabel(radiusKm)}.'
                              : query.isNotEmpty
                                  ? 'Aucun hopital ne correspond a votre recherche.'
                                  : 'Aucun hopital disponible pour le moment.',
                          style: TextStyle(
                            color: sub,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Column(
                        children: filteredItems.map((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _HospitalDirectoryCard(
                              item: item,
                              distanceLabel: _distanceLabelFromCoordinates(
                                item.lat,
                                item.lng,
                                enabled: radiusKm != null,
                              ),
                              cardBg: cardBg,
                              text: text,
                              sub: sub,
                              accent: accent,
                              onTap: () => _openHospitalActionSheet(
                                item: item,
                                accent: accent,
                                userContext: userContext,
                              ),
                              onOpenMap: () => _openMapLocation(
                                lat: item.lat,
                                lng: item.lng,
                                label: _joinParts([item.name, item.location]),
                              ),
                              onCall: item.phone.isEmpty
                                  ? null
                                  : () => _launchOrSnack(Uri.parse('tel:${item.phone.trim()}')),
                              onEmail: item.email.isEmpty
                                  ? null
                                  : () => _launchOrSnack(Uri.parse('mailto:${item.email.trim()}')),
                            ),
                          );
                        }).toList(growable: false),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHospitalManagementShowcase({
    required Color text,
    required Color sub,
    required Color cardBg,
    required Color accent,
    required List<_HospitalDirectoryItem> fallbackItems,
    required HealthUserContext? userContext,
    required bool canAdd,
    required int? patientsCount,
    required int? patientDocsCount,
    required int teleconsultCount,
    required int criticalAlertsCount,
    VoidCallback? onOpenPatients,
    VoidCallback? onOpenDocuments,
    VoidCallback? onOpenAppointments,
    VoidCallback? onOpenAi,
    VoidCallback? onOpenTeleconsultation,
  }) {
    final query = _personHospitalQuery;
    final radiusKm = _personHospitalRadiusKm;
    final filter = _hospitalDirectoryFilter;
    final hospitalsRef = FirebaseFirestore.instance.collection('health_hospitals');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: hospitalsRef.orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        final liveItems = snap.hasData
            ? snap.data!.docs
                .map((doc) => _hospitalItemFromMap(doc.data(), sourceId: doc.id))
                .where((item) => item.name.isNotEmpty && item.location.isNotEmpty)
                .toList(growable: false)
            : const <_HospitalDirectoryItem>[];
        final directoryItems = _mergeHospitalItems(liveItems, fallbackItems);
        final filteredItems = directoryItems.where((item) {
          final matchesQuery = query.isEmpty ||
              item.name.toLowerCase().contains(query) ||
              item.location.toLowerCase().contains(query) ||
              item.note.toLowerCase().contains(query) ||
              item.phone.toLowerCase().contains(query) ||
              item.email.toLowerCase().contains(query) ||
              item.doctors.any((doctor) => doctor.toLowerCase().contains(query)) ||
              item.services.any((service) => service.toLowerCase().contains(query));
          return matchesQuery &&
              _matchesHospitalDirectoryMode(item, filter) &&
              _matchesDistanceFilter(
                lat: item.lat,
                lng: item.lng,
                radiusKm: radiusKm,
              );
        }).toList(growable: false);

        final totalHospitals = directoryItems.length;
        final emergencyCount = directoryItems.where((item) => item.isEmergency24h).length;
        final openCount = directoryItems.where((item) => item.isOpen || item.isOpen24h).length;
        final mappedCount = directoryItems.where((item) => item.lat != null && item.lng != null).length;
        final contactCount = directoryItems.where((item) => item.phone.isNotEmpty || item.email.isNotEmpty).length;

        final metrics = <Map<String, dynamic>>[
          {'label': 'Hopitaux', 'value': '$totalHospitals', 'icon': Icons.local_hospital_outlined},
          {'label': 'Urgence 24/7', 'value': '$emergencyCount', 'icon': Icons.emergency_outlined},
          {'label': 'Ouverts', 'value': '$openCount', 'icon': Icons.schedule_rounded},
          {'label': 'Geolocalises', 'value': '$mappedCount', 'icon': Icons.map_outlined},
          {'label': 'Avec contact', 'value': '$contactCount', 'icon': Icons.call_outlined},
        ];

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(cardBg, accent, 0.10)!,
                cardBg,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pilotage hopital dynamique',
                          style: TextStyle(
                            color: text,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Annuaire hospitalier, urgences 24/7, cartographie et operations rapides dans un seul tableau de bord.',
                          style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Patients: ${patientsCount ?? 0}  •  Documents: ${patientDocsCount ?? 0}  •  Teleconsultations: $teleconsultCount  •  Alertes critiques: $criticalAlertsCount',
                          style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          canAdd
                              ? 'Votre compte entreprise peut publier et gerer des hopitaux.'
                              : 'Seuls les comptes Entreprise peuvent ajouter un hopital.',
                          style: TextStyle(
                            color: canAdd ? accent : sub,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (canAdd)
                    ElevatedButton.icon(
                      onPressed: _addingHospital ? null : () => _openAddHospital(accent),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: _addingHospital
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_business_outlined),
                      label: const Text('Ajouter'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: metrics.map((metric) {
                  return Container(
                    width: 148,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withOpacity(0.10)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(metric['icon'] as IconData, color: accent, size: 18),
                        const SizedBox(height: 10),
                        Text(
                          metric['value'] as String,
                          style: TextStyle(
                            color: text,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          metric['label'] as String,
                          style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onOpenPatients != null)
                    OutlinedButton.icon(
                      onPressed: onOpenPatients,
                      icon: const Icon(Icons.people_alt_outlined),
                      label: const Text('Patients'),
                    ),
                  if (onOpenAppointments != null)
                    OutlinedButton.icon(
                      onPressed: onOpenAppointments,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Rendez-vous'),
                    ),
                  if (onOpenDocuments != null)
                    OutlinedButton.icon(
                      onPressed: onOpenDocuments,
                      icon: const Icon(Icons.folder_shared_outlined),
                      label: const Text('Documents'),
                    ),
                  if (onOpenAi != null)
                    OutlinedButton.icon(
                      onPressed: onOpenAi,
                      icon: const Icon(Icons.psychology_outlined),
                      label: const Text('IA'),
                    ),
                  if (onOpenTeleconsultation != null)
                    OutlinedButton.icon(
                      onPressed: onOpenTeleconsultation,
                      icon: const Icon(Icons.video_call_outlined),
                      label: const Text('Teleconsultation'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withOpacity(0.10)),
                ),
                child: TextField(
                  controller: _personHospitalSearchCtrl,
                  style: TextStyle(color: text, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search, color: accent),
                    hintText: 'Rechercher un hopital, un service, une zone ou un contact',
                    hintStyle: TextStyle(color: sub),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const <MapEntry<String, String>>[
                  MapEntry<String, String>('all', 'Tout'),
                  MapEntry<String, String>('emergency', 'Urgence 24/7'),
                  MapEntry<String, String>('open', 'Ouverts'),
                  MapEntry<String, String>('mapped', 'Avec carte'),
                  MapEntry<String, String>('contact', 'Avec contact'),
                ].map((item) {
                  final isSelected = filter == item.key;
                  return ChoiceChip(
                    label: Text(item.value),
                    selected: isSelected,
                    showCheckmark: false,
                    backgroundColor: accent.withOpacity(0.06),
                    selectedColor: accent.withOpacity(0.18),
                    labelStyle: TextStyle(
                      color: isSelected ? accent : text,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) {
                      if (!mounted) return;
                      setState(() => _hospitalDirectoryFilter = item.key);
                    },
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 12),
              _buildDistanceFilterWrap(
                text: text,
                sub: sub,
                accent: accent,
                selectedRadiusKm: radiusKm,
                onSelected: (value) => _updateDistanceRadius(
                  radiusKm: value,
                  onApply: (selected) => _personHospitalRadiusKm = selected,
                ),
              ),
              const SizedBox(height: 14),
              if (!snap.hasData && directoryItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filteredItems.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withOpacity(0.10)),
                  ),
                  child: Text(
                    query.isNotEmpty || radiusKm != null || filter != 'all'
                        ? 'Aucun hopital ne correspond aux filtres actifs.'
                        : 'Aucun hopital publie pour le moment.',
                    style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
                  ),
                )
              else
                Column(
                  children: filteredItems.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _HospitalDirectoryCard(
                        item: item,
                        distanceLabel: _distanceLabelFromCoordinates(
                          item.lat,
                          item.lng,
                          enabled: radiusKm != null,
                        ),
                        cardBg: cardBg,
                        text: text,
                        sub: sub,
                        accent: accent,
                        onTap: () => _openHospitalActionSheet(
                          item: item,
                          accent: accent,
                          userContext: userContext,
                        ),
                        onOpenMap: () => _openMapLocation(
                          lat: item.lat,
                          lng: item.lng,
                          label: _joinParts([item.name, item.location]),
                        ),
                        onCall: item.phone.isEmpty
                            ? null
                            : () => _launchOrSnack(Uri.parse('tel:${item.phone.trim()}')),
                        onEmail: item.email.isEmpty
                            ? null
                            : () => _launchOrSnack(Uri.parse('mailto:${item.email.trim()}')),
                        onDelete: item.sourceId.isNotEmpty && _canDeleteHospital(item)
                            ? () => _confirmDeleteHospital(item.sourceId)
                            : null,
                      ),
                    );
                  }).toList(growable: false),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPersonPharmacyShowcase({
    required Color text,
    required Color sub,
    required Color cardBg,
    required Color accent,
  }) {
    final query = _personPharmacyQuery;
    final filter = _personPharmacyFilter;
    final radiusKm = _personPharmacyRadiusKm;
    final pharmacyAccent = const Color(0xFFFF8A1F);
    final pharmaciesRef = FirebaseFirestore.instance.collection('health_pharmacies');

    bool matchesPharmacy(Map<String, dynamic> pharmacy) {
      if (query.isEmpty) return true;
      final name = _safeStr(pharmacy['name']).toLowerCase();
      final address = _safeStr(pharmacy['address'] ?? pharmacy['adresse']).toLowerCase();
      final location = _safeStr(pharmacy['location'] ?? pharmacy['localisation']).toLowerCase();
      final medicines = _stringList(
        pharmacy['medicines'] ?? pharmacy['medications'] ?? pharmacy['medicaments'],
      ).map((item) => item.toLowerCase()).toList(growable: false);

      switch (filter) {
        case 'name':
          return name.contains(query);
        case 'medicine':
          return medicines.any((item) => item.contains(query));
        case 'location':
          return address.contains(query) || location.contains(query);
        case 'all':
        default:
          return name.contains(query) ||
              address.contains(query) ||
              location.contains(query) ||
              medicines.any((item) => item.contains(query));
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(cardBg, pharmacyAccent, 0.12)!,
            cardBg,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: pharmacyAccent.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: pharmacyAccent.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: pharmacyAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.local_pharmacy_outlined, color: pharmacyAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pharmacies disponibles',
                      style: TextStyle(
                        color: text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Touchez une pharmacie pour voir son stock, rechercher un medicament et filtrer la liste.',
                      style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: pharmacyAccent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: pharmacyAccent.withOpacity(0.10)),
            ),
            child: TextField(
              controller: _personPharmacySearchCtrl,
              style: TextStyle(color: text, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search, color: pharmacyAccent),
                hintText: 'Rechercher une pharmacie, une zone ou un medicament',
                hintStyle: TextStyle(color: sub),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: pharmacyAccent.withOpacity(0.10)),
                  ),
                  child: _userPosition == null
                      ? Row(
                          children: [
                            Icon(Icons.my_location_outlined, color: pharmacyAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Activez votre position pour voir le nombre dans 1 km.',
                                style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        )
                      : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: pharmaciesRef.orderBy('createdAt', descending: true).snapshots(),
                          builder: (context, snap) {
                            final nearbyCount = snap.hasData
                                ? snap.data!.docs.where((doc) {
                                    final pharmacy = doc.data();
                                    return _matchesDistanceFilter(
                                      lat: _toDouble(pharmacy['lat'] ?? pharmacy['latitude']),
                                      lng: _toDouble(pharmacy['lng'] ?? pharmacy['longitude']),
                                      radiusKm: 1,
                                    );
                                  }).length
                                : 0;
                            return Row(
                              children: [
                                Icon(Icons.radar_outlined, color: pharmacyAccent, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$nearbyCount pharmacie(s) visible(s) dans un rayon de 1 km.',
                                    style: TextStyle(color: text, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _locBusy
                    ? null
                    : () async {
                        await _ensureLocation();
                      },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: pharmacyAccent.withOpacity(0.22)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _locBusy
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.near_me_outlined, color: pharmacyAccent),
                label: Text(
                  '1 km',
                  style: TextStyle(color: text, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const <MapEntry<String, String>>[
              MapEntry<String, String>('all', 'Tout'),
              MapEntry<String, String>('name', 'Nom'),
              MapEntry<String, String>('medicine', 'Medicaments'),
              MapEntry<String, String>('location', 'Localisation'),
            ].map((item) {
              final isSelected = filter == item.key;
              return ChoiceChip(
                label: Text(item.value),
                selected: isSelected,
                showCheckmark: false,
                backgroundColor: pharmacyAccent.withOpacity(0.06),
                selectedColor: pharmacyAccent.withOpacity(0.18),
                labelStyle: TextStyle(
                  color: text,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) {
                  if (!mounted) return;
                  setState(() => _personPharmacyFilter = item.key);
                },
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 14),
          _buildDistanceFilterWrap(
            text: text,
            sub: sub,
            accent: pharmacyAccent,
            selectedRadiusKm: radiusKm,
            onSelected: (value) => _updateDistanceRadius(
              radiusKm: value,
              onApply: (selected) => _personPharmacyRadiusKm = selected,
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: pharmaciesRef.orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final filtered = snap.data!.docs
                  .where((doc) => matchesPharmacy(doc.data()))
                  .where((doc) {
                    final pharmacy = doc.data();
                    return _matchesDistanceFilter(
                      lat: _toDouble(pharmacy['lat'] ?? pharmacy['latitude']),
                      lng: _toDouble(pharmacy['lng'] ?? pharmacy['longitude']),
                      radiusKm: radiusKm,
                    );
                  })
                  .toList(growable: false);

              if (filtered.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: pharmacyAccent.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: pharmacyAccent.withOpacity(0.10)),
                  ),
                  child: Text(
                    radiusKm != null
                        ? 'Aucune pharmacie ne correspond dans un rayon de ${_radiusLabel(radiusKm)}.'
                        : query.isEmpty
                            ? 'Aucune pharmacie disponible pour le moment.'
                            : 'Aucun resultat pour cette recherche. Essayez un autre filtre ou un autre mot-cle.',
                    style: TextStyle(
                      color: sub,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }

              return Column(
                children: filtered.map((doc) {
                  final pharmacy = doc.data();
                  final name = _safeStr(pharmacy['name']);
                  final address = _safeStr(pharmacy['address'] ?? pharmacy['adresse']);
                  final location = _safeStr(pharmacy['location'] ?? pharmacy['localisation']);
                  final image = _safeStr(pharmacy['photo'] ?? pharmacy['image'] ?? pharmacy['photoUrl']);
                  final phone = _safeStr(pharmacy['phone'] ?? pharmacy['telephone']);
                  final email = _safeStr(pharmacy['email']);
                  final lat = _toDouble(pharmacy['lat'] ?? pharmacy['latitude']);
                  final lng = _toDouble(pharmacy['lng'] ?? pharmacy['longitude']);
                  final statusLabel = _pharmacyStatusLabel(pharmacy);
                  final isOpen = _isPharmacyOpen(pharmacy);
                  final medicines = _stringList(
                    pharmacy['medicines'] ?? pharmacy['medications'] ?? pharmacy['medicaments'],
                  );

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PersonPharmacyCard(
                      name: name.trim().isNotEmpty ? name : 'Pharmacie',
                      place: _joinParts([address, location]),
                      medicines: medicines,
                      image: image,
                      phone: phone,
                      email: email,
                      lat: lat,
                      lng: lng,
                      statusLabel: statusLabel,
                      isOpen: isOpen,
                      distanceLabel: _distanceLabelFromCoordinates(
                        lat,
                        lng,
                        enabled: radiusKm != null,
                      ),
                      text: text,
                      sub: sub,
                      accent: pharmacyAccent,
                      onTap: () => _openPharmacyMedicinesSheet(
                        name: name.trim().isNotEmpty ? name : 'Pharmacie',
                        place: _joinParts([address, location]),
                        medicines: medicines,
                        accent: pharmacyAccent,
                      ),
                      onOpenMap: () => _openMapLocation(
                        lat: lat,
                        lng: lng,
                        label: _joinParts([name, address, location]),
                      ),
                      onCall: phone.isEmpty
                          ? null
                          : () => _launchOrSnack(Uri.parse('tel:${phone.trim()}')),
                      onEmail: email.isEmpty
                          ? null
                          : () => _launchOrSnack(Uri.parse('mailto:${email.trim()}')),
                    ),
                  );
                }).toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _singleHealthView({
    required Color cardBg,
    required Color text,
    required Color sub,
    required Map<String, dynamic> data,
    required bool isDark,
  }) {
    switch (widget.viewMode) {
      case HealthProfileViewMode.hospital:
        return _buildTabContent(
          label: 'Hopital',
          cardBg: cardBg,
          text: text,
          sub: sub,
          data: data,
          isDark: isDark,
          includeHero: true,
        );
      case HealthProfileViewMode.pharmacy:
        return _buildTabContent(
          label: 'Pharmacies',
          cardBg: cardBg,
          text: text,
          sub: sub,
          data: data,
          isDark: isDark,
          includeHero: true,
        );
      case HealthProfileViewMode.person:
      case HealthProfileViewMode.all:
        return _buildTabContent(
          label: 'Personne',
          cardBg: cardBg,
          text: text,
          sub: sub,
          data: data,
          isDark: isDark,
          includeHero: true,
        );
    }
  }

  Widget _buildPersonTab(
    Color cardBg,
    Color text,
    Color sub,
    Color accent,
    Map<String, dynamic> data,
    {Widget? header}
  ) {
    final firstName = _safeStr(data['firstName']);
    final lastName = _safeStr(data['lastName']);
    final displayName = _safeStr(data['name']).isNotEmpty
        ? _safeStr(data['name'])
        : [firstName, lastName].where((v) => v.isNotEmpty).join(' ').trim();
    final birthDateRaw = _safeStr(data['birthDate']);
    final birthDate = birthDateRaw.isEmpty ? null : DateTime.tryParse(birthDateRaw);
    final age = _ageFromDate(birthDate);

    final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};
    final documents = (data['documents'] is Map) ? Map<String, dynamic>.from(data['documents'] as Map) : <String, dynamic>{};

    final weight = _toDouble(health['weight'] ?? health['weightKg'] ?? health['poids']);
    final height = _toDouble(health['height'] ?? health['heightCm'] ?? health['taille']);
    final bmi = _bmi(weight, height);
    final bloodType = _safeStr(health['bloodType'] ?? health['blood_group'] ?? health['groupe']);
    final tension = _safeStr(health['bloodPressure'] ?? health['tension']);
    final glycemie = _safeStr(health['glucose'] ?? health['glycemie']);
    final heartRate = _safeStr(health['heartRate'] ?? health['frequenceCardiaque']);
    final activity = _safeStr(health['activity'] ?? health['activitePhysique']);
    final gender = _safeStr(
      data['genre'] ?? data['gender'] ?? data['sex'] ?? health['genre'] ?? health['gender'] ?? health['sex'],
    );
    final isFemale = _isFemaleProfile(gender);

    final allergies = _stringList(health['allergies']);
    final conditions = _stringList(health['chronicConditions'] ?? health['conditions'] ?? health['medicalConditions']);
    final medicalHistory = _stringList(
      health['medicalHistory'] ?? health['history'] ?? data['medicalHistory'] ?? data['healthHistory'],
    );
    final hospitalizations = _stringList(health['hospitalizations']);
    final vaccinations = _stringList(health['vaccinations']);

    final meds = _medicationBullets(health['medications']);
    final medsToday = _medicationBullets(health['medicationsToday'] ?? health['todayMedications']);
    final medicationHistory = _stringList(health['medicationHistory'] ?? health['medsHistory']);

    final appointments = _appointmentBullets(health['appointments']);
    final appointmentHistory = _appointmentBullets(health['appointmentHistory'] ?? health['appointmentsHistory']);

    final alerts = _stringList(health['alerts'] ?? health['importantAlerts'] ?? health['notifications']);
    final aiAlerts = _stringList(health['aiAlerts'] ?? health['alertsAi']);

    final emergencyName = _safeStr(health['emergencyContact'] ?? health['emergencyName']);
    final emergencyPhone = _safeStr(health['emergencyPhone'] ?? health['emergencyNumber']);

    final cycleSummary = _cycleSummary(health['cycle'] ?? health['menstrualCycle']);
    final cycleSymptoms = _stringList(health['cycleSymptoms'] ?? health['symptoms']);
    final cycleHistory = _stringList(health['cycleHistory']);
    final cycleNext = _safeStr(health['nextPeriod'] ?? health['cycleNext']);

    final aiRecommendations = _stringList(health['aiRecommendations'] ?? health['recommendations']);
    final preventionTips = _stringList(health['preventionTips'] ?? health['tips']);

    final docCount = _countDocs(health['documents'] ?? health['medicalDocuments'] ?? documents['medical']);
    final labResults = _stringList(health['labResults'] ?? health['analyses']);
    final documentHistory = _stringList(health['documentHistory'] ?? health['documentsHistory']);

    final profilePdfUrl = _safeStr(
      health['profilePdf'] ?? health['profilePdfUrl'] ?? documents['profilePdf'] ?? documents['healthProfilePdf'],
    );
    final reportsPdfUrl = _safeStr(health['reportsPdf'] ?? documents['reportsPdf']);
    final qrCodeUrl = _safeStr(health['qrCode'] ?? health['qrCodeUrl']);

    final medsNotif = _boolValue(health['medicationNotifications']);
    final apptNotif = _boolValue(health['appointmentNotifications']);
    final cycleNotif = _boolValue(health['cycleNotifications']);
    final aiNotif = _boolValue(health['aiNotifications'] ?? health['aiAlertsEnabled']);
    final smartReminders = _boolValue(health['smartReminders']);
    final aiEnabled = _boolValue(health['aiEnabled'] ?? health['checkIa']);
    final aiDocAnalysis = _boolValue(health['aiDocAnalysis'] ?? health['aiDocuments']);
    final sosGps = _boolValue(health['sosGpsEnabled']);
    final sosNotif = _boolValue(health['sosNotifications']);
    final teleconsult = _boolValue(health['teleconsultationEnabled']);
    final pharmacy = _boolValue(health['pharmacyEnabled']);
    final preventionAlerts = _boolValue(health['vaccinationAlerts'] ?? health['screeningAlerts']);
    final thresholdAlerts = _boolValue(health['thresholdAlerts']);

    final ctx = (_userCollection != null && _userId != null)
        ? HealthUserContext(userId: _userId!, userCollection: _userCollection!)
        : null;
    void openPage(Widget page) {
      if (ctx == null) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }

    final profileMedicalBullets = <String>[
      'Informations personnelles : ${displayName.isNotEmpty ? displayName : 'Non renseigné'}, naissance ${_formatBirth(birthDate, age)}',
      'Groupe sanguin : ${bloodType.isNotEmpty ? bloodType : 'Non renseigné'}',
      'Allergies : ${allergies.isNotEmpty ? allergies.join(', ') : 'Non renseignées'}',
      'Maladies chroniques : ${conditions.isNotEmpty ? conditions.join(', ') : 'Non renseignées'}',
      'Taille, poids, IMC : ${_summaryBody(weight: weight, height: height, bmi: bmi)}',
      'Contact d’urgence : ${_summaryEmergency(emergencyName, emergencyPhone)}',
      'Historique médical complet : ${_summarizeList(_mergeLists([medicalHistory, hospitalizations, vaccinations]), empty: 'Aucun')}',
      'Export PDF du profil : ${profilePdfUrl.isNotEmpty ? 'Disponible' : 'Non disponible'}',
    ];
    final medicationBullets = <String>[
      'Ajouter / modifier / supprimer médicaments',
      'Dose et heure de prise : ${_summarizeList(meds, empty: 'Non renseigné')}',
      'Durée du traitement : ${_summarizeList(_stringList(health['medicationDurations']), empty: 'Non renseignée')}',
      'Historique de prise : ${_summarizeList(medicationHistory, empty: 'Aucun')}',
      'Notifications push pour rappel : ${_statusLabel(medsNotif)}',
      'Rappel intelligent basé sur la prise effective : ${_statusLabel(smartReminders)}',
    ];
    final cycleBullets = <String>[
      'Suivi du cycle : ${cycleSummary.isNotEmpty ? cycleSummary : 'Non renseigné'}',
      'Suivi des symptômes quotidiens : ${_summarizeList(cycleSymptoms, empty: 'Aucun')}',
      'Historique des cycles : ${_summarizeList(cycleHistory, empty: 'Aucun')}',
      'Prévision prochaines règles et fenêtre fertile : ${cycleNext.isNotEmpty ? cycleNext : 'Non renseignée'}',
      'Notifications et rappels : ${_statusLabel(cycleNotif)}',
      'Analyse IA pour détecter irrégularités et conseils personnalisés : ${_statusLabel(_boolValue(health['cycleAi']))}',
    ];
    final sosBullets = <String>[
      'Position GPS : ${_statusLabel(sosGps)}',
      'Informations médicales essentielles : ${_summaryEssentials(bloodType, allergies, conditions)}',
      'Contact d’urgence : ${_summaryEmergency(emergencyName, emergencyPhone)}',
      'Notifications aux proches ou services médicaux : ${_statusLabel(sosNotif)}',
    ];
    final notificationBullets = <String>[
      'Prise de médicaments : ${_statusLabel(medsNotif)}',
      'Rendez-vous médicaux : ${_statusLabel(apptNotif)}',
      if (isFemale) 'Cycle menstruel : ${_statusLabel(cycleNotif)}',
      'Alertes santé basées sur l’IA : ${_statusLabel(aiNotif)}',
    ];
    final qrBullets = <String>[
      'QR Code santé pour accès rapide aux informations essentielles : ${qrCodeUrl.isNotEmpty ? 'Disponible' : 'Non généré'}',
      'Contient : ${_summaryEssentials(bloodType, allergies, conditions, emergencyName: emergencyName, emergencyPhone: emergencyPhone)}',
    ];
    final historyBullets = <String>[
      'Historique complet de mesures, ${isFemale ? 'cycle, ' : ''}médicaments, rendez-vous : ${_summarizeList(_mergeLists([medicalHistory, if (isFemale) cycleHistory, medicationHistory, appointmentHistory]), empty: 'Aucun')}',
      'Export PDF ou partage sécurisé avec médecin : ${reportsPdfUrl.isNotEmpty ? 'Disponible' : 'Non disponible'}',
    ];

    final dashboardShortcuts = <_HealthDashboardShortcut>[
      _HealthDashboardShortcut(
        title: 'Profil médical',
        label: 'Profil',
        icon: Icons.badge_outlined,
        onTap: () => _openHealthMenuSheet(
          title: 'Profil médical',
          icon: Icons.badge_outlined,
          bullets: profileMedicalBullets,
          accent: accent,
          primaryLabel: ctx == null ? null : 'Modifier le profil',
          onPrimaryAction: ctx == null ? null : () => openPage(HealthProfileEditPage(contextRef: ctx)),
        ),
      ),
      _HealthDashboardShortcut(
        title: 'Médicaments',
        label: 'Médicaments',
        icon: Icons.medication_outlined,
        onTap: () => _openHealthMenuSheet(
          title: 'Médicaments',
          icon: Icons.medication_outlined,
          bullets: medicationBullets,
          accent: accent,
          primaryLabel: ctx == null ? null : 'Gérer les médicaments',
          onPrimaryAction: ctx == null ? null : () => openPage(HealthMedicationsPage(contextRef: ctx)),
        ),
      ),
      _HealthDashboardShortcut(
        title: 'SOS / Urgence',
        label: 'SOS',
        icon: Icons.emergency_outlined,
        onTap: () => _openHealthMenuSheet(
          title: 'Module urgence / SOS',
          icon: Icons.emergency_outlined,
          bullets: sosBullets,
          accent: accent,
          primaryLabel: ctx == null ? null : 'Mettre à jour le profil',
          onPrimaryAction: ctx == null ? null : () => openPage(HealthProfileEditPage(contextRef: ctx)),
        ),
      ),
      _HealthDashboardShortcut(
        title: 'Notifications',
        label: 'Notifications',
        icon: Icons.notifications_active_outlined,
        onTap: () => _openHealthMenuSheet(
          title: 'Notifications intelligentes',
          icon: Icons.notifications_active_outlined,
          bullets: notificationBullets,
          accent: accent,
          primaryLabel: ctx == null ? null : 'Ouvrir les notifications',
          onPrimaryAction: ctx == null ? null : () => openPage(HealthNotificationsPage(contextRef: ctx)),
        ),
      ),
      _HealthDashboardShortcut(
        title: 'Carte santé',
        label: 'Carte santé',
        icon: Icons.qr_code_2_outlined,
        onTap: () => _openHealthMenuSheet(
          title: 'QR Code / Carte santé numérique',
          icon: Icons.qr_code_2_outlined,
          bullets: qrBullets,
          accent: accent,
          primaryLabel: ctx == null ? null : 'Voir le QR code',
          onPrimaryAction: ctx == null ? null : () => openPage(HealthQrPage(contextRef: ctx)),
        ),
      ),
    ];

    final sections = <_HealthSection>[
      if (isFemale)
        _HealthSection(
          icon: Icons.water_drop_outlined,
          title: 'Module Menstruations / Cycle féminin',
          bullets: cycleBullets,
        ),
      _HealthSection(
        icon: Icons.insert_drive_file_outlined,
        title: 'Historique et rapports',
        bullets: historyBullets,
      ),
    ];

    final actions = ctx == null
        ? null
        : <VoidCallback?>[
            if (isFemale) () => openPage(HealthCyclePage(contextRef: ctx)),
            () => openPage(HealthDocumentsPage(contextRef: ctx)),
          ];

    final experienceHeader = _buildPersonExperienceHeader(
      isDark: Theme.of(context).brightness == Brightness.dark,
      cardBg: cardBg,
      text: text,
      sub: sub,
      accent: accent,
      data: data,
      displayName: displayName,
      age: age,
      bloodType: bloodType,
      bmi: bmi,
      tension: tension,
      glycemie: glycemie,
      heartRate: heartRate,
      medsToday: medsToday.isNotEmpty ? medsToday : meds,
      appointments: appointments,
      dashboardShortcuts: dashboardShortcuts,
      ctx: ctx,
      onOpenAi: () => openPage(HealthAiPage(contextRef: ctx!)),
      onScanPrescription: () {
        _snack('Ajoutez une photo ou un PDF de votre ordonnance pour lancer le scan.');
        openPage(HealthDocumentsPage(contextRef: ctx!));
      },
      onOpenAppointments: () => openPage(HealthAppointmentsPage(contextRef: ctx!)),
      onOpenProfile: () => openPage(HealthProfileEditPage(contextRef: ctx!)),
    );

    return _FeatureList(
      cardBg: cardBg,
      text: text,
      sub: sub,
      accent: accent,
      header: _mergeHeaderWidgets(header, experienceHeader),
      sections: sections,
      actions: actions,
    );
  }

  Widget _buildHospitalTab(
    Color cardBg,
    Color text,
    Color sub,
    Color accent,
    Map<String, dynamic> data,
    {Widget? header}
  ) {
    final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};
    final patients = _stringList(health['patients']);
    final patientsCountRaw = _toInt(health['patientsCount']);
    final patientsCount = patientsCountRaw ?? (patients.isNotEmpty ? patients.length : null);

    final patientDocs = _stringList(health['patientDocuments'] ?? health['patientDocs']);
    final patientDocsCountRaw = _toInt(health['patientDocumentsCount']);
    final patientDocsCount = patientDocsCountRaw ?? (patientDocs.isNotEmpty ? patientDocs.length : null);

    final appts = _appointmentBullets(health['appointments'] ?? health['hospitalAppointments']);
    final teleconsults = _stringList(health['teleconsultations']);
    final criticalAlerts = _stringList(health['criticalAlerts'] ?? health['alertsCritical']);
    final fallbackHospitals = _hospitalDirectory(data);
    final canAdd = _canAddHospital(data);

    final aiEnabled = _boolValue(health['aiEnabled'] ?? health['aiHospital']);
    final exportAvailable = _boolValue(health['exportPdfAvailable'] ?? health['exportAvailable']);

    final sections = <_HealthSection>[
      _HealthSection(
        icon: Icons.people_alt_outlined,
        title: 'Liste des patients',
        bullets: [
          'Patients enregistres : ${patientsCount != null ? patientsCount.toString() : 'Non renseigne'}',
          'Derniers patients : ${_summarizeList(patients, empty: 'Aucun')}',
        ],
      ),
      _HealthSection(
        icon: Icons.history_edu_outlined,
        title: 'Historique medical et documents',
        bullets: [
          'Documents patients : ${patientDocsCount != null ? patientDocsCount.toString() : 'Non renseigne'}',
          'Historique recent : ${_summarizeList(patientDocs, empty: 'Aucun')}',
        ],
      ),
      _HealthSection(
        icon: Icons.calendar_month_outlined,
        title: 'Gestion des rendez-vous et teleconsultations',
        bullets: [
          'Rendez-vous : ${_summarizeList(appts, empty: 'Aucun')}',
          'Teleconsultations : ${_summarizeList(teleconsults, empty: 'Aucune')}',
        ],
      ),
      _HealthSection(
        icon: Icons.analytics_outlined,
        title: 'Module IA pour analyse des mesures sante des patients',
        bullets: [
          'Analyse IA activee : ${_statusLabel(aiEnabled)}',
        ],
      ),
      _HealthSection(
        icon: Icons.warning_amber_outlined,
        title: 'Alertes pour patients en situation critique',
        bullets: [
          'Alertes critiques : ${_summarizeList(criticalAlerts, empty: 'Aucune')}',
        ],
      ),
      _HealthSection(
        icon: Icons.picture_as_pdf_outlined,
        title: 'Export des donnees PDF pour suivi medical',
        bullets: [
          'Export PDF : ${_statusLabel(exportAvailable)}',
        ],
      ),
    ];

    final ctx = (_userCollection != null && _userId != null)
        ? HealthUserContext(userId: _userId!, userCollection: _userCollection!)
        : null;
    void openPage(Widget page) {
      if (ctx == null) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }

    final actions = ctx == null
        ? null
        : <VoidCallback?>[
            () => openPage(HealthPatientsWaitingPage(contextRef: ctx)),
            () => openPage(HealthDocumentsPage(contextRef: ctx)),
            () => openPage(HealthAppointmentsPage(contextRef: ctx)),
            () => openPage(HealthAiPage(contextRef: ctx)),
            () => openPage(HealthDocumentsPage(contextRef: ctx)),
          ];

    final dashboard = _buildHospitalManagementShowcase(
      text: text,
      sub: sub,
      cardBg: cardBg,
      accent: accent,
      fallbackItems: fallbackHospitals,
      userContext: ctx,
      canAdd: canAdd,
      patientsCount: patientsCount,
      patientDocsCount: patientDocsCount,
      teleconsultCount: teleconsults.length,
      criticalAlertsCount: criticalAlerts.length,
      onOpenPatients: ctx == null ? null : () => openPage(HealthPatientsWaitingPage(contextRef: ctx)),
      onOpenDocuments: ctx == null ? null : () => openPage(HealthDocumentsPage(contextRef: ctx)),
      onOpenAppointments: ctx == null ? null : () => openPage(HealthAppointmentsPage(contextRef: ctx)),
      onOpenAi: ctx == null ? null : () => openPage(HealthAiPage(contextRef: ctx)),
      onOpenTeleconsultation: ctx == null ? null : () => openPage(HealthTeleconsultationPage(contextRef: ctx)),
    );

    return _FeatureList(
      cardBg: cardBg,
      text: text,
      sub: sub,
      accent: accent,
      header: _mergeHeaderWidgets(header, dashboard),
      sections: sections,
      actions: actions,
    );
  }

  Widget _buildPharmacyTab(
    Color cardBg,
    Color text,
    Color sub,
    Color accent,
    Map<String, dynamic> data,
    {required bool showHero}
  ) {
    final query = _pharmacyQuery;
    final pharmaciesRef = FirebaseFirestore.instance.collection('health_pharmacies');
    final pharmaciesStream = pharmaciesRef.orderBy('createdAt', descending: true).snapshots();
    final canAdd = _canAddPharmacy(data);
    final managerMode = canAdd && _userId != null;
    final displayName = _healthDisplayName(data);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: pharmaciesStream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        final totalPharmacies = docs.length;
        final totalProducts = docs.fold<int>(
          0,
          (sum, doc) => sum + _pharmacyCatalogFromData(doc.data()).length,
        );
        final filtered = docs.where((d) {
          if (query.isEmpty) return true;
          final data = d.data();
          final name = _safeStr(data['name']).toLowerCase();
          final address = _safeStr(data['address'] ?? data['adresse']).toLowerCase();
          final location = _safeStr(data['location'] ?? data['localisation']).toLowerCase();
          final meds = _pharmacyCatalogMedicineNames(_pharmacyCatalogFromData(data))
              .map((m) => m.toLowerCase())
              .toList();
          return name.contains(query) ||
              address.contains(query) ||
              location.contains(query) ||
              meds.any((m) => m.contains(query));
        }).where((d) {
          if (!managerMode) return true;
          switch (_pharmacyManagerScope) {
            case 'mine':
              return _canDeletePharmacy(d.data());
            case 'attention':
              return _canDeletePharmacy(d.data()) && _pharmacyAttentionScore(d.data()) > 0;
            case 'all':
            default:
              return true;
          }
        }).toList();
        filtered.sort(_comparePharmacyDashboardPriority);

        return Column(
          children: [
            if (showHero)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOutCubic,
                  );
                  return ClipRect(
                    child: SizeTransition(
                      sizeFactor: curved,
                      axisAlignment: -1,
                      child: FadeTransition(
                        opacity: curved,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _showPharmacyHeader
                    ? Padding(
                        key: const ValueKey<String>('pharmacy-header-visible'),
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: _buildPharmacyHero(
                          displayName: displayName,
                          totalPharmacies: totalPharmacies,
                          totalProducts: totalProducts,
                          accent: accent,
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('pharmacy-header-hidden'),
                      ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _pharmacySearchCtrl,
                  style: TextStyle(color: text, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search, color: accent),
                    hintText: 'Rechercher un medicament ou une pharmacie',
                    hintStyle: TextStyle(color: sub),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withOpacity(0.12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _exportingPharmacies ? null : _exportPharmaciesExcel,
                          icon: _exportingPharmacies
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.file_download_outlined),
                          label: const Text('Exporter'),
                        ),
                        OutlinedButton.icon(
                          onPressed: (!_importingPharmacies && canAdd) ? _importPharmaciesExcel : null,
                          icon: _importingPharmacies
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.file_upload_outlined),
                          label: const Text('Importer'),
                        ),
                        if (canAdd)
                          ElevatedButton.icon(
                            onPressed: _addingPharmacy ? null : () => _openAddPharmacy(accent),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.add_business_outlined),
                            label: const Text('Ajouter'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) => _handlePharmacyScrollNotification(
                  notification,
                  canToggleHeader: showHero,
                ),
                child: _buildPharmacyDashboardContent(
                  docs: filtered,
                  allDocs: docs,
                  cardBg: cardBg,
                  text: text,
                  sub: sub,
                  accent: accent,
                  canAdd: canAdd,
                  managerMode: managerMode,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatBirth(DateTime? birth, int? age) {
    if (birth == null) return 'Non renseignée';
    final formatted = DateFormat('dd/MM/yyyy').format(birth);
    return age != null ? '$formatted ($age ans)' : formatted;
  }

  String _accountLabel(int? profileType, String? collection) {
    if (profileType == 1 || collection == 'pro_users') return 'Pro';
    if (profileType == 2 || collection == 'enterprise_users') return 'Entreprise';
    return 'Classique';
  }

  String _safeStr(dynamic v) => (v ?? '').toString().trim();

  String _healthDisplayName(Map<String, dynamic> data) {
    final explicitName = _safeStr(data['name'] ?? data['displayName'] ?? data['fullName']);
    if (explicitName.isNotEmpty) return explicitName;

    final firstName = _safeStr(data['firstName'] ?? data['prenom']);
    final lastName = _safeStr(data['lastName'] ?? data['nom']);
    final joined = [firstName, lastName].where((value) => value.isNotEmpty).join(' ').trim();
    if (joined.isNotEmpty) return joined;

    final email = _safeStr(data['email']);
    if (email.contains('@')) {
      return email.split('@').first.trim();
    }
    return email;
  }

  int? _ageFromDate(DateTime? birth) {
    if (birth == null) return null;
    final now = DateTime.now();
    int age = now.year - birth.year;
    if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) {
      age -= 1;
    }
    return age < 0 ? null : age;
  }

  double? _toDouble(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    final s = raw.toString().replaceAll(',', '.');
    return double.tryParse(s);
  }

  double? _bmi(double? weightKg, double? heightCm) {
    if (weightKg == null || heightCm == null || heightCm <= 0) return null;
    final h = heightCm / 100;
    if (h <= 0) return null;
    return weightKg / (h * h);
  }

  int? _toInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    final s = raw.toString().trim();
    return int.tryParse(s);
  }

  bool? _boolValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final s = raw.toString().trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s == 'true' || s == '1' || s == 'yes' || s == 'oui') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'non') return false;
    return null;
  }

  String _statusLabel(bool? value) {
    if (value == null) return 'Non configure';
    return value ? 'Active' : 'Desactive';
  }

  String _summarizeList(List<String> items, {int max = 2, String empty = 'Aucun'}) {
    if (items.isEmpty) return empty;
    if (items.length <= max) return items.join(' / ');
    final head = items.take(max).join(' / ');
    return '$head (+${items.length - max})';
  }

  List<String> _mergeLists(List<List<String>> lists) {
    final out = <String>[];
    for (final list in lists) {
      for (final item in list) {
        final v = _safeStr(item);
        if (v.isNotEmpty) out.add(v);
      }
    }
    return out;
  }

  String _summaryIndicators({
    double? weight,
    String? tension,
    String? glycemie,
    String? cycle,
  }) {
    final parts = <String>[
      weight != null ? 'poids ${weight.toStringAsFixed(1)} kg' : 'poids n/d',
      _safeStr(tension).isNotEmpty ? 'tension ${_safeStr(tension)}' : 'tension n/d',
      _safeStr(glycemie).isNotEmpty ? 'glycémie ${_safeStr(glycemie)}' : 'glycémie n/d',
    ];
    if (cycle != null) {
      parts.add(_safeStr(cycle).isNotEmpty ? 'cycle ${_safeStr(cycle)}' : 'cycle n/d');
    }
    return parts.join(', ');
  }

  String _summaryMeasures({
    double? weight,
    String? tension,
    String? glycemie,
    String? heartRate,
    String? activity,
  }) {
    final parts = <String>[
      weight != null ? 'poids ${weight.toStringAsFixed(1)} kg' : 'poids n/d',
      _safeStr(tension).isNotEmpty ? 'tension ${_safeStr(tension)}' : 'tension n/d',
      _safeStr(glycemie).isNotEmpty ? 'glycémie ${_safeStr(glycemie)}' : 'glycémie n/d',
      _safeStr(heartRate).isNotEmpty ? 'FC ${_safeStr(heartRate)}' : 'FC n/d',
      _safeStr(activity).isNotEmpty ? 'activité ${_safeStr(activity)}' : 'activité n/d',
    ];
    return parts.join(', ');
  }

  String _summaryBody({double? weight, double? height, double? bmi}) {
    final parts = <String>[
      weight != null ? '${weight.toStringAsFixed(1)} kg' : 'poids n/d',
      height != null ? '${height.toStringAsFixed(1)} cm' : 'taille n/d',
      bmi != null ? 'IMC ${bmi.toStringAsFixed(1)}' : 'IMC n/d',
    ];
    return parts.join(' / ');
  }

  String _summaryEmergency(String name, String phone) {
    final n = _safeStr(name);
    final p = _safeStr(phone);
    if (n.isEmpty && p.isEmpty) return 'Non renseigne';
    if (n.isNotEmpty && p.isNotEmpty) return '$n ($p)';
    return n.isNotEmpty ? n : p;
  }

  bool _isHospitalOperationalStatus(String raw) {
    final value = _safeStr(raw).toLowerCase();
    return value.contains('ouvert') ||
        value.contains('open') ||
        value.contains('ferme') ||
        value.contains('closed');
  }

  String _hospitalExtraBadge(String raw) {
    final badge = _safeStr(raw);
    if (badge.isEmpty || _isHospitalOperationalStatus(badge)) return '';
    return badge;
  }

  bool _isHospitalOpenFromMap(Map<String, dynamic> map) {
    final direct = _boolValue(map['isOpen'] ?? map['open'] ?? map['openNow'] ?? map['currentlyOpen']);
    if (direct != null) return direct;
    final status = _safeStr(map['status'] ?? map['badge']).toLowerCase();
    if (status.contains('ferme') || status.contains('closed')) return false;
    if (_boolValue(map['open24h'] ?? map['alwaysOpen']) == true) return true;
    if (status.contains('ouvert') || status.contains('open') || status.contains('urgence')) return true;
    return true;
  }

  String _hospitalOperationalStatusFromMap(Map<String, dynamic> map) {
    final rawStatus = _safeStr(map['status']);
    if (_isHospitalOperationalStatus(rawStatus)) return rawStatus;
    final isOpen = _isHospitalOpenFromMap(map);
    final isOpen24h = _boolValue(map['open24h'] ?? map['alwaysOpen']) == true;
    return isOpen ? (isOpen24h ? 'Ouvert 24/7' : 'Ouvert') : 'Ferme';
  }

  String _hospitalStatusLabel(_HospitalDirectoryItem item) {
    final status = _safeStr(item.status);
    if (status.isNotEmpty) return status;
    if (!item.isOpen) return 'Ferme';
    if (item.isOpen24h) return 'Ouvert 24/7';
    return 'Ouvert';
  }

  List<_HospitalDoctorProfile> _hospitalDoctorProfiles(dynamic raw) {
    if (raw == null) return const <_HospitalDoctorProfile>[];
    if (raw is List) {
      final out = <_HospitalDoctorProfile>[];
      for (final item in raw) {
        if (item is Map) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final name = _safeStr(map['name'] ?? map['doctor'] ?? map['medecin']);
          if (name.isEmpty) continue;
          out.add(
            _HospitalDoctorProfile(
              name: name,
              service: _safeStr(map['service'] ?? map['speciality'] ?? map['specialty']),
              phone: _safeStr(map['phone'] ?? map['telephone']),
              photo: _safeStr(map['photo'] ?? map['image'] ?? map['photoUrl']),
              hidePhoto: _boolValue(map['hidePhoto'] ?? map['maskPhoto']) == true,
            ),
          );
        } else {
          final name = _safeStr(item);
          if (name.isEmpty) continue;
          out.add(_HospitalDoctorProfile(name: name));
        }
      }
      return out;
    }
    if (raw is Map) {
      return _hospitalDoctorProfiles(<dynamic>[raw]);
    }
    final name = _safeStr(raw);
    return name.isEmpty ? const <_HospitalDoctorProfile>[] : <_HospitalDoctorProfile>[_HospitalDoctorProfile(name: name)];
  }

  List<Map<String, dynamic>> _hospitalDoctorProfileMaps(List<_HospitalDoctorProfile> doctors) {
    return doctors
        .map(
          (doctor) => <String, dynamic>{
            'name': doctor.name,
            'service': doctor.service,
            'phone': doctor.phone,
            'photo': doctor.photo,
            'hidePhoto': doctor.hidePhoto,
          },
        )
        .toList(growable: false);
  }

  String _joinParts(List<String> parts) {
    final out = parts.map((p) => _safeStr(p)).where((p) => p.isNotEmpty).toList();
    return out.isEmpty ? '' : out.join(' / ');
  }

  bool _isFemaleProfile(String raw) {
    final value = _safeStr(raw).toLowerCase();
    return value == 'f' ||
        value == 'femme' ||
        value == 'female' ||
        value == 'woman' ||
        value == 'girl';
  }

  bool _canAddPharmacy(Map<String, dynamic> data) {
    final profileType = data['profileType'];
    if (profileType is int) return profileType == 1 || profileType == 2;
    final raw = _safeStr(profileType);
    if (raw.isEmpty) return false;
    return raw == '1' || raw == '2' || raw.toLowerCase() == 'pro' || raw.toLowerCase() == 'enterprise';
  }

  bool _canAddHospital(Map<String, dynamic> data) {
    final profileType = data['profileType'];
    if (profileType is int) return profileType == 2;
    final raw = _safeStr(profileType).toLowerCase();
    if (raw == '2' || raw == 'enterprise' || raw == 'entreprise') return true;
    return _userCollection == 'enterprise_users';
  }

  bool _canDeleteHospital(_HospitalDirectoryItem item) {
    if (_userCollection != 'enterprise_users') return false;
    if (item.sourceId.isEmpty) return false;
    if (item.ownerId.isEmpty) return true;
    if (_userId == null) return false;
    return item.ownerId == _userId;
  }

  bool _isPharmacyOpen(Map<String, dynamic> pharmacy) {
    final direct = _boolValue(
      pharmacy['isOpen'] ?? pharmacy['open'] ?? pharmacy['openNow'] ?? pharmacy['currentlyOpen'],
    );
    if (direct != null) return direct;
    if (_boolValue(pharmacy['open24h'] ?? pharmacy['alwaysOpen']) == true) return true;
    final status = _safeStr(pharmacy['status'] ?? pharmacy['badge']).toLowerCase();
    if (status.contains('ferme') || status.contains('closed')) return false;
    if (status.contains('ouvert') || status.contains('open') || status.contains('disponible')) return true;
    return true;
  }

  String _pharmacyStatusLabel(Map<String, dynamic> pharmacy) {
    if (_boolValue(pharmacy['open24h'] ?? pharmacy['alwaysOpen']) == true) return 'Ouvert 24/7';
    return _isPharmacyOpen(pharmacy) ? 'Ouvert' : 'Ferme';
  }

  bool _canDeletePharmacy(Map<String, dynamic> pharmacy) {
    final ownerId = _safeStr(pharmacy['ownerId'] ?? pharmacy['owner']);
    if (ownerId.isEmpty) return true; // legacy entries
    if (_userId == null) return false;
    return ownerId == _userId;
  }

  List<Map<String, dynamic>> _pharmacyCatalogFromData(Map<String, dynamic> pharmacy) {
    return _pharmacyCatalogFromRaw(
      pharmacy['medicineCatalog'] ??
          pharmacy['catalog'] ??
          pharmacy['inventory'] ??
          pharmacy['stock'] ??
          pharmacy['products'] ??
          pharmacy['medicines'] ??
          pharmacy['medications'] ??
          pharmacy['medicaments'],
    );
  }

  List<Map<String, dynamic>> _pharmacyCatalogFromRaw(dynamic raw) {
    if (raw == null) return const <Map<String, dynamic>>[];
    if (raw is List) {
      final out = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final name = _safeStr(map['name'] ?? map['medicament'] ?? map['label']);
          if (name.isEmpty) continue;
          out.add(
            <String, dynamic>{
              'name': name,
              'price': _toDouble(map['price']) ?? 0,
              'quantity': _toInt(map['quantity']) ?? _toInt(map['packQuantity']) ?? 0,
              'stock': _toInt(map['stock']) ?? 0,
              'form': _safeStr(map['form'] ?? map['forme']),
              'dosage': _safeStr(map['dosage'] ?? map['dose']),
              'therapeuticFamily': _safeStr(
                map['therapeuticFamily'] ?? map['family'] ?? map['familleTherapeutique'],
              ),
              'expiryDate': _safeStr(
                map['expiryDate'] ?? map['expiry'] ?? map['expiration'] ?? map['peremption'],
              ),
              'image': _safeStr(
                map['image'] ?? map['photo'] ?? map['photoUrl'] ?? map['imageUrl'],
              ),
            },
          );
        } else {
          final name = _safeStr(item);
          if (name.isEmpty) continue;
          out.add(
            <String, dynamic>{
              'name': name,
              'price': 0,
              'quantity': 0,
              'stock': 0,
              'form': '',
              'dosage': '',
              'therapeuticFamily': '',
              'expiryDate': '',
              'image': '',
            },
          );
        }
      }
      return out;
    }
    if (raw is Map) {
      return _pharmacyCatalogFromRaw(<dynamic>[raw]);
    }
    final s = _safeStr(raw);
    if (s.isEmpty) return const <Map<String, dynamic>>[];
    if (s.contains(',')) {
      return s
          .split(',')
          .map((item) => _safeStr(item))
          .where((item) => item.isNotEmpty)
          .map(
            (item) => <String, dynamic>{
              'name': item,
              'price': 0,
              'quantity': 0,
              'stock': 0,
              'form': '',
              'dosage': '',
              'therapeuticFamily': '',
              'expiryDate': '',
              'image': '',
            },
          )
          .toList(growable: false);
    }
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'name': s,
        'price': 0,
        'quantity': 0,
        'stock': 0,
        'form': '',
        'dosage': '',
        'therapeuticFamily': '',
        'expiryDate': '',
        'image': '',
      },
    ];
  }

  List<Map<String, dynamic>> _normalizePharmacyCatalog(List<Map<String, dynamic>> catalog) {
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final medicine in catalog) {
      final name = _safeStr(medicine['name']);
      if (name.isEmpty) continue;
      final normalized = <String, dynamic>{
        'name': name,
        'price': _toDouble(medicine['price']) ?? 0,
        'quantity': _toInt(medicine['quantity']) ?? 0,
        'stock': _toInt(medicine['stock']) ?? 0,
        'form': _safeStr(medicine['form']),
        'dosage': _safeStr(medicine['dosage']),
        'therapeuticFamily': _safeStr(medicine['therapeuticFamily']),
        'expiryDate': _safeStr(medicine['expiryDate']),
        'image': _safeStr(medicine['image']),
      };
      final key = '${name.toLowerCase()}|${_safeStr(normalized['dosage']).toLowerCase()}|'
          '${_safeStr(normalized['form']).toLowerCase()}';
      if (seen.add(key)) out.add(normalized);
    }
    return out;
  }

  List<String> _pharmacyCatalogMedicineNames(List<Map<String, dynamic>> catalog) {
    final out = <String>[];
    final seen = <String>{};
    for (final medicine in catalog) {
      final name = _safeStr(medicine['name']);
      final key = name.toLowerCase();
      if (name.isEmpty || !seen.add(key)) continue;
      out.add(name);
    }
    return out;
  }

  int _pharmacyTotalStock(List<Map<String, dynamic>> catalog) {
    var total = 0;
    for (final medicine in catalog) {
      total += _toInt(medicine['stock']) ?? 0;
    }
    return total;
  }

  int _pharmacyLowStockCount(List<Map<String, dynamic>> catalog) {
    var total = 0;
    for (final medicine in catalog) {
      final stock = _toInt(medicine['stock']) ?? 0;
      if (stock <= 5) total += 1;
    }
    return total;
  }

  DateTime? _pharmacyMedicineExpiryDate(Map<String, dynamic> medicine) {
    final raw = _safeStr(medicine['expiryDate']);
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
    for (final pattern in const <String>[
      'dd/MM/yyyy',
      'd/M/yyyy',
      'dd-MM-yyyy',
      'd-M-yyyy',
      'dd.MM.yyyy',
      'd.MM.yyyy',
    ]) {
      try {
        return DateFormat(pattern).parseStrict(raw);
      } catch (_) {}
    }
    return null;
  }

  int _pharmacyExpiringCount(List<Map<String, dynamic>> catalog) {
    var total = 0;
    final now = DateTime.now();
    for (final medicine in catalog) {
      final expiry = _pharmacyMedicineExpiryDate(medicine);
      if (expiry == null) continue;
      if (!expiry.isBefore(now) && expiry.difference(now).inDays <= 45) {
        total += 1;
      }
    }
    return total;
  }

  bool _pharmacyHasContact(Map<String, dynamic> pharmacy) {
    return _safeStr(pharmacy['phone'] ?? pharmacy['telephone']).isNotEmpty ||
        _safeStr(pharmacy['email']).isNotEmpty;
  }

  bool _pharmacyHasCoordinates(Map<String, dynamic> pharmacy) {
    return _toDouble(pharmacy['lat'] ?? pharmacy['latitude']) != null &&
        _toDouble(pharmacy['lng'] ?? pharmacy['longitude']) != null;
  }

  int _pharmacyProfileGapCount(Map<String, dynamic> pharmacy) {
    final catalog = _pharmacyCatalogFromData(pharmacy);
    var gaps = 0;
    if (!_pharmacyHasContact(pharmacy)) gaps += 1;
    if (!_pharmacyHasCoordinates(pharmacy)) gaps += 1;
    if (catalog.isEmpty) gaps += 1;
    if (_safeStr(pharmacy['photo'] ?? pharmacy['image'] ?? pharmacy['photoUrl']).isEmpty) gaps += 1;
    return gaps;
  }

  String _pharmacyProfileGapSummary(Map<String, dynamic> pharmacy) {
    final parts = <String>[];
    final catalog = _pharmacyCatalogFromData(pharmacy);
    if (!_pharmacyHasContact(pharmacy)) parts.add('ajouter un contact');
    if (!_pharmacyHasCoordinates(pharmacy)) parts.add('ajouter la position GPS');
    if (catalog.isEmpty) parts.add('renseigner le stock');
    if (_safeStr(pharmacy['photo'] ?? pharmacy['image'] ?? pharmacy['photoUrl']).isEmpty) {
      parts.add('ajouter une photo');
    }
    if (parts.isEmpty) return 'fiche complete';
    return parts.join(' / ');
  }

  int _pharmacyAttentionScore(Map<String, dynamic> pharmacy) {
    final catalog = _pharmacyCatalogFromData(pharmacy);
    final lowStock = _pharmacyLowStockCount(catalog);
    final expiring = _pharmacyExpiringCount(catalog);
    final profileGaps = _pharmacyProfileGapCount(pharmacy);
    var score = 0;
    if (catalog.isEmpty) score += 4;
    score += lowStock > 0 ? lowStock * 2 : 0;
    score += expiring > 0 ? expiring * 2 : 0;
    score += profileGaps;
    if (!_isPharmacyOpen(pharmacy)) score += 1;
    return score;
  }

  Color _pharmacyAttentionTone(Map<String, dynamic> pharmacy, Color accent) {
    final score = _pharmacyAttentionScore(pharmacy);
    if (score >= 6) return Colors.redAccent;
    if (score >= 3) return const Color(0xFFFF8A1F);
    return accent;
  }

  String _pharmacyManagementMessage(Map<String, dynamic> pharmacy) {
    final catalog = _pharmacyCatalogFromData(pharmacy);
    final lowStock = _pharmacyLowStockCount(catalog);
    final expiring = _pharmacyExpiringCount(catalog);
    final gapCount = _pharmacyProfileGapCount(pharmacy);
    final parts = <String>[];
    if (lowStock > 0) parts.add('$lowStock produit(s) en stock bas');
    if (expiring > 0) parts.add('$expiring produit(s) a verifier avant peremption');
    if (gapCount > 0) parts.add(_pharmacyProfileGapSummary(pharmacy));
    if (!_isPharmacyOpen(pharmacy)) parts.add('pharmacie fermee');
    if (parts.isEmpty) return 'Stock stable et fiche complete.';
    return parts.join(' / ');
  }

  int _comparePharmacyDashboardPriority(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final aData = a.data();
    final bData = b.data();
    final aScore = _pharmacyAttentionScore(aData);
    final bScore = _pharmacyAttentionScore(bData);
    if (aScore != bScore) return bScore.compareTo(aScore);
    final aOpen = _isPharmacyOpen(aData);
    final bOpen = _isPharmacyOpen(bData);
    if (aOpen != bOpen) return aOpen ? -1 : 1;
    return _safeStr(aData['name']).compareTo(_safeStr(bData['name']));
  }

  String _pharmacyDashboardEmptyMessage({
    required bool managerMode,
    required bool canAdd,
    String query = '',
  }) {
    if (query.isNotEmpty) return 'Aucune pharmacie ne correspond a votre recherche.';
    if (managerMode && _pharmacyManagerScope == 'mine') {
      return 'Aucune pharmacie ne vous est rattachee pour le moment.';
    }
    if (managerMode && _pharmacyManagerScope == 'attention') {
      return 'Aucune pharmacie ne demande une action urgente pour le moment.';
    }
    return canAdd
        ? 'Ajoutez la premiere pharmacie pour commencer.'
        : 'Aucune pharmacie disponible pour le moment.';
  }

  Widget _buildPharmacyMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
    required Color text,
    required Color sub,
  }) {
    return SizedBox(
      width: 152,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withOpacity(0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                color: text,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: sub, fontWeight: FontWeight.w700, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Color _pharmacyMedicineStockColor(int stock, Color accent) {
    if (stock <= 0) return Colors.redAccent;
    if (stock <= 5) return const Color(0xFFFF8A1F);
    return accent;
  }

  Color _pharmacyMedicineExpiryColor(Map<String, dynamic> medicine, Color accent) {
    final expiry = _pharmacyMedicineExpiryDate(medicine);
    if (expiry == null) return accent;
    final now = DateTime.now();
    if (expiry.isBefore(now)) return Colors.redAccent;
    if (expiry.difference(now).inDays <= 45) return const Color(0xFFFF8A1F);
    return accent;
  }

  Widget _buildPharmacyDashboardContent({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
    required Color cardBg,
    required Color text,
    required Color sub,
    required Color accent,
    required bool canAdd,
    required bool managerMode,
  }) {
    final managerDocs = allDocs.where((doc) => _canDeletePharmacy(doc.data())).toList(growable: false);
    final attentionDocs = managerDocs
        .where((doc) => _pharmacyAttentionScore(doc.data()) > 0)
        .toList(growable: false)
      ..sort(_comparePharmacyDashboardPriority);

    final visibleProducts = docs.fold<int>(
      0,
      (sum, doc) => sum + _pharmacyCatalogFromData(doc.data()).length,
    );
    final visibleStock = docs.fold<int>(
      0,
      (sum, doc) => sum + _pharmacyTotalStock(_pharmacyCatalogFromData(doc.data())),
    );
    final visibleOpen = docs.where((doc) => _isPharmacyOpen(doc.data())).length;
    final managedIncomplete = managerDocs.where((doc) => _pharmacyProfileGapCount(doc.data()) > 0).length;
    final managedClosed = managerDocs.where((doc) => !_isPharmacyOpen(doc.data())).length;
    final emptyMessage = _pharmacyDashboardEmptyMessage(
      managerMode: managerMode,
      canAdd: canAdd,
      query: _pharmacyQuery,
    );

    if (docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_pharmacy_outlined, color: accent),
              const SizedBox(height: 8),
              Text(
                'Aucune pharmacie',
                style: TextStyle(color: text, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: sub, height: 1.4),
              ),
              if (canAdd) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _addingPharmacy ? null : () => _openAddPharmacy(accent),
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Ajouter une pharmacie'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      children: [
        if (managerMode) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color.lerp(cardBg, accent, 0.05)!,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: accent.withOpacity(0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.dashboard_customize_outlined, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vue de gestion',
                            style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pilotez vos officines, vos stocks critiques et les fiches a completer.',
                            style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const <MapEntry<String, String>>[
                    MapEntry<String, String>('mine', 'Mes pharmacies'),
                    MapEntry<String, String>('attention', 'A traiter'),
                    MapEntry<String, String>('all', 'Toutes'),
                  ].map((item) {
                    final selected = _pharmacyManagerScope == item.key;
                    return ChoiceChip(
                      label: Text(item.value),
                      selected: selected,
                      showCheckmark: false,
                      backgroundColor: accent.withOpacity(0.06),
                      selectedColor: accent.withOpacity(0.18),
                      labelStyle: TextStyle(
                        color: selected ? accent : text,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => setState(() => _pharmacyManagerScope = item.key),
                    );
                  }).toList(growable: false),
                ),
              ],
            ),
          ),
          if (attentionDocs.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: accent.withOpacity(0.10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Priorites du jour',
                    style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Les pharmacies qui demandent le plus rapidement une action.',
                    style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  ...attentionDocs.take(3).map((doc) {
                    final pharmacy = doc.data();
                    final tone = _pharmacyAttentionTone(pharmacy, accent);
                    final lowStock = _pharmacyLowStockCount(_pharmacyCatalogFromData(pharmacy));
                    final expiring = _pharmacyExpiringCount(_pharmacyCatalogFromData(pharmacy));
                    final gaps = _pharmacyProfileGapCount(pharmacy);
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tone.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: tone.withOpacity(0.14)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _safeStr(pharmacy['name']).isNotEmpty
                                      ? _safeStr(pharmacy['name'])
                                      : 'Pharmacie',
                                  style: TextStyle(color: text, fontWeight: FontWeight.w900),
                                ),
                              ),
                              _buildHospitalInfoChip(
                                label: '${_pharmacyAttentionScore(pharmacy)} pts',
                                color: tone,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _pharmacyManagementMessage(pharmacy),
                            style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (lowStock > 0)
                                _buildHospitalInfoChip(
                                  label: '$lowStock stock bas',
                                  color: const Color(0xFFFF8A1F),
                                ),
                              if (expiring > 0)
                                _buildHospitalInfoChip(
                                  label: '$expiring peremption',
                                  color: Colors.redAccent,
                                ),
                              if (gaps > 0)
                                _buildHospitalInfoChip(
                                  label: '$gaps point(s) a completer',
                                  color: accent,
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _openPharmacyInventoryManager(
                                  accent: accent,
                                  reference: doc.reference,
                                  pharmacy: pharmacy,
                                ),
                                icon: const Icon(Icons.inventory_2_outlined),
                                label: const Text('Gerer'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _openAddPharmacy(
                                  accent,
                                  reference: doc.reference,
                                  existing: pharmacy,
                                ),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Modifier'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withOpacity(0.14),
                accent.withOpacity(0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withOpacity(0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                managerMode ? 'Console pharmacien' : 'Pilotage du stock pharmacie',
                style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                managerMode
                    ? 'Suivi des sites, des produits, des urgences et des fiches a completer.'
                    : 'Vue rapide des pharmacies disponibles et des stocks publies.',
                style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: managerMode
                    ? [
                        _buildPharmacyMetricTile(
                          icon: Icons.storefront_outlined,
                          label: 'Mes sites',
                          value: '${managerDocs.length}',
                          accent: accent,
                          text: text,
                          sub: sub,
                        ),
                        _buildPharmacyMetricTile(
                          icon: Icons.medication_outlined,
                          label: 'Produits',
                          value: '$visibleProducts',
                          accent: accent,
                          text: text,
                          sub: sub,
                        ),
                        _buildPharmacyMetricTile(
                          icon: Icons.inventory_outlined,
                          label: 'Stock total',
                          value: '$visibleStock',
                          accent: accent,
                          text: text,
                          sub: sub,
                        ),
                        _buildPharmacyMetricTile(
                          icon: Icons.warning_amber_rounded,
                          label: 'Urgences',
                          value: '${attentionDocs.length}',
                          accent: const Color(0xFFFF8A1F),
                          text: text,
                          sub: sub,
                        ),
                        _buildPharmacyMetricTile(
                          icon: Icons.fact_check_outlined,
                          label: 'Fiches a completer',
                          value: '$managedIncomplete',
                          accent: accent,
                          text: text,
                          sub: sub,
                        ),
                        _buildPharmacyMetricTile(
                          icon: Icons.pause_circle_outline,
                          label: 'Fermees',
                          value: '$managedClosed',
                          accent: Colors.redAccent,
                          text: text,
                          sub: sub,
                        ),
                      ]
                    : [
                        _buildPharmacyMetricTile(
                          icon: Icons.storefront_outlined,
                          label: 'Pharmacies visibles',
                          value: '${docs.length}',
                          accent: accent,
                          text: text,
                          sub: sub,
                        ),
                        _buildPharmacyMetricTile(
                          icon: Icons.medication_outlined,
                          label: 'Produits',
                          value: '$visibleProducts',
                          accent: accent,
                          text: text,
                          sub: sub,
                        ),
                        _buildPharmacyMetricTile(
                          icon: Icons.inventory_outlined,
                          label: 'Stock total',
                          value: '$visibleStock',
                          accent: accent,
                          text: text,
                          sub: sub,
                        ),
                        _buildPharmacyMetricTile(
                          icon: Icons.check_circle_outline,
                          label: 'Ouvertes',
                          value: '$visibleOpen',
                          accent: Colors.green,
                          text: text,
                          sub: sub,
                        ),
                      ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          managerMode
              ? '${docs.length} pharmacie(s) visible(s) / ${attentionDocs.length} a traiter / $visibleOpen ouverte(s)'
              : '${docs.length} pharmacie(s) visible(s) / $visibleProducts produit(s) / $visibleOpen ouverte(s)',
          style: TextStyle(color: sub, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...docs.map(
          (doc) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildPharmacyDashboardCard(
              doc: doc,
              cardBg: cardBg,
              text: text,
              sub: sub,
              accent: accent,
              canManage: managerMode,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPharmacyDashboardCard({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required Color cardBg,
    required Color text,
    required Color sub,
    required Color accent,
    required bool canManage,
  }) {
    final pharmacy = doc.data();
    final name = _safeStr(pharmacy['name']).isNotEmpty ? _safeStr(pharmacy['name']) : 'Pharmacie';
    final address = _safeStr(pharmacy['address'] ?? pharmacy['adresse']);
    final location = _safeStr(pharmacy['location'] ?? pharmacy['localisation']);
    final place = _joinParts([address, location]);
    final image = _safeStr(pharmacy['photo'] ?? pharmacy['image'] ?? pharmacy['photoUrl']);
    final phone = _safeStr(pharmacy['phone'] ?? pharmacy['telephone']);
    final email = _safeStr(pharmacy['email']);
    final lat = _toDouble(pharmacy['lat'] ?? pharmacy['latitude']);
    final lng = _toDouble(pharmacy['lng'] ?? pharmacy['longitude']);
    final catalog = _pharmacyCatalogFromData(pharmacy);
    final totalStock = _pharmacyTotalStock(catalog);
    final lowStock = _pharmacyLowStockCount(catalog);
    final expiring = _pharmacyExpiringCount(catalog);
    final profileGapCount = _pharmacyProfileGapCount(pharmacy);
    final isOpen = _isPharmacyOpen(pharmacy);
    final statusLabel = _pharmacyStatusLabel(pharmacy);
    final distanceLabel = _distanceLabel(pharmacy);
    final allowManage = canManage && _canDeletePharmacy(pharmacy);
    final managementTone = _pharmacyAttentionTone(pharmacy, accent);
    final managementMessage = _pharmacyManagementMessage(pharmacy);
    final open24h = _boolValue(pharmacy['open24h'] ?? pharmacy['alwaysOpen']) == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withOpacity(0.10),
            cardBg,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: image.isNotEmpty
                    ? Image.network(image, width: 72, height: 72, fit: BoxFit.cover)
                    : Container(
                        width: 72,
                        height: 72,
                        color: accent.withOpacity(0.12),
                        child: Icon(Icons.local_pharmacy_outlined, color: accent),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 17),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: (isOpen ? Colors.green : Colors.redAccent).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: isOpen ? Colors.green.shade700 : Colors.redAccent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      place.isNotEmpty ? place : 'Adresse non renseignee',
                      style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (allowManage)
                          _buildHospitalInfoChip(label: 'Gestion', color: accent),
                        _buildHospitalInfoChip(
                          label: '${catalog.length} produit(s)',
                          color: accent,
                        ),
                        _buildHospitalInfoChip(
                          label: 'Stock total $totalStock',
                          color: _pharmacyMedicineStockColor(totalStock, accent),
                        ),
                        if (distanceLabel.isNotEmpty)
                          _buildHospitalInfoChip(label: distanceLabel, color: accent),
                        if (lowStock > 0)
                          _buildHospitalInfoChip(
                            label: '$lowStock stock bas',
                            color: const Color(0xFFFF8A1F),
                          ),
                        if (expiring > 0)
                          _buildHospitalInfoChip(
                            label: '$expiring peremption',
                            color: Colors.redAccent,
                          ),
                        if (profileGapCount > 0)
                          _buildHospitalInfoChip(
                            label: '$profileGapCount element(s) a completer',
                            color: accent,
                          ),
                        if (open24h)
                          _buildHospitalInfoChip(label: '24/7', color: Colors.green),
                        if (!_pharmacyHasContact(pharmacy))
                          _buildHospitalInfoChip(label: 'Sans contact', color: Colors.blueGrey),
                        if (!_pharmacyHasCoordinates(pharmacy))
                          _buildHospitalInfoChip(label: 'Sans GPS', color: Colors.blueGrey),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: managementTone.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: managementTone.withOpacity(0.12)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tips_and_updates_outlined, color: managementTone),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    managementMessage,
                    style: TextStyle(
                      color: text,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (allowManage)
                OutlinedButton.icon(
                  onPressed: () => _openPharmacyInventoryManager(
                    accent: accent,
                    reference: doc.reference,
                    pharmacy: pharmacy,
                  ),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Produits'),
                ),
              if (allowManage)
                OutlinedButton.icon(
                  onPressed: () => _openAddPharmacy(
                    accent,
                    reference: doc.reference,
                    existing: pharmacy,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
                ),
              if (allowManage)
                OutlinedButton.icon(
                  onPressed: () => _updatePharmacyOpenStatus(
                    doc.reference,
                    pharmacy,
                    open: !isOpen,
                  ),
                  icon: Icon(
                    isOpen ? Icons.pause_circle_outline : Icons.play_circle_outline,
                  ),
                  label: Text(isOpen ? 'Fermer' : 'Ouvrir'),
                ),
              if (phone.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _launchOrSnack(Uri.parse('tel:${phone.trim()}')),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Appeler'),
                ),
              if (email.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _launchOrSnack(Uri.parse('mailto:${email.trim()}')),
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Email'),
                ),
              OutlinedButton.icon(
                onPressed: () => _openMapLocation(
                  lat: lat,
                  lng: lng,
                  label: _joinParts([name, address, location]),
                ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Carte'),
              ),
              if (allowManage)
                OutlinedButton.icon(
                  onPressed: () => _confirmDeletePharmacy(doc.reference),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeletePharmacy(DocumentReference<Map<String, dynamic>> ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Supprimer la pharmacie'),
          content: const Text('Cette action est irreversible.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await ref.delete();
      await _refreshHealthNotificationsIfAvailable();
      _snack('Pharmacie supprimee');
    } catch (e) {
      _snack('Erreur suppression: $e', error: true);
    }
  }

  Future<void> _updatePharmacyOpenStatus(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> pharmacy, {
    required bool open,
  }) async {
    try {
      await ref.set(
        {
          'isOpen': open,
          'status': open
              ? (_boolValue(pharmacy['open24h'] ?? pharmacy['alwaysOpen']) == true ? 'Ouvert 24/7' : 'Ouvert')
              : 'Ferme',
          'open24h': open ? (_boolValue(pharmacy['open24h'] ?? pharmacy['alwaysOpen']) == true) : false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _snack(open ? 'Pharmacie marquee ouverte' : 'Pharmacie marquee fermee');
    } catch (e) {
      _snack('Erreur changement statut pharmacie: $e', error: true);
    }
  }

  Future<void> _confirmDeleteHospital(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Supprimer l hopital'),
          content: const Text('Cette action est irreversible.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance.collection('health_hospitals').doc(docId).delete();
      _snack('Hopital supprime');
    } catch (e) {
      _snack('Erreur suppression: $e', error: true);
    }
  }

  Future<void> _updateHospitalOpenStatus(
    _HospitalDirectoryItem item, {
    required bool open,
  }) async {
    if (item.sourceId.isEmpty) {
      _snack('Impossible de modifier ce statut', error: true);
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('health_hospitals').doc(item.sourceId).set(
        {
          'isOpen': open,
          'status': open
              ? (item.isOpen24h ? 'Ouvert 24/7' : 'Ouvert')
              : 'Ferme',
          'open24h': open ? item.isOpen24h : false,
          'emergency24h': open ? item.isEmergency24h : false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _snack(open ? 'Hopital marque ouvert' : 'Hopital marque ferme');
    } catch (e) {
      _snack('Erreur changement statut: $e', error: true);
    }
  }

  String _distanceLabel(Map<String, dynamic> data) {
    return _distanceLabelFromCoordinates(
      _toDouble(data['lat'] ?? data['latitude']),
      _toDouble(data['lng'] ?? data['longitude']),
    );
  }

  Widget _buildHospitalInfoChip({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<void> _launchOrSnack(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        _snack('Impossible d ouvrir ce lien', error: true);
      }
    } catch (e) {
      _snack('Erreur ouverture: $e', error: true);
    }
  }

  Future<void> _openMapLocation({
    double? lat,
    double? lng,
    String label = '',
  }) async {
    Uri uri;
    if (lat != null && lng != null) {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else {
      final query = Uri.encodeComponent(label.trim());
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    }
    await _launchOrSnack(uri);
  }

  Future<void> _openHealthMenuSheet({
    required String title,
    required IconData icon,
    required List<String> bullets,
    required Color accent,
    String? primaryLabel,
    VoidCallback? onPrimaryAction,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF101622) : Colors.white;
        final text = isDark ? Colors.white : const Color(0xFF18202C);
        final sub = isDark ? Colors.white70 : const Color(0xFF687485);

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: accent.withOpacity(0.14)),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.10),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...bullets.map(
                  (bullet) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check_rounded, size: 13, color: accent),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            bullet,
                            style: TextStyle(
                              color: sub,
                              height: 1.42,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (primaryLabel != null && onPrimaryAction != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onPrimaryAction();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.arrow_outward_rounded),
                      label: Text(primaryLabel),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openHospitalActionSheet({
    required _HospitalDirectoryItem item,
    required Color accent,
    required HealthUserContext? userContext,
  }) async {
    final patientCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final doctorProfiles = item.doctorProfiles.isNotEmpty
        ? item.doctorProfiles
        : item.doctors
            .where((doctor) => doctor.trim().isNotEmpty)
            .map((doctor) => _HospitalDoctorProfile(name: doctor))
            .toList(growable: false);
    String? selectedDoctor = doctorProfiles.isNotEmpty ? doctorProfiles.first.displayLabel : null;
    String doctorQuery = '';
    DateTime requestedAt = DateTime.now().add(const Duration(days: 1));
    bool sending = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF111723) : Colors.white;
        final text = isDark ? Colors.white : const Color(0xFF18202C);
        final sub = isDark ? Colors.white70 : const Color(0xFF687485);

        Future<void> pickDate(StateSetter setModalState) async {
          final picked = await showDatePicker(
            context: ctx,
            initialDate: requestedAt,
            firstDate: DateTime.now().subtract(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (picked == null) return;
          setModalState(() {
            requestedAt = DateTime(
              picked.year,
              picked.month,
              picked.day,
              requestedAt.hour,
              requestedAt.minute,
            );
          });
        }

        Future<void> pickTime(StateSetter setModalState) async {
          final picked = await showTimePicker(
            context: ctx,
            initialTime: TimeOfDay.fromDateTime(requestedAt),
          );
          if (picked == null) return;
          setModalState(() {
            requestedAt = DateTime(
              requestedAt.year,
              requestedAt.month,
              requestedAt.day,
              picked.hour,
              picked.minute,
            );
          });
        }

        Future<void> submit(StateSetter setModalState) async {
          final patientName = patientCtrl.text.trim();
          final patientPhone = phoneCtrl.text.trim();
          final reason = reasonCtrl.text.trim();
          if (patientName.isEmpty) {
            _snack('Le nom du patient est obligatoire', error: true);
            return;
          }
          if (reason.isEmpty) {
            _snack('Indiquez le motif du rendez-vous', error: true);
            return;
          }
          if (userContext == null) {
            _snack('Connectez votre profil sante pour envoyer une demande', error: true);
            return;
          }

          setModalState(() => sending = true);
          final payload = <String, dynamic>{
            'patientName': patientName,
            'phone': patientPhone,
            'doctor': selectedDoctor ?? '',
            'hospital': item.name,
            'hospitalId': item.sourceId,
            'hospitalOwnerId': item.ownerId,
            'hospitalLocation': item.location,
            'reason': reason,
            'notes': notesCtrl.text.trim(),
            'status': 'requested',
            'channel': 'hospital_sheet',
            'dateTime': Timestamp.fromDate(requestedAt),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };

          try {
            await userContext.subCollection('health_appointments').add(payload);
            await FirebaseFirestore.instance.collection('health_hospital_requests').add({
              ...payload,
              'requesterId': userContext.userId,
              'requesterCollection': userContext.userCollection,
            });
            final when =
                '${DateFormat('dd/MM/yyyy').format(requestedAt)} ${DateFormat('HH:mm').format(requestedAt)}';
            final summary = _joinParts([when, selectedDoctor ?? '', item.name, reason]);
            await userContext.userRef.set(
              {
                'health.appointments': FieldValue.arrayUnion([summary]),
              },
              SetOptions(merge: true),
            );
            await HealthNotificationScheduler.refreshForUser(userContext);
            if (ctx.mounted) Navigator.of(ctx).pop();
            _snack('Demande de rendez-vous envoyee');
          } catch (e) {
            setModalState(() => sending = false);
            _snack('Erreur envoi rendez-vous: $e', error: true);
          }
        }

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final canRequest = userContext != null;
            final canManage = item.sourceId.isNotEmpty && _canDeleteHospital(item);
            final statusLabel = _hospitalStatusLabel(item);
            final statusColor = item.isOpen || item.isOpen24h ? Colors.green : Colors.redAccent;
            final filteredDoctors = doctorQuery.isEmpty
                ? doctorProfiles
                : doctorProfiles
                    .where((doctor) => doctor.searchText.contains(doctorQuery))
                    .toList(growable: false);

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.92),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: accent.withOpacity(0.14)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: item.image.isNotEmpty
                                ? Image.network(item.image, width: 72, height: 72, fit: BoxFit.cover)
                                : Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: accent.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Icon(Icons.local_hospital_outlined, color: accent, size: 34),
                                  ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: TextStyle(
                                    color: text,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item.location,
                                  style: TextStyle(
                                    color: sub,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                                ),
                                if (item.note.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    item.note,
                                    style: TextStyle(
                                      color: sub,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildHospitalInfoChip(
                            label: statusLabel,
                            color: statusColor,
                          ),
                          if (item.isEmergency24h)
                            _buildHospitalInfoChip(
                              label: 'Urgence 24/7',
                              color: Colors.redAccent,
                            ),
                          if (item.badge.isNotEmpty)
                            _buildHospitalInfoChip(
                              label: item.badge,
                              color: accent,
                            ),
                          if (item.phone.isNotEmpty)
                            _buildHospitalInfoChip(
                              label: item.phone,
                              color: Colors.green,
                            ),
                        ],
                      ),
                      if (canManage) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: accent.withOpacity(0.10)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gestion proprietaire',
                                style: TextStyle(
                                  color: text,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Mettez a jour la fiche, fermez ou rouvrez l hopital et supprimez la publication si necessaire.',
                                style: TextStyle(
                                  color: sub,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      Future<void>.delayed(
                                        const Duration(milliseconds: 120),
                                        () => _openAddHospital(accent, existing: item),
                                      );
                                    },
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Modifier'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      Future<void>.delayed(
                                        const Duration(milliseconds: 120),
                                        () => _updateHospitalOpenStatus(item, open: !item.isOpen),
                                      );
                                    },
                                    icon: Icon(
                                      item.isOpen ? Icons.pause_circle_outline : Icons.play_circle_outline,
                                    ),
                                    label: Text(
                                      item.isOpen ? 'Fermer l hopital' : 'Ouvrir l hopital',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      Future<void>.delayed(
                                        const Duration(milliseconds: 120),
                                        () => _confirmDeleteHospital(item.sourceId),
                                      );
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.redAccent,
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Supprimer'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (item.services.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(
                          'Services disponibles',
                          style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: item.services
                              .map((service) => _buildHospitalInfoChip(label: service, color: accent))
                              .toList(growable: false),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        'Medecins disponibles',
                        style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      if (doctorProfiles.isNotEmpty) ...[
                        TextField(
                          onChanged: (value) {
                            setModalState(() => doctorQuery = value.trim().toLowerCase());
                          },
                          style: TextStyle(color: text, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.search, color: accent),
                            hintText: 'Rechercher un medecin, un service ou un numero',
                            hintStyle: TextStyle(color: sub),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (doctorProfiles.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: accent.withOpacity(0.10)),
                          ),
                          child: Text(
                            'La liste des medecins n a pas encore ete publiee pour cet hopital.',
                            style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
                          ),
                        )
                      else if (filteredDoctors.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: accent.withOpacity(0.10)),
                          ),
                          child: Text(
                            'Aucun medecin ne correspond a votre recherche.',
                            style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
                          ),
                        )
                      else
                        Column(
                          children: filteredDoctors.map((doctor) {
                            final showPhoto = !doctor.hidePhoto && doctor.photo.isNotEmpty;
                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: accent.withOpacity(0.10)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: showPhoto
                                            ? Image.network(
                                                doctor.photo,
                                                width: 58,
                                                height: 58,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                width: 58,
                                                height: 58,
                                                decoration: BoxDecoration(
                                                  color: accent.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                                child: Icon(
                                                  doctor.hidePhoto
                                                      ? Icons.visibility_off_outlined
                                                      : Icons.medical_services_outlined,
                                                  color: accent,
                                                ),
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              doctor.name,
                                              style: TextStyle(
                                                color: text,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 15,
                                              ),
                                            ),
                                            if (doctor.service.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                doctor.service,
                                                style: TextStyle(
                                                  color: sub,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (doctor.service.isNotEmpty)
                                        _buildHospitalInfoChip(
                                          label: doctor.service,
                                          color: accent,
                                        ),
                                      if (doctor.phone.isNotEmpty)
                                        _buildHospitalInfoChip(
                                          label: doctor.phone,
                                          color: Colors.green,
                                        ),
                                      if (doctor.hidePhoto)
                                        _buildHospitalInfoChip(
                                          label: 'Photo masquee',
                                          color: Colors.blueGrey,
                                        ),
                                    ],
                                  ),
                                  if (doctor.phone.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: () => _launchOrSnack(
                                        Uri.parse('tel:${doctor.phone.trim()}'),
                                      ),
                                      icon: const Icon(Icons.call_outlined),
                                      label: const Text('Contacter ce medecin'),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(growable: false),
                        ),
                      const SizedBox(height: 18),
                      Text(
                        'Contacter l hopital',
                        style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (item.phone.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _launchOrSnack(Uri.parse('tel:${item.phone.trim()}')),
                              icon: const Icon(Icons.call_outlined),
                              label: const Text('Appeler'),
                            ),
                          if (item.email.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _launchOrSnack(Uri.parse('mailto:${item.email.trim()}')),
                              icon: const Icon(Icons.mail_outline),
                              label: const Text('Email'),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => _openMapLocation(
                              lat: item.lat,
                              lng: item.lng,
                              label: _joinParts([item.name, item.location]),
                            ),
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('Localiser'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accent.withOpacity(0.16),
                              accent.withOpacity(0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: accent.withOpacity(0.12)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Demander un rendez-vous',
                              style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 17),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              canRequest
                                  ? 'Choisissez un medecin, precisez votre besoin et envoyez la demande en quelques secondes.'
                                  : 'Connectez votre profil sante pour envoyer une demande de rendez-vous.',
                              style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: patientCtrl,
                              style: TextStyle(color: text, fontWeight: FontWeight.w600),
                              decoration: const InputDecoration(labelText: 'Nom du patient'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: TextStyle(color: text, fontWeight: FontWeight.w600),
                              decoration: const InputDecoration(labelText: 'Telephone'),
                            ),
                            if (doctorProfiles.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: selectedDoctor,
                                decoration: const InputDecoration(labelText: 'Medecin souhaite'),
                                items: doctorProfiles
                                    .map(
                                      (doctor) => DropdownMenuItem<String>(
                                        value: doctor.displayLabel,
                                        child: Text(doctor.displayLabel),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) => setModalState(() => selectedDoctor = value),
                              ),
                            ],
                            const SizedBox(height: 10),
                            TextField(
                              controller: reasonCtrl,
                              style: TextStyle(color: text, fontWeight: FontWeight.w600),
                              decoration: const InputDecoration(labelText: 'Motif du rendez-vous'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: notesCtrl,
                              minLines: 2,
                              maxLines: 4,
                              style: TextStyle(color: text, fontWeight: FontWeight.w600),
                              decoration: const InputDecoration(labelText: 'Notes complementaires'),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => pickDate(setModalState),
                                    icon: const Icon(Icons.calendar_month_outlined),
                                    label: Text(DateFormat('dd/MM/yyyy').format(requestedAt)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => pickTime(setModalState),
                                    icon: const Icon(Icons.schedule_outlined),
                                    label: Text(DateFormat('HH:mm').format(requestedAt)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: sending ? null : () => submit(setModalState),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                icon: sending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.send_outlined),
                                label: Text(sending ? 'Envoi...' : 'Envoyer la demande'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color.lerp(cardBg, accent, 0.06)!,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: accent.withOpacity(0.10)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: accent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(Icons.video_call_outlined, color: accent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Teleconsultation',
                                        style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Passez rapidement vers un parcours video pour echanger avec un professionnel de sante.',
                                        style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: userContext == null
                                    ? null
                                    : () {
                                        Navigator.of(ctx).pop();
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => HealthTeleconsultationPage(contextRef: userContext),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.videocam_outlined),
                                label: const Text('Lancer une teleconsultation'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    patientCtrl.dispose();
    phoneCtrl.dispose();
    reasonCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _openPharmacyMedicinesSheet({
    required String name,
    required String place,
    required List<String> medicines,
    required Color accent,
  }) async {
    final searchCtrl = TextEditingController();
    String query = '';
    String filter = 'all';

    bool matchesFilter(String medicine) {
      if (medicine.isEmpty) return false;
      final first = medicine.toLowerCase().codeUnitAt(0);
      switch (filter) {
        case 'a-m':
          return first >= 97 && first <= 109;
        case 'n-z':
          return first >= 110 && first <= 122;
        case '0-9':
          return first >= 48 && first <= 57;
        case 'all':
        default:
          return true;
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF16120B) : Colors.white;
        final text = isDark ? Colors.white : const Color(0xFF23160A);
        final sub = isDark ? Colors.white70 : const Color(0xFF6F5843);

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = medicines
                .where((medicine) {
                  final lower = medicine.toLowerCase();
                  return (query.isEmpty || lower.contains(query)) && matchesFilter(lower);
                })
                .toList(growable: false);

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: accent.withOpacity(0.16)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.10),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.local_pharmacy_outlined, color: accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  color: text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                place.isNotEmpty ? place : 'Localisation non renseignee',
                                style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: searchCtrl,
                      style: TextStyle(color: text, fontWeight: FontWeight.w600),
                      onChanged: (value) => setModalState(() => query = value.trim().toLowerCase()),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search, color: accent),
                        hintText: 'Rechercher un medicament',
                        hintStyle: TextStyle(color: sub),
                        filled: true,
                        fillColor: accent.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: accent.withOpacity(0.10)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: accent.withOpacity(0.10)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: accent.withOpacity(0.30)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const <MapEntry<String, String>>[
                        MapEntry<String, String>('all', 'Tout'),
                        MapEntry<String, String>('a-m', 'A-M'),
                        MapEntry<String, String>('n-z', 'N-Z'),
                        MapEntry<String, String>('0-9', '0-9'),
                      ].map((item) {
                        final isSelected = filter == item.key;
                        return ChoiceChip(
                          label: Text(item.value),
                          selected: isSelected,
                          showCheckmark: false,
                          backgroundColor: accent.withOpacity(0.06),
                          selectedColor: accent.withOpacity(0.16),
                          labelStyle: TextStyle(
                            color: isSelected ? accent : text,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (_) => setModalState(() => filter = item.key),
                        );
                      }).toList(growable: false),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${filtered.length} medicament(s) visible(s)',
                      style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 320,
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                medicines.isEmpty
                                    ? 'Aucun medicament n est renseigne pour cette pharmacie.'
                                    : 'Aucun medicament ne correspond a votre recherche.',
                                style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => Divider(color: accent.withOpacity(0.10)),
                              itemBuilder: (ctx, index) {
                                final medicine = filtered[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: accent.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.medication_outlined, color: accent, size: 18),
                                  ),
                                  title: Text(
                                    medicine,
                                    style: TextStyle(color: text, fontWeight: FontWeight.w800),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    searchCtrl.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : Colors.black87,
      ),
    );
  }

  Future<_PhotoPickResult> _pickAndUploadHealthPhoto({
    required String bucket,
    required String objectFolder,
    required String fallbackPrefix,
  }) async {
    if (!SupabaseService.isInitialized) {
      _snack('Supabase non initialise', error: true);
      return const _PhotoPickResult(url: '');
    }
    try {
      await SupabaseService.ensureAuthenticated();
      final storageUserId = SupabaseService.client.auth.currentUser?.id.trim() ?? '';
      if (storageUserId.isEmpty) {
        _snack(
          'Session Supabase absente. Activez Anonymous Sign-In ou reconnectez Supabase.',
          error: true,
        );
        return const _PhotoPickResult(url: '');
      }
      String name = '';
      Uint8List bytes = Uint8List(0);
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (result == null || result.files.isEmpty) return const _PhotoPickResult(url: '');
        final file = result.files.first;
        if (file.bytes == null || file.bytes!.isEmpty) return const _PhotoPickResult(url: '');
        name = file.name;
        bytes = file.bytes!;
      } else {
        final picked = await _imagePicker.pickImage(source: ImageSource.gallery, maxWidth: 1600);
        if (picked == null) return const _PhotoPickResult(url: '');
        bytes = await picked.readAsBytes();
        if (bytes.isEmpty) return const _PhotoPickResult(url: '');
        name = picked.name;
      }
      if (name.isEmpty) {
        name = '${fallbackPrefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }
      final objectPath =
          '$objectFolder/$storageUserId/${DateTime.now().millisecondsSinceEpoch}_$name';
      final url = await SupabaseService.uploadBytesNamed(
        bytes,
        objectPath,
        bucket,
        contentType: _imageContentType(name),
      );
      return _PhotoPickResult(url: url, bytes: bytes);
    } catch (e) {
      _snack('Erreur photo: $e', error: true);
      return const _PhotoPickResult(url: '');
    }
  }

  Future<_PhotoPickResult> _pickAndUploadPharmacyPhoto() {
    return _pickAndUploadHealthPhoto(
      bucket: 'health_pharmacies',
      objectFolder: 'health_pharmacies',
      fallbackPrefix: 'pharmacy',
    );
  }

  Future<_PhotoPickResult> _pickAndUploadHospitalPhoto({
    String scope = 'hospital',
  }) {
    return _pickAndUploadHealthPhoto(
      bucket: 'health_hospitals',
      objectFolder: 'health_hospitals/$scope',
      fallbackPrefix: scope,
    );
  }

  String _imageContentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  Future<void> _exportPharmaciesExcel() async {
    if (_exportingPharmacies) return;
    setState(() => _exportingPharmacies = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('health_pharmacies').get();
      final excel = xl.Excel.createExcel();
      final sheet = excel['Pharmacies'];
      sheet.appendRow([
        xl.TextCellValue('name'),
        xl.TextCellValue('address'),
        xl.TextCellValue('location'),
        xl.TextCellValue('lat'),
        xl.TextCellValue('lng'),
        xl.TextCellValue('medicines'),
        xl.TextCellValue('photo'),
      ]);
      for (final doc in snap.docs) {
        final data = doc.data();
        final meds = _stringList(data['medicines'] ?? data['medications'] ?? data['medicaments']).join(', ');
        sheet.appendRow([
          xl.TextCellValue(_safeStr(data['name'])),
          xl.TextCellValue(_safeStr(data['address'] ?? data['adresse'])),
          xl.TextCellValue(_safeStr(data['location'] ?? data['localisation'])),
          xl.TextCellValue(_safeStr(data['lat'] ?? data['latitude'])),
          xl.TextCellValue(_safeStr(data['lng'] ?? data['longitude'])),
          xl.TextCellValue(meds),
          xl.TextCellValue(_safeStr(data['photo'] ?? data['image'] ?? data['photoUrl'])),
        ]);
      }
      final bytes = excel.save();
      if (bytes == null) throw Exception('Export Excel vide');
      if (kIsWeb) {
        _snack('Export non disponible sur web', error: true);
        return;
      }
      final file = XFile.fromData(
        Uint8List.fromList(bytes),
        name: 'pharmacies_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      await Share.shareXFiles([file], text: 'Liste des pharmacies');
    } catch (e) {
      _snack('Erreur export: $e', error: true);
    } finally {
      if (mounted) setState(() => _exportingPharmacies = false);
    }
  }

  Future<void> _importPharmaciesExcel() async {
    if (_importingPharmacies) return;
    setState(() => _importingPharmacies = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('Fichier Excel illisible');

      final excel = xl.Excel.decodeBytes(bytes);
      final table = excel.tables.values.isNotEmpty ? excel.tables.values.first : null;
      if (table == null || table.rows.isEmpty) throw Exception('Feuille Excel vide');

      final headerRow = table.rows.first;
      final headerIndex = <String, int>{};
      for (var i = 0; i < headerRow.length; i++) {
        final key = _cellText(headerRow[i]).toLowerCase();
        if (key.isNotEmpty) headerIndex[key] = i;
      }

      int imported = 0;
      var batch = FirebaseFirestore.instance.batch();
      int batchCount = 0;
      for (var r = 1; r < table.rows.length; r++) {
        final row = table.rows[r];
        final name = _cellAt(row, headerIndex, 'name');
        if (name.isEmpty) continue;
        final address = _cellAt(row, headerIndex, 'address');
        final location = _cellAt(row, headerIndex, 'location');
        final lat = _toDouble(_cellAt(row, headerIndex, 'lat'));
        final lng = _toDouble(_cellAt(row, headerIndex, 'lng'));
        final medsRaw = _cellAt(row, headerIndex, 'medicines');
        final meds = medsRaw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final photo = _cellAt(row, headerIndex, 'photo');

        final ref = FirebaseFirestore.instance.collection('health_pharmacies').doc();
        batch.set(ref, {
          'name': name,
          'address': address,
          'location': location,
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
          if (photo.isNotEmpty) 'photo': photo,
          if (meds.isNotEmpty) 'medicines': meds,
          'createdAt': FieldValue.serverTimestamp(),
        });
        batchCount += 1;
        imported += 1;
        if (batchCount >= 400) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) await batch.commit();
      _snack('Import termine: $imported pharmacies');
    } catch (e) {
      _snack('Erreur import: $e', error: true);
    } finally {
      if (mounted) setState(() => _importingPharmacies = false);
    }
  }

  String _cellText(xl.Data? cell) {
    if (cell == null) return '';
    final v = cell.value;
    if (v == null) return '';
    return v.toString().trim();
  }

  String _cellAt(List<xl.Data?> row, Map<String, int> index, String key) {
    final i = index[key];
    if (i == null || i < 0 || i >= row.length) return '';
    return _cellText(row[i]);
  }

  String _radiusLabel(double radiusKm) => '${radiusKm.toStringAsFixed(0)} km';

  Future<void> _updateDistanceRadius({
    required double? radiusKm,
    required void Function(double? value) onApply,
  }) async {
    if (radiusKm != null) {
      final ok = await _ensureLocation();
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => onApply(radiusKm));
  }

  bool _matchesDistanceFilter({
    required double? lat,
    required double? lng,
    required double? radiusKm,
  }) {
    if (radiusKm == null) return true;
    final pos = _userPosition;
    if (pos == null || lat == null || lng == null) return false;
    final meters = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      lat,
      lng,
    );
    return meters <= radiusKm * 1000;
  }

  bool _matchesHospitalDirectoryMode(_HospitalDirectoryItem item, String mode) {
    switch (mode) {
      case 'emergency':
        return item.isEmergency24h;
      case 'open':
        return item.isOpen || item.isOpen24h;
      case 'mapped':
        return item.lat != null && item.lng != null;
      case 'contact':
        return item.phone.isNotEmpty || item.email.isNotEmpty;
      case 'all':
      default:
        return true;
    }
  }

  String _distanceLabelFromCoordinates(
    double? lat,
    double? lng, {
    bool enabled = true,
  }) {
    if (!enabled || _userPosition == null || lat == null || lng == null) return '';
    final meters = Geolocator.distanceBetween(
      _userPosition!.latitude,
      _userPosition!.longitude,
      lat,
      lng,
    );
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Widget _buildDistanceFilterWrap({
    required Color text,
    required Color sub,
    required Color accent,
    required double? selectedRadiusKm,
    required Future<void> Function(double? radiusKm) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Distance depuis ma position',
          style: TextStyle(
            color: text,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <double?>[null, ..._distanceRadiusOptionsKm].map((radiusKm) {
            final isSelected = selectedRadiusKm == radiusKm;
            final label = radiusKm == null ? 'Toutes' : _radiusLabel(radiusKm);
            return ChoiceChip(
              label: Text(label),
              selected: isSelected,
              showCheckmark: false,
              backgroundColor: accent.withOpacity(0.06),
              selectedColor: accent.withOpacity(0.18),
              labelStyle: TextStyle(
                color: isSelected ? accent : text,
                fontWeight: FontWeight.w700,
              ),
              onSelected: (_) async {
                await onSelected(radiusKm);
              },
            );
          }).toList(growable: false),
        ),
        if (selectedRadiusKm != null) ...[
          const SizedBox(height: 6),
          Text(
            'Les resultats sans coordonnees ne sont pas inclus dans ce filtre.',
            style: TextStyle(
              color: sub,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Future<bool> _ensureLocation() async {
    if (_locBusy) return false;
    setState(() => _locBusy = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _snack('GPS desactive', error: true);
        return false;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _snack('Permission GPS refusee', error: true);
        return false;
      }
      _userPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      return true;
    } catch (_) {
      _snack('Erreur GPS', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _locBusy = false);
    }
  }

  Future<void> _openAddHospital(
    Color accent, {
    _HospitalDirectoryItem? existing,
  }) async {
    if (_addingHospital) return;
    setState(() => _addingHospital = true);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final addressCtrl = TextEditingController();
    final locationCtrl = TextEditingController(text: existing?.location ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    final badgeCtrl = TextEditingController(text: existing?.badge ?? '');
    final photoCtrl = TextEditingController(text: existing?.image ?? '');
    final latCtrl = TextEditingController(text: existing?.lat?.toString() ?? '');
    final lngCtrl = TextEditingController(text: existing?.lng?.toString() ?? '');
    final serviceCtrl = TextEditingController();
    final doctorNameCtrl = TextEditingController();
    final doctorServiceCtrl = TextEditingController();
    final doctorPhoneCtrl = TextEditingController();
    final doctorPhotoCtrl = TextEditingController();
    final services = <String>[...(existing?.services ?? const <String>[])];
    final doctors = <_HospitalDoctorProfile>[
      ...(existing?.doctorProfiles.isNotEmpty == true
          ? existing!.doctorProfiles
          : (existing?.doctors ?? const <String>[])
              .where((doctor) => doctor.trim().isNotEmpty)
              .map((doctor) => _HospitalDoctorProfile(name: doctor))),
    ];
    bool emergency24h = existing?.isEmergency24h ?? false;
    bool open24h = existing?.isOpen24h ?? false;
    String status = existing == null
        ? 'Ouvert'
        : existing.isOpen
            ? (existing.isOpen24h ? 'Ouvert 24/7' : 'Ouvert')
            : 'Ferme';
    bool uploadingHospitalPhoto = false;
    bool uploadingDoctorPhoto = false;
    bool doctorHidePhoto = false;
    bool saving = false;
    Uint8List? hospitalPhotoPreview;
    Uint8List? doctorPhotoPreview;
    int? editingDoctorIndex;

    void resetDoctorDraft() {
      editingDoctorIndex = null;
      doctorHidePhoto = false;
      doctorPhotoPreview = null;
      doctorNameCtrl.clear();
      doctorServiceCtrl.clear();
      doctorPhoneCtrl.clear();
      doctorPhotoCtrl.clear();
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null ? 'Ajouter un hopital' : 'Modifier l hopital',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom de l hopital')),
                    TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Adresse')),
                    TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Quartier / Ville')),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: 'Telephone'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: 'Email'),
                          ),
                        ),
                      ],
                    ),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Description / Specialites'),
                    ),
                    TextField(
                      controller: badgeCtrl,
                      decoration: const InputDecoration(labelText: 'Badge / categorie'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: uploadingHospitalPhoto
                              ? null
                              : () async {
                                  setModalState(() {
                                    uploadingHospitalPhoto = true;
                                    hospitalPhotoPreview = null;
                                  });
                                  final result = await _pickAndUploadHospitalPhoto();
                                  if (result.url.isNotEmpty) {
                                    photoCtrl.text = result.url;
                                    hospitalPhotoPreview = result.bytes;
                                  }
                                  if (!ctx.mounted) return;
                                  setModalState(() => uploadingHospitalPhoto = false);
                                },
                          icon: uploadingHospitalPhoto
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.photo_library_outlined),
                          label: const Text('Photo hopital'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: photoCtrl,
                            onChanged: (_) => setModalState(() {}),
                            decoration: const InputDecoration(labelText: 'Photo URL'),
                          ),
                        ),
                      ],
                    ),
                    if (hospitalPhotoPreview != null || photoCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: hospitalPhotoPreview != null
                            ? Image.memory(
                                hospitalPhotoPreview!,
                                width: 92,
                                height: 92,
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                photoCtrl.text.trim(),
                                width: 92,
                                height: 92,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Statut operationnel'),
                      items: const [
                        DropdownMenuItem(value: 'Ouvert', child: Text('Ouvert')),
                        DropdownMenuItem(value: 'Ferme', child: Text('Ferme')),
                        DropdownMenuItem(value: 'Ouvert 24/7', child: Text('Ouvert 24/7')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          status = value;
                          open24h = value == 'Ouvert 24/7';
                          if (value == 'Ferme') {
                            emergency24h = false;
                            open24h = false;
                          }
                        });
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: emergency24h,
                      onChanged: status == 'Ferme'
                          ? null
                          : (value) => setModalState(() => emergency24h = value),
                      title: const Text('Urgence 24/7'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: open24h,
                      onChanged: status == 'Ferme'
                          ? null
                          : (value) {
                              setModalState(() {
                                open24h = value;
                                if (value) status = 'Ouvert 24/7';
                                if (!value && status == 'Ouvert 24/7') status = 'Ouvert';
                              });
                            },
                      title: const Text('Ouvert 24/7'),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latCtrl,
                            decoration: const InputDecoration(labelText: 'Latitude'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: lngCtrl,
                            decoration: const InputDecoration(labelText: 'Longitude'),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          final ok = await _ensureLocation();
                          if (!ok || _userPosition == null) return;
                          latCtrl.text = _userPosition!.latitude.toStringAsFixed(6);
                          lngCtrl.text = _userPosition!.longitude.toStringAsFixed(6);
                          setModalState(() {});
                        },
                        icon: const Icon(Icons.my_location),
                        label: const Text('Utiliser ma position'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: serviceCtrl,
                            decoration: const InputDecoration(labelText: 'Service / Unite'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final value = serviceCtrl.text.trim();
                            if (value.isEmpty) return;
                            services.add(value);
                            serviceCtrl.clear();
                            setModalState(() {});
                          },
                          child: const Text('Ajouter'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: services
                          .map(
                            (service) => Chip(
                              label: Text(service),
                              onDeleted: () {
                                services.remove(service);
                                setModalState(() {});
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Equipe medicale',
                      style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                    ),
                    TextField(
                      controller: doctorNameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom du medecin'),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: doctorServiceCtrl,
                            decoration: const InputDecoration(labelText: 'Service'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: doctorPhoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: 'Numero'),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: uploadingDoctorPhoto
                              ? null
                              : () async {
                                  setModalState(() {
                                    uploadingDoctorPhoto = true;
                                    doctorPhotoPreview = null;
                                  });
                                  final result = await _pickAndUploadHospitalPhoto(scope: 'doctor');
                                  if (result.url.isNotEmpty) {
                                    doctorPhotoCtrl.text = result.url;
                                    doctorPhotoPreview = result.bytes;
                                  }
                                  if (!ctx.mounted) return;
                                  setModalState(() => uploadingDoctorPhoto = false);
                                },
                          icon: uploadingDoctorPhoto
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.badge_outlined),
                          label: const Text('Photo docteur'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: doctorPhotoCtrl,
                            onChanged: (_) => setModalState(() {}),
                            decoration: const InputDecoration(labelText: 'Photo URL'),
                          ),
                        ),
                      ],
                    ),
                    if (doctorPhotoPreview != null ||
                        (doctorPhotoCtrl.text.trim().isNotEmpty && !doctorHidePhoto)) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: doctorPhotoPreview != null
                            ? Image.memory(
                                doctorPhotoPreview!,
                                width: 82,
                                height: 82,
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                doctorPhotoCtrl.text.trim(),
                                width: 82,
                                height: 82,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: doctorHidePhoto,
                      onChanged: (value) => setModalState(() => doctorHidePhoto = value),
                      title: const Text('Masquer la photo du medecin'),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            final name = doctorNameCtrl.text.trim();
                            if (name.isEmpty) {
                              _snack('Le nom du medecin est obligatoire', error: true);
                              return;
                            }
                            final profile = _HospitalDoctorProfile(
                              name: name,
                              service: doctorServiceCtrl.text.trim(),
                              phone: doctorPhoneCtrl.text.trim(),
                              photo: doctorPhotoCtrl.text.trim(),
                              hidePhoto: doctorHidePhoto,
                            );
                            setModalState(() {
                              if (editingDoctorIndex == null) {
                                doctors.add(profile);
                              } else {
                                doctors[editingDoctorIndex!] = profile;
                              }
                              resetDoctorDraft();
                            });
                          },
                          icon: Icon(
                            editingDoctorIndex == null
                                ? Icons.person_add_alt_1_outlined
                                : Icons.save_as_outlined,
                          ),
                          label: Text(
                            editingDoctorIndex == null ? 'Ajouter le medecin' : 'Mettre a jour',
                          ),
                        ),
                        if (editingDoctorIndex != null)
                          OutlinedButton.icon(
                            onPressed: () => setModalState(resetDoctorDraft),
                            icon: const Icon(Icons.close),
                            label: const Text('Annuler'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Column(
                      children: List.generate(doctors.length, (index) {
                        final doctor = doctors[index];
                        final showPhoto = !doctor.hidePhoto && doctor.photo.isNotEmpty;
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: accent.withOpacity(0.10)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: showPhoto
                                    ? Image.network(
                                        doctor.photo,
                                        width: 46,
                                        height: 46,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: accent.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          doctor.hidePhoto
                                              ? Icons.visibility_off_outlined
                                              : Icons.person_outline,
                                          color: accent,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(doctor.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    if (doctor.service.isNotEmpty) Text(doctor.service),
                                    if (doctor.phone.isNotEmpty) Text(doctor.phone),
                                    if (doctor.hidePhoto) const Text('Photo masquee'),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      setModalState(() {
                                        editingDoctorIndex = index;
                                        doctorNameCtrl.text = doctor.name;
                                        doctorServiceCtrl.text = doctor.service;
                                        doctorPhoneCtrl.text = doctor.phone;
                                        doctorPhotoCtrl.text = doctor.photo;
                                        doctorHidePhoto = doctor.hidePhoto;
                                        doctorPhotoPreview = null;
                                      });
                                    },
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setModalState(() {
                                        doctors.removeAt(index);
                                        if (editingDoctorIndex == index) {
                                          resetDoctorDraft();
                                        }
                                      });
                                    },
                                    color: Colors.redAccent,
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: saving
                            ? null
                            : () async {
                          final name = nameCtrl.text.trim();
                          final address = addressCtrl.text.trim();
                          final location = locationCtrl.text.trim();
                          if (name.isEmpty) {
                            _snack('Le nom de l hopital est obligatoire', error: true);
                            return;
                          }
                          if (address.isEmpty && location.isEmpty) {
                            _snack('Renseignez au moins une adresse ou une localisation', error: true);
                            return;
                          }
                          final normalizedStatus = status == 'Ferme'
                              ? 'Ferme'
                              : open24h
                                  ? 'Ouvert 24/7'
                                  : 'Ouvert';
                          setModalState(() => saving = true);
                          try {
                            final payload = <String, dynamic>{
                              'name': name,
                              'address': address,
                              'location': location,
                              'phone': phoneCtrl.text.trim(),
                              'email': emailCtrl.text.trim(),
                              'note': noteCtrl.text.trim(),
                              'badge': badgeCtrl.text.trim(),
                              'status': normalizedStatus,
                              'isOpen': normalizedStatus != 'Ferme',
                              'photo': photoCtrl.text.trim(),
                              'lat': _toDouble(latCtrl.text.trim()),
                              'lng': _toDouble(lngCtrl.text.trim()),
                              'services': services,
                              'doctorProfiles': _hospitalDoctorProfileMaps(doctors),
                              'doctors': doctors
                                  .map((doctor) => doctor.displayLabel)
                                  .toList(growable: false),
                              'emergency24h': normalizedStatus == 'Ferme' ? false : emergency24h,
                              'open24h': normalizedStatus == 'Ouvert 24/7',
                              'ownerId': existing != null && existing.ownerId.isNotEmpty
                                  ? existing.ownerId
                                  : (_userId ?? ''),
                              'updatedAt': FieldValue.serverTimestamp(),
                            };
                            if (existing != null && existing.sourceId.isNotEmpty) {
                              await FirebaseFirestore.instance
                                  .collection('health_hospitals')
                                  .doc(existing.sourceId)
                                  .set(payload, SetOptions(merge: true));
                            } else {
                              await FirebaseFirestore.instance.collection('health_hospitals').add({
                                ...payload,
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                            }
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            _snack(existing == null ? 'Hopital ajoute' : 'Hopital mis a jour');
                          } catch (e) {
                            if (ctx.mounted) setModalState(() => saving = false);
                            _snack(
                              existing == null
                                  ? 'Erreur ajout hopital: $e'
                                  : 'Erreur modification hopital: $e',
                              error: true,
                            );
                          }
                        },
                        icon: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          saving
                              ? 'Enregistrement...'
                              : existing == null
                                  ? 'Enregistrer l hopital'
                                  : 'Mettre a jour l hopital',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    nameCtrl.dispose();
    addressCtrl.dispose();
    locationCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    noteCtrl.dispose();
    badgeCtrl.dispose();
    photoCtrl.dispose();
    latCtrl.dispose();
    lngCtrl.dispose();
    serviceCtrl.dispose();
    doctorNameCtrl.dispose();
    doctorServiceCtrl.dispose();
    doctorPhoneCtrl.dispose();
    doctorPhotoCtrl.dispose();
    if (mounted) setState(() => _addingHospital = false);
  }

  Future<Map<String, dynamic>?> _openAddPharmacyMedicineDialog(
    Color accent, {
    Map<String, dynamic>? existing,
  }) async {
    final nameCtrl = TextEditingController(text: _safeStr(existing?['name']));
    final priceCtrl = TextEditingController(
      text: _toDouble(existing?['price'])?.toString() ?? '',
    );
    final quantityCtrl = TextEditingController(
      text: (_toInt(existing?['quantity']) ?? 0) > 0 ? '${_toInt(existing?['quantity'])}' : '',
    );
    final stockCtrl = TextEditingController(
      text: (_toInt(existing?['stock']) ?? 0) > 0 ? '${_toInt(existing?['stock'])}' : '',
    );
    final dosageCtrl = TextEditingController(text: _safeStr(existing?['dosage']));
    final familyCtrl = TextEditingController(text: _safeStr(existing?['therapeuticFamily']));
    final expiryCtrl = TextEditingController(text: _safeStr(existing?['expiryDate']));
    final photoCtrl = TextEditingController(text: _safeStr(existing?['image']));
    String form = _safeStr(existing?['form']).isNotEmpty ? _safeStr(existing?['form']) : 'Comprime';
    bool uploadingPhoto = false;
    Uint8List? photoPreview;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF16120B) : Colors.white;
        final text = isDark ? Colors.white : const Color(0xFF23160A);
        final sub = isDark ? Colors.white70 : const Color(0xFF6F5843);

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: accent.withOpacity(0.16)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.10),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        existing == null ? 'Ajouter un produit' : 'Modifier le produit',
                        style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        style: TextStyle(color: text, fontWeight: FontWeight.w700),
                        decoration: const InputDecoration(labelText: 'Nom du produit'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: priceCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Prix'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: quantityCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Quantite'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: stockCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Stock'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: dosageCtrl,
                              decoration: const InputDecoration(labelText: 'Dosage'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: form,
                        decoration: const InputDecoration(labelText: 'Forme'),
                        items: const [
                          DropdownMenuItem(value: 'Comprime', child: Text('Comprime')),
                          DropdownMenuItem(value: 'Gelule', child: Text('Gelule')),
                          DropdownMenuItem(value: 'Sirop', child: Text('Sirop')),
                          DropdownMenuItem(value: 'Injection', child: Text('Injection')),
                          DropdownMenuItem(value: 'Pommade', child: Text('Pommade')),
                          DropdownMenuItem(value: 'Autre', child: Text('Autre')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setModalState(() => form = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: familyCtrl,
                        decoration: const InputDecoration(labelText: 'Famille therapeutique'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: expiryCtrl,
                        decoration: const InputDecoration(labelText: 'Date de peremption'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: uploadingPhoto
                                ? null
                                : () async {
                                    setModalState(() {
                                      uploadingPhoto = true;
                                      photoPreview = null;
                                    });
                                    final photo = await _pickAndUploadPharmacyPhoto();
                                    if (photo.url.isNotEmpty) {
                                      photoCtrl.text = photo.url;
                                      photoPreview = photo.bytes;
                                    }
                                    if (!ctx.mounted) return;
                                    setModalState(() => uploadingPhoto = false);
                                  },
                            icon: uploadingPhoto
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.photo_library_outlined),
                            label: const Text('Photo produit'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: photoCtrl,
                              onChanged: (_) => setModalState(() {}),
                              decoration: const InputDecoration(labelText: 'Photo URL'),
                            ),
                          ),
                        ],
                      ),
                      if (photoPreview != null || photoCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: photoPreview != null
                              ? Image.memory(photoPreview!, width: 88, height: 88, fit: BoxFit.cover)
                              : Image.network(photoCtrl.text.trim(), width: 88, height: 88, fit: BoxFit.cover),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) {
                              _snack('Le nom du produit est obligatoire', error: true);
                              return;
                            }
                            Navigator.of(ctx).pop(
                              <String, dynamic>{
                                'name': name,
                                'price': _toDouble(priceCtrl.text.trim()) ?? 0,
                                'quantity': _toInt(quantityCtrl.text.trim()) ?? 0,
                                'stock': _toInt(stockCtrl.text.trim()) ?? 0,
                                'form': form,
                                'dosage': dosageCtrl.text.trim(),
                                'therapeuticFamily': familyCtrl.text.trim(),
                                'expiryDate': expiryCtrl.text.trim(),
                                'image': photoCtrl.text.trim(),
                              },
                            );
                          },
                          icon: const Icon(Icons.save_outlined),
                          label: Text(existing == null ? 'Ajouter le produit' : 'Enregistrer le produit'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    priceCtrl.dispose();
    quantityCtrl.dispose();
    stockCtrl.dispose();
    dosageCtrl.dispose();
    familyCtrl.dispose();
    expiryCtrl.dispose();
    photoCtrl.dispose();
    return result;
  }

  Future<void> _openPharmacyInventoryManager({
    required Color accent,
    required DocumentReference<Map<String, dynamic>> reference,
    required Map<String, dynamic> pharmacy,
  }) async {
    final catalog = _normalizePharmacyCatalog(_pharmacyCatalogFromData(pharmacy))
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    String query = '';
    String sortMode = 'priority';
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF16120B) : Colors.white;
        final text = isDark ? Colors.white : const Color(0xFF23160A);
        final sub = isDark ? Colors.white70 : const Color(0xFF6F5843);
        final place = _joinParts([
          _safeStr(pharmacy['address'] ?? pharmacy['adresse']),
          _safeStr(pharmacy['location'] ?? pharmacy['localisation']),
        ]);

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = catalog.where((medicine) {
              if (query.isEmpty) return true;
              final haystack = [
                _safeStr(medicine['name']),
                _safeStr(medicine['form']),
                _safeStr(medicine['dosage']),
                _safeStr(medicine['therapeuticFamily']),
              ].join(' ').toLowerCase();
              return haystack.contains(query);
            }).toList();

            switch (sortMode) {
              case 'name':
                filtered.sort(
                  (a, b) => _safeStr(a['name']).toLowerCase().compareTo(_safeStr(b['name']).toLowerCase()),
                );
                break;
              case 'stock':
                filtered.sort((a, b) => (_toInt(a['stock']) ?? 0).compareTo(_toInt(b['stock']) ?? 0));
                break;
              case 'priority':
              default:
                filtered.sort((a, b) {
                  final aDays = _pharmacyMedicineExpiryDate(a)?.difference(DateTime.now()).inDays;
                  final bDays = _pharmacyMedicineExpiryDate(b)?.difference(DateTime.now()).inDays;
                  final aScore = ((_toInt(a['stock']) ?? 0) <= 5 ? 2 : 0) + (((aDays ?? 9999) <= 45) ? 1 : 0);
                  final bScore = ((_toInt(b['stock']) ?? 0) <= 5 ? 2 : 0) + (((bDays ?? 9999) <= 45) ? 1 : 0);
                  if (aScore != bScore) return bScore.compareTo(aScore);
                  return _safeStr(a['name']).compareTo(_safeStr(b['name']));
                });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: FractionallySizedBox(
                heightFactor: 0.92,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: accent.withOpacity(0.16)),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.10),
                        blurRadius: 28,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _safeStr(pharmacy['name']).isNotEmpty ? _safeStr(pharmacy['name']) : 'Pharmacie',
                        style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      if (place.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          place,
                          style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildHospitalInfoChip(label: '${catalog.length} produit(s)', color: accent),
                          _buildHospitalInfoChip(
                            label: 'Stock ${_pharmacyTotalStock(catalog)}',
                            color: accent,
                          ),
                          if (_pharmacyLowStockCount(catalog) > 0)
                            _buildHospitalInfoChip(
                              label: '${_pharmacyLowStockCount(catalog)} stock bas',
                              color: const Color(0xFFFF8A1F),
                            ),
                          if (_pharmacyExpiringCount(catalog) > 0)
                            _buildHospitalInfoChip(
                              label: '${_pharmacyExpiringCount(catalog)} peremption',
                              color: Colors.redAccent,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              onChanged: (value) => setModalState(() => query = value.trim().toLowerCase()),
                              style: TextStyle(color: text, fontWeight: FontWeight.w700),
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.search, color: accent),
                                hintText: 'Rechercher un produit',
                                hintStyle: TextStyle(color: sub),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final created = await _openAddPharmacyMedicineDialog(accent);
                              if (created == null || !ctx.mounted) return;
                              setModalState(() => catalog.add(created));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Produit'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: const <MapEntry<String, String>>[
                          MapEntry<String, String>('priority', 'Priorite'),
                          MapEntry<String, String>('stock', 'Stock'),
                          MapEntry<String, String>('name', 'Nom'),
                        ].map((item) {
                          final selected = sortMode == item.key;
                          return ChoiceChip(
                            label: Text(item.value),
                            selected: selected,
                            showCheckmark: false,
                            backgroundColor: accent.withOpacity(0.06),
                            selectedColor: accent.withOpacity(0.18),
                            labelStyle: TextStyle(
                              color: selected ? accent : text,
                              fontWeight: FontWeight.w700,
                            ),
                            onSelected: (_) => setModalState(() => sortMode = item.key),
                          );
                        }).toList(growable: false),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  catalog.isEmpty
                                      ? 'Aucun produit n est encore renseigne pour cette pharmacie.'
                                      : 'Aucun produit ne correspond a votre recherche.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (ctx, index) {
                                  final medicine = filtered[index];
                                  final rawIndex = catalog.indexOf(medicine);
                                  final stock = _toInt(medicine['stock']) ?? 0;
                                  final quantity = _toInt(medicine['quantity']);
                                  final price = _toDouble(medicine['price']);
                                  final stockColor = _pharmacyMedicineStockColor(stock, accent);
                                  final expiryColor = _pharmacyMedicineExpiryColor(medicine, accent);
                                  final image = _safeStr(medicine['image']);
                                  final details = _joinParts([
                                    _safeStr(medicine['form']),
                                    _safeStr(medicine['dosage']),
                                    _safeStr(medicine['therapeuticFamily']),
                                  ]);
                                  final expiry = _safeStr(medicine['expiryDate']);
                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: accent.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: accent.withOpacity(0.10)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(14),
                                              child: image.isNotEmpty
                                                  ? Image.network(image, width: 54, height: 54, fit: BoxFit.cover)
                                                  : Container(
                                                      width: 54,
                                                      height: 54,
                                                      color: accent.withOpacity(0.12),
                                                      child: Icon(Icons.medication_outlined, color: accent),
                                                    ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _safeStr(medicine['name']).isNotEmpty
                                                        ? _safeStr(medicine['name'])
                                                        : 'Produit',
                                                    style: TextStyle(
                                                      color: text,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                  if (details.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      details,
                                                      style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            Column(
                                              children: [
                                                IconButton(
                                                  onPressed: rawIndex < 0
                                                      ? null
                                                      : () async {
                                                          final updated = await _openAddPharmacyMedicineDialog(
                                                            accent,
                                                            existing: medicine,
                                                          );
                                                          if (updated == null || !ctx.mounted) return;
                                                          setModalState(() => catalog[rawIndex] = updated);
                                                        },
                                                  icon: const Icon(Icons.edit_outlined),
                                                ),
                                                IconButton(
                                                  onPressed: rawIndex < 0
                                                      ? null
                                                      : () => setModalState(() => catalog.removeAt(rawIndex)),
                                                  color: Colors.redAccent,
                                                  icon: const Icon(Icons.delete_outline),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            _buildHospitalInfoChip(label: 'Stock $stock', color: stockColor),
                                            if (quantity != null && quantity > 0)
                                              _buildHospitalInfoChip(label: 'Qt $quantity', color: accent),
                                            if (price != null && price > 0)
                                              _buildHospitalInfoChip(
                                                label: 'Prix ${price.toStringAsFixed(2)}',
                                                color: accent,
                                              ),
                                            if (expiry.isNotEmpty)
                                              _buildHospitalInfoChip(
                                                label: expiry,
                                                color: expiryColor,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: saving
                              ? null
                              : () async {
                                  setModalState(() => saving = true);
                                  try {
                                    final normalized = _normalizePharmacyCatalog(catalog);
                                    await reference.set(
                                      {
                                        'medicineCatalog': normalized,
                                        'medicines': _pharmacyCatalogMedicineNames(normalized),
                                        'updatedAt': FieldValue.serverTimestamp(),
                                      },
                                      SetOptions(merge: true),
                                    );
                                    await _refreshHealthNotificationsIfAvailable();
                                    if (ctx.mounted) Navigator.of(ctx).pop();
                                    _snack('Stock pharmacie mis a jour');
                                  } catch (e) {
                                    if (ctx.mounted) setModalState(() => saving = false);
                                    _snack('Erreur mise a jour stock: $e', error: true);
                                  }
                                },
                          icon: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(saving ? 'Enregistrement...' : 'Enregistrer le stock'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAddPharmacy(
    Color accent, {
    DocumentReference<Map<String, dynamic>>? reference,
    Map<String, dynamic>? existing,
  }) async {
    if (_addingPharmacy) return;
    setState(() => _addingPharmacy = true);
    final isEditing = existing != null;
    final nameCtrl = TextEditingController(text: _safeStr(existing?['name']));
    final addressCtrl = TextEditingController(text: _safeStr(existing?['address'] ?? existing?['adresse']));
    final locationCtrl = TextEditingController(text: _safeStr(existing?['location'] ?? existing?['localisation']));
    final phoneCtrl = TextEditingController(text: _safeStr(existing?['phone'] ?? existing?['telephone']));
    final emailCtrl = TextEditingController(text: _safeStr(existing?['email']));
    final photoCtrl = TextEditingController(text: _safeStr(existing?['photo'] ?? existing?['image'] ?? existing?['photoUrl']));
    final latCtrl = TextEditingController(
      text: _toDouble(existing?['lat'] ?? existing?['latitude'])?.toString() ?? '',
    );
    final lngCtrl = TextEditingController(
      text: _toDouble(existing?['lng'] ?? existing?['longitude'])?.toString() ?? '',
    );
    final catalog = _normalizePharmacyCatalog(_pharmacyCatalogFromData(existing ?? const <String, dynamic>{}))
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    bool open24h = _boolValue(existing?['open24h'] ?? existing?['alwaysOpen']) == true;
    String status = _safeStr(existing?['status']).isNotEmpty
        ? _safeStr(existing?['status'])
        : (open24h ? 'Ouvert 24/7' : 'Ouvert');
    bool uploadingPhoto = false;
    bool saving = false;
    Uint8List? photoPreview;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing ? 'Modifier la pharmacie' : 'Ajouter une pharmacie',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom')),
                    TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Adresse')),
                    TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Localisation')),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: 'Telephone'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: 'Email'),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latCtrl,
                            decoration: const InputDecoration(labelText: 'Latitude'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: lngCtrl,
                            decoration: const InputDecoration(labelText: 'Longitude'),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          final ok = await _ensureLocation();
                          if (!ok || _userPosition == null) return;
                          latCtrl.text = _userPosition!.latitude.toStringAsFixed(6);
                          lngCtrl.text = _userPosition!.longitude.toStringAsFixed(6);
                          setModalState(() {});
                        },
                        icon: const Icon(Icons.my_location),
                        label: const Text('Utiliser ma position'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: uploadingPhoto
                              ? null
                              : () async {
                                  setModalState(() {
                                    uploadingPhoto = true;
                                    photoPreview = null;
                                  });
                                  final result = await _pickAndUploadPharmacyPhoto();
                                  if (result.url.isNotEmpty) {
                                    photoCtrl.text = result.url;
                                    photoPreview = result.bytes;
                                  }
                                  if (!ctx.mounted) return;
                                  setModalState(() => uploadingPhoto = false);
                                },
                          icon: uploadingPhoto
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.photo_library_outlined),
                          label: const Text('Importer une photo'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: photoCtrl,
                            decoration: const InputDecoration(labelText: 'Photo URL'),
                          ),
                        ),
                      ],
                    ),
                    if (photoPreview != null || photoCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: photoPreview != null
                            ? Image.memory(photoPreview!, width: 96, height: 96, fit: BoxFit.cover)
                            : Image.network(photoCtrl.text.trim(), width: 96, height: 96, fit: BoxFit.cover),
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Statut'),
                      items: const [
                        DropdownMenuItem(value: 'Ouvert', child: Text('Ouvert')),
                        DropdownMenuItem(value: 'Ferme', child: Text('Ferme')),
                        DropdownMenuItem(value: 'Ouvert 24/7', child: Text('Ouvert 24/7')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          status = value;
                          open24h = value == 'Ouvert 24/7';
                        });
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: open24h,
                      onChanged: (value) {
                        setModalState(() {
                          open24h = value;
                          if (value) status = 'Ouvert 24/7';
                          if (!value && status == 'Ouvert 24/7') status = 'Ouvert';
                        });
                      },
                      title: const Text('Ouvert 24/7'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Catalogue pharmacie',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final created = await _openAddPharmacyMedicineDialog(accent);
                            if (created == null || !ctx.mounted) return;
                            setModalState(() => catalog.add(created));
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Produit'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (catalog.isEmpty)
                      const Text('Aucun produit renseigne pour le moment.')
                    else
                      Column(
                        children: List.generate(catalog.length, (index) {
                          final medicine = catalog[index];
                          final stock = _toInt(medicine['stock']) ?? 0;
                          final details = _joinParts([
                            _safeStr(medicine['form']),
                            _safeStr(medicine['dosage']),
                            _safeStr(medicine['therapeuticFamily']),
                          ]);
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: accent.withOpacity(0.10)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _safeStr(medicine['name']).isNotEmpty
                                            ? _safeStr(medicine['name'])
                                            : 'Produit',
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        final updated = await _openAddPharmacyMedicineDialog(
                                          accent,
                                          existing: medicine,
                                        );
                                        if (updated == null || !ctx.mounted) return;
                                        setModalState(() => catalog[index] = updated);
                                      },
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      onPressed: () => setModalState(() => catalog.removeAt(index)),
                                      color: Colors.redAccent,
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                                if (details.isNotEmpty) Text(details),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildHospitalInfoChip(
                                      label: 'Stock $stock',
                                      color: _pharmacyMedicineStockColor(stock, accent),
                                    ),
                                    if ((_toDouble(medicine['price']) ?? 0) > 0)
                                      _buildHospitalInfoChip(
                                        label:
                                            'Prix ${(_toDouble(medicine['price']) ?? 0).toStringAsFixed(2)}',
                                        color: accent,
                                      ),
                                    if ((_toInt(medicine['quantity']) ?? 0) > 0)
                                      _buildHospitalInfoChip(
                                        label: 'Qt ${_toInt(medicine['quantity'])}',
                                        color: accent,
                                      ),
                                    if (_safeStr(medicine['expiryDate']).isNotEmpty)
                                      _buildHospitalInfoChip(
                                        label: _safeStr(medicine['expiryDate']),
                                        color: _pharmacyMedicineExpiryColor(medicine, accent),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: saving
                            ? null
                            : () async {
                                final name = nameCtrl.text.trim();
                                final address = addressCtrl.text.trim();
                                final location = locationCtrl.text.trim();
                                if (name.isEmpty) {
                                  _snack('Le nom de la pharmacie est obligatoire', error: true);
                                  return;
                                }
                                if (address.isEmpty && location.isEmpty) {
                                  _snack('Renseignez au moins une adresse ou une localisation', error: true);
                                  return;
                                }
                                final normalizedStatus = status == 'Ferme'
                                    ? 'Ferme'
                                    : open24h
                                        ? 'Ouvert 24/7'
                                        : 'Ouvert';
                                final normalizedCatalog = _normalizePharmacyCatalog(catalog);
                                setModalState(() => saving = true);
                                try {
                                  final payload = <String, dynamic>{
                                    'name': name,
                                    'address': address,
                                    'location': location,
                                    'phone': phoneCtrl.text.trim(),
                                    'email': emailCtrl.text.trim(),
                                    'photo': photoCtrl.text.trim(),
                                    'status': normalizedStatus,
                                    'isOpen': normalizedStatus != 'Ferme',
                                    'open24h': normalizedStatus == 'Ouvert 24/7',
                                    'lat': _toDouble(latCtrl.text.trim()),
                                    'lng': _toDouble(lngCtrl.text.trim()),
                                    'medicineCatalog': normalizedCatalog,
                                    'medicines': _pharmacyCatalogMedicineNames(normalizedCatalog),
                                    'ownerId': _safeStr(existing?['ownerId']).isNotEmpty
                                        ? _safeStr(existing?['ownerId'])
                                        : (_userId ?? ''),
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  };
                                  if (reference != null) {
                                    await reference.set(payload, SetOptions(merge: true));
                                  } else {
                                    await FirebaseFirestore.instance.collection('health_pharmacies').add({
                                      ...payload,
                                      'createdAt': FieldValue.serverTimestamp(),
                                    });
                                  }
                                  await _refreshHealthNotificationsIfAvailable();
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                  _snack(isEditing ? 'Pharmacie mise a jour' : 'Pharmacie enregistree');
                                } catch (e) {
                                  if (ctx.mounted) setModalState(() => saving = false);
                                  _snack(
                                    isEditing
                                        ? 'Erreur modification pharmacie: $e'
                                        : 'Erreur ajout pharmacie: $e',
                                    error: true,
                                  );
                                }
                              },
                        icon: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          saving
                              ? 'Enregistrement...'
                              : isEditing
                                  ? 'Enregistrer les modifications'
                                  : 'Enregistrer',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    nameCtrl.dispose();
    addressCtrl.dispose();
    locationCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    photoCtrl.dispose();
    latCtrl.dispose();
    lngCtrl.dispose();
    if (mounted) {
      setState(() => _addingPharmacy = false);
    }
  }

  String _summaryEssentials(
    String bloodType,
    List<String> allergies,
    List<String> conditions, {
    String? emergencyName,
    String? emergencyPhone,
  }) {
    final parts = <String>[];
    if (_safeStr(bloodType).isNotEmpty) parts.add('groupe ${_safeStr(bloodType)}');
    if (allergies.isNotEmpty) parts.add('allergies ${allergies.take(3).join(', ')}');
    if (conditions.isNotEmpty) parts.add('conditions ${conditions.take(3).join(', ')}');
    final emergency = _summaryEmergency(emergencyName ?? '', emergencyPhone ?? '');
    if (emergency != 'Non renseigné') parts.add('urgence $emergency');
    if (parts.isEmpty) return 'Non renseigné';
    return parts.join(' / ');
  }

  String _cycleSummary(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is Map) {
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      final start = _safeStr(map['start'] ?? map['startDate']);
      final duration = _safeStr(map['duration']);
      final phase = _safeStr(map['phase']);
      final parts = <String>[];
      if (start.isNotEmpty) parts.add('début $start');
      if (duration.isNotEmpty) parts.add('durée $duration j');
      if (phase.isNotEmpty) parts.add('phase $phase');
      return parts.join(' / ');
    }
    return _safeStr(raw);
  }

  int _countDocs(dynamic raw) {
    if (raw == null) return 0;
    if (raw is List) {
      return raw.where((e) => _safeStr(e).isNotEmpty).length;
    }
    if (raw is Map) {
      return raw.values.where((e) => _safeStr(e).isNotEmpty).length;
    }
    return _safeStr(raw).isNotEmpty ? 1 : 0;
  }

  List<String> _stringList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.map((e) => _safeStr(e)).where((e) => e.isNotEmpty).toList();
    }
    final s = _safeStr(raw);
    if (s.isEmpty) return const [];
    if (s.contains(',')) {
      return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return [s];
  }

  List<String> _doctorList(dynamic raw) {
    final profiles = _hospitalDoctorProfiles(raw);
    if (profiles.isNotEmpty) {
      return profiles.map((doctor) => doctor.displayLabel).toList(growable: false);
    }
    return _stringList(raw);
  }

  _HealthRiskSummary _buildHealthRiskSummary({
    required double? bmi,
    required String tension,
    required String glycemie,
    required String heartRate,
    required List<String> allergies,
    required List<String> conditions,
    required List<String> alerts,
    required List<String> aiAlerts,
    required int treatmentsCount,
  }) {
    final summary = computeHealthRiskSummary(
      bmi: bmi,
      tension: tension,
      glycemie: glycemie,
      heartRate: heartRate,
      allergies: allergies,
      conditions: conditions,
      alerts: alerts,
      aiAlerts: aiAlerts,
      treatmentsCount: treatmentsCount,
    );
    return _HealthRiskSummary(
      score: summary.score,
      label: summary.label,
      risks: summary.risks,
    );
  }

  List<String> _medicationBullets(dynamic raw) {
    if (raw is List) {
      final out = <String>[];
      for (final item in raw) {
        if (item is Map) {
          final m = item.map((k, v) => MapEntry(k.toString(), v));
          final name = _safeStr(m['name'] ?? m['medicament'] ?? m['label']);
          final dose = _safeStr(m['dose']);
          final schedule = _safeStr(m['schedule'] ?? m['horaire']);
          if (name.isNotEmpty) {
            final details = [
              if (dose.isNotEmpty) dose,
              if (schedule.isNotEmpty) schedule,
            ].join(' / ');
            out.add(details.isNotEmpty ? '$name - $details' : name);
          }
        } else {
          final s = _safeStr(item);
          if (s.isNotEmpty) out.add(s);
        }
      }
      return out;
    }
    return _stringList(raw);
  }

  List<String> _appointmentBullets(dynamic raw) {
    if (raw is List) {
      final out = <String>[];
      for (final item in raw) {
        if (item is Map) {
          final m = item.map((k, v) => MapEntry(k.toString(), v));
          final date = _safeStr(m['date'] ?? m['jour']);
          final doctor = _safeStr(m['doctor'] ?? m['medecin']);
          final place = _safeStr(m['hospital'] ?? m['lieu']);
          final reason = _safeStr(m['reason'] ?? m['motif']);
          final parts = <String>[
            if (date.isNotEmpty) date,
            if (doctor.isNotEmpty) doctor,
            if (place.isNotEmpty) place,
            if (reason.isNotEmpty) reason,
          ];
          if (parts.isNotEmpty) out.add(parts.join(' / '));
        } else {
          final s = _safeStr(item);
          if (s.isNotEmpty) out.add(s);
        }
      }
      return out;
    }
    return _stringList(raw);
  }
}

class _HealthRiskSummary {
  final int score;
  final String label;
  final List<String> risks;

  const _HealthRiskSummary({
    required this.score,
    required this.label,
    required this.risks,
  });
}

class _HealthDashboardShortcut {
  final String title;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _HealthDashboardShortcut({
    required this.title,
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class _PhotoPickResult {
  final String url;
  final Uint8List? bytes;

  const _PhotoPickResult({required this.url, this.bytes});
}

class _FeatureList extends StatelessWidget {
  final Color cardBg;
  final Color text;
  final Color sub;
  final Color accent;
  final Widget? header;
  final List<_HealthSection> sections;
  final List<VoidCallback?>? actions;

  const _FeatureList({
    required this.cardBg,
    required this.text,
    required this.sub,
    required this.accent,
    this.header,
    required this.sections,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (header != null) header!,
        ...sections.asMap().entries.map((entry) {
          final index = entry.key;
          final s = entry.value;
          final onTap = (actions != null && index < actions!.length) ? actions![index] : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 260 + (index * 90)),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, (1 - value) * 14),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: _FeatureCard(
                icon: s.icon,
                title: s.title,
                bullets: s.bullets,
                text: text,
                sub: sub,
                cardBg: cardBg,
                accent: accent,
                onTap: onTap,
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> bullets;
  final Color text;
  final Color sub;
  final Color cardBg;
  final Color accent;
  final VoidCallback? onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.bullets,
    required this.text,
    required this.sub,
    required this.cardBg,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(cardBg, accent, 0.05)!,
                cardBg,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
            border: Border.all(color: accent.withOpacity(0.14)),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent.withOpacity(0.20),
                          accent.withOpacity(0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${bullets.length} point(s) cles',
                          style: TextStyle(
                            color: sub.withOpacity(0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Ouvrir',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              ...bullets.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check_rounded, size: 13, color: accent),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          b,
                          style: TextStyle(
                            color: sub,
                            height: 1.42,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (onTap != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onTap,
                    child: Text(
                      'Gerer',
                      style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthDashboardShortcutTile extends StatelessWidget {
  const _HealthDashboardShortcutTile({
    required this.item,
    required this.cardBg,
    required this.text,
    required this.sub,
    required this.accent,
    this.compact = false,
  });

  final _HealthDashboardShortcut item;
  final Color cardBg;
  final Color text;
  final Color sub;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tileWidth = compact ? 24.0 : 94.0;
    final iconSize = compact ? 13.0 : 22.0;
    final iconBox = compact ? 24.0 : 42.0;
    final labelFont = compact ? 11.0 : 12.0;
    final padding = compact
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 12);

    if (compact) {
      return Tooltip(
        message: item.title,
        child: SizedBox(
          width: tileWidth,
          height: tileWidth,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: item.onTap,
              borderRadius: BorderRadius.circular(9),
              child: Ink(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white.withOpacity(0.22)),
                ),
                child: Center(
                  child: Icon(item.icon, color: accent, size: iconSize),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: tileWidth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color.lerp(cardBg, accent, 0.08)!,
                  cardBg,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withOpacity(0.12)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: iconBox,
                  height: iconBox,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.icon, color: accent, size: iconSize),
                ),
                const SizedBox(height: 10),
                Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: text,
                    fontSize: labelFont,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ouvrir',
                  style: TextStyle(
                    color: sub,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _HealthAiRole { user, assistant }

class _HealthAiMessage {
  final _HealthAiRole role;
  final String text;

  const _HealthAiMessage({
    required this.role,
    required this.text,
  });
}

class _MiniStatData {
  final String label;
  final String value;
  final IconData icon;

  const _MiniStatData({
    required this.label,
    required this.value,
    required this.icon,
  });
}

class _QuickHealthActionData {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickHealthActionData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}

class _HospitalDoctorProfile {
  final String name;
  final String service;
  final String phone;
  final String photo;
  final bool hidePhoto;

  const _HospitalDoctorProfile({
    required this.name,
    this.service = '',
    this.phone = '',
    this.photo = '',
    this.hidePhoto = false,
  });

  String get displayLabel => service.isEmpty ? name : '$name - $service';
  String get searchText => '$name $service $phone'.toLowerCase();
}

class _HospitalDirectoryItem {
  final String sourceId;
  final String ownerId;
  final String name;
  final String location;
  final String note;
  final String phone;
  final String email;
  final String badge;
  final double? lat;
  final double? lng;
  final String image;
  final String status;
  final bool isOpen;
  final List<String> services;
  final List<String> doctors;
  final List<_HospitalDoctorProfile> doctorProfiles;
  final bool isEmergency24h;
  final bool isOpen24h;

  const _HospitalDirectoryItem({
    this.sourceId = '',
    this.ownerId = '',
    required this.name,
    required this.location,
    this.note = '',
    this.phone = '',
    this.email = '',
    this.badge = '',
    this.lat,
    this.lng,
    this.image = '',
    this.status = '',
    this.isOpen = true,
    this.services = const <String>[],
    this.doctors = const <String>[],
    this.doctorProfiles = const <_HospitalDoctorProfile>[],
    this.isEmergency24h = false,
    this.isOpen24h = false,
  });
}

class _HealthQuickActionCard extends StatelessWidget {
  const _HealthQuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.cardBg,
    required this.text,
    required this.sub,
    required this.accent,
    required this.enabled,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color cardBg;
  final Color text;
  final Color sub;
  final Color accent;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.lerp(cardBg, accent, 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withOpacity(enabled ? 0.90 : 0.30),
                      Color.lerp(accent, Colors.blue, 0.35)!.withOpacity(enabled ? 0.90 : 0.30),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled ? text : sub,
                        fontWeight: FontWeight.w800,
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
              Icon(Icons.arrow_outward_rounded, color: enabled ? accent : sub),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthAiBubble extends StatelessWidget {
  const _HealthAiBubble({
    required this.message,
    required this.accent,
    required this.text,
    required this.sub,
  });

  final _HealthAiMessage message;
  final Color accent;
  final Color text;
  final Color sub;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _HealthAiRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? accent : accent.withOpacity(0.07),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 18),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : text,
            height: 1.42,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _HospitalDirectoryCard extends StatelessWidget {
  const _HospitalDirectoryCard({
    required this.item,
    this.distanceLabel = '',
    required this.cardBg,
    required this.text,
    required this.sub,
    required this.accent,
    this.onTap,
    this.onOpenMap,
    this.onCall,
    this.onEmail,
    this.onDelete,
  });

  final _HospitalDirectoryItem item;
  final String distanceLabel;
  final Color cardBg;
  final Color text;
  final Color sub;
  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onOpenMap;
  final VoidCallback? onCall;
  final VoidCallback? onEmail;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final statusLabel = item.status.isNotEmpty
        ? item.status
        : item.isOpen
            ? (item.isOpen24h ? 'Ouvert 24/7' : 'Ouvert')
            : 'Ferme';
    final statusColor = item.isOpen || item.isOpen24h ? Colors.green : Colors.redAccent;
    final doctorCount = item.doctorProfiles.isNotEmpty ? item.doctorProfiles.length : item.doctors.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withOpacity(0.10),
                cardBg,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withOpacity(0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: item.image.isNotEmpty
                        ? Image.network(item.image, width: 54, height: 54, fit: BoxFit.cover)
                        : Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.local_hospital_outlined, color: accent),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 4),
                      child: Icon(Icons.open_in_new_rounded, color: accent, size: 18),
                    ),
                  if (onDelete != null)
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.redAccent,
                      tooltip: 'Supprimer',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.place_outlined, color: accent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.location,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: text, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (item.note.isNotEmpty)
                Text(
                  item.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                ),
              if (item.services.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: item.services
                      .take(4)
                      .map(
                        (service) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: accent.withOpacity(0.10)),
                          ),
                          child: Text(
                            service,
                            style: TextStyle(
                              color: text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 12),
              _HealthLocationMap(
                lat: item.lat,
                lng: item.lng,
                label: item.location,
                accent: accent,
                text: text,
                sub: sub,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (distanceLabel.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.near_me_outlined, color: accent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            distanceLabel,
                            style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  if (item.isEmergency24h)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Urgence 24/7',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800),
                      ),
                    ),
                  if (item.badge.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item.badge,
                        style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                      ),
                    ),
                  if (doctorCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$doctorCount medecin(s)',
                        style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                      ),
                    ),
                  if (item.phone.isNotEmpty)
                    Text(
                      item.phone,
                      style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (onTap != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withOpacity(0.10)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_outlined, color: accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Touchez pour rendez-vous, medecins, contact et teleconsultation.',
                          style: TextStyle(color: text, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onCall != null)
                    OutlinedButton.icon(
                      onPressed: onCall,
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Appeler'),
                    ),
                  if (onEmail != null)
                    OutlinedButton.icon(
                      onPressed: onEmail,
                      icon: const Icon(Icons.mail_outline),
                      label: const Text('Email'),
                    ),
                  if (onOpenMap != null)
                    OutlinedButton.icon(
                      onPressed: onOpenMap,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Voir carte'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonPharmacyCard extends StatelessWidget {
  const _PersonPharmacyCard({
    required this.name,
    required this.place,
    required this.medicines,
    required this.image,
    required this.phone,
    required this.email,
    required this.lat,
    required this.lng,
    required this.statusLabel,
    required this.isOpen,
    this.distanceLabel = '',
    required this.text,
    required this.sub,
    required this.accent,
    this.onTap,
    this.onOpenMap,
    this.onCall,
    this.onEmail,
  });

  final String name;
  final String place;
  final List<String> medicines;
  final String image;
  final String phone;
  final String email;
  final double? lat;
  final double? lng;
  final String statusLabel;
  final bool isOpen;
  final String distanceLabel;
  final Color text;
  final Color sub;
  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onOpenMap;
  final VoidCallback? onCall;
  final VoidCallback? onEmail;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withOpacity(0.12),
                accent.withOpacity(0.03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.08),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: image.trim().isNotEmpty
                        ? Image.network(image, width: 72, height: 72, fit: BoxFit.cover)
                        : Container(
                            width: 72,
                            height: 72,
                            color: accent.withOpacity(0.12),
                            child: Icon(Icons.local_pharmacy_outlined, color: accent),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: (isOpen ? Colors.green : Colors.redAccent).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  color: isOpen ? Colors.green.shade700 : Colors.redAccent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          place.trim().isNotEmpty ? place : 'Localisation non renseignee',
                          style: TextStyle(
                            color: sub,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (distanceLabel.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: accent.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.near_me_outlined, color: accent, size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      distanceLabel,
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${medicines.length} medicament(s)',
                                style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        if (phone.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            phone,
                            style: TextStyle(
                              color: sub,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _HealthLocationMap(
                lat: lat,
                lng: lng,
                label: place,
                accent: accent,
                text: text,
                sub: sub,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.36),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withOpacity(0.10)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        medicines.isEmpty
                            ? 'Touchez pour verifier si des medicaments ont ete renseignes.'
                            : 'Touchez pour voir le stock, rechercher et filtrer les medicaments.',
                        style: TextStyle(
                          color: text,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, color: accent, size: 16),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onCall != null)
                    OutlinedButton.icon(
                      onPressed: onCall,
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Appeler'),
                    ),
                  if (onEmail != null)
                    OutlinedButton.icon(
                      onPressed: onEmail,
                      icon: const Icon(Icons.mail_outline),
                      label: const Text('Email'),
                    ),
                  if (onOpenMap != null)
                    OutlinedButton.icon(
                      onPressed: onOpenMap,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Voir carte'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthLocationMap extends StatelessWidget {
  const _HealthLocationMap({
    required this.lat,
    required this.lng,
    required this.label,
    required this.accent,
    required this.text,
    required this.sub,
  });

  final double? lat;
  final double? lng;
  final String label;
  final Color accent;
  final Color text;
  final Color sub;

  @override
  Widget build(BuildContext context) {
    if (lat == null || lng == null) {
      return Container(
        height: 132,
        decoration: BoxDecoration(
          color: accent.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withOpacity(0.10)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.map_outlined, color: accent),
                const SizedBox(height: 8),
                Text(
                  'Coordonnees GPS non renseignees',
                  style: TextStyle(
                    color: text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label.trim().isNotEmpty ? label : 'Localisation a confirmer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: sub,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final point = LatLng(lat!, lng!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 144,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 14.6,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.lualaba.konnect.app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.location_on_rounded,
                    color: accent,
                    size: 34,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthSection {
  final IconData icon;
  final String title;
  final List<String> bullets;

  const _HealthSection({
    required this.icon,
    required this.title,
    required this.bullets,
  });
}

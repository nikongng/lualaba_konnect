import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:lualaba_konnect/core/supabase_service.dart';
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

class HealthProfilePage extends StatefulWidget {
  const HealthProfilePage({super.key});

  @override
  State<HealthProfilePage> createState() => _HealthProfilePageState();
}

class _HealthProfilePageState extends State<HealthProfilePage> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  bool _initializing = true;
  String? _error;
  String? _userCollection;
  String? _userId;
  bool _notifPrimed = false;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _pharmacySearchCtrl = TextEditingController();
  String _pharmacyQuery = '';
  bool _addingPharmacy = false;
  bool _nearMeOnly = false;
  double _nearMeRadiusKm = 5;
  bool _locBusy = false;
  Position? _userPosition;
  bool _exportingPharmacies = false;
  bool _importingPharmacies = false;

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
  }

  @override
  void dispose() {
    _pharmacySearchCtrl.dispose();
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
    final accent = const Color(0xFF00CBA9);

    final stream = _userStream;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          iconTheme: IconThemeData(color: text),
          title: Text(
            'Ma Santé',
            style: TextStyle(color: text, fontWeight: FontWeight.bold),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
              child: _buildTabBar(isDark, accent),
            ),
          ),
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
                            child: TabBarView(
                              children: [
                                _buildPersonTab(cardBg, text, sub, accent, data),
                                _buildHospitalTab(cardBg, text, sub, accent, data),
                                _buildPharmacyTab(cardBg, text, sub, accent, data),
                              ],
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

  Widget _buildTabBar(bool isDark, Color accent) {
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
      tabs: const [
        Tab(text: 'Personne'),
        Tab(text: 'Hopital'),
        Tab(text: 'Pharmacies'),
      ],
    );
  }

  Widget _buildPersonTab(
    Color cardBg,
    Color text,
    Color sub,
    Color accent,
    Map<String, dynamic> data,
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

    final sections = <_HealthSection>[
      _HealthSection(
        icon: Icons.dashboard_customize_outlined,
        title: 'Tableau de bord santé',
        bullets: [
          'Vue d’ensemble des indicateurs santé principaux : ${_summaryIndicators(weight: weight, tension: tension, glycemie: glycemie, cycle: cycleSummary)}',
          'Prochains rendez-vous médicaux : ${_summarizeList(appointments, empty: 'Aucun')}',
          'Médicaments à prendre aujourd’hui : ${_summarizeList(medsToday.isNotEmpty ? medsToday : meds, empty: 'Aucun')}',
          'Alertes importantes et notifications : ${_summarizeList(alerts, empty: 'Aucune')}',
        ],
      ),
      _HealthSection(
        icon: Icons.badge_outlined,
        title: 'Profil médical',
        bullets: [
          'Informations personnelles : ${displayName.isNotEmpty ? displayName : 'Non renseigné'}, naissance ${_formatBirth(birthDate, age)}',
          'Groupe sanguin : ${bloodType.isNotEmpty ? bloodType : 'Non renseigné'}',
          'Allergies : ${allergies.isNotEmpty ? allergies.join(', ') : 'Non renseignées'}',
          'Maladies chroniques : ${conditions.isNotEmpty ? conditions.join(', ') : 'Non renseignées'}',
          'Taille, poids, IMC : ${_summaryBody(weight: weight, height: height, bmi: bmi)}',
          'Contact d’urgence : ${_summaryEmergency(emergencyName, emergencyPhone)}',
          'Historique médical complet : ${_summarizeList(_mergeLists([medicalHistory, hospitalizations, vaccinations]), empty: 'Aucun')}',
          'Export PDF du profil : ${profilePdfUrl.isNotEmpty ? 'Disponible' : 'Non disponible'}',
        ],
      ),
      _HealthSection(
        icon: Icons.medication_outlined,
        title: 'Médicaments',
        bullets: [
          'Ajouter / modifier / supprimer médicaments',
          'Dose et heure de prise : ${_summarizeList(meds, empty: 'Non renseigné')}',
          'Durée du traitement : ${_summarizeList(_stringList(health['medicationDurations']), empty: 'Non renseignée')}',
          'Historique de prise : ${_summarizeList(medicationHistory, empty: 'Aucun')}',
          'Notifications push pour rappel : ${_statusLabel(medsNotif)}',
          'Rappel intelligent basé sur la prise effective : ${_statusLabel(smartReminders)}',
        ],
      ),
      _HealthSection(
        icon: Icons.event_available_outlined,
        title: 'Rendez-vous médicaux',
        bullets: [
          'Ajouter / modifier / supprimer rendez-vous',
          'Informations : ${_summarizeList(appointments, empty: 'Aucun rendez-vous')}',
          'Notifications push pour rappel : ${_statusLabel(apptNotif)}',
          'Historique consultable : ${_summarizeList(appointmentHistory, empty: 'Aucun')}',
        ],
      ),
      _HealthSection(
        icon: Icons.folder_shared_outlined,
        title: 'Analyses et documents médicaux',
        bullets: [
          'Stockage sécurisé de fichiers (PDF, images) : ${docCount > 0 ? '$docCount fichier(s)' : 'Aucun fichier'}',
          'Résultats d’analyses, radiographies, prescriptions : ${_summarizeList(labResults, empty: 'Aucun')}',
          'Scanner de documents via appareil photo',
          'Historique consultable et exportable : ${_summarizeList(documentHistory, empty: 'Aucun')}',
        ],
      ),
      _HealthSection(
        icon: Icons.show_chart_outlined,
        title: 'Suivi santé et graphiques',
        bullets: [
          'Poids, tension, glycémie, fréquence cardiaque, activité physique : ${_summaryMeasures(weight: weight, tension: tension, glycemie: glycemie, heartRate: heartRate, activity: activity)}',
          'Graphiques interactifs pour suivre l’évolution',
          'Alertes automatiques si certaines mesures dépassent des seuils : ${_statusLabel(thresholdAlerts)}',
          'Calcul du BMI et suivi des objectifs santé : ${bmi != null ? bmi.toStringAsFixed(1) : 'Non calculé'}',
        ],
      ),
      _HealthSection(
        icon: Icons.water_drop_outlined,
        title: 'Module Menstruations / Cycle féminin',
        bullets: [
          'Suivi du cycle : ${cycleSummary.isNotEmpty ? cycleSummary : 'Non renseigné'}',
          'Suivi des symptômes quotidiens : ${_summarizeList(cycleSymptoms, empty: 'Aucun')}',
          'Historique des cycles : ${_summarizeList(cycleHistory, empty: 'Aucun')}',
          'Prévision prochaines règles et fenêtre fertile : ${cycleNext.isNotEmpty ? cycleNext : 'Non renseignée'}',
          'Notifications et rappels : ${_statusLabel(cycleNotif)}',
          'Analyse IA pour détecter irrégularités et conseils personnalisés : ${_statusLabel(_boolValue(health['cycleAi']))}',
        ],
      ),
      _HealthSection(
        icon: Icons.psychology_outlined,
        title: 'Module IA / Check IA',
        bullets: [
          'Analyse des mesures de santé pour détecter anomalies ou risques : ${_statusLabel(aiEnabled)}',
          'Recommandations personnalisées (nutrition, sommeil, activité) : ${_summarizeList(aiRecommendations, empty: 'Aucune')}',
          'Analyse de documents médicaux ou prescriptions : ${_statusLabel(aiDocAnalysis)}',
          'Alertes automatiques basées sur l’IA : ${_summarizeList(aiAlerts, empty: 'Aucune')}',
        ],
      ),
      _HealthSection(
        icon: Icons.emergency_outlined,
        title: 'Module urgence / SOS',
        bullets: [
          'Position GPS : ${_statusLabel(sosGps)}',
          'Informations médicales essentielles (groupe sanguin, allergies, maladies chroniques) : ${_summaryEssentials(bloodType, allergies, conditions)}',
          'Contact d’urgence : ${_summaryEmergency(emergencyName, emergencyPhone)}',
          'Notifications aux proches ou services médicaux : ${_statusLabel(sosNotif)}',
        ],
      ),
      _HealthSection(
        icon: Icons.video_call_outlined,
        title: 'Téléconsultation',
        bullets: [
          'Chat ou appel vidéo avec un médecin : ${_statusLabel(teleconsult)}',
          'Envoi de documents ou photos pour diagnostic',
          'Réception de prescriptions numériques',
        ],
      ),
      _HealthSection(
        icon: Icons.local_pharmacy_outlined,
        title: 'Pharmacie',
        bullets: [
          'Recherche de médicaments',
          'Localisation des pharmacies proches',
          'Possibilité de commander des médicaments : ${_statusLabel(pharmacy)}',
        ],
      ),
      _HealthSection(
        icon: Icons.notifications_active_outlined,
        title: 'Notifications intelligentes',
        bullets: [
          'Prise de médicaments : ${_statusLabel(medsNotif)}',
          'Rendez-vous médicaux : ${_statusLabel(apptNotif)}',
          'Cycle menstruel : ${_statusLabel(cycleNotif)}',
          'Alertes santé basées sur l’IA : ${_statusLabel(aiNotif)}',
        ],
      ),
      _HealthSection(
        icon: Icons.health_and_safety_outlined,
        title: 'Prévention et conseils santé',
        bullets: [
          'Conseils personnalisés : ${_summarizeList(preventionTips, empty: 'Aucun')}',
          'Alertes vaccination et dépistage : ${_statusLabel(preventionAlerts)}',
          'Suggestions adaptées selon l’âge et les mesures santé : ${_summarizeList(_stringList(health['ageSuggestions']), empty: 'Aucune')}',
        ],
      ),
      _HealthSection(
        icon: Icons.qr_code_2_outlined,
        title: 'QR Code / Carte santé numérique',
        bullets: [
          'QR Code santé pour accès rapide aux informations essentielles : ${qrCodeUrl.isNotEmpty ? 'Disponible' : 'Non généré'}',
          'Contient : ${_summaryEssentials(bloodType, allergies, conditions, emergencyName: emergencyName, emergencyPhone: emergencyPhone)}',
        ],
      ),
      _HealthSection(
        icon: Icons.insert_drive_file_outlined,
        title: 'Historique et rapports',
        bullets: [
          'Historique complet de mesures, cycle, médicaments, rendez-vous : ${_summarizeList(_mergeLists([medicalHistory, cycleHistory, medicationHistory, appointmentHistory]), empty: 'Aucun')}',
          'Export PDF ou partage sécurisé avec médecin : ${reportsPdfUrl.isNotEmpty ? 'Disponible' : 'Non disponible'}',
        ],
      ),
    ];

    final actions = ctx == null
        ? null
        : <VoidCallback?>[
            () => openPage(HealthMetricsPage(contextRef: ctx)),
            () => openPage(HealthProfileEditPage(contextRef: ctx)),
            () => openPage(HealthMedicationsPage(contextRef: ctx)),
            () => openPage(HealthAppointmentsPage(contextRef: ctx)),
            () => openPage(HealthDocumentsPage(contextRef: ctx)),
            () => openPage(HealthMetricsPage(contextRef: ctx)),
            () => openPage(HealthCyclePage(contextRef: ctx)),
            () => openPage(HealthAiPage(contextRef: ctx)),
            () => openPage(HealthProfileEditPage(contextRef: ctx)),
            () => openPage(HealthTeleconsultationPage(contextRef: ctx)),
            () => openPage(HealthPharmacyPage(contextRef: ctx)),
            () => openPage(HealthNotificationsPage(contextRef: ctx)),
            () => openPage(HealthPreventionPage(contextRef: ctx)),
            () => openPage(HealthQrPage(contextRef: ctx)),
            () => openPage(HealthDocumentsPage(contextRef: ctx)),
          ];

    return _FeatureList(
      cardBg: cardBg,
      text: text,
      sub: sub,
      accent: accent,
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

    final aiEnabled = _boolValue(health['aiEnabled'] ?? health['aiHospital']);
    final exportAvailable = _boolValue(health['exportPdfAvailable'] ?? health['exportAvailable']);

    final sections = <_HealthSection>[
      _HealthSection(
        icon: Icons.people_alt_outlined,
        title: 'Liste des patients',
        bullets: [
          'Patients enregistrés : ${patientsCount != null ? patientsCount.toString() : 'Non renseigné'}',
          'Derniers patients : ${_summarizeList(patients, empty: 'Aucun')}',
        ],
      ),
      _HealthSection(
        icon: Icons.history_edu_outlined,
        title: 'Historique médical et documents',
        bullets: [
          'Documents patients : ${patientDocsCount != null ? patientDocsCount.toString() : 'Non renseigné'}',
          'Historique récent : ${_summarizeList(patientDocs, empty: 'Aucun')}',
        ],
      ),
      _HealthSection(
        icon: Icons.calendar_month_outlined,
        title: 'Gestion des rendez-vous et téléconsultations',
        bullets: [
          'Rendez-vous : ${_summarizeList(appts, empty: 'Aucun')}',
          'Téléconsultations : ${_summarizeList(teleconsults, empty: 'Aucune')}',
        ],
      ),
      _HealthSection(
        icon: Icons.analytics_outlined,
        title: 'Module IA pour analyse des mesures santé des patients',
        bullets: [
          'Analyse IA activée : ${_statusLabel(aiEnabled)}',
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
        title: 'Export des données PDF pour suivi médical',
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

    return _FeatureList(
      cardBg: cardBg,
      text: text,
      sub: sub,
      accent: accent,
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
  ) {
    final query = _pharmacyQuery;
    final pharmaciesRef = FirebaseFirestore.instance.collection('health_pharmacies');
    final canAdd = _canAddPharmacy(data);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: _pharmacySearchCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Rechercher un medicament ou une pharmacie',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _nearMeOnly,
                  title: const Text('Pres de moi'),
                  onChanged: (v) async {
                    if (v) {
                      final ok = await _ensureLocation();
                      if (!ok) return;
                    }
                    if (!mounted) return;
                    setState(() => _nearMeOnly = v);
                  },
                ),
              ),
              if (_nearMeOnly)
                DropdownButton<double>(
                  value: _nearMeRadiusKm,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _nearMeRadiusKm = v);
                  },
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2 km')),
                    DropdownMenuItem(value: 5, child: Text('5 km')),
                    DropdownMenuItem(value: 10, child: Text('10 km')),
                  ],
                ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Exporter Excel',
                onPressed: _exportingPharmacies ? null : _exportPharmaciesExcel,
                icon: _exportingPharmacies
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.file_download_outlined),
              ),
              IconButton(
                tooltip: 'Importer Excel',
                onPressed: (!_importingPharmacies && canAdd) ? _importPharmaciesExcel : null,
                icon: _importingPharmacies
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.file_upload_outlined),
              ),
              if (canAdd)
                ElevatedButton.icon(
                  onPressed: _addingPharmacy ? null : () => _openAddPharmacy(accent),
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Ajouter'),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: pharmaciesRef.orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs;
              final filtered = docs.where((d) {
                if (query.isEmpty) return true;
                final data = d.data();
                final name = _safeStr(data['name']).toLowerCase();
                final address = _safeStr(data['address'] ?? data['adresse']).toLowerCase();
                final location = _safeStr(data['location'] ?? data['localisation']).toLowerCase();
                final meds = _stringList(data['medicines'] ?? data['medications'] ?? data['medicaments'])
                    .map((m) => m.toLowerCase())
                    .toList();
                return name.contains(query) ||
                    address.contains(query) ||
                    location.contains(query) ||
                    meds.any((m) => m.contains(query));
              }).where((d) {
                if (!_nearMeOnly) return true;
                final pos = _userPosition;
                if (pos == null) return false;
                final data = d.data();
                final lat = _toDouble(data['lat'] ?? data['latitude']);
                final lng = _toDouble(data['lng'] ?? data['longitude']);
                if (lat == null || lng == null) return false;
                final meters = Geolocator.distanceBetween(
                  pos.latitude,
                  pos.longitude,
                  lat,
                  lng,
                );
                return meters <= _nearMeRadiusKm * 1000;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_pharmacy_outlined, color: accent),
                        const SizedBox(height: 8),
                        Text('Aucune pharmacie', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          _nearMeOnly
                              ? 'Aucune pharmacie trouvee pres de vous.'
                              : 'Ajoutez la premiere pharmacie pour commencer.',
                          style: TextStyle(color: sub),
                        ),
                        if (canAdd) ...[
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _addingPharmacy ? null : () => _openAddPharmacy(accent),
                            child: const Text('Ajouter une pharmacie'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => Divider(color: sub.withOpacity(0.2)),
                itemBuilder: (ctx, i) {
                  final data = filtered[i].data();
                  final name = _safeStr(data['name']);
                  final address = _safeStr(data['address'] ?? data['adresse']);
                  final location = _safeStr(data['location'] ?? data['localisation']);
                  final image = _safeStr(data['photo'] ?? data['image'] ?? data['photoUrl']);
                  final meds = _stringList(data['medicines'] ?? data['medications'] ?? data['medicaments']);
                  final medLabel = meds.isNotEmpty ? meds.take(5).join(', ') : 'Non renseigne';
                  final place = _joinParts([address, location]);
                  final distanceLabel = _distanceLabel(data);
                  final canDelete = canAdd && _canDeletePharmacy(data);
                  return Card(
                    color: cardBg,
                    elevation: 0.6,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: image.isNotEmpty
                                ? Image.network(image, width: 64, height: 64, fit: BoxFit.cover)
                                : Container(
                                    width: 64,
                                    height: 64,
                                    color: accent.withOpacity(0.12),
                                    child: Icon(Icons.local_pharmacy, color: accent),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isNotEmpty ? name : 'Pharmacie',
                                  style: TextStyle(color: text, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  place.isNotEmpty ? place : 'Adresse non renseignee',
                                  style: TextStyle(color: sub),
                                ),
                                if (distanceLabel.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(distanceLabel, style: TextStyle(color: sub)),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  'Medicaments: $medLabel',
                                  style: TextStyle(color: sub),
                                ),
                              ],
                            ),
                          ),
                          if (canDelete)
                            IconButton(
                              onPressed: () => _confirmDeletePharmacy(filtered[i].reference),
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.redAccent,
                              tooltip: 'Supprimer',
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
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
      _safeStr(glycemie).isNotEmpty ? 'glycÃ©mie ${_safeStr(glycemie)}' : 'glycÃ©mie n/d',
      _safeStr(cycle).isNotEmpty ? 'cycle ${_safeStr(cycle)}' : 'cycle n/d',
    ];
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
      _safeStr(glycemie).isNotEmpty ? 'glycÃ©mie ${_safeStr(glycemie)}' : 'glycÃ©mie n/d',
      _safeStr(heartRate).isNotEmpty ? 'FC ${_safeStr(heartRate)}' : 'FC n/d',
      _safeStr(activity).isNotEmpty ? 'activitÃ© ${_safeStr(activity)}' : 'activitÃ© n/d',
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

  

  String _joinParts(List<String> parts) {
    final out = parts.map((p) => _safeStr(p)).where((p) => p.isNotEmpty).toList();
    return out.isEmpty ? '' : out.join(' / ');
  }

  bool _canAddPharmacy(Map<String, dynamic> data) {
    final profileType = data['profileType'];
    if (profileType is int) return profileType == 1 || profileType == 2;
    final raw = _safeStr(profileType);
    if (raw.isEmpty) return false;
    return raw == '1' || raw == '2' || raw.toLowerCase() == 'pro' || raw.toLowerCase() == 'enterprise';
  }

  bool _canDeletePharmacy(Map<String, dynamic> pharmacy) {
    final ownerId = _safeStr(pharmacy['ownerId'] ?? pharmacy['owner']);
    if (ownerId.isEmpty) return true; // legacy entries
    if (_userId == null) return false;
    return ownerId == _userId;
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
      _snack('Pharmacie supprimee');
    } catch (e) {
      _snack('Erreur suppression: $e', error: true);
    }
  }

  String _distanceLabel(Map<String, dynamic> data) {
    if (!_nearMeOnly || _userPosition == null) return '';
    final lat = _toDouble(data['lat'] ?? data['latitude']);
    final lng = _toDouble(data['lng'] ?? data['longitude']);
    if (lat == null || lng == null) return '';
    final meters = Geolocator.distanceBetween(
      _userPosition!.latitude,
      _userPosition!.longitude,
      lat,
      lng,
    );
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
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

  Future<_PhotoPickResult> _pickAndUploadPharmacyPhoto() async {
    if (!SupabaseService.isInitialized) {
      _snack('Supabase non initialise', error: true);
      return const _PhotoPickResult(url: '');
    }
    try {
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
        name = 'pharmacy_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }
      final objectPath = 'health_pharmacies/${_userId ?? 'anonymous'}/${DateTime.now().millisecondsSinceEpoch}_$name';
      final url = await SupabaseService.uploadBytesNamed(
        bytes,
        objectPath,
        'health_pharmacies',
        contentType: _imageContentType(name),
      );
      return _PhotoPickResult(url: url, bytes: bytes);
    } catch (e) {
      _snack('Erreur photo: $e', error: true);
      return const _PhotoPickResult(url: '');
    }
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

  String _cellAt(List<xl.Data?> row, Map<String, int> index, String key) {    final i = index[key];
    if (i == null || i < 0 || i >= row.length) return '';
    return _cellText(row[i]);
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

  Future<void> _openAddPharmacy(Color accent) async {
    if (_addingPharmacy) return;
    setState(() => _addingPharmacy = true);
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final photoCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final medCtrl = TextEditingController();
    final meds = <String>[];
    bool uploadingPhoto = false;
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
                    const Text('Ajouter une pharmacie', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 12),
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom')),
                    TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Adresse')),
                    TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Localisation')),
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
                    if (photoPreview != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(photoPreview!, width: 96, height: 96, fit: BoxFit.cover),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: medCtrl,
                            decoration: const InputDecoration(labelText: 'Medicament'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final v = medCtrl.text.trim();
                            if (v.isEmpty) return;
                            meds.add(v);
                            medCtrl.clear();
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
                      children: meds
                          .map(
                            (m) => Chip(
                              label: Text(m),
                              onDeleted: () {
                                meds.remove(m);
                                setModalState(() {});
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        final lat = double.tryParse(latCtrl.text.replaceAll(',', '.'));
                        final lng = double.tryParse(lngCtrl.text.replaceAll(',', '.'));
                        await FirebaseFirestore.instance.collection('health_pharmacies').add({
                          'name': name,
                          'address': addressCtrl.text.trim(),
                          'location': locationCtrl.text.trim(),
                          'photo': photoCtrl.text.trim(),
                          if (meds.isNotEmpty) 'medicines': meds,
                          if (lat != null) 'lat': lat,
                          if (lng != null) 'lng': lng,
                          if (_userId != null) 'ownerId': _userId,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                        if (mounted) Navigator.of(ctx).pop();
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Enregistrer'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
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
    if (emergency != 'Non renseignÃ©') parts.add('urgence $emergency');
    if (parts.isEmpty) return 'Non renseignÃ©';
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
      if (start.isNotEmpty) parts.add('dÃ©but $start');
      if (duration.isNotEmpty) parts.add('durÃ©e $duration j');
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
  final List<_HealthSection> sections;
  final List<VoidCallback?>? actions;

  const _FeatureList({
    required this.cardBg,
    required this.text,
    required this.sub,
    required this.accent,
    required this.sections,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final s = sections[index];
        final onTap = (actions != null && index < actions!.length) ? actions![index] : null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
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
        );
      },
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: accent.withOpacity(0.15)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...bullets.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(Icons.check_circle, size: 16, color: accent),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          b,
                          style: TextStyle(color: sub, height: 1.35),
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
                    child: const Text('Gerer'),
                  ),
                ),
            ],
          ),
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

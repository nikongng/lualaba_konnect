import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:lualaba_konnect/core/config.dart';
import 'package:lualaba_konnect/core/notification_service.dart';

class TrafficManagementPage extends StatefulWidget {
  const TrafficManagementPage({super.key});

  @override
  State<TrafficManagementPage> createState() => _TrafficManagementPageState();
}

class _TrafficManagementPageState extends State<TrafficManagementPage> {
  static const Color _green = Color(0xFF17A34A);
  static const Color _orange = Color(0xFFFF9800);
  static const Color _red = Color(0xFFE53935);

  final List<_TrafficRouteConfig> _routeConfigs = const [
    _TrafficRouteConfig(
      name: 'Boulevard Lumumba',
      zone: 'Rond-point Mwangeji',
      alternative: 'Avenue des Ecoles -> Boulevard du 30 Juin',
      icon: Icons.alt_route_rounded,
      center: LatLng(-10.7144, 25.4682),
      path: [
        LatLng(-10.7191, 25.4604),
        LatLng(-10.7165, 25.4647),
        LatLng(-10.7144, 25.4682),
        LatLng(-10.7114, 25.4731),
      ],
    ),
    _TrafficRouteConfig(
      name: 'Axe Musompo',
      zone: 'Entree du port sec',
      alternative: 'Contournement Industriel',
      icon: Icons.local_shipping_outlined,
      center: LatLng(-10.7181, 25.4754),
      path: [
        LatLng(-10.7248, 25.4686),
        LatLng(-10.7212, 25.4710),
        LatLng(-10.7181, 25.4754),
        LatLng(-10.7135, 25.4798),
      ],
    ),
    _TrafficRouteConfig(
      name: 'Route Dilala',
      zone: 'Pont de Dilala',
      alternative: 'Avenue Likasi',
      icon: Icons.directions_car_outlined,
      center: LatLng(-10.7170, 25.4585),
      path: [
        LatLng(-10.7230, 25.4497),
        LatLng(-10.7200, 25.4546),
        LatLng(-10.7170, 25.4585),
        LatLng(-10.7132, 25.4651),
      ],
    ),
    _TrafficRouteConfig(
      name: 'Avenue Industrielle',
      zone: 'Zone mines',
      alternative: 'Boulevard Kasaji',
      icon: Icons.location_city_rounded,
      center: LatLng(-10.7215, 25.4826),
      path: [
        LatLng(-10.7278, 25.4867),
        LatLng(-10.7246, 25.4841),
        LatLng(-10.7215, 25.4826),
        LatLng(-10.7167, 25.4790),
      ],
    ),
  ];

  bool _notificationsEnabled = true;
  bool _isAdmin = false;
  bool _adminChecked = false;
  bool _watchAllRoutes = true;
  bool _savingWatchPrefs = false;
  bool _locating = false;
  bool _aiLoading = false;

  final MapController _mapController = MapController();
  final TextEditingController _aiCtrl = TextEditingController(text: 'Je dois aller a Musompo apres 17h');
  final Set<String> _watchedRoutes = <String>{};
  final Map<String, String> _lastRouteAlerts = <String, String>{};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reportSubscription;
  Position? _currentPosition;
  String _aiResponse = '';
  DateTime? _aiGeneratedAt;
  static const LatLng _defaultCenter = LatLng(-10.7167, 25.4729);

  @override
  void initState() {
    super.initState();
    _loadAdminClaim();
    _loadWatcherPrefs();
    _refreshLocation();
    _startTrafficAlertListener();
    unawaited(NotificationService.initLocalOnly());
  }

  @override
  void dispose() {
    _reportSubscription?.cancel();
    _aiCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAdminClaim() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _adminChecked = true);
        return;
      }
      final token = await user.getIdTokenResult(true);
      final claims = token.claims ?? const <String, dynamic>{};
      if (claims['admin'] == true) {
        if (mounted) {
          setState(() {
            _isAdmin = true;
            _adminChecked = true;
          });
        }
        return;
      }
      final snap = await FirebaseFirestore.instance.collection('admin_users').doc(user.uid).get();
      final enabled = snap.exists && (snap.data()?['enabled'] ?? true);
      if (mounted) {
        setState(() {
          _isAdmin = enabled;
          _adminChecked = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _adminChecked = true);
    }
  }

  Future<void> _loadWatcherPrefs() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('traffic_watchers').doc(user.uid).get();
      if (!doc.exists) {
        _watchedRoutes
          ..clear()
          ..addAll(_routeConfigs.map((route) => route.name));
        if (mounted) {
          setState(() {
            _notificationsEnabled = true;
            _watchAllRoutes = true;
          });
        }
        unawaited(_persistWatcherPrefs());
        return;
      }

      final data = doc.data() ?? const <String, dynamic>{};
      final enabled = data['enabled'] != false;
      final allRoutes = data['watchAllRoutes'] != false;
      final watched = (data['watchedRoutes'] is List)
          ? List<String>.from((data['watchedRoutes'] as List).map((e) => e.toString()))
          : _routeConfigs.map((route) => route.name).toList();

      _watchedRoutes
        ..clear()
        ..addAll(watched);

      if (mounted) {
        setState(() {
          _notificationsEnabled = enabled;
          _watchAllRoutes = allRoutes;
        });
      }
    } catch (_) {
      _watchedRoutes
        ..clear()
        ..addAll(_routeConfigs.map((route) => route.name));
    }
  }

  Future<void> _persistWatcherPrefs() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _savingWatchPrefs) return;
    setState(() => _savingWatchPrefs = true);
    try {
      await FirebaseFirestore.instance.collection('traffic_watchers').doc(user.uid).set({
        'uid': user.uid,
        'enabled': _notificationsEnabled,
        'watchAllRoutes': _watchAllRoutes,
        'watchedRoutes': _watchAllRoutes ? _routeConfigs.map((route) => route.name).toList() : _watchedRoutes.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      }, SetOptions(merge: true));
    } finally {
      if (mounted) setState(() => _savingWatchPrefs = false);
    }
  }

  void _toggleRouteWatch(String routeName) {
    setState(() {
      _watchAllRoutes = false;
      if (_watchedRoutes.contains(routeName)) {
        _watchedRoutes.remove(routeName);
      } else {
        _watchedRoutes.add(routeName);
      }
      if (_watchedRoutes.isEmpty) {
        _watchedRoutes.add(routeName);
      }
    });
    unawaited(_persistWatcherPrefs());
  }

  Future<void> _refreshLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _currentPosition = pos;
      if (mounted) {
        setState(() {});
        _mapController.move(LatLng(pos.latitude, pos.longitude), 14.2);
      }
    } catch (_) {
      // best effort only
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _startTrafficAlertListener() {
    _reportSubscription?.cancel();
    _reportSubscription = _reportsStream().listen((snapshot) {
      final reports = snapshot.docs.map(_reportFromDoc).toList();
      final summaries = _buildSummaries(reports);
      _handleLiveTrafficNotifications(summaries);
    });
  }

  Future<void> _handleLiveTrafficNotifications(List<_TrafficRouteSummary> summaries) async {
    final current = <String, String>{};
    for (final summary in summaries) {
      if (summary.severity == 'green') continue;
      current[summary.config.name] = '${summary.severity}|${summary.highlightedZone}|${summary.reportCount}';
    }

    if (_lastRouteAlerts.isEmpty) {
      _lastRouteAlerts.addAll(current);
      return;
    }

    for (final summary in summaries) {
      if (summary.severity == 'green') continue;
      final shouldWatch = _watchAllRoutes || _watchedRoutes.contains(summary.config.name);
      if (!_notificationsEnabled || !shouldWatch) continue;

      final nextKey = current[summary.config.name];
      final previousKey = _lastRouteAlerts[summary.config.name];
      if (nextKey == null || nextKey == previousKey) continue;

      await NotificationService.showNotification(
        'Alerte trafic',
        '${summary.config.name} est ${_severityLabel(summary.severity).toLowerCase()} vers ${summary.highlightedZone}.',
        payload: 'traffic:${summary.config.name}',
        id: NotificationService.stableIdForKey('traffic:${summary.config.name}'),
      );
    }

    _lastRouteAlerts
      ..clear()
      ..addAll(current);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _reportsStream() {
    return FirebaseFirestore.instance.collection('traffic_reports').orderBy('createdAtMs', descending: true).limit(80).snapshots();
  }

  Future<void> _dispatchTrafficPush({
    required String route,
    required String zone,
    required String severity,
    required String cause,
    required String note,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final watcherSnap = await FirebaseFirestore.instance.collection('traffic_watchers').where('enabled', isEqualTo: true).get();
      final recipients = <String>[];
      for (final doc in watcherSnap.docs) {
        if (doc.id == user.uid) continue;
        final data = doc.data();
        final watchAll = data['watchAllRoutes'] != false;
        final watched = (data['watchedRoutes'] is List)
            ? List<String>.from((data['watchedRoutes'] as List).map((e) => e.toString()))
            : const <String>[];
        if (watchAll || watched.contains(route)) {
          recipients.add(doc.id);
        }
      }
      if (recipients.isEmpty) return;

      final title = 'Alerte trafic';
      final body = '$route: ${_severityLabel(severity)} vers $zone. ${cause.trim()}';
      final cleanNote = note.trim();
      final senderName = (user.displayName ?? '').trim().isNotEmpty ? (user.displayName ?? '').trim() : 'Lualaba Konnect';
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      const batchLimit = 450;
      for (int i = 0; i < recipients.length; i += batchLimit) {
        final batch = FirebaseFirestore.instance.batch();
        final chunk = recipients.sublist(i, (i + batchLimit) > recipients.length ? recipients.length : i + batchLimit);
        for (final toUid in chunk) {
          final ref = FirebaseFirestore.instance.collection('notifications').doc();
          batch.set(ref, {
            'toUserId': toUid,
            'fromUserId': user.uid,
            'fromName': senderName,
            'fromAvatar': user.photoURL ?? '',
            'type': 'traffic_alert',
            'text': cleanNote.isEmpty ? body : '$body\n$cleanNote',
            'route': route,
            'zone': zone,
            'severity': severity,
            'seen': false,
            'createdAt': FieldValue.serverTimestamp(),
            'createdAtMs': nowMs,
          });
        }
        await batch.commit();
      }

      final idToken = await user.getIdToken();
      const pushChunk = 80;
      for (int i = 0; i < recipients.length; i += pushChunk) {
        final chunk = recipients.sublist(i, (i + pushChunk) > recipients.length ? recipients.length : i + pushChunk);
        await http.post(
          Uri.parse(kNotifierUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'recipients': chunk,
            'title': title,
            'body': cleanNote.isEmpty ? body : '$body\n$cleanNote',
            'senderAvatarUrl': (user.photoURL ?? '').trim(),
            'imageUrl': '',
            'data': {
              'type': 'traffic_alert',
              'route': route,
              'zone': zone,
              'severity': severity,
            },
          }),
        );
      }
    } catch (_) {
      // Traffic alerts should not block reporting flow.
    }
  }

  Future<void> _runTrafficAiAnalysis({
    required List<_TrafficRouteSummary> summaries,
    required List<_TrafficReport> reports,
  }) async {
    if (_aiLoading) return;
    final apiKey = dotenv.maybeGet('GEMINI_API_KEY') ?? '';
    if (apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GEMINI_API_KEY manquant pour l assistant IA.')),
      );
      return;
    }

    setState(() => _aiLoading = true);
    try {
      final activeReports = reports.where((report) => !report.isFalseReport && report.status != 'false_report').take(10).toList();
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      final target = _aiCtrl.text.trim().isEmpty ? 'un trajet general en ville' : _aiCtrl.text.trim();
      final prompt = [
        'Tu es un assistant trafic urbain pour Kolwezi.',
        'Reponds en francais simple et utile.',
        'Donne:',
        '1. un resume de la situation',
        '2. le meilleur itineraire ou la meilleure option pour cet objectif: $target',
        '3. les heures ou zones a eviter',
        '4. si un signalement semble fragile ou a confirmer',
        '5. une recommendation finale en 1 phrase',
        '',
        'Etat des routes:',
        ...summaries.map(
          (summary) => '- ${summary.config.name}: ${_severityLabel(summary.severity)}, zone=${summary.highlightedZone}, signalements=${summary.reportCount}, alternative=${summary.config.alternative}',
        ),
        '',
        'Signalements recents:',
        ...activeReports.map(
          (report) => '- ${report.route} | ${report.zone} | ${_severityLabel(report.severity)} | ${report.cause} | statut=${_statusLabel(report.status)} | note=${report.note.isEmpty ? 'aucune' : report.note}',
        ),
      ].join('\n');

      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? 'Aucune reponse IA disponible pour le moment.';
      if (mounted) {
        setState(() {
          _aiResponse = text;
          _aiGeneratedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur IA trafic: $e')),
      );
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required Color sub,
    required Color divider,
    required bool isDark,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: sub, fontWeight: FontWeight.w700),
      filled: true,
      fillColor: isDark ? Colors.white10 : const Color(0xFFF8FAFC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
    );
  }

  _TrafficReport _reportFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return _TrafficReport(
      id: doc.id,
      route: _stringValue(data['route'], _routeConfigs.first.name),
      zone: _stringValue(data['zone'], 'Zone non precisee'),
      severity: _normalizeSeverity(data['severity']),
      cause: _stringValue(data['cause'], 'Bouchon'),
      note: _stringValue(data['note']),
      reporterName: _stringValue(data['reporterName'], 'Utilisateur'),
      status: _stringValue(data['status'], 'pending'),
      isFalseReport: _boolValue(data['isFalseReport']),
      routeClosed: _boolValue(data['routeClosed']),
      createdAt: _dateValue(data['createdAt'], data['createdAtMs']),
    );
  }

  List<_TrafficRouteSummary> _buildSummaries(List<_TrafficReport> reports) {
    final now = DateTime.now();
    final active = reports.where((report) {
      if (report.isFalseReport || report.status == 'false_report') return false;
      return now.difference(report.createdAt) <= const Duration(hours: 6);
    }).toList();

    return _routeConfigs.map((config) {
      final routeReports = active.where((report) => report.route == config.name).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      var severity = 'green';
      for (final report in routeReports) {
        if (_severityWeight(report.severity) > _severityWeight(severity)) {
          severity = report.severity;
        }
      }

      return _TrafficRouteSummary(
        config: config,
        severity: severity,
        reportCount: routeReports.length,
        highlightedZone: routeReports.isNotEmpty ? routeReports.first.zone : config.zone,
        hasPending: routeReports.any((report) => report.status == 'pending'),
        hasClosure: routeReports.any((report) => report.routeClosed),
        reports: routeReports,
      );
    }).toList();
  }

  List<_TrafficRouteSummary> _congestedRoutes(List<_TrafficRouteSummary> summaries) {
    final items = summaries.where((summary) => summary.severity != 'green').toList();
    items.sort((a, b) {
      final severityCompare = _severityWeight(b.severity).compareTo(_severityWeight(a.severity));
      if (severityCompare != 0) return severityCompare;
      return b.reportCount.compareTo(a.reportCount);
    });
    return items;
  }

  List<_TrafficReport> _pendingReports(List<_TrafficReport> reports) {
    return reports.where((report) => !report.isFalseReport && report.status == 'pending').take(5).toList();
  }

  _TrafficStats _buildStats(List<_TrafficReport> reports, List<_TrafficRouteSummary> summaries) {
    final recent = reports.where((report) => !report.isFalseReport).toList();
    final now = DateTime.now();
    final weekly = recent.where((report) => now.difference(report.createdAt) <= const Duration(days: 7)).toList();

    final hours = <int, int>{};
    final routes = <String, int>{};
    final dangerZones = <String, int>{};

    for (final report in weekly) {
      hours.update(report.createdAt.hour, (value) => value + 1, ifAbsent: () => 1);
      routes.update(report.route, (value) => value + 1, ifAbsent: () => 1);
      if (report.severity == 'red') {
        dangerZones.update(report.zone, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    final peakHour = _topEntry(hours);
    final topRoute = _topEntry(routes);
    final topDangerZone = _topEntry(dangerZones);
    final redRoutes = summaries.where((summary) => summary.severity == 'red').length;
    final alerts = summaries.where((summary) => summary.severity != 'green').length;
    final peakLabel = peakHour == null
        ? 'Aucune tendance'
        : '${peakHour.key.toString().padLeft(2, '0')}h - ${((peakHour.key + 1) % 24).toString().padLeft(2, '0')}h';

    return _TrafficStats(
      activeAlerts: alerts,
      redRoutes: redRoutes,
      peakHours: peakLabel,
      busiestRoute: topRoute?.key ?? 'Aucune route critique',
      dangerousZone: topDangerZone?.key ?? 'Aucune zone rouge',
    );
  }

  MapEntry<T, int>? _topEntry<T>(Map<T, int> source) {
    if (source.isEmpty) return null;
    final entries = source.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.first;
  }

  DateTime _dateValue(dynamic timestamp, dynamic milliseconds) {
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is DateTime) return timestamp;
    if (milliseconds is int) return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    if (milliseconds is num) return DateTime.fromMillisecondsSinceEpoch(milliseconds.toInt());
    return DateTime.now();
  }

  String _stringValue(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  bool _boolValue(dynamic value) {
    return value == true || value == 1 || value == '1' || value == 'true' || value == 'True';
  }

  String _normalizeSeverity(dynamic value) {
    final raw = _stringValue(value, 'orange').toLowerCase();
    if (raw == 'green' || raw == 'orange' || raw == 'red') return raw;
    return 'orange';
  }

  int _severityWeight(String severity) {
    switch (severity) {
      case 'red':
        return 3;
      case 'orange':
        return 2;
      default:
        return 1;
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'red':
        return _red;
      case 'orange':
        return _orange;
      default:
        return _green;
    }
  }

  String _severityLabel(String severity) {
    switch (severity) {
      case 'red':
        return 'Rouge';
      case 'orange':
        return 'Orange';
      default:
        return 'Vert';
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'confirmed':
        return 'Valide';
      case 'false_report':
        return 'Faux signalement';
      default:
        return 'En attente';
    }
  }

  String _formatDate(DateTime value) => DateFormat('dd/MM - HH:mm').format(value);

  Future<void> _openReportSheet() async {
    final formKey = GlobalKey<FormState>();
    final zoneCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String route = _routeConfigs.first.name;
    String severity = 'orange';
    String cause = 'Bouchon dense';
    bool routeClosed = false;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF111B21) : Colors.white;
        final text = isDark ? const Color(0xFFEAF0F6) : const Color(0xFF102033);
        final sub = isDark ? const Color(0xFF9EB0BF) : const Color(0xFF64748B);
        final divider = isDark ? Colors.white12 : const Color(0xFFE2E8F0);

        Future<void> submit(StateSetter setModal) async {
          if (saving) return;
          if (!(formKey.currentState?.validate() ?? false)) return;
          setModal(() => saving = true);
          try {
            final user = FirebaseAuth.instance.currentUser;
            await FirebaseFirestore.instance.collection('traffic_reports').add({
              'route': route,
              'zone': zoneCtrl.text.trim(),
              'severity': severity,
              'cause': cause,
              'note': noteCtrl.text.trim(),
              'routeClosed': routeClosed,
              'status': 'pending',
              'isFalseReport': false,
              'createdAt': FieldValue.serverTimestamp(),
              'createdAtMs': DateTime.now().millisecondsSinceEpoch,
              'createdByUid': user?.uid,
              'reporterName': user?.displayName ?? user?.email ?? 'Utilisateur',
            });
            if (severity == 'orange' || severity == 'red') {
              await _dispatchTrafficPush(
                route: route,
                zone: zoneCtrl.text.trim(),
                severity: severity,
                cause: cause,
                note: noteCtrl.text.trim(),
              );
            }
            if (!mounted) return;
            Navigator.pop(sheetContext);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Signalement envoye. Les alertes trafic ont ete mises a jour.')),
            );
          } catch (e) {
            setModal(() => saving = false);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Impossible d envoyer le signalement: $e')),
            );
          }
        }

        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModal) {
              return DraggableScrollableSheet(
                initialChildSize: 0.88,
                minChildSize: 0.55,
                maxChildSize: 0.96,
                expand: false,
                builder: (context, controller) {
                  return Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: divider),
                    ),
                    child: ListView(
                      controller: controller,
                      padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
                      children: [
                        Center(
                          child: Container(
                            width: 48,
                            height: 4,
                            margin: const EdgeInsets.only(top: 4, bottom: 12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.black12,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Signaler un embouteillage',
                                style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                            ),
                            IconButton(
                              onPressed: saving ? null : () => Navigator.pop(sheetContext),
                              icon: Icon(Icons.close, color: sub),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Les utilisateurs peuvent signaler une route dense, un axe bloque ou une zone dangereuse.',
                          style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
                        Form(
                          key: formKey,
                          child: Column(
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: route,
                                decoration: _inputDecoration(label: 'Route', sub: sub, divider: divider, isDark: isDark),
                                items: _routeConfigs
                                    .map((config) => DropdownMenuItem<String>(value: config.name, child: Text(config.name)))
                                    .toList(),
                                onChanged: saving ? null : (value) => setModal(() => route = value ?? route),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: zoneCtrl,
                                style: TextStyle(color: text, fontWeight: FontWeight.w700),
                                decoration: _inputDecoration(label: 'Zone bloquee / repere', sub: sub, divider: divider, isDark: isDark),
                                validator: (value) => (value == null || value.trim().isEmpty) ? 'Zone requise' : null,
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: severity,
                                decoration: _inputDecoration(label: 'Niveau de trafic', sub: sub, divider: divider, isDark: isDark),
                                items: const [
                                  DropdownMenuItem(value: 'green', child: Text('Vert - circulation fluide')),
                                  DropdownMenuItem(value: 'orange', child: Text('Orange - trafic dense')),
                                  DropdownMenuItem(value: 'red', child: Text('Rouge - congestion forte')),
                                ],
                                onChanged: saving ? null : (value) => setModal(() => severity = value ?? severity),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: cause,
                                decoration: _inputDecoration(label: 'Cause probable', sub: sub, divider: divider, isDark: isDark),
                                items: const [
                                  DropdownMenuItem(value: 'Bouchon dense', child: Text('Bouchon dense')),
                                  DropdownMenuItem(value: 'Accident', child: Text('Accident')),
                                  DropdownMenuItem(value: 'Travaux', child: Text('Travaux')),
                                  DropdownMenuItem(value: 'Camion en panne', child: Text('Camion en panne')),
                                  DropdownMenuItem(value: 'Inondation / pluie', child: Text('Inondation / pluie')),
                                  DropdownMenuItem(value: 'Manifestation', child: Text('Manifestation')),
                                ],
                                onChanged: saving ? null : (value) => setModal(() => cause = value ?? cause),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: noteCtrl,
                                maxLines: 4,
                                style: TextStyle(color: text, fontWeight: FontWeight.w700),
                                decoration: _inputDecoration(label: 'Detail ou contexte', sub: sub, divider: divider, isDark: isDark),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                value: routeClosed,
                                onChanged: saving ? null : (value) => setModal(() => routeClosed = value),
                                title: Text('Route momentanement bloquee', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                                subtitle: Text('Activez si la circulation est presque impossible.', style: TextStyle(color: sub)),
                                activeThumbColor: _red,
                                contentPadding: EdgeInsets.zero,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton.icon(
                                  onPressed: saving ? null : () => submit(setModal),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F8A5F),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  ),
                                  icon: saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : const Icon(Icons.warning_amber_rounded),
                                  label: Text(
                                    saving ? 'Envoi en cours...' : 'Publier le signalement',
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );

    zoneCtrl.dispose();
    noteCtrl.dispose();
  }

  Future<void> _moderateReport(_TrafficReport report, {required bool markFalse}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous pour moderer un signalement.')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('traffic_reports').doc(report.id).update({
        'status': markFalse ? 'false_report' : 'confirmed',
        'isFalseReport': markFalse,
        'moderatedAt': FieldValue.serverTimestamp(),
        'moderatedAtMs': DateTime.now().millisecondsSinceEpoch,
        'moderatedByUid': user.uid,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(markFalse ? 'Signalement marque comme faux.' : 'Signalement confirme.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moderation impossible: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF081117) : const Color(0xFFF4F7FB);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final cardAlt = isDark ? const Color(0xFF102331) : const Color(0xFFEFF6FF);
    final text = isDark ? const Color(0xFFEAF0F6) : const Color(0xFF102033);
    final sub = isDark ? const Color(0xFF9EB0BF) : const Color(0xFF64748B);
    final divider = isDark ? Colors.white12 : const Color(0xFFE2E8F0);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reportsStream(),
      builder: (context, snapshot) {
        final reports = snapshot.hasData ? snapshot.data!.docs.map(_reportFromDoc).toList() : <_TrafficReport>[];
        final summaries = _buildSummaries(reports);
        final congestedRoutes = _congestedRoutes(summaries);
        final pendingReports = _pendingReports(reports);
        final stats = _buildStats(reports, summaries);
        final highlightedRoute = congestedRoutes.isNotEmpty ? congestedRoutes.first : null;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            foregroundColor: text,
            title: const Text('Gestion des embouteillages'),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openReportSheet,
            backgroundColor: const Color(0xFF0F8A5F),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Signaler'),
          ),
          body: snapshot.hasError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Impossible de charger le trafic en direct pour le moment.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                  children: [
                    _buildHeroCard(card: card, cardAlt: cardAlt, text: text, sub: sub, stats: stats, pendingCount: pendingReports.length),
                    const SizedBox(height: 16),
                    _buildLiveMapCard(card: card, text: text, sub: sub, summaries: summaries),
                    const SizedBox(height: 16),
                    _buildSectionTitle(title: 'Routes et niveaux de trafic', subtitle: 'Vert, orange et rouge pour suivre les zones bloquees.', text: text, sub: sub),
                    const SizedBox(height: 10),
                    ...summaries.map(
                      (summary) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildRouteCard(summary: summary, card: card, text: text, sub: sub, divider: divider),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildNotificationsCard(card: card, text: text, sub: sub, highlightedRoute: highlightedRoute),
                    const SizedBox(height: 16),
                    _buildSectionTitle(title: 'Itineraires alternatifs', subtitle: 'Des options rapides quand une route devient congestionnee.', text: text, sub: sub),
                    const SizedBox(height: 10),
                    _buildAlternativeRoutesCard(card: card, text: text, sub: sub, congestedRoutes: congestedRoutes),
                    const SizedBox(height: 16),
                    _buildSectionTitle(title: 'Assistant IA trafic', subtitle: 'Analyse en direct des signalements pour recommander le meilleur passage.', text: text, sub: sub),
                    const SizedBox(height: 10),
                    _buildAiAssistantCard(card: card, text: text, sub: sub, summaries: summaries, reports: reports),
                    const SizedBox(height: 16),
                    _buildSectionTitle(title: 'Historique des bouchons', subtitle: 'Trace recente des signalements, validations et alertes.', text: text, sub: sub),
                    const SizedBox(height: 10),
                    _buildHistoryCard(card: card, text: text, sub: sub, reports: reports),
                    const SizedBox(height: 16),
                    _buildSectionTitle(title: 'Administration et moderation', subtitle: 'Validation des signalements et filtrage des faux retours.', text: text, sub: sub),
                    const SizedBox(height: 10),
                    _buildModerationCard(card: card, text: text, sub: sub, divider: divider, pendingReports: pendingReports),
                    const SizedBox(height: 16),
                    _buildSectionTitle(title: 'Statistiques trafic', subtitle: 'Heures de pointe, routes bloquees et zones dangereuses.', text: text, sub: sub),
                    const SizedBox(height: 10),
                    _buildStatsCard(card: card, text: text, sub: sub, stats: stats),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildHeroCard({
    required Color card,
    required Color cardAlt,
    required Color text,
    required Color sub,
    required _TrafficStats stats,
    required int pendingCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Centre de gestion trafic', style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(
                      'Carte en direct, signalements utilisateurs, moderation et statistiques.',
                      style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: cardAlt, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF00C853), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text('Live', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Alertes actives',
                  value: '${stats.activeAlerts}',
                  color: const Color(0xFFDBEAFE),
                  accent: const Color(0xFF2563EB),
                  text: text,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  label: 'Routes rouges',
                  value: '${stats.redRoutes}',
                  color: const Color(0xFFFEE2E2),
                  accent: _red,
                  text: text,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  label: 'A moderer',
                  value: '$pendingCount',
                  color: const Color(0xFFFFEDD5),
                  accent: _orange,
                  text: text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color color,
    required Color accent,
    required Color text,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(color: accent, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: text, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildLiveMapCard({
    required Color card,
    required Color text,
    required Color sub,
    required List<_TrafficRouteSummary> summaries,
  }) {
    final center = _currentPosition == null ? _defaultCenter : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Carte en direct', style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w900))),
              if (_locating)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton.icon(onPressed: _refreshLocation, icon: const Icon(Icons.my_location_rounded, size: 18), label: const Text('Me localiser')),
            ],
          ),
          Text('Carte OpenStreetMap dynamique avec position actuelle, marqueurs d alertes et routes colorees.', style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 320,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 13.2,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.lualaba.konnect.app',
                  ),
                  PolylineLayer(polylines: _buildTrafficPolylines(summaries)),
                  MarkerLayer(markers: _buildTrafficMarkers(summaries)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: summaries
                .map(
                  (summary) => ActionChip(
                    backgroundColor: _severityColor(summary.severity).withOpacity(0.12),
                    avatar: Icon(summary.config.icon, color: _severityColor(summary.severity), size: 18),
                    label: Text(summary.config.name),
                    onPressed: () => _mapController.move(summary.config.center, 14.6),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LegendRow(
                color: _green,
                label: 'Vert',
                description: 'Circulation fluide',
                textColor: text,
              ),
              _LegendRow(
                color: _orange,
                label: 'Orange',
                description: 'Trafic dense, ralentissements',
                textColor: text,
              ),
              _LegendRow(
                color: _red,
                label: 'Rouge',
                description: 'Congestion forte, route a eviter',
                textColor: text,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Polyline> _buildTrafficPolylines(List<_TrafficRouteSummary> summaries) {
    return summaries
        .map(
          (summary) => Polyline(
            points: summary.config.path,
            strokeWidth: 6,
            color: _severityColor(summary.severity).withOpacity(0.92),
            borderColor: Colors.white.withOpacity(0.85),
            borderStrokeWidth: 1.2,
          ),
        )
        .toList();
  }

  List<Marker> _buildTrafficMarkers(List<_TrafficRouteSummary> summaries) {
    final markers = <Marker>[
      for (final summary in summaries)
        Marker(
          point: summary.config.center,
          width: 140,
          height: 62,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 8))],
              border: Border.all(color: _severityColor(summary.severity).withOpacity(0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _severityColor(summary.severity), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summary.config.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  summary.highlightedZone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
    ];

    if (_currentPosition != null) {
      markers.add(
        Marker(
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          width: 26,
          height: 26,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.3), blurRadius: 12)],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildMapRoad({
    required _TrafficRouteSummary summary,
    required double left,
    required double top,
    required double length,
    bool vertical = false,
    double angle = 0,
  }) {
    final color = _severityColor(summary.severity);
    final road = Container(
      width: vertical ? 12 : length,
      height: vertical ? length : 12,
      decoration: BoxDecoration(
        color: color.withOpacity(0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 6))],
      ),
    );

    return Positioned(left: left, top: top, child: Transform.rotate(angle: angle, child: road));
  }

  Widget _buildMapLabel({
    required _TrafficRouteSummary summary,
    required double left,
    required double top,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 152),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.34),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              summary.config.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: _severityColor(summary.severity), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    summary.highlightedZone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle({
    required String title,
    required String subtitle,
    required Color text,
    required Color sub,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildRouteCard({
    required _TrafficRouteSummary summary,
    required Color card,
    required Color text,
    required Color sub,
    required Color divider,
  }) {
    final color = _severityColor(summary.severity);
    final progress = summary.severity == 'red'
        ? 1.0
        : summary.severity == 'orange'
            ? 0.65
            : 0.25;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(22), border: Border.all(color: divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(16)),
                child: Icon(summary.config.icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary.config.name, style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(summary.highlightedZone, style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
                child: Text(_severityLabel(summary.severity), style: TextStyle(color: color, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: progress, minHeight: 9, color: color, backgroundColor: color.withOpacity(0.12)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TrafficBadge(label: '${summary.reportCount} signalement(s)', color: text, background: const Color(0xFFEEF2FF)),
              if (summary.hasPending)
                _TrafficBadge(label: 'A confirmer', color: const Color(0xFF9A6700), background: const Color(0xFFFFF4D6)),
              if (summary.hasClosure)
                _TrafficBadge(label: 'Zone bloquee', color: _red, background: const Color(0xFFFDE8E8)),
            ],
          ),
          const SizedBox(height: 10),
          Text('Itineraire alternatif: ${summary.config.alternative}', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildNotificationsCard({
    required Color card,
    required Color text,
    required Color sub,
    required _TrafficRouteSummary? highlightedRoute,
  }) {
    final selectedRoutes = _watchAllRoutes ? _routeConfigs.map((route) => route.name).toSet() : _watchedRoutes;
    final routeMessage = highlightedRoute == null
        ? 'Aucune route n est actuellement congestionnee. Les notifications restent en veille.'
        : '${highlightedRoute.config.name} devient ${_severityLabel(highlightedRoute.severity).toLowerCase()} vers ${highlightedRoute.highlightedZone}.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Notification de congestion', style: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w900))),
              Switch(
                value: _notificationsEnabled,
                onChanged: (value) {
                  setState(() => _notificationsEnabled = value);
                  unawaited(_persistWatcherPrefs());
                },
              ),
            ],
          ),
          Text('Notifications locales + push OneSignal pour les routes que vous suivez.', style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _notificationsEnabled ? const Color(0xFFEEF6FF) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(
                  _notificationsEnabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                  color: _notificationsEnabled ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _notificationsEnabled ? routeMessage : 'Notifications desactivees. Activez-les pour recevoir les alertes trafic.',
                    style: TextStyle(color: text, fontWeight: FontWeight.w700),
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
              FilterChip(
                selected: _watchAllRoutes,
                label: const Text('Toutes les routes'),
                onSelected: (value) {
                  setState(() {
                    _watchAllRoutes = true;
                    _watchedRoutes
                      ..clear()
                      ..addAll(_routeConfigs.map((route) => route.name));
                  });
                  unawaited(_persistWatcherPrefs());
                },
              ),
              ..._routeConfigs.map(
                (route) => FilterChip(
                  selected: selectedRoutes.contains(route.name),
                  label: Text(route.name),
                  onSelected: (_) => _toggleRouteWatch(route.name),
                ),
              ),
            ],
          ),
          if (_savingWatchPrefs) ...[
            const SizedBox(height: 8),
            Text('Sauvegarde des preferences...', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  Widget _buildAlternativeRoutesCard({
    required Color card,
    required Color text,
    required Color sub,
    required List<_TrafficRouteSummary> congestedRoutes,
  }) {
    final suggestions = congestedRoutes.isEmpty ? _routeConfigs.take(2).toList() : congestedRoutes.map((item) => item.config).take(3).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: suggestions
            .map(
              (config) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(18)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.map_outlined, color: Color(0xFF0284C7)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(config.name, style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text('Alternative proposee: ${config.alternative}', style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildAiAssistantCard({
    required Color card,
    required Color text,
    required Color sub,
    required List<_TrafficRouteSummary> summaries,
    required List<_TrafficReport> reports,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divider = isDark ? Colors.white12 : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Conseiller IA', style: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w900)),
              ),
              ElevatedButton.icon(
                onPressed: _aiLoading ? null : () => _runTrafficAiAnalysis(summaries: summaries, reports: reports),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _aiLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                      )
                    : const Icon(Icons.psychology_outlined, size: 18),
                label: Text(_aiLoading ? 'Analyse...' : 'Analyser'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Indiquez votre trajet ou votre objectif. L IA synthese les bouchons en direct et conseille un passage plus sur.',
            style: TextStyle(color: sub, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _aiCtrl,
            minLines: 2,
            maxLines: 3,
            decoration: _inputDecoration(
              label: 'Ex: Je dois aller au centre-ville avant 18h',
              sub: sub,
              divider: divider,
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(label: const Text('Vers Musompo'), onPressed: () => _aiCtrl.text = 'Je dois aller a Musompo apres 17h'),
              ActionChip(label: const Text('Retour centre'), onPressed: () => _aiCtrl.text = 'Quel est le meilleur retour vers le centre maintenant ?'),
              ActionChip(label: const Text('Eviter route rouge'), onPressed: () => _aiCtrl.text = 'Propose-moi un trajet qui evite les routes rouges'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: divider),
            ),
            child: Text(
              _aiResponse.isEmpty
                  ? 'L assistant IA peut resumer la situation, proposer une route alternative et signaler les alertes a confirmer.'
                  : _aiResponse,
              style: TextStyle(color: _aiResponse.isEmpty ? sub : text, height: 1.5, fontWeight: _aiResponse.isEmpty ? FontWeight.w600 : FontWeight.w700),
            ),
          ),
          if (_aiGeneratedAt != null) ...[
            const SizedBox(height: 8),
            Text('Derniere analyse: ${_formatDate(_aiGeneratedAt!)}', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryCard({
    required Color card,
    required Color text,
    required Color sub,
    required List<_TrafficReport> reports,
  }) {
    final history = reports.take(8).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24)),
      child: history.isEmpty
          ? Text(
              'Aucun historique pour le moment. Les nouveaux signalements apparaitront ici.',
              style: TextStyle(color: sub, fontWeight: FontWeight.w600),
            )
          : Column(
              children: history
                  .map(
                    (report) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: _severityColor(report.severity), shape: BoxShape.circle),
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
                                        '${report.route} • ${report.zone}',
                                        style: TextStyle(color: text, fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                    Text(_formatDate(report.createdAt), style: TextStyle(color: sub, fontWeight: FontWeight.w600, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text('${report.cause} par ${report.reporterName}', style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
                                if (report.note.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(report.note, style: TextStyle(color: sub)),
                                ],
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _TrafficBadge(
                                      label: _severityLabel(report.severity),
                                      color: _severityColor(report.severity),
                                      background: _severityColor(report.severity).withOpacity(0.12),
                                    ),
                                    _TrafficBadge(
                                      label: _statusLabel(report.status),
                                      color: const Color(0xFF334155),
                                      background: const Color(0xFFE2E8F0),
                                    ),
                                    if (report.routeClosed)
                                      _TrafficBadge(label: 'Blocage fort', color: _red, background: const Color(0xFFFDE8E8)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildModerationCard({
    required Color card,
    required Color text,
    required Color sub,
    required Color divider,
    required List<_TrafficReport> pendingReports,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24), border: Border.all(color: divider)),
      child: !_adminChecked
          ? Row(
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text('Verification des droits de moderation...', style: TextStyle(color: sub, fontWeight: FontWeight.w600))),
              ],
            )
          : !_isAdmin
              ? Text(
                  'Les admins peuvent valider les embouteillages reels et annuler les faux signalements.',
                  style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                )
              : pendingReports.isEmpty
                  ? Text('Aucun signalement en attente de moderation.', style: TextStyle(color: sub, fontWeight: FontWeight.w600))
                  : Column(
                      children: pendingReports
                          .map(
                            (report) => Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(18)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${report.route} • ${report.zone}', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${report.cause} | ${report.reporterName} | ${_formatDate(report.createdAt)}',
                                    style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                                  ),
                                  if (report.note.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(report.note, style: TextStyle(color: sub)),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () => _moderateReport(report, markFalse: true),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _red,
                                            side: BorderSide(color: _red.withOpacity(0.25)),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          ),
                                          child: const Text('Faux'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () => _moderateReport(report, markFalse: false),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF0F8A5F),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          ),
                                          child: const Text('Valider'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
    );
  }

  Widget _buildStatsCard({
    required Color card,
    required Color text,
    required Color sub,
    required _TrafficStats stats,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(24)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: width,
                child: _StatCard(
                  title: 'Heures de pointe',
                  value: stats.peakHours,
                  icon: Icons.access_time_rounded,
                  color: const Color(0xFF2563EB),
                  text: text,
                  sub: sub,
                ),
              ),
              SizedBox(
                width: width,
                child: _StatCard(
                  title: 'Route la plus bloquee',
                  value: stats.busiestRoute,
                  icon: Icons.alt_route_rounded,
                  color: _orange,
                  text: text,
                  sub: sub,
                ),
              ),
              SizedBox(
                width: width,
                child: _StatCard(
                  title: 'Zone dangereuse',
                  value: stats.dangerousZone,
                  icon: Icons.place_outlined,
                  color: _red,
                  text: text,
                  sub: sub,
                ),
              ),
              SizedBox(
                width: width,
                child: _StatCard(
                  title: 'Alertes actives',
                  value: '${stats.activeAlerts}',
                  icon: Icons.query_stats_rounded,
                  color: const Color(0xFF0F8A5F),
                  text: text,
                  sub: sub,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrafficRouteConfig {
  final String name;
  final String zone;
  final String alternative;
  final IconData icon;
  final LatLng center;
  final List<LatLng> path;

  const _TrafficRouteConfig({
    required this.name,
    required this.zone,
    required this.alternative,
    required this.icon,
    required this.center,
    required this.path,
  });
}

class _TrafficReport {
  final String id;
  final String route;
  final String zone;
  final String severity;
  final String cause;
  final String note;
  final String reporterName;
  final String status;
  final bool isFalseReport;
  final bool routeClosed;
  final DateTime createdAt;

  const _TrafficReport({
    required this.id,
    required this.route,
    required this.zone,
    required this.severity,
    required this.cause,
    required this.note,
    required this.reporterName,
    required this.status,
    required this.isFalseReport,
    required this.routeClosed,
    required this.createdAt,
  });
}

class _TrafficRouteSummary {
  final _TrafficRouteConfig config;
  final String severity;
  final int reportCount;
  final String highlightedZone;
  final bool hasPending;
  final bool hasClosure;
  final List<_TrafficReport> reports;

  const _TrafficRouteSummary({
    required this.config,
    required this.severity,
    required this.reportCount,
    required this.highlightedZone,
    required this.hasPending,
    required this.hasClosure,
    required this.reports,
  });
}

class _TrafficStats {
  final int activeAlerts;
  final int redRoutes;
  final String peakHours;
  final String busiestRoute;
  final String dangerousZone;

  const _TrafficStats({
    required this.activeAlerts,
    required this.redRoutes,
    required this.peakHours,
    required this.busiestRoute,
    required this.dangerousZone,
  });
}

class _TrafficBadge extends StatelessWidget {
  const _TrafficBadge({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    this.description = '',
    this.textColor = Colors.white,
  });

  final Color color;
  final String label;
  final String description;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 12)),
          if (description.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(description, style: TextStyle(color: textColor.withOpacity(0.78), fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.text,
    required this.sub,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color text;
  final Color sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

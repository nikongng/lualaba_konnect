
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:lualaba_konnect/core/config.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:lualaba_konnect/core/supabase_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:url_launcher/url_launcher.dart';

class RealEstateManagementPage extends StatefulWidget {
  const RealEstateManagementPage({
    super.key,
    this.initialTabIndex = 0,
    this.initialHouseId,
  });

  final int initialTabIndex;
  final String? initialHouseId;

  @override
  State<RealEstateManagementPage> createState() =>
      _RealEstateManagementPageState();
}

class _RealEstateManagementPageState extends State<RealEstateManagementPage> {
  static const Color _accent = Color(0xFFFB8C00);
  static const Color _ctaBlue = Color(0xFF2D6BFF);
  static const String _housesTable = 'gestion_immo_houses';
  static const String _tenantsTable = 'gestion_immo_tenants';
  static const String _immoBucket = 'gestion_immo';
  static const String _tenantPaidMonthColumn = 'rent_paid_month';
  static const String _immoAlertSubscribersCollection =
      'immo_house_alert_subscribers';
  static const String _rentPaymentsCollection = 'immo_rent_payments';

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _rentSearchCtrl = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  String _searchQuery = '';
  String _selectedQuartier = 'Tous';
  String _selectedPrice = 'Tous';
  String _selectedBedrooms = 'Tous';
  _HousingStatus? _selectedStatus;
  String _rentDashboardMonthKey = '';
  String _rentFilter = 'all';
  String _rentSearchQuery = '';
  int _rentDueDay = 5;
  bool _lateRentAlertsEnabled = true;
  bool _lateRentNotifBusy = false;
  bool _loadingRemote = false;
  bool _syncingRemote = false;
  bool _generatingReceipt = false;
  bool _generatingReport = false;
  bool _remoteImmoEnabled = true;
  bool _remoteImmoNoticeShown = false;
  bool _newHouseAlertsEnabled = false;
  bool _newHouseAlertsBusy = false;
  StreamSubscription<User?>? _authStateSub;
  bool _initialHouseHandled = false;
  bool _rentPaymentsBootstrapped = false;

  final Map<String, bool> _notifyDisabledCache = <String, bool>{};

  final Set<String> _favoriteIds = <String>{};
  final Set<String> _savedIds = <String>{};

  late List<_HouseListing> _houses = <_HouseListing>[
    const _HouseListing(
      id: 'house_1',
      title: 'Maison moderne - Golf',
      quartier: 'Golf',
      bedrooms: 3,
      price: 450,
      description:
          'Maison securisee avec parking, salon lumineux et cuisine amenagee.',
      location: 'Avenue du Stade, Golf',
      photos: <String>[
        'https://images.unsplash.com/photo-1568605114967-8130f3a36994?auto=format&fit=crop&w=1300&q=80',
        'https://images.unsplash.com/photo-1570129477492-45c003edd2be?auto=format&fit=crop&w=1300&q=80',
      ],
      status: _HousingStatus.vacant,
      ownerName: 'M. Kanku',
      ownerPhone: '+243970000111',
      fromCommissioner: false,
      latitude: -10.72385,
      longitude: 25.46392,
    ),
    const _HouseListing(
      id: 'house_2',
      title: 'Appartement centre ville',
      quartier: 'Manika',
      bedrooms: 2,
      price: 320,
      description:
          'Appartement proche des commerces, eau et electricite disponibles.',
      location: 'Boulevard Lumumba, Manika',
      photos: <String>[
        'https://images.unsplash.com/photo-1493809842364-78817add7ffb?auto=format&fit=crop&w=1300&q=80',
      ],
      status: _HousingStatus.occupied,
      ownerName: 'Mme Mbuyi',
      ownerPhone: '+243970000222',
      fromCommissioner: false,
      latitude: -10.71542,
      longitude: 25.47781,
    ),
    const _HouseListing(
      id: 'house_3',
      title: 'Villa familiale - Biashara',
      quartier: 'Biashara',
      bedrooms: 4,
      price: 700,
      description:
          'Grande villa avec jardin, 2 salles de bain, quartier calme.',
      location: 'Route Kasapa, Biashara',
      photos: <String>[
        'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=1300&q=80',
        'https://images.unsplash.com/photo-1600573472550-8090b5e0745e?auto=format&fit=crop&w=1300&q=80',
      ],
      status: _HousingStatus.toRelease,
      ownerName: 'M. Ilunga',
      ownerPhone: '+243970000333',
      fromCommissioner: false,
      latitude: -10.73125,
      longitude: 25.45131,
    ),
    const _HouseListing(
      id: 'house_4',
      title: 'Studio - Cinq Ans',
      quartier: 'Cinq Ans',
      bedrooms: 1,
      price: 180,
      description: 'Studio simple, ideal pour etudiant ou jeune travailleur.',
      location: 'Avenue Kasongo, Cinq Ans',
      photos: <String>[
        'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?auto=format&fit=crop&w=1300&q=80',
      ],
      status: _HousingStatus.vacant,
      ownerName: 'Agence Immo Plus',
      ownerPhone: '+243970000444',
      fromCommissioner: true,
      latitude: -10.70984,
      longitude: 25.48942,
    ),
  ];

  late List<_TenantRecord> _tenants = <_TenantRecord>[
    const _TenantRecord(
      id: 'tenant_1',
      name: 'Jean Kalala',
      phone: '+243971111111',
      houseId: 'house_2',
      monthlyRent: 320,
      rentPaid: true,
      paidMonthKey: '2026-03',
    ),
    const _TenantRecord(
      id: 'tenant_2',
      name: 'Lina Mbuyi',
      phone: '+243972222222',
      houseId: 'house_3',
      monthlyRent: 700,
      rentPaid: false,
    ),
  ];

  bool get _isSupabaseReady => SupabaseService.isInitialized;
  bool get _canSyncImmoRemote => _isSupabaseReady && _remoteImmoEnabled;
  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _rentDashboardMonthKey = _monthKeyFromDate(DateTime.now());
    unawaited(_loadRentSettings());
    _loadFromSupabase();
    _loadNewHouseAlertsPreference(silent: true);
    _authStateSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      _loadNewHouseAlertsPreference(silent: true);
      unawaited(_bootstrapRentPaymentsIfNeeded());
    });
    _rentSearchCtrl.addListener(() {
      final v = _rentSearchCtrl.text;
      if (v == _rentSearchQuery) return;
      if (!mounted) return;
      setState(() => _rentSearchQuery = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpenInitialHouse());
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    _searchCtrl.dispose();
    _rentSearchCtrl.dispose();
    super.dispose();
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  double? _asDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  bool _asBool(dynamic v) {
    return v == true || v == 1 || v == '1' || v == 'true' || v == 'True';
  }

  List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    return const <String>[];
  }

  _HousingStatus _statusFromDb(dynamic raw) {
    final key = (raw ?? '').toString().trim().toLowerCase();
    if (key == 'occupied' || key == 'occupe') return _HousingStatus.occupied;
    if (key == 'to_release' || key == 'a_liberer' || key == 'a liberer') {
      return _HousingStatus.toRelease;
    }
    return _HousingStatus.vacant;
  }

  String _statusToDb(_HousingStatus status) {
    switch (status) {
      case _HousingStatus.vacant:
        return 'vacant';
      case _HousingStatus.occupied:
        return 'occupied';
      case _HousingStatus.toRelease:
        return 'to_release';
    }
  }

  String _mapsQueryFromHouse(_HouseListing house) {
    if (house.hasCoordinates) {
      return '${house.latitude},${house.longitude}';
    }
    return house.location;
  }

  String? _staticMapUrl(_HouseListing house) {
    if (!house.hasCoordinates) return null;
    final lat = house.latitude!.toStringAsFixed(6);
    final lng = house.longitude!.toStringAsFixed(6);
    return 'https://staticmap.openstreetmap.de/staticmap.php?center=$lat,$lng'
        '&zoom=14&size=900x260&markers=$lat,$lng,red-pushpin';
  }

  _HouseListing _houseFromRow(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString().trim();
    final quartier = (row['quartier'] ?? row['district'] ?? '').toString().trim();
    return _HouseListing(
      id: id.isEmpty ? 'house_${DateTime.now().millisecondsSinceEpoch}' : id,
      title: (row['title'] ?? row['name'] ?? 'Maison - $quartier').toString(),
      quartier: quartier,
      bedrooms: _asInt(row['bedrooms'] ?? row['rooms']),
      price: _asInt(row['price']),
      description: (row['description'] ?? '').toString(),
      location: (row['location'] ?? row['localisation'] ?? '').toString(),
      photos: _asStringList(row['photos'] ?? row['photo_urls']),
      status: _statusFromDb(row['status']),
      ownerName: (row['owner_name'] ?? row['ownerName'] ?? '').toString(),
      ownerPhone: (row['owner_phone'] ?? row['ownerPhone'] ?? '').toString(),
      fromCommissioner: _asBool(row['from_commissioner'] ?? row['fromCommissioner']),
      latitude: _asDoubleOrNull(row['latitude'] ?? row['lat']),
      longitude: _asDoubleOrNull(row['longitude'] ?? row['lng']),
    );
  }

  _TenantRecord _tenantFromRow(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString().trim();
    final rentPaid = _asBool(row['rent_paid'] ?? row['rentPaid']);
    final paidMonth = _normalizeMonthKey(
      row[_tenantPaidMonthColumn] ??
          row['paid_month'] ??
          row['payment_month'] ??
          row['rent_month'],
    );
    return _TenantRecord(
      id: id.isEmpty ? 'tenant_${DateTime.now().millisecondsSinceEpoch}' : id,
      name: (row['name'] ?? '').toString(),
      phone: (row['phone'] ?? '').toString(),
      houseId: (row['house_id'] ?? row['houseId'] ?? '').toString(),
      monthlyRent: _asInt(row['monthly_rent'] ?? row['monthlyRent']),
      rentPaid: rentPaid,
      paidMonthKey: rentPaid ? paidMonth : null,
    );
  }

  String? _normalizeMonthKey(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})').firstMatch(text);
    if (match == null) return null;
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    if (year == null || month == null || month < 1 || month > 12) return null;
    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
  }

  String _monthKeyFromDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
  }

  List<String> _recentMonthKeys({int count = 18}) {
    final now = DateTime.now();
    final out = <String>[];
    for (int i = 0; i < count; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      out.add(_monthKeyFromDate(d));
    }
    return out;
  }

  String _monthLabel(String? monthKey) {
    final key = _normalizeMonthKey(monthKey);
    if (key == null) return '-';
    final parts = key.split('-');
    final year = int.tryParse(parts[0]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 1;
    const monthNames = <String>[
      'Janvier',
      'Fevrier',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Aout',
      'Septembre',
      'Octobre',
      'Novembre',
      'Decembre',
    ];
    return '${monthNames[month - 1]} $year';
  }

  bool _isTenantPaidForMonth(_TenantRecord tenant, String monthKey) {
    final target = _normalizeMonthKey(monthKey);
    if (target == null) return tenant.rentPaid;
    if (!tenant.rentPaid) return false;
    final paidKey = _normalizeMonthKey(tenant.paidMonthKey);
    return paidKey == target;
  }

  Future<void> _loadRentSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dueDayRaw = prefs.getInt('immo_rent_due_day');
      final enabledRaw = prefs.getBool('immo_late_rent_alerts_enabled');
      final dueDay = (dueDayRaw ?? 5).clamp(1, 28);
      final enabled = enabledRaw ?? true;
      if (!mounted) return;
      setState(() {
        _rentDueDay = dueDay;
        _lateRentAlertsEnabled = enabled;
      });
    } catch (_) {}
  }

  Future<void> _saveRentSettings({
    required int dueDay,
    required bool enabled,
  }) async {
    final cleanDay = dueDay.clamp(1, 28);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('immo_rent_due_day', cleanDay);
      await prefs.setBool('immo_late_rent_alerts_enabled', enabled);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _rentDueDay = cleanDay;
      _lateRentAlertsEnabled = enabled;
    });
    unawaited(_maybeNotifyOwnerAboutLateRent());
  }

  Future<void> _maybeNotifyOwnerAboutLateRent() async {
    if (_lateRentNotifBusy) return;
    if (!_lateRentAlertsEnabled) return;

    final now = DateTime.now();
    final monthKey = _monthKeyFromDate(now);
    if (now.day <= _rentDueDay) return;

    final arrearsCount =
        _tenants.where((t) => !_isTenantPaidForMonth(t, monthKey)).length;
    if (arrearsCount <= 0) return;

    _lateRentNotifBusy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMonth = (prefs.getString('immo_late_rent_notified_month') ?? '').trim();
      if (lastMonth == monthKey) return;

      final daysLate = now.day - _rentDueDay;
      await NotificationService.initLocalOnly();
      await NotificationService.showNotification(
        'Loyers en retard • ${_monthLabel(monthKey)}',
        "$arrearsCount locataire(s) en retard (+$daysLate j).",
        payload: 'immo_rent_late',
      );
      await prefs.setString('immo_late_rent_notified_month', monthKey);
    } catch (_) {
      // ignore
    } finally {
      _lateRentNotifBusy = false;
    }
  }

  Future<void> _openRentSettingsSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        int dueDay = _rentDueDay;
        bool enabled = _lateRentAlertsEnabled;
        final days = List<int>.generate(28, (i) => i + 1);

        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModal) {
              return Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: divider),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 4,
                        margin: const EdgeInsets.only(top: 6, bottom: 10),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Parametres loyers',
                            style: TextStyle(
                              color: text,
                              fontWeight: FontWeight.w900,
                              fontSize: 16.5,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(Icons.close, color: sub),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      value: enabled,
                      activeThumbColor: _accent,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Alerte retard loyer',
                        style: TextStyle(color: text, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        'Notification locale apres la date limite.',
                        style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                      ),
                      onChanged: (v) => setModal(() => enabled = v),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: dueDay,
                      decoration: InputDecoration(
                        labelText: 'Jour limite de paiement',
                        labelStyle: TextStyle(color: sub),
                        filled: true,
                        fillColor: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: divider),
                        ),
                      ),
                      dropdownColor: bg,
                      style: TextStyle(color: text, fontWeight: FontWeight.w700),
                      items: days
                          .map(
                            (d) => DropdownMenuItem<int>(
                              value: d,
                              child: Text('Le $d'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setModal(() => dueDay = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _saveRentSettings(dueDay: dueDay, enabled: enabled);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ctaBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text(
                          'Enregistrer',
                          style: TextStyle(fontWeight: FontWeight.w800),
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
  }

  Future<String?> _pickRentMonth({String? initialMonthKey}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;
    final options = _recentMonthKeys();
    final normalizedInitial = _normalizeMonthKey(initialMonthKey);
    final first = options.first;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String selected = normalizedInitial != null && options.contains(normalizedInitial)
            ? normalizedInitial
            : first;
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModal) {
              return Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: divider),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Choisir le mois de paiement',
                            style: TextStyle(
                              color: text,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(Icons.close, color: sub),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selected,
                      decoration: InputDecoration(
                        labelText: 'Mois paye',
                        labelStyle: TextStyle(color: sub),
                        filled: true,
                        fillColor: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: divider),
                        ),
                      ),
                      dropdownColor: bg,
                      style: TextStyle(color: text, fontWeight: FontWeight.w700),
                      items: options
                          .map(
                            (m) => DropdownMenuItem<String>(
                              value: m,
                              child: Text(_monthLabel(m)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setModal(() => selected = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx, selected),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ctaBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text(
                          'Confirmer',
                          style: TextStyle(fontWeight: FontWeight.w800),
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
  }

  Future<bool> _notificationsEnabledForUser(String uid) async {
    if (uid.trim().isEmpty) return false;
    final cached = _notifyDisabledCache[uid];
    if (cached != null) return cached != true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notification_settings')
          .doc(uid)
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      final disabled = data['disabled'] == true ||
          data['disabled'] == 1 ||
          data['disabled'] == '1' ||
          data['disabled'] == 'true';
      _notifyDisabledCache[uid] = disabled;
      return !disabled;
    } catch (_) {
      return true;
    }
  }

  Future<void> _sendPush({
    required List<String> recipients,
    required String title,
    required String body,
    String? imageUrl,
    Map<String, dynamic>? data,
  }) async {
    try {
      final me = FirebaseAuth.instance.currentUser;
      if (me == null) return;
      final cleanRecipients = recipients
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && e != me.uid)
          .toSet()
          .toList();
      if (cleanRecipients.isEmpty) return;
      final idToken = await me.getIdToken();
      await http.post(
        Uri.parse(kNotifierUrl),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(<String, dynamic>{
          'recipients': cleanRecipients,
          'title': title,
          'body': body,
          'imageUrl': (imageUrl ?? '').toString(),
          'data': data ?? <String, dynamic>{},
        }),
      );
    } catch (e) {
      debugPrint('Immo push error: $e');
    }
  }

  int _minInt(int a, int b) => a < b ? a : b;

  Future<void> _loadNewHouseAlertsPreference({bool silent = false}) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      if (!mounted) return;
      setState(() {
        _newHouseAlertsEnabled = false;
        _newHouseAlertsBusy = false;
      });
      return;
    }
    if (!silent && mounted) {
      setState(() => _newHouseAlertsBusy = true);
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_immoAlertSubscribersCollection)
          .doc(me.uid)
          .get();
      final data = snap.data();
      final enabled = snap.exists
          ? (data?['enabled'] == null ? true : _asBool(data?['enabled']))
          : false;
      if (!mounted) return;
      setState(() {
        _newHouseAlertsEnabled = enabled;
        _newHouseAlertsBusy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _newHouseAlertsBusy = false);
      }
      if (!silent) {
        _showInfo("Impossible de charger l'option d'alerte: $e");
      }
    }
  }

  Future<void> _setNewHouseAlertsEnabled(bool enabled) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      _showInfo("Connectez-vous pour activer les alertes de nouvelles maisons.");
      return;
    }
    if (mounted) {
      setState(() => _newHouseAlertsBusy = true);
    }
    try {
      await FirebaseFirestore.instance
          .collection(_immoAlertSubscribersCollection)
          .doc(me.uid)
          .set({
        'uid': me.uid,
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        if (enabled) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _newHouseAlertsEnabled = enabled;
        _newHouseAlertsBusy = false;
      });
      _showInfo(
        enabled
            ? 'Alerte activee: vous serez informe des nouvelles maisons.'
            : 'Alerte desactivee.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _newHouseAlertsBusy = false);
      }
      _showInfo("Impossible de mettre a jour l'alerte: $e");
    }
  }

  Future<void> _notifySubscribersForNewHouse(
    _HouseListing house,
  ) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      final subs = await FirebaseFirestore.instance
          .collection(_immoAlertSubscribersCollection)
          .where('enabled', isEqualTo: true)
          .get();
      final rawRecipients = subs.docs
          .map((d) => d.id.trim())
          .where((uid) => uid.isNotEmpty && uid != me.uid)
          .toSet()
          .toList();
      if (rawRecipients.isEmpty) return;

      final recipients = <String>[];
      for (final uid in rawRecipients) {
        if (await _notificationsEnabledForUser(uid)) {
          recipients.add(uid);
        }
      }
      if (recipients.isEmpty) return;

      final roleLabel =
          house.fromCommissioner ? 'Commissionnaire' : 'Proprietaire';
      final notifType =
          house.fromCommissioner ? 'new_commissioner_house' : 'new_owner_house';
      final displayName = (me.displayName ?? '').trim();
      final houseOwnerName = house.ownerName.trim();
      final fromName = displayName.isNotEmpty
          ? displayName
          : (houseOwnerName.isNotEmpty ? houseOwnerName : roleLabel);
      final body =
          '${house.title} est disponible a ${house.quartier} (${_priceLabel(house.price)}).';
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      const writeBatchLimit = 450;
      for (int i = 0; i < recipients.length; i += writeBatchLimit) {
        final chunk =
            recipients.sublist(i, _minInt(i + writeBatchLimit, recipients.length));
        final batch = FirebaseFirestore.instance.batch();
        for (final toUid in chunk) {
          final ref = FirebaseFirestore.instance.collection('notifications').doc();
          batch.set(ref, {
            'toUserId': toUid,
            'fromUserId': me.uid,
            'fromName': fromName,
            'fromAvatar': (me.photoURL ?? '').toString(),
            'type': notifType,
            'text': body,
            'houseId': house.id,
            'seen': false,
            'createdAt': FieldValue.serverTimestamp(),
            'createdAtMs': nowMs,
          });
        }
        await batch.commit();
      }

      const pushChunk = 80;
      for (int i = 0; i < recipients.length; i += pushChunk) {
        final chunk = recipients.sublist(i, _minInt(i + pushChunk, recipients.length));
        await _sendPush(
          recipients: chunk,
          title: fromName,
          body: body,
          imageUrl: house.photos.isNotEmpty ? house.photos.first : null,
          data: <String, dynamic>{
            'type': notifType,
            'houseId': house.id,
            'fromCommissioner': house.fromCommissioner,
          },
        );
      }
    } catch (e) {
      debugPrint('Immo new house notifier error: $e');
    }
  }

  bool _isMissingTenantPaidMonthColumnError(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains(_tenantPaidMonthColumn.toLowerCase()) &&
        (raw.contains('42703') ||
            raw.contains('does not exist') ||
            raw.contains('not found') ||
            raw.contains('schema cache'));
  }

  bool _isMissingSchemaError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('42p01') || raw.contains('42703')) return true;
    if (raw.contains('column') && raw.contains('does not exist')) return true;
    if (raw.contains('relation') && raw.contains('does not exist')) return true;
    if (raw.contains('schema cache') && raw.contains('not found')) return true;
    if (raw.contains(_housesTable.toLowerCase()) && raw.contains('not found')) {
      return true;
    }
    if (raw.contains(_tenantsTable.toLowerCase()) && raw.contains('not found')) {
      return true;
    }
    return false;
  }

  bool _isMissingCreatedAtColumnError(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('created_at') &&
        (raw.contains('42703') || raw.contains('does not exist'));
  }

  void _disableRemoteImmoSync() {
    _remoteImmoEnabled = false;
    if (_remoteImmoNoticeShown) return;
    _remoteImmoNoticeShown = true;
    _showInfo(
      'Tables/colonnes Gestion Immo absentes sur Supabase. Mode local actif.',
    );
  }

  Future<List<Map<String, dynamic>>> _selectTableRows(String table) async {
    try {
      final dynamic rows = await _supabase
          .from(table)
          .select()
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      if (!_isMissingCreatedAtColumnError(e)) rethrow;
      final dynamic rows = await _supabase.from(table).select();
      return List<Map<String, dynamic>>.from(rows as List);
    }
  }

  _HouseListing _buildLocalHouse({
    required String quartier,
    required int bedrooms,
    required int price,
    required String description,
    required String location,
    required List<String> photos,
    required _HousingStatus status,
    required String ownerName,
    required String ownerPhone,
    required bool fromCommissioner,
    double? latitude,
    double? longitude,
  }) {
    return _HouseListing(
      id: 'house_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Maison - $quartier',
      quartier: quartier,
      bedrooms: bedrooms,
      price: price,
      description: description,
      location: location,
      photos: photos,
      status: status,
      ownerName: ownerName,
      ownerPhone: ownerPhone,
      fromCommissioner: fromCommissioner,
      latitude: latitude,
      longitude: longitude,
    );
  }

  _TenantRecord _buildLocalTenant({
    required String name,
    required String phone,
    required String houseId,
    required int monthlyRent,
    required bool rentPaid,
    String? paidMonthKey,
  }) {
    return _TenantRecord(
      id: 'tenant_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      phone: phone,
      houseId: houseId,
      monthlyRent: monthlyRent,
      rentPaid: rentPaid,
      paidMonthKey: paidMonthKey,
    );
  }

  String _guessContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<List<String>> _uploadPhotosToSupabase(List<XFile> files) async {
    if (files.isEmpty) return const <String>[];
    if (!_isSupabaseReady) {
      throw Exception('Supabase non initialise.');
    }
    await SupabaseService.ensureAuthenticated();
    final out = <String>[];
    for (int i = 0; i < files.length; i++) {
      final x = files[i];
      final bytes = await x.readAsBytes();
      final ext = (() {
        final parts = x.path.split('.');
        if (parts.length < 2) return 'jpg';
        final e = parts.last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        return e.isEmpty ? 'jpg' : e;
      })();
      final objectPath = 'houses/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
      await _supabase.storage.from(_immoBucket).uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _guessContentType(x.path),
            ),
          );
      out.add(_supabase.storage.from(_immoBucket).getPublicUrl(objectPath));
    }
    return out;
  }

  Future<({double? latitude, double? longitude})> _resolveCoordinates({
    required String locationLabel,
    double? latitude,
    double? longitude,
  }) async {
    if (latitude != null && longitude != null) {
      return (latitude: latitude, longitude: longitude);
    }
    final place = locationLabel.trim();
    if (place.isEmpty) return (latitude: latitude, longitude: longitude);
    try {
      final found = await locationFromAddress(place);
      if (found.isNotEmpty) {
        return (latitude: found.first.latitude, longitude: found.first.longitude);
      }
    } catch (_) {}
    return (latitude: latitude, longitude: longitude);
  }

  Future<void> _loadFromSupabase({bool silent = false}) async {
    if (!_canSyncImmoRemote) return;
    if (!silent && mounted) {
      setState(() => _loadingRemote = true);
    }
    try {
      final houseRows = await _selectTableRows(_housesTable);
      final tenantRows = await _selectTableRows(_tenantsTable);
      final loadedHouses = houseRows.map(_houseFromRow).toList();
      final loadedTenants = tenantRows.map(_tenantFromRow).toList();

      if (!mounted) return;
      setState(() {
        _houses = loadedHouses;
        _tenants = loadedTenants;
        _loadingRemote = false;
      });
      _maybeOpenInitialHouse();
      unawaited(_maybeNotifyOwnerAboutLateRent());
      unawaited(_bootstrapRentPaymentsIfNeeded());
    } catch (e) {
      if (mounted) {
        setState(() => _loadingRemote = false);
      }
      if (_isMissingSchemaError(e)) {
        _disableRemoteImmoSync();
        return;
      }
      if (!silent && mounted) {
        _showInfo('Connexion Supabase impossible: $e');
      }
    }
  }

  List<String> get _quartierOptions {
    final set = <String>{'Tous'};
    for (final house in _houses) {
      set.add(house.quartier);
    }
    final out = set.toList();
    out.sort((a, b) {
      if (a == 'Tous') return -1;
      if (b == 'Tous') return 1;
      return a.compareTo(b);
    });
    return out;
  }

  List<_HouseListing> get _tenantHouses {
    return _houses.where((house) {
      if (house.status == _HousingStatus.occupied) return false;
      if (_selectedQuartier != 'Tous' && house.quartier != _selectedQuartier) {
        return false;
      }
      if (_selectedBedrooms != 'Tous') {
        final rooms = int.tryParse(_selectedBedrooms);
        if (rooms == null || house.bedrooms != rooms) return false;
      }
      if (_selectedStatus != null && house.status != _selectedStatus) {
        return false;
      }
      if (!_matchesPrice(house.price)) return false;
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      final hay = <String>[
        house.title,
        house.quartier,
        house.description,
        house.location,
        house.status.label,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  bool _matchesPrice(int price) {
    switch (_selectedPrice) {
      case '<= 250 USD':
        return price <= 250;
      case '251 - 500 USD':
        return price >= 251 && price <= 500;
      case '> 500 USD':
        return price > 500;
      default:
        return true;
    }
  }

  List<_HouseListing> get _ownerHouses =>
      _houses
          .where(
            (h) =>
                !h.fromCommissioner && h.status != _HousingStatus.occupied,
          )
          .toList();

  List<_HouseListing> get _availableOwnerHouses =>
      _ownerHouses;

  List<_HouseListing> get _commissionerHouses =>
      _houses
          .where(
            (h) =>
                h.fromCommissioner && h.status != _HousingStatus.occupied,
          )
          .toList();

  int get _totalRevenue {
    return _tenants
        .where((t) => t.rentPaid)
        .fold<int>(0, (sum, t) => sum + t.monthlyRent);
  }

  int get _freeHouses =>
      _houses.where((h) => h.status == _HousingStatus.vacant).length;

  int get _occupiedHouses =>
      _houses.where((h) => h.status == _HousingStatus.occupied).length;

  String _priceLabel(int price) => '$price USD/mois';

  _HouseListing? _houseById(String id) {
    for (final house in _houses) {
      if (house.id == id) return house;
    }
    return null;
  }

  void _maybeOpenInitialHouse() {
    if (_initialHouseHandled) return;
    final id = (widget.initialHouseId ?? '').trim();
    if (id.isEmpty) return;
    final house = _houseById(id);
    if (house == null) return;
    _initialHouseHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openContactSheet(house);
    });
  }

  Future<void> _launchOrSnack(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'ouvrir ce lien.")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  void _showInfo(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  void _openContactSheet(_HouseListing house) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final phone = house.ownerPhone.trim();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 4,
                  margin: const EdgeInsets.only(top: 6, bottom: 10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    house.title,
                    style: TextStyle(
                      color: text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16.5,
                    ),
                  ),
                  subtitle: Text(
                    'Proprietaire: ${house.ownerName}',
                    style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                  ),
                ),
                if (house.photos.isNotEmpty)
                  ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _openPhotoViewer(house);
                    },
                    leading:
                        const Icon(Icons.photo_library_outlined, color: _accent),
                    title: Text(
                      'Voir les photos',
                      style: TextStyle(color: text, fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${house.photos.length} photo(s) disponible(s)',
                      style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                    ),
                  ),
                if (phone.isNotEmpty)
                  ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchOrSnack(Uri.parse('tel:$phone'));
                    },
                    leading: const Icon(Icons.call_rounded, color: _ctaBlue),
                    title: Text(
                      'Appeler le proprietaire',
                      style: TextStyle(color: text, fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      phone,
                      style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                    ),
                  ),
                if (phone.isNotEmpty)
                  ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchOrSnack(Uri.parse('sms:$phone'));
                    },
                    leading: const Icon(Icons.sms_rounded, color: _accent),
                    title: Text(
                      'Envoyer un message',
                      style: TextStyle(color: text, fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'Contacter rapidement le proprietaire',
                      style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                    ),
                  ),
                if (phone.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Aucun numero disponible.',
                      style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openPhotoViewer(_HouseListing house) {
    if (house.photos.isEmpty) {
      _showInfo('Aucune photo disponible pour cette maison.');
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        int page = 0;
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModal) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.78,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111B21) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Photos - ${house.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark
                                    ? const Color(0xFFE9EDF0)
                                    : const Color(0xFF111827),
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: Icon(
                              Icons.close,
                              color: isDark
                                  ? const Color(0xFFAAB2B8)
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        itemCount: house.photos.length,
                        onPageChanged: (v) => setModal(() => page = v),
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                house.photos[index],
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: isDark
                                      ? Colors.white10
                                      : const Color(0xFFF3F4F6),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: isDark
                                        ? const Color(0xFFAAB2B8)
                                        : const Color(0xFF6B7280),
                                    size: 34,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        '${page + 1}/${house.photos.length}',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFAAB2B8)
                              : const Color(0xFF6B7280),
                          fontWeight: FontWeight.w700,
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
  }

  Future<void> _openAddHouseSheet({required bool fromCommissioner}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final quartierCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final bedroomsCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final photosCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final ownerNameCtrl = TextEditingController(
      text: fromCommissioner ? 'Commissionnaire' : 'Proprietaire',
    );
    final ownerPhoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final pickedPhotos = <XFile>[];
    _HousingStatus status = _HousingStatus.vacant;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModal) {
              Future<void> submit() async {
                if (saving) return;
                if (!(formKey.currentState?.validate() ?? false)) return;
                final useRemote = _canSyncImmoRemote;

                final price = int.tryParse(priceCtrl.text.trim());
                final bedrooms = int.tryParse(bedroomsCtrl.text.trim());
                if (price == null || price <= 0) {
                  _showInfo('Prix invalide.');
                  return;
                }
                if (bedrooms == null || bedrooms <= 0) {
                  _showInfo('Nombre de pieces invalide.');
                  return;
                }

                final photos = photosCtrl.text
                    .split(RegExp(r'[,;\n]'))
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final quartier = quartierCtrl.text.trim();
                final description = descCtrl.text.trim();
                final location = locationCtrl.text.trim();
                final ownerName = ownerNameCtrl.text.trim().isEmpty
                    ? (fromCommissioner ? 'Commissionnaire' : 'Proprietaire')
                    : ownerNameCtrl.text.trim();
                final ownerPhone = ownerPhoneCtrl.text.trim();
                final parsedLat = double.tryParse(latCtrl.text.trim());
                final parsedLng = double.tryParse(lngCtrl.text.trim());
                if ((parsedLat == null) != (parsedLng == null)) {
                  _showInfo('Latitude et longitude doivent etre toutes les deux renseignees.');
                  return;
                }

                setModal(() => saving = true);
                if (useRemote && mounted) {
                  setState(() => _syncingRemote = true);
                }
                try {
                  final coordinates = await _resolveCoordinates(
                    locationLabel: location,
                    latitude: parsedLat,
                    longitude: parsedLng,
                  );
                  List<String> allPhotos = photos;
                  if (useRemote) {
                    final uploadedPhotos = await _uploadPhotosToSupabase(pickedPhotos);
                    allPhotos = <String>[...uploadedPhotos, ...photos];
                  } else if (pickedPhotos.isNotEmpty) {
                    _showInfo(
                      'Mode local: les photos selectionnees ne sont pas uploadees.',
                    );
                  }

                  final payload = <String, dynamic>{
                    'title': 'Maison - $quartier',
                    'quartier': quartier,
                    'bedrooms': bedrooms,
                    'price': price,
                    'description': description,
                    'location': location,
                    'photos': allPhotos,
                    'status': _statusToDb(status),
                    'owner_name': ownerName,
                    'owner_phone': ownerPhone,
                    'from_commissioner': fromCommissioner,
                    'latitude': coordinates.latitude,
                    'longitude': coordinates.longitude,
                  };
                  _HouseListing created;
                  if (useRemote) {
                    final dynamic inserted = await _supabase
                        .from(_housesTable)
                        .insert(payload)
                        .select()
                        .single();
                    created = _houseFromRow(
                      Map<String, dynamic>.from(inserted as Map),
                    );
                  } else {
                    created = _buildLocalHouse(
                      quartier: quartier,
                      bedrooms: bedrooms,
                      price: price,
                      description: description,
                      location: location,
                      photos: allPhotos,
                      status: status,
                      ownerName: ownerName,
                      ownerPhone: ownerPhone,
                      fromCommissioner: fromCommissioner,
                      latitude: coordinates.latitude,
                      longitude: coordinates.longitude,
                    );
                  }

                  if (!mounted) return;
                  setState(() {
                    _houses = <_HouseListing>[created, ..._houses];
                  });
                  if (useRemote) {
                    unawaited(_notifySubscribersForNewHouse(created));
                  }
                  Navigator.pop(ctx);
                  if (useRemote) {
                    _showInfo(
                      fromCommissioner
                          ? 'Annonce publiee (commissionnaire).'
                          : 'Maison publiee avec succes.',
                    );
                  } else {
                    _showInfo('Maison ajoutee en mode local.');
                  }
                } catch (e) {
                  if (_isMissingSchemaError(e)) {
                    _disableRemoteImmoSync();
                    final coordinates = await _resolveCoordinates(
                      locationLabel: location,
                      latitude: parsedLat,
                      longitude: parsedLng,
                    );
                    final localHouse = _buildLocalHouse(
                      quartier: quartier,
                      bedrooms: bedrooms,
                      price: price,
                      description: description,
                      location: location,
                      photos: photos,
                      status: status,
                      ownerName: ownerName,
                      ownerPhone: ownerPhone,
                      fromCommissioner: fromCommissioner,
                      latitude: coordinates.latitude,
                      longitude: coordinates.longitude,
                    );
                    if (!mounted) return;
                    setState(() {
                      _houses = <_HouseListing>[localHouse, ..._houses];
                    });
                    Navigator.pop(ctx);
                    _showInfo('Maison ajoutee localement.');
                    return;
                  }
                  _showInfo('Erreur de publication: $e');
                  setModal(() => saving = false);
                } finally {
                  if (useRemote && mounted) {
                    setState(() => _syncingRemote = false);
                  }
                }
              }

              return DraggableScrollableSheet(
                initialChildSize: 0.9,
                minChildSize: 0.55,
                maxChildSize: 0.95,
                expand: false,
                builder: (context, controller) {
                  return Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: divider),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.55 : 0.12),
                          blurRadius: 26,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ListView(
                      controller: controller,
                      padding: EdgeInsets.only(
                        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                      ),
                      children: [
                        Center(
                          child: Container(
                            width: 46,
                            height: 4,
                            margin: const EdgeInsets.only(top: 6, bottom: 10),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.black12,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                fromCommissioner
                                    ? 'Ajouter un bien (Commissionnaire)'
                                    : 'Ajouter une maison (Proprietaire)',
                                style: TextStyle(
                                  color: text,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16.5,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: saving ? null : () => Navigator.pop(ctx),
                              icon: Icon(Icons.close, color: sub),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Form(
                          key: formKey,
                          child: Column(
                            children: [
                              _Field(
                                label: 'Quartier',
                                controller: quartierCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Quartier requis'
                                    : null,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _Field(
                                      label: 'Prix (USD/mois)',
                                      controller: priceCtrl,
                                      textColor: text,
                                      subColor: sub,
                                      divider: divider,
                                      keyboardType: TextInputType.number,
                                      validator: (v) => (v == null ||
                                              int.tryParse(v.trim()) == null)
                                          ? 'Prix invalide'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _Field(
                                      label: 'Pièces',
                                      controller: bedroomsCtrl,
                                      textColor: text,
                                      subColor: sub,
                                      divider: divider,
                                      keyboardType: TextInputType.number,
                                      validator: (v) => (v == null ||
                                              int.tryParse(v.trim()) == null)
                                          ? 'Nombre invalide'
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                label: 'Description',
                                controller: descCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                minLines: 3,
                                maxLines: 4,
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Description requise'
                                    : null,
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                label: 'Localisation',
                                controller: locationCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Localisation requise'
                                    : null,
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<_HousingStatus>(
                                initialValue: status,
                                decoration: InputDecoration(
                                  labelText: 'Etat',
                                  labelStyle: TextStyle(color: sub),
                                  filled: true,
                                  fillColor: isDark
                                      ? Colors.white10
                                      : const Color(0xFFF3F4F6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: divider),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: divider),
                                  ),
                                ),
                                dropdownColor: bg,
                                style: TextStyle(color: text, fontWeight: FontWeight.w700),
                                items: _HousingStatus.values
                                    .map(
                                      (s) => DropdownMenuItem<_HousingStatus>(
                                        value: s,
                                        child: Text(s.label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setModal(() => status = v);
                                },
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                label: 'Photos (URL, separees par virgule)',
                                controller: photosCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                minLines: 2,
                                maxLines: 3,
                              ),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: divider),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${pickedPhotos.length} photo(s) locale(s) selectionnee(s)',
                                      style: TextStyle(
                                        color: text,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Ces photos seront uploades visible pour tout le monde".',
                                      style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: saving
                                              ? null
                                              : () async {
                                                  final images = await _imagePicker.pickMultiImage(
                                                    imageQuality: 78,
                                                  );
                                                  if (images.isEmpty) return;
                                                  setModal(() {
                                                    pickedPhotos
                                                      ..clear()
                                                      ..addAll(images);
                                                  });
                                                },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _ctaBlue,
                                            foregroundColor: Colors.white,
                                          ),
                                          icon: const Icon(Icons.photo_library_outlined),
                                          label: const Text(
                                            'Choisir photos',
                                            style: TextStyle(fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        if (pickedPhotos.isNotEmpty)
                                          OutlinedButton.icon(
                                            onPressed: saving
                                                ? null
                                                : () => setModal(() => pickedPhotos.clear()),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: sub,
                                              side: BorderSide(color: divider),
                                            ),
                                            icon: const Icon(Icons.clear_rounded),
                                            label: const Text('Vider'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _Field(
                                      label: 'Latitude (optionnel)',
                                      controller: latCtrl,
                                      textColor: text,
                                      subColor: sub,
                                      divider: divider,
                                      keyboardType: const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _Field(
                                      label: 'Longitude (optionnel)',
                                      controller: lngCtrl,
                                      textColor: text,
                                      subColor: sub,
                                      divider: divider,
                                      keyboardType: const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                label: fromCommissioner
                                    ? 'Nom du commissionnaire'
                                    : 'Nom du proprietaire',
                                controller: ownerNameCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                label: 'Telephone de contact',
                                controller: ownerPhoneCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: saving ? null : submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _accent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: saving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.add_home_outlined),
                                  label: Text(
                                    saving ? 'Ajout en cours...' : 'Publier',
                                    style: const TextStyle(fontWeight: FontWeight.w800),
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

    quartierCtrl.dispose();
    priceCtrl.dispose();
    bedroomsCtrl.dispose();
    descCtrl.dispose();
    locationCtrl.dispose();
    photosCtrl.dispose();
    latCtrl.dispose();
    lngCtrl.dispose();
    ownerNameCtrl.dispose();
    ownerPhoneCtrl.dispose();
  }

  Future<void> _openEditHouseLocationSheet(_HouseListing house) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final locationCtrl = TextEditingController(text: house.location);
    final quartierCtrl = TextEditingController(text: house.quartier);
    final latCtrl = TextEditingController(
      text: house.latitude?.toStringAsFixed(6) ?? '',
    );
    final lngCtrl = TextEditingController(
      text: house.longitude?.toStringAsFixed(6) ?? '',
    );
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModal) {
              Future<void> submit() async {
                if (saving) return;
                if (!(formKey.currentState?.validate() ?? false)) return;
                final useRemote = _canSyncImmoRemote;

                final location = locationCtrl.text.trim();
                final quartier = quartierCtrl.text.trim();
                final parsedLat = double.tryParse(latCtrl.text.trim());
                final parsedLng = double.tryParse(lngCtrl.text.trim());
                if ((parsedLat == null) != (parsedLng == null)) {
                  _showInfo(
                    'Latitude et longitude doivent etre toutes les deux renseignees.',
                  );
                  return;
                }

                setModal(() => saving = true);
                if (useRemote && mounted) {
                  setState(() => _syncingRemote = true);
                }

                final before = house;
                try {
                  final coordinates = await _resolveCoordinates(
                    locationLabel: location,
                    latitude: parsedLat,
                    longitude: parsedLng,
                  );
                  final updated = before.copyWith(
                    location: location,
                    quartier: quartier,
                    latitude: coordinates.latitude,
                    longitude: coordinates.longitude,
                  );

                  if (!mounted) return;
                  setState(() {
                    _houses = _houses
                        .map((h) => h.id == before.id ? updated : h)
                        .toList();
                  });

                  if (useRemote) {
                    final payload = <String, dynamic>{
                      'location': location,
                      'quartier': quartier,
                      'latitude': coordinates.latitude,
                      'longitude': coordinates.longitude,
                    };
                    await _supabase.from(_housesTable).update(payload).eq(
                          'id',
                          before.id,
                        );
                  }

                  if (!mounted) return;
                  Navigator.pop(ctx);
                  _showInfo('Localisation mise a jour.');
                } catch (e) {
                  if (_isMissingSchemaError(e)) {
                    _disableRemoteImmoSync();
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    _showInfo('Localisation mise a jour (mode local).');
                    return;
                  }
                  if (!mounted) return;
                  setState(() {
                    _houses = _houses
                        .map((h) => h.id == before.id ? before : h)
                        .toList();
                  });
                  _showInfo('Erreur modification localisation: $e');
                  setModal(() => saving = false);
                } finally {
                  if (useRemote && mounted) {
                    setState(() => _syncingRemote = false);
                  }
                }
              }

              return Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: divider),
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Modifier localisation',
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.w900,
                                fontSize: 16.5,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed:
                                saving ? null : () => Navigator.pop(ctx),
                            icon: Icon(Icons.close, color: sub),
                          ),
                        ],
                      ),
                      _Field(
                        label: 'Quartier',
                        controller: quartierCtrl,
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Quartier requis'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        label: 'Adresse / Localisation',
                        controller: locationCtrl,
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Localisation requise'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _Field(
                              label: 'Latitude (optionnel)',
                              controller: latCtrl,
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Field(
                              label: 'Longitude (optionnel)',
                              controller: lngCtrl,
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: saving ? null : submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _ctaBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            saving ? 'Mise a jour...' : 'Enregistrer',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    locationCtrl.dispose();
    quartierCtrl.dispose();
    latCtrl.dispose();
    lngCtrl.dispose();
  }

  Future<void> _openEditHouseSheet(_HouseListing house) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final quartierCtrl = TextEditingController(text: house.quartier);
    final priceCtrl = TextEditingController(text: house.price.toString());
    final bedroomsCtrl = TextEditingController(text: house.bedrooms.toString());
    final descCtrl = TextEditingController(text: house.description);
    final locationCtrl = TextEditingController(text: house.location);
    final latCtrl = TextEditingController(
      text: house.latitude?.toStringAsFixed(6) ?? '',
    );
    final lngCtrl = TextEditingController(
      text: house.longitude?.toStringAsFixed(6) ?? '',
    );
    final ownerNameCtrl = TextEditingController(text: house.ownerName);
    final ownerPhoneCtrl = TextEditingController(text: house.ownerPhone);

    final formKey = GlobalKey<FormState>();
    _HousingStatus status = house.status;
    bool saving = false;
    final linkedTenants =
        _tenants.where((t) => t.houseId == house.id).toList(growable: false);
    bool syncTenantRent = linkedTenants.isNotEmpty;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModal) {
              Future<void> submit() async {
                if (saving) return;
                if (!(formKey.currentState?.validate() ?? false)) return;
                final useRemote = _canSyncImmoRemote;

                final quartier = quartierCtrl.text.trim();
                final location = locationCtrl.text.trim();
                final description = descCtrl.text.trim();
                final ownerName = ownerNameCtrl.text.trim();
                final ownerPhone = ownerPhoneCtrl.text.trim();

                final price = int.tryParse(priceCtrl.text.trim());
                final bedrooms = int.tryParse(bedroomsCtrl.text.trim());
                if (price == null || price <= 0) {
                  _showInfo('Prix invalide.');
                  return;
                }
                if (bedrooms == null || bedrooms <= 0) {
                  _showInfo('Nombre de pieces invalide.');
                  return;
                }

                final parsedLat = double.tryParse(latCtrl.text.trim());
                final parsedLng = double.tryParse(lngCtrl.text.trim());
                if ((parsedLat == null) != (parsedLng == null)) {
                  _showInfo(
                    'Latitude et longitude doivent etre toutes les deux renseignees.',
                  );
                  return;
                }

                setModal(() => saving = true);
                if (useRemote && mounted) {
                  setState(() => _syncingRemote = true);
                }

                final beforeHouses = List<_HouseListing>.from(_houses);
                final beforeTenants = List<_TenantRecord>.from(_tenants);
                try {
                  final coordinates = await _resolveCoordinates(
                    locationLabel: location,
                    latitude: parsedLat,
                    longitude: parsedLng,
                  );

                  final updated = house.copyWith(
                    quartier: quartier,
                    bedrooms: bedrooms,
                    price: price,
                    description: description,
                    location: location,
                    status: status,
                    ownerName: ownerName,
                    ownerPhone: ownerPhone,
                    latitude: coordinates.latitude,
                    longitude: coordinates.longitude,
                  );

                  if (!mounted) return;
                  setState(() {
                    _houses =
                        _houses.map((h) => h.id == house.id ? updated : h).toList();
                    if (syncTenantRent) {
                      _tenants = _tenants
                          .map((t) => t.houseId == house.id
                              ? t.copyWith(monthlyRent: price)
                              : t)
                          .toList();
                    }
                  });

                  if (useRemote) {
                    final payload = <String, dynamic>{
                      'quartier': quartier,
                      'bedrooms': bedrooms,
                      'price': price,
                      'description': description,
                      'location': location,
                      'status': _statusToDb(status),
                      'owner_name': ownerName,
                      'owner_phone': ownerPhone,
                      'latitude': coordinates.latitude,
                      'longitude': coordinates.longitude,
                    };
                    await _supabase.from(_housesTable).update(payload).eq(
                          'id',
                          house.id,
                        );
                    if (syncTenantRent) {
                      await _supabase
                          .from(_tenantsTable)
                          .update({'monthly_rent': price}).eq(
                            'house_id',
                            house.id,
                          );
                    }
                  }

                  if (!mounted) return;
                  Navigator.pop(ctx);
                  _showInfo('Maison mise a jour.');
                } catch (e) {
                  if (_isMissingSchemaError(e)) {
                    _disableRemoteImmoSync();
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    _showInfo('Maison mise a jour (mode local).');
                    return;
                  }
                  if (!mounted) return;
                  setState(() {
                    _houses = beforeHouses;
                    _tenants = beforeTenants;
                  });
                  _showInfo('Erreur modification maison: $e');
                  setModal(() => saving = false);
                } finally {
                  if (useRemote && mounted) {
                    setState(() => _syncingRemote = false);
                  }
                }
              }

              return Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: divider),
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Modifier la maison',
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.w900,
                                fontSize: 16.5,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed:
                                saving ? null : () => Navigator.pop(ctx),
                            icon: Icon(Icons.close, color: sub),
                          ),
                        ],
                      ),
                      _Field(
                        label: 'Quartier',
                        controller: quartierCtrl,
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Quartier requis'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _Field(
                              label: 'Prix (USD/mois)',
                              controller: priceCtrl,
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              keyboardType: TextInputType.number,
                              validator: (v) => (v == null ||
                                      int.tryParse(v.trim()) == null)
                                  ? 'Prix requis'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Field(
                              label: 'Pieces',
                              controller: bedroomsCtrl,
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              keyboardType: TextInputType.number,
                              validator: (v) => (v == null ||
                                      int.tryParse(v.trim()) == null)
                                  ? 'Pieces requises'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<_HousingStatus>(
                        initialValue: status,
                        decoration: InputDecoration(
                          labelText: 'Statut',
                          labelStyle: TextStyle(color: sub),
                          filled: true,
                          fillColor:
                              isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: divider),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: divider),
                          ),
                        ),
                        dropdownColor: bg,
                        style: TextStyle(color: text, fontWeight: FontWeight.w700),
                        items: _HousingStatus.values
                            .map(
                              (s) => DropdownMenuItem<_HousingStatus>(
                                value: s,
                                child: Text(s.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setModal(() => status = v);
                        },
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        label: 'Description',
                        controller: descCtrl,
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                        minLines: 3,
                        maxLines: 6,
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        label: 'Adresse / Localisation',
                        controller: locationCtrl,
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Localisation requise'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _Field(
                              label: 'Latitude (optionnel)',
                              controller: latCtrl,
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Field(
                              label: 'Longitude (optionnel)',
                              controller: lngCtrl,
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        label: 'Nom proprietaire',
                        controller: ownerNameCtrl,
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        label: 'Telephone proprietaire',
                        controller: ownerPhoneCtrl,
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                        keyboardType: TextInputType.phone,
                      ),
                      if (linkedTenants.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        SwitchListTile(
                          value: syncTenantRent,
                          activeThumbColor: _accent,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Mettre a jour le loyer du locataire',
                            style: TextStyle(
                              color: text,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            'Synchronise ${linkedTenants.length} locataire(s) lie(s).',
                            style: TextStyle(
                              color: sub,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onChanged: (v) => setModal(() => syncTenantRent = v),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: saving ? null : submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _ctaBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            saving ? 'Mise a jour...' : 'Enregistrer',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    quartierCtrl.dispose();
    priceCtrl.dispose();
    bedroomsCtrl.dispose();
    descCtrl.dispose();
    locationCtrl.dispose();
    latCtrl.dispose();
    lngCtrl.dispose();
    ownerNameCtrl.dispose();
    ownerPhoneCtrl.dispose();
  }

  Future<void> _deleteHouse(_HouseListing house) async {
    final linkedTenants =
        _tenants.where((t) => t.houseId == house.id).toList(growable: false);
    if (linkedTenants.isNotEmpty) {
      _showInfo(
        "Impossible de supprimer: ${linkedTenants.length} locataire(s) lie(s). Terminez d'abord le contrat.",
      );
      return;
    }

    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final bg = isDark ? const Color(0xFF111B21) : Colors.white;
            final text =
                isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
            final sub =
                isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
            return AlertDialog(
              backgroundColor: bg,
              title: Text(
                'Supprimer la publication ?',
                style: TextStyle(color: text, fontWeight: FontWeight.w900),
              ),
              content: Text(
                'Cette action est irreversible.',
                style: TextStyle(color: sub, fontWeight: FontWeight.w600),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Supprimer',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirm) return;

    final beforeHouses = List<_HouseListing>.from(_houses);
    final beforeFavorites = Set<String>.from(_favoriteIds);
    final beforeSaved = Set<String>.from(_savedIds);

    setState(() {
      _houses = _houses.where((h) => h.id != house.id).toList();
      _favoriteIds.remove(house.id);
      _savedIds.remove(house.id);
    });

    if (!_canSyncImmoRemote) {
      _showInfo('Publication supprimee.');
      return;
    }

    setState(() => _syncingRemote = true);
    try {
      await _supabase.from(_housesTable).delete().eq('id', house.id);
      _showInfo('Publication supprimee.');
    } catch (e) {
      if (_isMissingSchemaError(e)) {
        _disableRemoteImmoSync();
        _showInfo('Publication supprimee (mode local).');
        return;
      }
      if (!mounted) return;
      setState(() {
        _houses = beforeHouses;
        _favoriteIds
          ..clear()
          ..addAll(beforeFavorites);
        _savedIds
          ..clear()
          ..addAll(beforeSaved);
      });
      _showInfo('Erreur suppression: $e');
    } finally {
      if (mounted) setState(() => _syncingRemote = false);
    }
  }

  Future<void> _openAddTenantSheet() async {
    if (_availableOwnerHouses.isEmpty) {
      _showInfo(
        'Ajoutez une maison disponible avant de lier un locataire.',
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String selectedHouseId = _availableOwnerHouses.first.id;
    bool rentPaid = false;
    String? paidMonthKey = _monthKeyFromDate(DateTime.now());
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModal) {
              Future<void> submit() async {
                if (saving) return;
                if (!(formKey.currentState?.validate() ?? false)) return;
                final useRemote = _canSyncImmoRemote;
                if (rentPaid && _normalizeMonthKey(paidMonthKey) == null) {
                  _showInfo('Choisissez le mois du loyer paye.');
                  return;
                }

                final house = _houseById(selectedHouseId);
                if (house == null) {
                  _showInfo('Maison introuvable.');
                  return;
                }

                setModal(() => saving = true);
                if (useRemote && mounted) {
                  setState(() => _syncingRemote = true);
                }
                try {
                  final name = nameCtrl.text.trim();
                  final phone = phoneCtrl.text.trim();
                  final payload = <String, dynamic>{
                    'name': name,
                    'phone': phone,
                    'house_id': selectedHouseId,
                    'monthly_rent': house.price,
                    'rent_paid': rentPaid,
                    _tenantPaidMonthColumn:
                        rentPaid ? _normalizeMonthKey(paidMonthKey) : null,
                  };
                  _TenantRecord createdTenant;
                  if (useRemote) {
                    dynamic inserted;
                    try {
                      inserted = await _supabase
                          .from(_tenantsTable)
                          .insert(payload)
                          .select()
                          .single();
                    } catch (e) {
                      if (!_isMissingTenantPaidMonthColumnError(e)) rethrow;
                      final payloadWithoutMonth = Map<String, dynamic>.from(payload)
                        ..remove(_tenantPaidMonthColumn);
                      inserted = await _supabase
                          .from(_tenantsTable)
                          .insert(payloadWithoutMonth)
                          .select()
                          .single();
                    }
                    await _supabase
                        .from(_housesTable)
                        .update({'status': _statusToDb(_HousingStatus.occupied)})
                        .eq('id', selectedHouseId);
                    createdTenant = _tenantFromRow(
                      Map<String, dynamic>.from(inserted as Map),
                    ).copyWith(
                      paidMonthKey:
                          rentPaid ? _normalizeMonthKey(paidMonthKey) : null,
                    );
                  } else {
                    createdTenant = _buildLocalTenant(
                      name: name,
                      phone: phone,
                      houseId: selectedHouseId,
                      monthlyRent: house.price,
                      rentPaid: rentPaid,
                      paidMonthKey:
                          rentPaid ? _normalizeMonthKey(paidMonthKey) : null,
                    );
                  }

                  if (!mounted) return;
                  setState(() {
                    _tenants = <_TenantRecord>[..._tenants, createdTenant];
                    _houses = _houses
                        .map((h) => h.id == selectedHouseId
                            ? h.copyWith(status: _HousingStatus.occupied)
                            : h)
                        .toList();
                  });
                  Navigator.pop(ctx);
                  _showInfo(
                    useRemote
                        ? 'Locataire ajoute a ${house.title}.'
                        : 'Locataire ajoute localement a ${house.title}.',
                  );
                } catch (e) {
                  if (_isMissingSchemaError(e)) {
                    _disableRemoteImmoSync();
                    final localTenant = _buildLocalTenant(
                      name: nameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      houseId: selectedHouseId,
                      monthlyRent: house.price,
                      rentPaid: rentPaid,
                      paidMonthKey:
                          rentPaid ? _normalizeMonthKey(paidMonthKey) : null,
                    );
                    if (!mounted) return;
                    setState(() {
                      _tenants = <_TenantRecord>[..._tenants, localTenant];
                      _houses = _houses
                          .map((h) => h.id == selectedHouseId
                              ? h.copyWith(status: _HousingStatus.occupied)
                              : h)
                          .toList();
                    });
                    Navigator.pop(ctx);
                    _showInfo('Locataire ajoute en mode local.');
                    return;
                  }
                  _showInfo('Erreur ajout locataire: $e');
                  setModal(() => saving = false);
                } finally {
                  if (useRemote && mounted) {
                    setState(() => _syncingRemote = false);
                  }
                }
              }

              return Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: divider),
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ajouter un locataire',
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.w900,
                                fontSize: 16.5,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: saving ? null : () => Navigator.pop(ctx),
                            icon: Icon(Icons.close, color: sub),
                          ),
                        ],
                      ),
                      _Field(
                        label: 'Nom du locataire',
                        controller: nameCtrl,
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        label: 'Telephone',
                        controller: phoneCtrl,
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Telephone requis'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedHouseId,
                        decoration: InputDecoration(
                          labelText: 'Maison louee',
                          labelStyle: TextStyle(color: sub),
                          filled: true,
                          fillColor:
                              isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: divider),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: divider),
                          ),
                        ),
                        dropdownColor: bg,
                        style: TextStyle(color: text, fontWeight: FontWeight.w700),
                        items: _availableOwnerHouses
                            .map(
                              (h) => DropdownMenuItem<String>(
                                value: h.id,
                                child: Text('${h.title} (${h.quartier})'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setModal(() => selectedHouseId = v);
                        },
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        value: rentPaid,
                        activeThumbColor: _accent,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Loyer deja paye',
                          style: TextStyle(color: text, fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          rentPaid ? 'Paye' : 'En retard',
                          style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                        ),
                        onChanged: (v) => setModal(() {
                          rentPaid = v;
                          if (rentPaid && _normalizeMonthKey(paidMonthKey) == null) {
                            paidMonthKey = _monthKeyFromDate(DateTime.now());
                          }
                        }),
                      ),
                      if (rentPaid) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _normalizeMonthKey(paidMonthKey),
                          decoration: InputDecoration(
                            labelText: 'Mois du loyer paye',
                            labelStyle: TextStyle(color: sub),
                            filled: true,
                            fillColor:
                                isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: divider),
                            ),
                          ),
                          dropdownColor: bg,
                          style: TextStyle(
                            color: text,
                            fontWeight: FontWeight.w700,
                          ),
                          items: _recentMonthKeys()
                              .map(
                                (m) => DropdownMenuItem<String>(
                                  value: m,
                                  child: Text(_monthLabel(m)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setModal(() => paidMonthKey = v);
                          },
                        ),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: saving ? null : submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _ctaBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: Text(
                            saving ? 'Ajout...' : 'Enregistrer',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    nameCtrl.dispose();
    phoneCtrl.dispose();
  }

  Future<void> _toggleRentStatus(String tenantId) async {
    final idx = _tenants.indexWhere((t) => t.id == tenantId);
    if (idx < 0) return;
    final before = _tenants[idx];
    final monthKey = _normalizeMonthKey(_rentDashboardMonthKey) ??
        _monthKeyFromDate(DateTime.now());
    final wasPaidForMonth = _isTenantPaidForMonth(before, monthKey);
    final nextPaid = !wasPaidForMonth;
    final nextMonthKey = nextPaid ? monthKey : null;
    final after = before.copyWith(
      rentPaid: nextPaid,
      paidMonthKey: nextMonthKey,
    );
    final house = _houseById(after.houseId);

    setState(() {
      _tenants[idx] = after;
    });

    if (!_canSyncImmoRemote) {
      if (nextPaid) {
        _offerQuittanceSnack(tenant: after, house: house, monthKey: monthKey);
      }
      unawaited(
        _syncRentPaymentRecord(
          paid: nextPaid,
          tenant: after,
          house: house,
          monthKey: monthKey,
        ),
      );
      unawaited(_maybeNotifyOwnerAboutLateRent());
      return;
    }

    try {
      final payload = <String, dynamic>{
        'rent_paid': nextPaid,
        _tenantPaidMonthColumn: nextPaid ? nextMonthKey : null,
      };
      try {
        await _supabase.from(_tenantsTable).update(payload).eq('id', tenantId);
      } catch (e) {
        if (!_isMissingTenantPaidMonthColumnError(e)) rethrow;
        await _supabase
            .from(_tenantsTable)
            .update({'rent_paid': nextPaid})
            .eq('id', tenantId);
      }
      if (nextPaid) {
        _offerQuittanceSnack(tenant: after, house: house, monthKey: monthKey);
      }
      unawaited(
        _syncRentPaymentRecord(
          paid: nextPaid,
          tenant: after,
          house: house,
          monthKey: monthKey,
        ),
      );
      unawaited(_maybeNotifyOwnerAboutLateRent());
    } catch (e) {
      if (_isMissingSchemaError(e)) {
        _disableRemoteImmoSync();
        return;
      }
      if (!mounted) return;
      setState(() {
        _tenants[idx] = before;
      });
      _showInfo('Erreur mise a jour loyer: $e');
    }
  }

  String _rentPaymentDocId({
    required String ownerId,
    required String tenantId,
    required String monthKey,
  }) {
    final cleanOwner = ownerId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final cleanTenant = tenantId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final cleanMonth = monthKey.replaceAll(RegExp(r'[^0-9]'), '');
    return 'pay_${cleanOwner}_${cleanTenant}_$cleanMonth';
  }

  Future<void> _syncRentPaymentRecord({
    required bool paid,
    required _TenantRecord tenant,
    required _HouseListing? house,
    required String monthKey,
    bool recordPaidAt = true,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final cleanMonth = _normalizeMonthKey(monthKey);
    if (cleanMonth == null) return;
    final docId = _rentPaymentDocId(
      ownerId: me.uid,
      tenantId: tenant.id,
      monthKey: cleanMonth,
    );
    final ref =
        FirebaseFirestore.instance.collection(_rentPaymentsCollection).doc(docId);

    try {
      if (!paid) {
        await ref.delete();
        return;
      }
      final payload = <String, dynamic>{
        'id': docId,
        'ownerId': me.uid,
        'tenantId': tenant.id,
        'tenantName': tenant.name,
        'tenantPhone': tenant.phone,
        'houseId': tenant.houseId,
        'houseTitle': (house?.title ?? '').toString(),
        'amount': tenant.monthlyRent,
        'currency': 'USD',
        'monthKey': cleanMonth,
      };
      if (recordPaidAt) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdAtMs'] = DateTime.now().millisecondsSinceEpoch;
        payload['inferred'] = false;
      }
      await ref.set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Immo payment record error: $e');
    }
  }

  Future<void> _bootstrapRentPaymentsIfNeeded() async {
    if (_rentPaymentsBootstrapped) return;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    _rentPaymentsBootstrapped = true;

    for (final t in _tenants) {
      if (!t.rentPaid) continue;
      final mk = _normalizeMonthKey(t.paidMonthKey);
      if (mk == null) continue;
      await _syncRentPaymentRecord(
        paid: true,
        tenant: t,
        house: _houseById(t.houseId),
        monthKey: mk,
        recordPaidAt: false,
      );
    }
  }

  Future<void> _terminateLease(String tenantId) async {
    final idx = _tenants.indexWhere((t) => t.id == tenantId);
    if (idx < 0) return;
    final tenant = _tenants[idx];
    final houseId = tenant.houseId.trim();
    final house = _houseById(houseId);

    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final bg = isDark ? const Color(0xFF111B21) : Colors.white;
            final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
            final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
            return AlertDialog(
              backgroundColor: bg,
              title: Text(
                'Terminer le contrat ?',
                style: TextStyle(color: text, fontWeight: FontWeight.w900),
              ),
              content: Text(
                'Le locataire sera retire du suivi et la maison redeviendra disponible.',
                style: TextStyle(color: sub, fontWeight: FontWeight.w600),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Terminer',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirm) return;

    final beforeTenants = List<_TenantRecord>.from(_tenants);
    final beforeHouses = List<_HouseListing>.from(_houses);

    setState(() {
      _tenants = _tenants.where((t) => t.id != tenantId).toList();
      if (houseId.isNotEmpty) {
        _houses = _houses
            .map(
              (h) => h.id == houseId
                  ? h.copyWith(status: _HousingStatus.vacant)
                  : h,
            )
            .toList();
      }
    });

    if (!_canSyncImmoRemote) {
      _showInfo('Contrat termine. Maison disponible.');
      unawaited(_maybeNotifyOwnerAboutLateRent());
      return;
    }

    setState(() => _syncingRemote = true);
    try {
      await _supabase.from(_tenantsTable).delete().eq('id', tenantId);
      if (houseId.isNotEmpty) {
        await _supabase
            .from(_housesTable)
            .update({'status': _statusToDb(_HousingStatus.vacant)})
            .eq('id', houseId);
      }
      _showInfo(
        'Contrat termine${house != null ? " (${house.title})" : ""}. Maison disponible.',
      );
      unawaited(_maybeNotifyOwnerAboutLateRent());
    } catch (e) {
      if (_isMissingSchemaError(e)) {
        _disableRemoteImmoSync();
        _showInfo('Contrat termine (mode local).');
        return;
      }
      if (!mounted) return;
      setState(() {
        _tenants = beforeTenants;
        _houses = beforeHouses;
      });
      _showInfo('Erreur fin contrat: $e');
    } finally {
      if (mounted) setState(() => _syncingRemote = false);
    }
  }

  void _openRentArrearsSheet({
    required List<_TenantRecord> tenants,
    required String monthKey,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final pending = List<_TenantRecord>.from(tenants);
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModal) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.74,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: divider),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.55 : 0.12),
                      blurRadius: 26,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 4,
                        margin: const EdgeInsets.only(top: 6, bottom: 10),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Impayes • ${_monthLabel(monthKey)}',
                            style: TextStyle(
                              color: text,
                              fontWeight: FontWeight.w900,
                              fontSize: 16.5,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(Icons.close, color: sub),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Relance rapide: appeler, SMS, ou marquer paye.',
                        style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: pending.isEmpty
                          ? Center(
                              child: Text(
                                'Aucun impaye.',
                                style: TextStyle(
                                  color: sub,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: pending.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: divider),
                              itemBuilder: (c, i) {
                                final t = pending[i];
                                final house = _houseById(t.houseId);
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    t.name,
                                    style: TextStyle(
                                      color: text,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${house?.title ?? '-'} • ${_priceLabel(t.monthlyRent)}',
                                    style: TextStyle(
                                      color: sub,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  trailing: Wrap(
                                    spacing: 4,
                                    children: [
                                      IconButton(
                                        tooltip: 'Marquer paye',
                                        onPressed: () async {
                                          await _toggleRentStatus(t.id);
                                          if (!context.mounted) return;
                                          setModal(() {
                                            pending.removeWhere(
                                              (x) => x.id == t.id,
                                            );
                                          });
                                        },
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                          color: Color(0xFF2ECC71),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Appeler',
                                        onPressed: t.phone.trim().isEmpty
                                            ? null
                                            : () {
                                                Navigator.pop(ctx);
                                                _launchOrSnack(
                                                  Uri.parse('tel:${t.phone}'),
                                                );
                                              },
                                        icon: const Icon(
                                          Icons.call_outlined,
                                          color: _ctaBlue,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'SMS',
                                        onPressed: t.phone.trim().isEmpty
                                            ? null
                                            : () {
                                                Navigator.pop(ctx);
                                                _launchOrSnack(
                                                  Uri.parse('sms:${t.phone}'),
                                                );
                                              },
                                        icon: const Icon(
                                          Icons.sms_outlined,
                                          color: _accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
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
  }

  String _safePdfName(String input) {
    final cleaned = input
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '');
    return cleaned.isEmpty ? 'quittance.pdf' : cleaned;
  }

  String _receiptNumber({
    required String tenantId,
    required String monthKey,
  }) {
    final yyyymm = monthKey.replaceAll('-', '');
    final raw = tenantId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    final suffix = raw.isEmpty ? 'LK' : raw.substring(0, _minInt(6, raw.length));
    return 'QTN-$yyyymm-$suffix';
  }

  Uint8List _buildQuittancePdfBytes({
    required _TenantRecord tenant,
    required _HouseListing? house,
    required String monthKey,
  }) {
    final now = DateTime.now();
    String two(int v) => v < 10 ? '0$v' : '$v';
    final dateLabel = '${two(now.day)}/${two(now.month)}/${now.year}';
    final receiptNo = _receiptNumber(tenantId: tenant.id, monthKey: monthKey);

    final ownerName = (house?.ownerName ?? '').trim().isNotEmpty
        ? house!.ownerName.trim()
        : (FirebaseAuth.instance.currentUser?.displayName ?? 'Proprietaire');
    final ownerPhone = (house?.ownerPhone ?? '').trim();
    final houseTitle = (house?.title ?? '').trim().isNotEmpty
        ? house!.title.trim()
        : 'Maison';
    final houseAddress = (house?.location ?? '').trim();
    final houseQuartier = (house?.quartier ?? '').trim();

    final document = PdfDocument();
    final page = document.pages.add();
    final size = page.getClientSize();
    final margin = 28.0;

    final titleFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      20,
      style: PdfFontStyle.bold,
    );
    final hFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      12,
      style: PdfFontStyle.bold,
    );
    final tFont = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final tBold = PdfStandardFont(
      PdfFontFamily.helvetica,
      11,
      style: PdfFontStyle.bold,
    );

    final g = page.graphics;
    g.drawString(
      'QUITTANCE DE LOYER',
      titleFont,
      bounds: Rect.fromLTWH(margin, margin, size.width - margin * 2, 28),
    );

    double y = margin + 34;
    g.drawString(
      'Recu N° $receiptNo',
      hFont,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 18),
    );
    y += 20;
    g.drawString(
      'Date: $dateLabel',
      tFont,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 16),
    );
    y += 18;

    g.drawLine(
      PdfPen(PdfColor(220, 220, 220)),
      Offset(margin, y),
      Offset(size.width - margin, y),
    );
    y += 14;

    final grid = PdfGrid();
    grid.columns.add(count: 2);
    grid.style = PdfGridStyle(
      font: tFont,
      cellPadding: PdfPaddings(left: 6, right: 6, top: 6, bottom: 6),
    );

    void addRow(String k, String v) {
      final row = grid.rows.add();
      row.cells[0].value = k;
      row.cells[1].value = v;
      row.cells[0].style = PdfGridCellStyle(font: tBold);
    }

    addRow('Proprietaire', ownerName);
    if (ownerPhone.isNotEmpty) addRow('Telephone', ownerPhone);
    addRow('Locataire', tenant.name.trim().isEmpty ? '-' : tenant.name.trim());
    if (tenant.phone.trim().isNotEmpty) addRow('Telephone locataire', tenant.phone.trim());
    addRow('Maison', houseTitle);
    if (houseQuartier.isNotEmpty) addRow('Quartier', houseQuartier);
    if (houseAddress.isNotEmpty) addRow('Adresse', houseAddress);
    addRow('Mois', _monthLabel(monthKey));
    addRow('Montant', _priceLabel(tenant.monthlyRent));
    addRow('Statut', 'PAYE');

    final result = grid.draw(
      page: page,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 0),
    );
    y = (result?.bounds.bottom ?? y) + 12;

    final note = PdfTextElement(
      text:
          'Cette quittance confirme la reception du paiement du loyer pour la periode indiquee.',
      font: tFont,
    ).draw(
      page: page,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 0),
    );
    y = (note?.bounds.bottom ?? y) + 18;

    g.drawString(
      'Signature: ____________________________',
      tFont,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 16),
    );

    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    return bytes;
  }

  void _offerQuittanceSnack({
    required _TenantRecord tenant,
    required _HouseListing? house,
    required String monthKey,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Quittance prete: ${tenant.name} • ${_monthLabel(monthKey)}',
        ),
        action: SnackBarAction(
          label: 'Partager',
          onPressed: () => unawaited(
            _generateAndShareQuittance(
              tenant: tenant,
              house: house,
              monthKey: monthKey,
            ),
          ),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _generateAndShareQuittance({
    required _TenantRecord tenant,
    required _HouseListing? house,
    required String monthKey,
  }) async {
    if (_generatingReceipt) return;
    if (!mounted) return;
    setState(() => _generatingReceipt = true);
    try {
      final receiptNo = _receiptNumber(tenantId: tenant.id, monthKey: monthKey);
      final bytes = _buildQuittancePdfBytes(
        tenant: tenant,
        house: house,
        monthKey: monthKey,
      );
      final fileName = _safePdfName(
        'quittance_${tenant.name}_${monthKey}_$receiptNo.pdf',
      );
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: fileName,
          ),
        ],
        subject: 'Quittance de loyer',
        text: 'Quittance $receiptNo • ${tenant.name} • ${_monthLabel(monthKey)}',
      );
    } catch (e) {
      _showInfo('Erreur generation quittance: $e');
    } finally {
      if (mounted) setState(() => _generatingReceipt = false);
    }
  }

  Uint8List _buildMonthlyReportPdfBytes({
    required String monthKey,
    required List<_TenantRecord> tenants,
    required Map<String, int> paidAmountsByTenantId,
    required int expectedRent,
    required int collectedRent,
    required int remainingRent,
    required int coveragePct,
  }) {
    final now = DateTime.now();
    String two(int v) => v < 10 ? '0$v' : '$v';
    final dateLabel = '${two(now.day)}/${two(now.month)}/${now.year}';

    final document = PdfDocument();
    final page = document.pages.add();
    final size = page.getClientSize();
    final margin = 28.0;

    final titleFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      18,
      style: PdfFontStyle.bold,
    );
    final hFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      12,
      style: PdfFontStyle.bold,
    );
    final tFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final tBold = PdfStandardFont(
      PdfFontFamily.helvetica,
      10,
      style: PdfFontStyle.bold,
    );

    final g = page.graphics;
    g.drawString(
      'RAPPORT MENSUEL - LOYERS',
      titleFont,
      bounds: Rect.fromLTWH(margin, margin, size.width - margin * 2, 26),
    );

    double y = margin + 28;
    g.drawString(
      'Mois: ${_monthLabel(monthKey)}',
      hFont,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 16),
    );
    y += 18;
    g.drawString(
      'Genere le: $dateLabel',
      tFont,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 14),
    );
    y += 16;

    g.drawLine(
      PdfPen(PdfColor(220, 220, 220)),
      Offset(margin, y),
      Offset(size.width - margin, y),
    );
    y += 12;

    final statsGrid = PdfGrid();
    statsGrid.columns.add(count: 2);
    statsGrid.style = PdfGridStyle(
      font: tFont,
      cellPadding: PdfPaddings(left: 6, right: 6, top: 6, bottom: 6),
    );

    void addStat(String k, String v) {
      final row = statsGrid.rows.add();
      row.cells[0].value = k;
      row.cells[1].value = v;
      row.cells[0].style = PdfGridCellStyle(font: tBold);
    }

    addStat('Attendu', '$expectedRent USD');
    addStat('Encaisse', '$collectedRent USD');
    addStat('Reste', '$remainingRent USD');
    addStat('Taux', '$coveragePct%');

    final statsResult = statsGrid.draw(
      page: page,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 0),
    );
    y = (statsResult?.bounds.bottom ?? y) + 14;

    g.drawString(
      'Details locataires',
      hFont,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 16),
    );
    y += 18;

    final detailGrid = PdfGrid();
    detailGrid.columns.add(count: 4);
    detailGrid.style = PdfGridStyle(
      font: tFont,
      cellPadding: PdfPaddings(left: 5, right: 5, top: 5, bottom: 5),
    );
    final header = detailGrid.headers.add(1)[0];
    header.cells[0].value = 'Locataire';
    header.cells[1].value = 'Maison';
    header.cells[2].value = 'Montant';
    header.cells[3].value = 'Statut';
    header.style = PdfGridRowStyle(
      backgroundBrush: PdfSolidBrush(PdfColor(245, 245, 245)),
      font: PdfStandardFont(
        PdfFontFamily.helvetica,
        10,
        style: PdfFontStyle.bold,
      ),
    );

    final sorted = List<_TenantRecord>.from(tenants)
      ..sort((a, b) {
        final ap = paidAmountsByTenantId.containsKey(a.id);
        final bp = paidAmountsByTenantId.containsKey(b.id);
        if (ap != bp) return ap ? 1 : -1; // impayes d'abord
        return a.name.compareTo(b.name);
      });

    for (final t in sorted) {
      final paid = paidAmountsByTenantId.containsKey(t.id);
      final amount = paidAmountsByTenantId[t.id] ?? t.monthlyRent;
      final houseTitle = (_houseById(t.houseId)?.title ?? '-').toString();
      final row = detailGrid.rows.add();
      row.cells[0].value = t.name.trim().isEmpty ? '-' : t.name.trim();
      row.cells[1].value = houseTitle;
      row.cells[2].value = '$amount USD';
      row.cells[3].value = paid ? 'PAYE' : 'IMPAYE';
      if (!paid) {
        row.cells[3].style = PdfGridCellStyle(
          font: tBold,
          textBrush: PdfSolidBrush(PdfColor(231, 76, 60)),
        );
      } else {
        row.cells[3].style = PdfGridCellStyle(
          font: tBold,
          textBrush: PdfSolidBrush(PdfColor(46, 204, 113)),
        );
      }
    }

    detailGrid.draw(
      page: page,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 0),
    );

    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    return bytes;
  }

  Future<void> _generateAndShareMonthlyReport({required String monthKey}) async {
    if (_generatingReport) return;
    final cleanMonth = _normalizeMonthKey(monthKey) ?? _monthKeyFromDate(DateTime.now());

    if (!mounted) return;
    setState(() => _generatingReport = true);

    try {
      final me = FirebaseAuth.instance.currentUser;
      final paidAmountsByTenantId = <String, int>{};
      final currentTenantIds = _tenants.map((t) => t.id).toSet();

      if (me != null) {
        final snap = await FirebaseFirestore.instance
            .collection(_rentPaymentsCollection)
            .where('ownerId', isEqualTo: me.uid)
            .where('monthKey', isEqualTo: cleanMonth)
            .get();

        for (final d in snap.docs) {
          final data = d.data();
          final tenantId = (data['tenantId'] ?? '').toString().trim();
          if (tenantId.isEmpty) continue;
          if (!currentTenantIds.contains(tenantId)) continue;
          paidAmountsByTenantId[tenantId] = _asInt(data['amount']);
        }
      }

      if (paidAmountsByTenantId.isEmpty) {
        for (final t in _tenants) {
          if (_isTenantPaidForMonth(t, cleanMonth)) {
            paidAmountsByTenantId[t.id] = t.monthlyRent;
          }
        }
      }

      final expectedRent =
          _tenants.fold<int>(0, (sum, t) => sum + t.monthlyRent);
      final collectedRent = paidAmountsByTenantId.values.fold<int>(
        0,
        (sum, v) => sum + v,
      );
      final remainingRent =
          expectedRent > collectedRent ? (expectedRent - collectedRent) : 0;
      final coveragePct = expectedRent <= 0
          ? 0
          : ((collectedRent / expectedRent) * 100).round();

      final bytes = _buildMonthlyReportPdfBytes(
        monthKey: cleanMonth,
        tenants: _tenants,
        paidAmountsByTenantId: paidAmountsByTenantId,
        expectedRent: expectedRent,
        collectedRent: collectedRent,
        remainingRent: remainingRent,
        coveragePct: coveragePct,
      );

      final fileName = _safePdfName('rapport_loyers_$cleanMonth.pdf');
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: fileName,
          ),
        ],
        subject: 'Rapport loyers',
        text: 'Rapport • ${_monthLabel(cleanMonth)}',
      );
    } catch (e) {
      _showInfo('Erreur generation rapport: $e');
    } finally {
      if (mounted) setState(() => _generatingReport = false);
    }
  }

  String _paymentReference({
    required _TenantRecord tenant,
    required _HouseListing? house,
    required String monthKey,
  }) {
    String lastToken(String raw, {int count = 4}) {
      final cleaned =
          raw.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
      if (cleaned.isEmpty) return '----';
      final take = _minInt(count, cleaned.length);
      return cleaned.substring(cleaned.length - take);
    }

    final cleanMonth =
        _normalizeMonthKey(monthKey) ?? _monthKeyFromDate(DateTime.now());
    final yyyymm = cleanMonth.replaceAll('-', '');

    final t = lastToken(tenant.id, count: 4);
    final h = lastToken(tenant.houseId, count: 4);
    return 'PAY-$yyyymm-$t$h';
  }

  String _twoDigits(int value) => value < 10 ? '0$value' : '$value';

  String _formatDateTime(DateTime dt) {
    return '${_twoDigits(dt.day)}/${_twoDigits(dt.month)}/${dt.year} '
        '${_twoDigits(dt.hour)}:${_twoDigits(dt.minute)}:${_twoDigits(dt.second)}';
  }

  String _vcardEscape(String input) {
    return input
        .replaceAll('\\', r'\\')
        .replaceAll('\r\n', '\n')
        .replaceAll('\n', r'\n')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,');
  }

  Future<({String? monthKey, int? paidAtMs})> _fetchLastRentPaymentInfo(
    _TenantRecord tenant,
  ) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return (monthKey: null, paidAtMs: null);

    final months = _recentMonthKeys(count: 18);
    for (final m in months) {
      final docId = _rentPaymentDocId(ownerId: me.uid, tenantId: tenant.id, monthKey: m);
      try {
        final doc = await FirebaseFirestore.instance
            .collection(_rentPaymentsCollection)
            .doc(docId)
            .get();
        if (!doc.exists) continue;
        final data = doc.data() ?? <String, dynamic>{};
        int? ms;
        final rawMs = data['createdAtMs'];
        if (rawMs is int) {
          ms = rawMs;
        } else if (rawMs is num) {
          ms = rawMs.toInt();
        }
        final rawTs = data['createdAt'];
        if (ms == null && rawTs is Timestamp) {
          ms = rawTs.millisecondsSinceEpoch;
        }
        return (monthKey: m, paidAtMs: ms);
      } catch (_) {
        // ignore
      }
    }

    return (monthKey: null, paidAtMs: null);
  }

  String _paymentVcardData({
    required String reference,
    required _TenantRecord tenant,
    required _HouseListing? house,
    required String monthKey,
    required String lastPaymentLabel,
  }) {
    final cleanMonth =
        _normalizeMonthKey(monthKey) ?? _monthKeyFromDate(DateTime.now());
    final ownerName = (house?.ownerName ?? '').trim().isNotEmpty
        ? house!.ownerName.trim()
        : 'Proprietaire';
    final ownerPhone = (house?.ownerPhone ?? '').trim();
    final tenantName = tenant.name.trim().isEmpty ? 'Locataire' : tenant.name.trim();
    final tenantPhone = tenant.phone.trim();
    final houseTitle = (house?.title ?? '').trim().isNotEmpty ? house!.title.trim() : 'Maison';
    final houseQuartier = (house?.quartier ?? '').trim();
    final houseLocation = (house?.location ?? '').trim();

    final noteLines = <String>[
      'Ref: $reference',
      'Mois: $cleanMonth',
      'Montant: ${tenant.monthlyRent} USD',
      'Locataire: $tenantName',
      if (tenantPhone.isNotEmpty) 'Tel locataire: $tenantPhone',
      'Maison: $houseTitle${houseQuartier.isNotEmpty ? " ($houseQuartier)" : ""}',
      if (houseLocation.isNotEmpty) 'Adresse: $houseLocation',
      'Dernier paiement: $lastPaymentLabel',
    ];

    final vcardLines = <String>[
      'BEGIN:VCARD',
      'VERSION:3.0',
      'N:${_vcardEscape(ownerName)};;;;',
      'FN:${_vcardEscape('$ownerName - $houseTitle')}',
      'ORG:${_vcardEscape('Lualaba Konnect')}',
      'TITLE:${_vcardEscape('Paiement de loyer')}',
      if (ownerPhone.isNotEmpty) 'TEL;TYPE=CELL,VOICE:${_vcardEscape(ownerPhone)}',
      if (tenantPhone.isNotEmpty) 'TEL;TYPE=HOME,VOICE:${_vcardEscape(tenantPhone)}',
      'NOTE:${_vcardEscape(noteLines.join('\n'))}',
      'UID:${_vcardEscape(reference)}',
      'END:VCARD',
    ];

    return vcardLines.join('\r\n');
  }

  String _paymentDisplayText({
    required String reference,
    required _TenantRecord tenant,
    required _HouseListing? house,
    required String monthKey,
    required String lastPaymentLabel,
  }) {
    final cleanMonth =
        _normalizeMonthKey(monthKey) ?? _monthKeyFromDate(DateTime.now());
    final ownerName = (house?.ownerName ?? '').trim();
    final ownerPhone = (house?.ownerPhone ?? '').trim();
    final who = ownerName.isEmpty
        ? (ownerPhone.isEmpty ? '-' : ownerPhone)
        : (ownerPhone.isEmpty ? ownerName : '$ownerName ($ownerPhone)');
    final houseTitle = (_houseById(tenant.houseId)?.title ?? '-').toString();

    return <String>[
      'Proprietaire: $who',
      'Maison: $houseTitle',
      'Locataire: ${tenant.name.trim().isEmpty ? '-' : tenant.name.trim()}',
      'Montant: ${tenant.monthlyRent} USD',
      'Mois: ${_monthLabel(cleanMonth)} ($cleanMonth)',
      'Dernier paiement: $lastPaymentLabel',
      'Reference: $reference',
    ].join('\n');
  }

  void _openPaymentQrSheet({
    required _TenantRecord tenant,
    required _HouseListing? house,
    required String monthKey,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final reference =
        _paymentReference(tenant: tenant, house: house, monthKey: monthKey);
    final lastPaymentFuture = _fetchLastRentPaymentInfo(tenant);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: FutureBuilder<({String? monthKey, int? paidAtMs})>(
            future: lastPaymentFuture,
            builder: (context, snap) {
              final info = snap.data;
              final lastMonth = info?.monthKey;
              final lastMs = info?.paidAtMs;
              String lastPaymentLabel = '-';
              if (lastMonth != null && lastMs != null) {
                lastPaymentLabel =
                    '${_monthLabel(lastMonth)} • ${_formatDateTime(DateTime.fromMillisecondsSinceEpoch(lastMs))}';
              } else if (lastMonth != null) {
                lastPaymentLabel = '${_monthLabel(lastMonth)} • Date inconnue';
              }

              final vcard = _paymentVcardData(
                reference: reference,
                tenant: tenant,
                house: house,
                monthKey: monthKey,
                lastPaymentLabel: lastPaymentLabel,
              );
              final displayText = _paymentDisplayText(
                reference: reference,
                tenant: tenant,
                house: house,
                monthKey: monthKey,
                lastPaymentLabel: lastPaymentLabel,
              );

              return Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: divider),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 4,
                    margin: const EdgeInsets.only(top: 6, bottom: 10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'QR paiement',
                        style: TextStyle(
                          color: text,
                          fontWeight: FontWeight.w900,
                          fontSize: 16.5,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: sub),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${tenant.name} • ${_monthLabel(monthKey)} • ${_priceLabel(tenant.monthlyRent)}',
                    style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(
                      data: vcard,
                      size: 240,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      errorStateBuilder: (_, __) => SizedBox(
                        width: 240,
                        height: 240,
                        child: Center(
                          child: Text(
                            'QR indisponible',
                            style: TextStyle(
                              color: sub,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: divider),
                  ),
                  child: SelectableText(
                    displayText,
                    style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: reference));
                          if (!mounted) return;
                          _showInfo('Reference de paiement copiee.');
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: text,
                          side: BorderSide(color: divider),
                          backgroundColor: bg,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text(
                          'Copier ref',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: tenant.phone.trim().isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                final message =
                                    'Paiement loyer ${_monthLabel(monthKey)} • ${_priceLabel(tenant.monthlyRent)}\nRef: $reference';
                                _launchOrSnack(
                                  Uri(
                                    scheme: 'sms',
                                    path: tenant.phone,
                                    queryParameters: <String, String>{
                                      'body': message,
                                    },
                                  ),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ctaBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.sms_outlined, size: 18),
                        label: const Text(
                          'Envoyer',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;
    final initialIndex = widget.initialTabIndex < 0
        ? 0
        : (widget.initialTabIndex > 2 ? 2 : widget.initialTabIndex);

    return DefaultTabController(
      length: 3,
      initialIndex: initialIndex,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: bg,
          foregroundColor: text,
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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(Icons.arrow_back, color: text),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Gestion Immo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: text,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Rafraichir',
              onPressed: _loadingRemote ? null : () => _loadFromSupabase(),
              icon: _loadingRemote
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.sync_rounded, color: sub),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(58),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: divider),
                ),
                child: TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: sub,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                  indicator: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tabs: const [
                    Tab(text: 'Locataire'),
                    Tab(text: 'Proprietaire'),
                    Tab(text: 'Commissionnaire'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            if (_loadingRemote ||
                _syncingRemote ||
                _generatingReceipt ||
                _generatingReport)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: TabBarView(
                children: [
                  _buildTenantTab(
                    isDark: isDark,
                    card: card,
                    text: text,
                    sub: sub,
                    divider: divider,
                  ),
                  _buildOwnerTab(
                    isDark: isDark,
                    card: card,
                    text: text,
                    sub: sub,
                    divider: divider,
                  ),
                  _buildCommissionerTab(
                    isDark: isDark,
                    card: card,
                    text: text,
                    sub: sub,
                    divider: divider,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTenantTab({
    required bool isDark,
    required Color card,
    required Color text,
    required Color sub,
    required Color divider,
  }) {
    final items = _tenantHouses;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.20 : 0.06),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SwitchListTile(
            value: _newHouseAlertsEnabled,
            activeThumbColor: _accent,
            contentPadding: EdgeInsets.zero,
            title: Text(
              "M'informer des nouvelles maisons",
              style: TextStyle(color: text, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              _newHouseAlertsBusy
                  ? 'Mise a jour en cours...'
                  : 'Recevoir une notification push a chaque nouvelle maison.',
              style: TextStyle(color: sub, fontWeight: FontWeight.w600),
            ),
            onChanged: _newHouseAlertsBusy
                ? null
                : (v) => _setNewHouseAlertsEnabled(v),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.20 : 0.06),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: sub),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(color: text, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: 'Rechercher une maison',
                    hintStyle: TextStyle(color: sub),
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (_searchQuery.isNotEmpty)
                IconButton(
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.close, color: _accent),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _FilterSelect(
              width: 170,
              value: _selectedPrice,
              label: 'Prix',
              options: const ['Tous', '<= 250 USD', '251 - 500 USD', '> 500 USD'],
              onChanged: (v) => setState(() => _selectedPrice = v),
            ),
            _FilterSelect(
              width: 170,
              value: _selectedQuartier,
              label: 'Quartier',
              options: _quartierOptions,
              onChanged: (v) => setState(() => _selectedQuartier = v),
            ),
            _FilterSelect(
              width: 170,
              value: _selectedBedrooms,
              label: 'Pièces',
              options: const ['Tous', '1', '2', '3', '4', '5'],
              onChanged: (v) => setState(() => _selectedBedrooms = v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Tous'),
                selected: _selectedStatus == null,
                onSelected: (_) => setState(() => _selectedStatus = null),
              ),
              const SizedBox(width: 8),
              for (final status in _HousingStatus.values.where(
                (s) => s != _HousingStatus.occupied,
              )) ...[
                ChoiceChip(
                  label: Text(status.label),
                  selected: _selectedStatus == status,
                  onSelected: (_) => setState(() => _selectedStatus = status),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${items.length} maison(s) trouvee(s)',
          style: TextStyle(color: sub, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Aucun resultat pour vos filtres.',
                style: TextStyle(color: sub, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        for (final house in items) ...[
          _buildHouseCard(
            house: house,
            isDark: isDark,
            card: card,
            text: text,
            sub: sub,
            divider: divider,
            showTenantActions: true,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildOwnerTab({
    required bool isDark,
    required Color card,
    required Color text,
    required Color sub,
    required Color divider,
  }) {
    final ownerHouses = _ownerHouses;
    final monthKey = _normalizeMonthKey(_rentDashboardMonthKey) ??
        _monthKeyFromDate(DateTime.now());

    bool paidForMonth(_TenantRecord t) => _isTenantPaidForMonth(t, monthKey);

    final expectedRent = _tenants.fold<int>(0, (sum, t) => sum + t.monthlyRent);
    final collectedRent = _tenants
        .where(paidForMonth)
        .fold<int>(0, (sum, t) => sum + t.monthlyRent);
    final remainingRent =
        expectedRent > collectedRent ? (expectedRent - collectedRent) : 0;
    final coveragePct =
        expectedRent <= 0 ? 0 : ((collectedRent / expectedRent) * 100).round();

    final arrearsTenants = _tenants.where((t) => !paidForMonth(t)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final q = _rentSearchQuery.trim().toLowerCase();
    final filteredTenants = _tenants.where((t) {
      final isPaid = paidForMonth(t);
      if (_rentFilter == 'paid' && !isPaid) return false;
      if (_rentFilter == 'unpaid' && isPaid) return false;
      if (q.isEmpty) return true;
      final houseTitle = (_houseById(t.houseId)?.title ?? '').trim();
      final hay = '${t.name} ${t.phone} $houseTitle'.toLowerCase();
      return hay.contains(q);
    }).toList()
      ..sort((a, b) {
        final ap = paidForMonth(a);
        final bp = paidForMonth(b);
        if (ap != bp) return ap ? 1 : -1; // impayes d'abord
        return a.name.compareTo(b.name);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatCard(
              title: 'Encaisse (${_monthLabel(monthKey)})',
              value: '$collectedRent USD',
              icon: Icons.payments_outlined,
              color: const Color(0xFF2ECC71),
            ),
            _StatCard(
              title: 'Maisons libres',
              value: '$_freeHouses',
              icon: Icons.home_work_outlined,
              color: _ctaBlue,
            ),
            _StatCard(
              title: 'Maisons occupees',
              value: '$_occupiedHouses',
              icon: Icons.house_siding_outlined,
              color: _accent,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _openAddHouseSheet(fromCommissioner: false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.add_home_outlined),
                label: const Text(
                  'Ajouter une maison',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openAddTenantSheet,
                style: OutlinedButton.styleFrom(
                  foregroundColor: text,
                  side: BorderSide(color: divider),
                  backgroundColor: card,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text(
                  'Ajouter un locataire',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (context) {
            final now = DateTime.now();
            final currentMonthKey = _monthKeyFromDate(now);
            final isLate = now.day > _rentDueDay;
            final currentArrears = _tenants
                .where((t) => !_isTenantPaidForMonth(t, currentMonthKey))
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _ctaBlue.withOpacity(isDark ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.notifications_active_outlined,
                          color: _ctaBlue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Alertes loyers',
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Jour limite: le $_rentDueDay • ${_lateRentAlertsEnabled ? "Actives" : "Desactivees"}',
                              style: TextStyle(
                                color: sub,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Parametres',
                        onPressed: _openRentSettingsSheet,
                        icon: Icon(Icons.tune_rounded, color: sub),
                      ),
                    ],
                  ),
                  if (isLate && currentArrears.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF7043).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFFF7043).withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${currentArrears.length} loyer(s) en retard • ${_monthLabel(currentMonthKey)}',
                              style: const TextStyle(
                                color: Color(0xFFFF7043),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _openRentArrearsSheet(
                              tenants: currentArrears,
                              monthKey: currentMonthKey,
                            ),
                            child: const Text('Voir'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Maisons disponibles',
          style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 8),
        if (ownerHouses.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: divider),
            ),
            child: Text(
              'Aucune maison disponible pour le moment.',
              style: TextStyle(color: sub, fontWeight: FontWeight.w700),
            ),
          ),
        for (final house in ownerHouses) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: house.status.color(isDark).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.home_work_outlined, color: house.status.color(isDark)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        house.title,
                        style: TextStyle(color: text, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${house.quartier} • ${_priceLabel(house.price)}',
                        style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: house.status.color(isDark).withOpacity(0.16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    house.status.label,
                    style: TextStyle(
                      color: house.status.color(isDark),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Modifier',
                  onPressed: () => _openEditHouseSheet(house),
                  icon: Icon(Icons.edit_outlined, color: sub),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  onPressed: () => _deleteHouse(house),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'Suivi des loyers',
                style: TextStyle(
                  color: text,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final selected =
                    await _pickRentMonth(initialMonthKey: monthKey);
                if (selected == null) return;
                final normalized = _normalizeMonthKey(selected);
                if (normalized == null) return;
                if (!mounted) return;
                setState(() => _rentDashboardMonthKey = normalized);
                unawaited(_maybeNotifyOwnerAboutLateRent());
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: text,
                backgroundColor: card,
                side: BorderSide(color: divider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(
                _monthLabel(monthKey),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Rapport PDF',
              onPressed: _generatingReport
                  ? null
                  : () => _generateAndShareMonthlyReport(monthKey: monthKey),
              icon: Icon(Icons.picture_as_pdf_outlined, color: sub),
            ),
            IconButton(
              tooltip: 'Parametres',
              onPressed: _openRentSettingsSheet,
              icon: Icon(Icons.tune_rounded, color: sub),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatCard(
              title: 'Attendu',
              value: '$expectedRent USD',
              icon: Icons.request_quote_outlined,
              color: _ctaBlue,
            ),
            _StatCard(
              title: 'Encaisse',
              value: '$collectedRent USD',
              icon: Icons.check_circle_outline,
              color: const Color(0xFF2ECC71),
            ),
            _StatCard(
              title: 'Reste',
              value: '$remainingRent USD',
              icon: Icons.pending_actions_outlined,
              color: const Color(0xFFFF7043),
            ),
            _StatCard(
              title: 'Taux',
              value: '$coveragePct%',
              icon: Icons.pie_chart_outline,
              color: _accent,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildMonthlyRentStatsCard(
          isDark: isDark,
          card: card,
          text: text,
          sub: sub,
          divider: divider,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: divider),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: sub),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _rentSearchCtrl,
                  style: TextStyle(color: text, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: 'Rechercher un locataire',
                    hintStyle: TextStyle(color: sub),
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (_rentSearchQuery.trim().isNotEmpty)
                IconButton(
                  onPressed: () => _rentSearchCtrl.clear(),
                  icon: const Icon(Icons.close, color: _accent),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Tous'),
              selected: _rentFilter == 'all',
              onSelected: (_) => setState(() => _rentFilter = 'all'),
            ),
            ChoiceChip(
              label: const Text('Payes'),
              selected: _rentFilter == 'paid',
              onSelected: (_) => setState(() => _rentFilter = 'paid'),
            ),
            ChoiceChip(
              label: const Text('Impayes'),
              selected: _rentFilter == 'unpaid',
              onSelected: (_) => setState(() => _rentFilter = 'unpaid'),
            ),
            if (arrearsTenants.isNotEmpty)
              _ActionChipButton(
                icon: Icons.notifications_active_outlined,
                label: 'Impayes (${arrearsTenants.length})',
                color: const Color(0xFFFF7043),
                onTap: () => _openRentArrearsSheet(
                  tenants: arrearsTenants,
                  monthKey: monthKey,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_tenants.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: divider),
            ),
            child: Text(
              'Aucun locataire enregistre.',
              style: TextStyle(color: sub, fontWeight: FontWeight.w700),
            ),
          )
        else if (filteredTenants.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: divider),
            ),
            child: Text(
              'Aucun locataire pour ce filtre.',
              style: TextStyle(color: sub, fontWeight: FontWeight.w700),
            ),
          ),
        for (final tenant in filteredTenants) ...[
          Builder(
            builder: (context) {
              final paid = paidForMonth(tenant);
              final lastPaid = _normalizeMonthKey(tenant.paidMonthKey);
              final lastPaidLabel =
                  lastPaid == null ? '-' : _monthLabel(lastPaid);
              final houseRef = _houseById(tenant.houseId);

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tenant.name,
                            style: TextStyle(
                              color: text,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: paid
                                ? const Color(0xFF2ECC71).withOpacity(0.16)
                                : const Color(0xFFFF7043).withOpacity(0.16),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            paid
                                ? 'Paye • ${_monthLabel(monthKey)}'
                                : 'Impayé • ${_monthLabel(monthKey)}',
                            style: TextStyle(
                              color: paid
                                  ? const Color(0xFF2ECC71)
                                  : const Color(0xFFFF7043),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Actions',
                          icon: Icon(Icons.more_vert, color: sub),
                          onSelected: (v) {
                            switch (v) {
                              case 'edit_house_location':
                                if (houseRef == null) {
                                  _showInfo('Maison introuvable.');
                                  return;
                                }
                                _openEditHouseLocationSheet(houseRef);
                                return;
                              case 'qr':
                                _openPaymentQrSheet(
                                  tenant: tenant,
                                  house: houseRef,
                                  monthKey: monthKey,
                                );
                                return;
                              case 'receipt':
                                _generateAndShareQuittance(
                                  tenant: tenant,
                                  house: houseRef,
                                  monthKey: monthKey,
                                );
                                return;
                              case 'terminate':
                                _terminateLease(tenant.id);
                                return;
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'edit_house_location',
                              child: Text('Modifier localisation'),
                            ),
                            const PopupMenuItem(
                              value: 'qr',
                              child: Text('QR paiement'),
                            ),
                            if (paid)
                              const PopupMenuItem(
                                value: 'receipt',
                                child: Text('Generer quittance'),
                              ),
                            const PopupMenuItem(
                              value: 'terminate',
                              child: Text('Terminer contrat'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Maison louee: ${houseRef?.title ?? '-'}',
                      style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Telephone: ${tenant.phone}',
                      style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Montant mensuel: ${_priceLabel(tenant.monthlyRent)}',
                      style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                    ),
                    if (lastPaid != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Dernier paiement: $lastPaidLabel',
                        style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ActionChipButton(
                          icon: paid
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          label: paid ? 'Marquer impaye' : 'Marquer paye',
                          color: paid
                              ? const Color(0xFFFF7043)
                              : const Color(0xFF2ECC71),
                          onTap: () => _toggleRentStatus(tenant.id),
                        ),
                        _ActionChipButton(
                          icon: Icons.call_outlined,
                          label: 'Appeler',
                          color: _ctaBlue,
                          onTap: () =>
                              _launchOrSnack(Uri.parse('tel:${tenant.phone}')),
                        ),
                        _ActionChipButton(
                          icon: Icons.sms_outlined,
                          label: 'SMS',
                          color: _accent,
                          onTap: () =>
                              _launchOrSnack(Uri.parse('sms:${tenant.phone}')),
                        ),
                        _ActionChipButton(
                          icon: Icons.qr_code_2_rounded,
                          label: 'QR paiement',
                          color: _ctaBlue,
                          onTap: () => _openPaymentQrSheet(
                            tenant: tenant,
                            house: _houseById(tenant.houseId),
                            monthKey: monthKey,
                          ),
                        ),
                        if (paid)
                          _ActionChipButton(
                            icon: Icons.picture_as_pdf_outlined,
                            label: 'Quittance',
                            color: _ctaBlue,
                            onTap: () => _generateAndShareQuittance(
                              tenant: tenant,
                              house: _houseById(tenant.houseId),
                              monthKey: monthKey,
                            ),
                          ),
                        _ActionChipButton(
                          icon: Icons.free_cancellation_outlined,
                          label: 'Terminer contrat',
                          color: Colors.redAccent,
                          onTap: () => _terminateLease(tenant.id),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildMonthlyRentStatsCard({
    required bool isDark,
    required Color card,
    required Color text,
    required Color sub,
    required Color divider,
  }) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: divider),
        ),
        child: Text(
          'Connectez-vous pour voir les statistiques mensuelles.',
          style: TextStyle(color: sub, fontWeight: FontWeight.w700),
        ),
      );
    }

    final months = _recentMonthKeys(count: 6).reversed.toList();
    final stream = FirebaseFirestore.instance
        .collection(_rentPaymentsCollection)
        .where('ownerId', isEqualTo: me.uid)
        .where('monthKey', whereIn: months)
        .snapshots();

    String shortLabel(String monthKey) {
      final label = _monthLabel(monthKey);
      final p = label.split(' ');
      if (p.isEmpty) return label;
      final m = p.first;
      final short = m.substring(0, _minInt(3, m.length));
      return short;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: divider),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Text(
              'Erreur stats: ${snap.error}',
              style: TextStyle(color: sub, fontWeight: FontWeight.w700),
            );
          }

          final sums = <String, int>{for (final m in months) m: 0};
          for (final d in (snap.data?.docs ?? const <QueryDocumentSnapshot>[])) {
            final data = d.data() as Map<String, dynamic>? ?? const {};
            final m = (data['monthKey'] ?? '').toString();
            if (!sums.containsKey(m)) continue;
            sums[m] = (sums[m] ?? 0) + _asInt(data['amount']);
          }

          final values = months.map((m) => sums[m] ?? 0).toList();
          final maxV = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);
          final total = values.fold<int>(0, (s, v) => s + v);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Statistiques (6 mois)',
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    '$total USD',
                    style: TextStyle(color: text, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final m in months) ...[
                      _MonthBar(
                        month: shortLabel(m),
                        amount: sums[m] ?? 0,
                        maxAmount: maxV,
                        color: _ctaBlue,
                        textColor: text,
                        subColor: sub,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCommissionerTab({
    required bool isDark,
    required Color card,
    required Color text,
    required Color sub,
    required Color divider,
  }) {
    final items = _commissionerHouses;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Commissionnaire',
                style: TextStyle(color: text, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Publiez des maisons de location avec prix, quartier, Pièces, '
                'photos, description, localisation et etat (vide, occupe, a liberer).',
                style: TextStyle(color: sub, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: _newHouseAlertsEnabled,
                activeThumbColor: _accent,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  "M'informer des nouvelles maisons",
                  style: TextStyle(color: text, fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  _newHouseAlertsBusy
                      ? 'Mise a jour en cours...'
                      : 'Recevoir une notification push a chaque nouvelle maison.',
                  style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                ),
                onChanged: _newHouseAlertsBusy
                    ? null
                    : (v) => _setNewHouseAlertsEnabled(v),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openAddHouseSheet(fromCommissioner: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ctaBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.apartment_outlined),
                  label: const Text(
                    'Ajouter une maison de location',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${items.length} annonce(s) commissionnaire',
          style: TextStyle(color: sub, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: divider),
            ),
            child: Text(
              'Aucune annonce pour le moment.',
              style: TextStyle(color: sub, fontWeight: FontWeight.w700),
            ),
          ),
        for (final house in items) ...[
          _buildHouseCard(
            house: house,
            isDark: isDark,
            card: card,
            text: text,
            sub: sub,
            divider: divider,
            showTenantActions: false,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildHouseCard({
    required _HouseListing house,
    required bool isDark,
    required Color card,
    required Color text,
    required Color sub,
    required Color divider,
    required bool showTenantActions,
  }) {
    final cover = house.photos.isNotEmpty ? house.photos.first : '';
    final statusColor = house.status.color(isDark);
    final isFavorite = _favoriteIds.contains(house.id);
    final isSaved = _savedIds.contains(house.id);
    final mapPreviewUrl = _staticMapUrl(house);

    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: SizedBox(
                  height: 170,
                  width: double.infinity,
                  child: cover.isEmpty
                      ? Container(
                          color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.home_work_outlined,
                            color: sub,
                            size: 34,
                          ),
                        )
                      : InkWell(
                          onTap: () => _openPhotoViewer(house),
                          child: Image.network(
                            cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: isDark
                                  ? Colors.white10
                                  : const Color(0xFFF3F4F6),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: sub,
                                size: 34,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: statusColor.withOpacity(0.35)),
                  ),
                  child: Text(
                    house.status.label,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
              if (house.photos.length > 1)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.52),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'Plusieurs photos',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        house.title,
                        style: TextStyle(
                          color: text,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _priceLabel(house.price),
                      style: const TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  house.description,
                  style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  '${house.quartier} • ${house.bedrooms} pièces',
                  style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Localisation: ${house.location}',
                  style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                ),
                if (house.hasCoordinates && mapPreviewUrl != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _launchOrSnack(
                      Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(_mapsQueryFromHouse(house))}',
                      ),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 138,
                        child: Image.network(
                          mapPreviewUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                            alignment: Alignment.center,
                            child: Text(
                              'Carte indisponible',
                              style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ActionChipButton(
                      icon: Icons.photo_library_outlined,
                      label: 'Photos',
                      color: _ctaBlue,
                      onTap: () => _openPhotoViewer(house),
                    ),
                    _ActionChipButton(
                      icon: Icons.location_on_outlined,
                      label: 'Localisation',
                      color: _accent,
                      onTap: () => _launchOrSnack(
                        Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(_mapsQueryFromHouse(house))}',
                        ),
                      ),
                    ),
                    _ActionChipButton(
                      icon: Icons.call_outlined,
                      label: 'Appeler',
                      color: const Color(0xFF2ECC71),
                      onTap: () => house.ownerPhone.trim().isEmpty
                          ? _showInfo('Aucun numero disponible.')
                          : _launchOrSnack(Uri.parse('tel:${house.ownerPhone}')),
                    ),
                    _ActionChipButton(
                      icon: Icons.sms_outlined,
                      label: 'Message',
                      color: const Color(0xFF5C6BC0),
                      onTap: () => house.ownerPhone.trim().isEmpty
                          ? _showInfo('Aucun numero disponible.')
                          : _launchOrSnack(Uri.parse('sms:${house.ownerPhone}')),
                    ),
                    if (!showTenantActions)
                      _ActionChipButton(
                        icon: Icons.edit_outlined,
                        label: 'Modifier',
                        color: _ctaBlue,
                        onTap: () => _openEditHouseSheet(house),
                      ),
                    if (!showTenantActions)
                      _ActionChipButton(
                        icon: Icons.delete_outline_rounded,
                        label: 'Supprimer',
                        color: Colors.redAccent,
                        onTap: () => _deleteHouse(house),
                      ),
                    if (showTenantActions)
                      _ActionChipButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Contacter',
                        color: _ctaBlue,
                        onTap: () => _openContactSheet(house),
                      ),
                    if (showTenantActions)
                      _ActionChipButton(
                        icon: isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: isFavorite ? 'Favori' : 'Favoris',
                        color: const Color(0xFFE91E63),
                        onTap: () {
                          setState(() {
                            if (isFavorite) {
                              _favoriteIds.remove(house.id);
                            } else {
                              _favoriteIds.add(house.id);
                            }
                          });
                        },
                      ),
                    if (showTenantActions)
                      _ActionChipButton(
                        icon: isSaved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_add_outlined,
                        label: isSaved ? 'Enregistree' : 'Enregistrer',
                        color: const Color(0xFF607D8B),
                        onTap: () {
                          setState(() {
                            if (isSaved) {
                              _savedIds.remove(house.id);
                            } else {
                              _savedIds.add(house.id);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSelect extends StatelessWidget {
  const _FilterSelect({
    required this.width,
    required this.value,
    required this.label,
    required this.options,
    required this.onChanged,
  });

  final double width;
  final String value;
  final String label;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;

    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: sub, fontWeight: FontWeight.w600),
          filled: true,
          fillColor: bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: divider),
          ),
        ),
        dropdownColor: bg,
        style: TextStyle(color: text, fontWeight: FontWeight.w700),
        items: options
            .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          onChanged(v);
        },
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
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final divider = isDark ? Colors.white12 : Colors.black12;

    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: text, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.month,
    required this.amount,
    required this.maxAmount,
    required this.color,
    required this.textColor,
    required this.subColor,
    required this.isDark,
  });

  final String month;
  final int amount;
  final int maxAmount;
  final Color color;
  final Color textColor;
  final Color subColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    const double chartHeight = 88;
    final pct = maxAmount <= 0 ? 0.0 : (amount / maxAmount);
    final barHeight = (chartHeight * pct).clamp(0.0, chartHeight);
    final track = isDark ? Colors.white12 : Colors.black12;

    return SizedBox(
      width: 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$amount',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: subColor,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: chartHeight,
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 18,
              height: chartHeight,
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(99),
              ),
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                width: 18,
                height: barHeight,
                decoration: BoxDecoration(
                  color: color.withOpacity(isDark ? 0.85 : 1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            month,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.textColor,
    required this.subColor,
    required this.divider,
    this.keyboardType,
    this.validator,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final Color textColor;
  final Color subColor;
  final Color divider;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subColor),
        filled: true,
        fillColor: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: divider),
        ),
      ),
    );
  }
}

enum _HousingStatus { vacant, occupied, toRelease }

extension _HousingStatusX on _HousingStatus {
  String get label {
    switch (this) {
      case _HousingStatus.vacant:
        return 'Vide';
      case _HousingStatus.occupied:
        return 'Occupe';
      case _HousingStatus.toRelease:
        return 'A liberer';
    }
  }

  Color color(bool isDark) {
    switch (this) {
      case _HousingStatus.vacant:
        return const Color(0xFF2ECC71);
      case _HousingStatus.occupied:
        return const Color(0xFFFF7043);
      case _HousingStatus.toRelease:
        return isDark ? const Color(0xFFFFC107) : const Color(0xFFE67E22);
    }
  }
}

class _HouseListing {
  const _HouseListing({
    required this.id,
    required this.title,
    required this.quartier,
    required this.bedrooms,
    required this.price,
    required this.description,
    required this.location,
    required this.photos,
    required this.status,
    required this.ownerName,
    required this.ownerPhone,
    required this.fromCommissioner,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String title;
  final String quartier;
  final int bedrooms;
  final int price;
  final String description;
  final String location;
  final List<String> photos;
  final _HousingStatus status;
  final String ownerName;
  final String ownerPhone;
  final bool fromCommissioner;
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => latitude != null && longitude != null;

  _HouseListing copyWith({
    String? id,
    String? title,
    String? quartier,
    int? bedrooms,
    int? price,
    String? description,
    String? location,
    List<String>? photos,
    _HousingStatus? status,
    String? ownerName,
    String? ownerPhone,
    bool? fromCommissioner,
    double? latitude,
    double? longitude,
  }) {
    return _HouseListing(
      id: id ?? this.id,
      title: title ?? this.title,
      quartier: quartier ?? this.quartier,
      bedrooms: bedrooms ?? this.bedrooms,
      price: price ?? this.price,
      description: description ?? this.description,
      location: location ?? this.location,
      photos: photos ?? this.photos,
      status: status ?? this.status,
      ownerName: ownerName ?? this.ownerName,
      ownerPhone: ownerPhone ?? this.ownerPhone,
      fromCommissioner: fromCommissioner ?? this.fromCommissioner,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}

class _TenantRecord {
  static const Object _unset = Object();

  const _TenantRecord({
    required this.id,
    required this.name,
    required this.phone,
    required this.houseId,
    required this.monthlyRent,
    required this.rentPaid,
    this.paidMonthKey,
  });

  final String id;
  final String name;
  final String phone;
  final String houseId;
  final int monthlyRent;
  final bool rentPaid;
  final String? paidMonthKey;

  _TenantRecord copyWith({
    String? id,
    String? name,
    String? phone,
    String? houseId,
    int? monthlyRent,
    bool? rentPaid,
    Object? paidMonthKey = _unset,
  }) {
    return _TenantRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      houseId: houseId ?? this.houseId,
      monthlyRent: monthlyRent ?? this.monthlyRent,
      rentPaid: rentPaid ?? this.rentPaid,
      paidMonthKey: identical(paidMonthKey, _unset)
          ? this.paidMonthKey
          : paidMonthKey as String?,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

// Tes imports originaux
import '../widgets/services/services_tiles/rapid_services_tile.dart';
import '../widgets/services/services_tiles/job_announcement_tile.dart';
import '../widgets/services/services_tiles/daily_tip_tile.dart';
import '../../../chat/presentation/pages/chat_list_page.dart';
import '../../../live/live_page.dart';
import '../../../marketplace/marketplace_page.dart';
import 'health_space_picker_page.dart';
import 'news_feed_page.dart';
import 'profile_page_widgets.dart';
import 'package:lualaba_konnect/features/adult/adult_space_page.dart';
import 'package:lualaba_konnect/features/admin/presentation/pages/identity_validation_admin_page.dart';
import 'profile_settings_page.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/weather_widget.dart';
import '../widgets/header_widget.dart';
import '../widgets/masta_card.dart';
import '../widgets/copper_card.dart';
import '../../../../core/config.dart';
import '../../../../core/notification_service.dart';
import '../../../../core/theme_controller.dart';

class _DashboardMediaEntry {
  final String url;
  final bool isVideo;
  const _DashboardMediaEntry({required this.url, required this.isVideo});
}

List<_DashboardMediaEntry> _extractDashboardMedia(Map<String, dynamic> data) {
  final out = <_DashboardMediaEntry>[];
  final rawMedia = data['media'];
  if (rawMedia is List) {
    for (final raw in rawMedia) {
      if (raw is! Map) continue;
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      final url = (map['url'] ?? '').toString().trim();
      if (url.isEmpty) continue;
      final type = (map['type'] ?? '').toString().toLowerCase();
      out.add(_DashboardMediaEntry(url: url, isVideo: type == 'video'));
    }
  }
  if (out.isNotEmpty) return out;

  final images = (data['images'] is List)
      ? List<String>.from((data['images'] as List).map((e) => e.toString()))
      : const <String>[];
  final videos = (data['videos'] is List)
      ? List<String>.from((data['videos'] as List).map((e) => e.toString()))
      : const <String>[];

  out.addAll(
    images
        .where((u) => u.trim().isNotEmpty)
        .map((u) => _DashboardMediaEntry(url: u, isVideo: false)),
  );
  out.addAll(
    videos
        .where((u) => u.trim().isNotEmpty)
        .map((u) => _DashboardMediaEntry(url: u, isVideo: true)),
  );
  return out;
}

_DashboardMediaEntry? _firstDashboardMedia(
  Map<String, dynamic> data, {
  bool preferImage = true,
}) {
  final items = _extractDashboardMedia(data);
  if (items.isEmpty) return null;
  if (preferImage) {
    for (final item in items) {
      if (!item.isVideo) return item;
    }
  }
  return items.first;
}

class _DashboardVideoThumbnail extends StatefulWidget {
  final String videoUrl;
  final BoxFit fit;
  const _DashboardVideoThumbnail({
    required this.videoUrl,
    this.fit = BoxFit.cover,
  });

  @override
  State<_DashboardVideoThumbnail> createState() =>
      _DashboardVideoThumbnailState();
}

class _DashboardVideoThumbnailState extends State<_DashboardVideoThumbnail> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _DashboardVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _init();
    }
  }

  Future<void> _init() async {
    _ready = false;
    final prev = _controller;
    _controller = null;
    await prev?.dispose();
    final raw = widget.videoUrl.trim();
    if (raw.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(raw));
      await c.setVolume(0);
      await c.initialize();
      await c.seekTo(Duration.zero);
      await c.pause();
      if (!mounted) {
        await c.dispose();
        return;
      }
      _controller = c;
      _ready = true;
      setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (!_ready || c == null || !c.value.isInitialized) {
      return Container(color: const Color(0xFF202C33));
    }
    final size = c.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return Container(color: const Color(0xFF202C33));
    }
    return Container(
      color: const Color(0xFF202C33),
      child: SizedBox.expand(
        child: FittedBox(
          fit: widget.fit,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(c),
          ),
        ),
      ),
    );
  }
}

class ModernDashboard extends StatefulWidget {
  const ModernDashboard({super.key});
  @override
  State<ModernDashboard> createState() => _ModernDashboardState();
}

// global notifier to allow pages to hide/show the floating nav bar
class ModernDashboardGlobals {
  static ValueNotifier<bool> navBarVisible = ValueNotifier<bool>(true);
}

class _ModernDashboardState extends State<ModernDashboard> {
  final GlobalKey<ChatListPageState> _chatKey = GlobalKey<ChatListPageState>();
  int _selectedIndex = 0;
  final ThemeController _themeCtrl = ThemeController.instance;
  bool _isDarkMode = false;
  bool _notificationsEnabled = true;
  bool _isAdmin = false;
  bool _adminChecked = false;
  double _dataLanUsedGb = 0;
  double? _dataLanTotalGb;
  String _dataLanSource = 'cache';
  DateTime? _dataLanUpdatedAt;
  bool _isRefreshingLan = false;
  // --- partage alerte ---
  List<Map<String, String>> _contacts = [];
  List<Map<String, String>> _savedRecipients = [];
  final Set<String> _selectedEmails = {};
  String _messageType = 'auto';
  bool _isSendingAlert = false;

  @override
  void initState() {
    super.initState();
    _isDarkMode = _themeCtrl.isDark;
    _themeCtrl.addListener(_onThemeChanged);
    _loadNotificationPref();
    _loadDataLanUsage();
    _loadAdminClaim();
  }

  void _onThemeChanged() {
    if (!mounted) return;
    setState(() => _isDarkMode = _themeCtrl.isDark);
  }

  Future<void> _loadNotificationPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('notifications_enabled');
      if (enabled != null && mounted) {
        setState(() => _notificationsEnabled = enabled);
      }
    } catch (_) {}
  }

  Future<void> _loadAdminClaim() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _adminChecked = true);
        return;
      }
      final res = await user.getIdTokenResult(true);
      final claims = res.claims ?? {};
      if (claims['admin'] == true) {
        if (mounted) {
          setState(() {
            _isAdmin = true;
            _adminChecked = true;
          });
        }
        return;
      }
      try {
        final snap = await FirebaseFirestore.instance
            .collection('admin_users')
            .doc(user.uid)
            .get();
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
    } catch (_) {
      if (mounted) setState(() => _adminChecked = true);
    }
  }

  double? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    try {
      return double.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  double? _pickUsageFrom(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = _parseNum(data[k]);
      if (v != null) return v;
    }
    return null;
  }

  ({double? used, double? total}) _extractLanUsage(Map<String, dynamic> data) {
    final usedKeys = <String>[
      'dataLanUsedGb',
      'dataLanUsed',
      'dataUsedGb',
      'dataUsed',
      'dataUsageGb',
      'lanUsedGb',
    ];
    final totalKeys = <String>[
      'dataLanTotalGb',
      'dataLanTotal',
      'dataTotalGb',
      'dataCapGb',
      'dataLimitGb',
      'lanTotalGb',
    ];

    double? used = _pickUsageFrom(data, usedKeys);
    double? total = _pickUsageFrom(data, totalKeys);

    if (used == null || total == null) {
      final nested = data['data'];
      if (nested is Map) {
        final m = Map<String, dynamic>.from(nested);
        used ??= _pickUsageFrom(m, usedKeys);
        total ??= _pickUsageFrom(m, totalKeys);
      }
    }

    if (used == null || total == null) {
      final nested = data['lan'];
      if (nested is Map) {
        final m = Map<String, dynamic>.from(nested);
        used ??= _pickUsageFrom(m, usedKeys);
        total ??= _pickUsageFrom(m, totalKeys);
      }
    }

    return (used: used, total: total);
  }

  @override
  void dispose() {
    _themeCtrl.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _loadDataLanUsage() async {
    if (mounted) setState(() => _isRefreshingLan = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUsed = prefs.getDouble('data_lan_used_gb');
      final cachedTotal = prefs.getDouble('data_lan_total_gb');
      final cachedUpdatedAt = prefs.getInt('data_lan_updated_at');
      if (mounted) {
        if (cachedUsed != null) _dataLanUsedGb = cachedUsed;
        if (cachedTotal != null) _dataLanTotalGb = cachedTotal;
        if (cachedUpdatedAt != null)
          _dataLanUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
            cachedUpdatedAt,
          );
        _dataLanSource = 'cache';
        setState(() {});
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final cols = ['classic_users', 'pro_users', 'enterprise_users'];
      Map<String, dynamic>? data;
      for (final col in cols) {
        final snap = await FirebaseFirestore.instance
            .collection(col)
            .doc(user.uid)
            .get();
        if (snap.exists) {
          data = snap.data();
          break;
        }
      }
      if (data == null) return;

      final usage = _extractLanUsage(data);
      final used = usage.used;
      final total = usage.total;

      if (used != null) {
        await prefs.setDouble('data_lan_used_gb', used);
        if (mounted) {
          _dataLanUsedGb = used;
          _dataLanSource = 'live';
          _dataLanUpdatedAt = DateTime.now();
          setState(() {});
        }
      }
      if (total != null) {
        await prefs.setDouble('data_lan_total_gb', total);
        if (mounted) {
          _dataLanTotalGb = total;
          _dataLanSource = 'live';
          _dataLanUpdatedAt = DateTime.now();
          setState(() {});
        }
      }
      if (used != null || total != null) {
        await prefs.setInt(
          'data_lan_updated_at',
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _isRefreshingLan = false);
  }

  // --- FONCTIONS SOS ---
  Future<void> _makeCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  // ignore: unused_element
  Future<void> _sendGPSAlert() async {
    try {
      HapticFeedback.heavyImpact();
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final String message =
          "🚨 SOS URGENCE - 🚨\nPosition : https://www.google.com/maps?q=${position.latitude},${position.longitude}";
      final Uri smsUri = Uri(
        scheme: 'sms',
        path: '112',
        queryParameters: {'body': message},
      );
      if (await canLaunchUrl(smsUri)) await launchUrl(smsUri);
    } catch (e) {
      debugPrint("Erreur GPS : $e");
    }
  }

  Future<void> _loadContacts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      // Only load contacts that belong to this user (no global scan of users)
      final q = await FirebaseFirestore.instance
          .collection('contacts')
          .where('owner', isEqualTo: user.uid)
          .limit(200)
          .get();
      _contacts = [];
      if (q.docs.isNotEmpty) {
        for (var d in q.docs) {
          final data = d.data();
          final email = (data['email'] ?? '').toString();
          final name = (data['name'] ?? data['email'] ?? '').toString();
          final Map<String, String> entry = {'email': email, 'name': name};
          // Try to resolve a uid for this contact email and store it for reuse
          if (email.isNotEmpty) {
            try {
              final resolved = await _findUidByEmail(email);
              if (resolved != null && resolved.isNotEmpty)
                entry['uid'] = resolved;
            } catch (_) {}
          }
          _contacts.add(entry);
        }
      }
      // Charger les emails ajoutés manuellement depuis SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final manual = prefs.getStringList('alert_manual_emails') ?? <String>[];
        for (var e in manual.reversed) {
          if (!_contacts.any((c) => (c['email'] ?? '') == e)) {
            final Map<String, String> me = {'email': e, 'name': e};
            try {
              final resolved = await _findUidByEmail(e);
              if (resolved != null && resolved.isNotEmpty) me['uid'] = resolved;
            } catch (_) {}
            _contacts.insert(0, me);
          }
        }
      } catch (_) {}
      setState(() {});
    } catch (_) {}
  }

  Future<void> _loadSavedRecipients() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('alert_recipients') ?? <String>[];
      final List<Map<String, String>> list = [];
      for (final s in stored) {
        try {
          final decoded = jsonDecode(s);
          if (decoded is Map) {
            list.add({
              'email': decoded['email']?.toString() ?? '',
              'uid': decoded['uid']?.toString() ?? '',
              'name': decoded['email']?.toString() ?? '',
            });
            continue;
          }
        } catch (_) {}
        // fallback: simple email
        final email = s.toString();
        list.add({'email': email, 'uid': '', 'name': email});
      }
      if (mounted) setState(() => _savedRecipients = list);
    } catch (_) {}
  }

  Future<void> _removeSavedRecipient(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('alert_recipients') ?? <String>[];
      final remaining = <String>[];
      for (final s in stored) {
        try {
          final decoded = jsonDecode(s);
          if (decoded is Map &&
              decoded['email'] != null &&
              decoded['email'].toString().toLowerCase() == email.toLowerCase())
            continue;
        } catch (_) {
          if (s.toString().toLowerCase() == email.toLowerCase()) continue;
        }
        remaining.add(s);
      }
      await prefs.setStringList('alert_recipients', remaining);
      await _loadSavedRecipients();
    } catch (_) {}
  }

  Future<Position?> _fetchLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveAlertSettings(List<String> recipients, String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // store as list of JSON strings with email+uid when uid can be resolved
      final List<String> toStore = [];
      for (final e in recipients) {
        String? uid;
        try {
          // try to reuse resolved uid from _contacts
          for (var c in _contacts) {
            final ce = (c['email'] ?? '').toString();
            if (ce.isNotEmpty && ce.toLowerCase() == e.toLowerCase()) {
              uid = c['uid'];
              break;
            }
          }
        } catch (_) {}
        if (uid == null || uid.isEmpty) {
          try {
            uid = await _findUidByEmail(e);
          } catch (_) {
            uid = null;
          }
        }
        final map = {'email': e, 'uid': uid ?? ''};
        try {
          toStore.add(jsonEncode(map));
        } catch (_) {
          toStore.add(map.toString());
        }
      }
      await prefs.setStringList('alert_recipients', toStore);
      await prefs.setString('alert_message_type', type);
      await prefs.setBool('alert_configured', true);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _getSavedAlertSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configured = prefs.getBool('alert_configured') ?? false;
      if (!configured) return null;
      final stored = prefs.getStringList('alert_recipients') ?? <String>[];
      final type = prefs.getString('alert_message_type') ?? 'auto';
      if (stored.isEmpty) return null;
      // stored entries are strings like {email:..., uid:...} — parse to extract emails
      final List<String> emails = [];
      for (final s in stored) {
        try {
          final decoded = jsonDecode(s);
          if (decoded is Map && decoded['email'] != null) {
            emails.add(decoded['email'].toString());
            continue;
          }
        } catch (_) {}
        try {
          // crude parse as fallback
          final m =
              RegExp(r'''email':?
\s*([^,}\]]+)''').firstMatch(s) ??
              RegExp(
                r'''['"]?email['"]?\s*:\s*['"]?([^'\"]+)['"]?''',
              ).firstMatch(s);
          if (m != null) {
            var raw = m.group(1) ?? '';
            raw = raw.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
            emails.add(raw.trim());
            continue;
          }
        } catch (_) {}
        // fallback: treat whole string as email
        emails.add(s);
      }
      if (emails.isEmpty) return null;
      return {'recipients': emails, 'type': type};
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveManualEmail(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('alert_manual_emails') ?? <String>[];
      if (!list.contains(email)) {
        list.add(email);
        await prefs.setStringList('alert_manual_emails', list);
      }
    } catch (_) {}
  }

  Future<void> _sendSosNotifier({
    required String recipientUid,
    required String chatId,
    required String alertId,
    required String senderName,
    required String senderPhoto,
    required String? idToken,
  }) async {
    if (recipientUid.trim().isEmpty || chatId.trim().isEmpty) return;
    if (idToken == null || idToken.trim().isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse(kNotifierUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'recipients': [recipientUid],
          'title': 'SOS urgent',
          'body': '$senderName a besoin d aide immediatement.',
          'senderAvatarUrl': senderPhoto,
          'data': {
            'type': 'sos_alert',
            'chatId': chatId,
            'chatName': senderName,
            'fromName': senderName,
            'alertId': alertId,
          },
        }),
      );
      debugPrint(
        '[Notifier][sos_alert] status=${response.statusCode} body=${response.body}',
      );
    } catch (e) {
      debugPrint('Notifier SOS error: $e');
    }
  }

  Future<void> _sendAlertWithSettings(
    List<String> recipients,
    String type,
  ) async {
    if (recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun destinataire sélectionné')),
      );
      return;
    }
    setState(() => _isSendingAlert = true);
    try {
      final pos = await _fetchLocation();
      final user = FirebaseAuth.instance.currentUser;
      final payload = {
        'fromUid': user?.uid,
        'fromName': user?.displayName ?? '',
        'recipients': recipients,
        'messageType': type,
        'location': pos == null
            ? null
            : {
                'lat': pos.latitude,
                'lng': pos.longitude,
                'ts': DateTime.now().toIso8601String(),
              },
        'createdAt': DateTime.now().toIso8601String(),
        'status': 'pending_ai_send',
      };
      await FirebaseFirestore.instance.collection('alerts').add(payload);
      // Poster un message de type 'alert' dans le chat pour chaque destinataire
      try {
        final me = FirebaseAuth.instance.currentUser;
        final senderName = (me?.displayName ?? '').trim();
        final senderPhoto = (me?.photoURL ?? '').trim();
        final fallbackSenderName = senderName.isNotEmpty
            ? senderName
            : ((me?.email ?? '').trim().isNotEmpty
                  ? me!.email!.trim()
                  : 'Un proche');
        final notifierToken = me == null ? null : await me.getIdToken();
        final pushTasks = <Future<void>>[];

        for (var email in recipients) {
          try {
            String? otherUid;
            // try to use cached/resolved uid from the user's contacts list
            try {
              for (var c in _contacts) {
                final e = (c['email'] ?? '').toString();
                if (e.isNotEmpty && e.toLowerCase() == email.toLowerCase()) {
                  otherUid = c['uid'];
                  break;
                }
              }
            } catch (_) {}

            // fallback to resolving by email if uid not available
            if (otherUid == null || otherUid.isEmpty) {
              otherUid = await _findUidByEmail(email);
            }

            if (otherUid == null) continue;
            final chatId = await _findOrCreateDirectChat(otherUid);
            if (chatId == null) continue;
            final now = DateTime.now();
            final dateStr = DateFormat('dd/MM/yyyy').format(now);
            final timeStr = DateFormat('HH:mm').format(now);
            final composedText =
                'Alerte ! je suis en danger je demande du secours\nDate : $dateStr\nHeure : $timeStr';
            final msgId = await _postChatMessage(chatId, {
              'text': composedText,
              'type': 'alert',
              'fromName': fallbackSenderName,
              'alertModel': 'standard',
              'location': pos == null
                  ? null
                  : {'lat': pos.latitude, 'lng': pos.longitude},
            });
            if (msgId != null) {
              try {
                await FirebaseFirestore.instance
                    .collection('user_alerts')
                    .doc(otherUid)
                    .collection('pending')
                    .doc(msgId)
                    .set({
                      'chatId': chatId,
                      'chatName': fallbackSenderName,
                      'fromUid': me?.uid,
                      'fromName': fallbackSenderName,
                      'fromPhoto': senderPhoto,
                      'location': pos == null
                          ? null
                          : {
                              'lat': pos.latitude,
                              'lng': pos.longitude,
                              'ts': DateTime.now().toIso8601String(),
                            },
                      'createdAt': FieldValue.serverTimestamp(),
                    });
                pushTasks.add(
                  _sendSosNotifier(
                    recipientUid: otherUid,
                    chatId: chatId,
                    alertId: msgId,
                    senderName: fallbackSenderName,
                    senderPhoto: senderPhoto,
                    idToken: notifierToken,
                  ),
                );
              } catch (_) {}
            }
          } catch (_) {}
        }

        if (pushTasks.isNotEmpty) {
          await Future.wait(pushTasks);
        }
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alerte créée, envoi en cours')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur envoi alerte: $e')));
    } finally {
      setState(() => _isSendingAlert = false);
    }
  }

  Future<void> _onSignalPressed() async {
    final saved = await _getSavedAlertSettings();
    if (saved != null) {
      final rec = List<String>.from(saved['recipients'] as List);
      final type = saved['type'] as String;
      await _sendAlertWithSettings(rec, type);
    } else {
      // ouvrir configuration si pas encore défini
      _openShareAlertMenu();
    }
  }

  Future<String?> _findUidByEmail(String email) async {
    try {
      final cols = ['classic_users', 'pro_users', 'enterprise_users'];
      for (var col in cols) {
        final q = await FirebaseFirestore.instance
            .collection(col)
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) return q.docs.first.id;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _findOrCreateDirectChat(String otherUid) async {
    try {
      final me = FirebaseAuth.instance.currentUser;
      if (me == null) return null;
      final meUid = me.uid;
      // chercher un chat existant contenant les deux participants
      final query = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: meUid)
          .limit(50)
          .get();
      for (var d in query.docs) {
        final data = d.data();
        final parts = (data['participants'] is List)
            ? List.from(data['participants'])
            : [];
        if (parts.contains(otherUid) && parts.length == 2) return d.id;
      }
      // créer nouveau chat 1:1
      final chatRef = FirebaseFirestore.instance.collection('chats').doc();
      final map = {
        'participants': [meUid, otherUid],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCounts': {otherUid: 0, meUid: 0},
      };
      await chatRef.set(map);
      return chatRef.id;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _postChatMessage(
    String chatId,
    Map<String, dynamic> data,
  ) async {
    try {
      final me = FirebaseAuth.instance.currentUser;
      if (me == null) return null;
      final chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId);
      final msgRef = chatRef.collection('messages').doc();
      final msg = {
        'senderId': me.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'delivered': false,
        'deliveredAt': null,
        ...data,
      };
      await msgRef.set(msg);
      final msgId = msgRef.id;
      // mettre à jour meta du chat
      try {
        await chatRef.update({
          'lastMessage': data['text'] ?? '',
          'lastMessageTime': FieldValue.serverTimestamp(),
        });
        // incrémenter unread pour autres participants
        final snap = await chatRef.get();
        final participants = (snap.data()?['participants'] is List)
            ? List.from(snap.data()?['participants'] ?? [])
            : [];
        WriteBatch batch = FirebaseFirestore.instance.batch();
        for (var p in participants) {
          if (p != me.uid)
            batch.update(chatRef, {'unreadCounts.$p': FieldValue.increment(1)});
        }
        await batch.commit();
      } catch (_) {}
      return msgId;
    } catch (_) {}
    return null;
  }

  // ignore: unused_element
  Future<void> _sendAlertViaAI() async {
    if (_selectedEmails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun destinataire sélectionné')),
      );
      return;
    }
    setState(() => _isSendingAlert = true);
    try {
      final pos = await _fetchLocation();
      final user = FirebaseAuth.instance.currentUser;
      final payload = {
        'fromUid': user?.uid,
        'fromName': user?.displayName ?? '',
        'recipients': _selectedEmails.toList(),
        'messageType': _messageType,
        'location': pos == null
            ? null
            : {
                'lat': pos.latitude,
                'lng': pos.longitude,
                'ts': DateTime.now().toIso8601String(),
              },
        'createdAt': DateTime.now().toIso8601String(),
        'status': 'pending_ai_send',
      };
      await FirebaseFirestore.instance.collection('alerts').add(payload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alerte créée, envoi en cours')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur envoi alerte: $e')));
    } finally {
      setState(() => _isSendingAlert = false);
    }
  }

  void _openShareAlertMenu() async {
    await _loadContacts();
    await _loadSavedRecipients();
    final bool isDark = ThemeController.instance.isDark;
    final Color sheetBg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final Color sheetText = isDark ? Colors.white : Colors.black87;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final TextEditingController emailController =
                TextEditingController();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: DefaultTextStyle(
                  style: TextStyle(color: sheetText),
                  child: IconTheme(
                    data: IconThemeData(color: sheetText),
                    child: Column(
                      children: [
                        // saved recipients chips
                        if (_savedRecipients.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8,
                            ),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: _savedRecipients.map((r) {
                                final email = r['email'] ?? '';
                                final name =
                                    (r['name'] != null && r['name']!.isNotEmpty)
                                    ? r['name']!
                                    : email;
                                return InputChip(
                                  label: Text(name),
                                  avatar: const Icon(Icons.person, size: 18),
                                  onPressed: () {
                                    // toggle selection
                                    if (_selectedEmails.contains(email)) {
                                      _selectedEmails.remove(email);
                                    } else {
                                      _selectedEmails.add(email);
                                    }
                                    setLocalState(() {});
                                  },
                                  selected: _selectedEmails.contains(email),
                                  onDeleted: () async {
                                    await _removeSavedRecipient(email);
                                    setLocalState(() {});
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                        const SizedBox(height: 12),
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Selectionnez les personnes a signaler en cas de problème',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                    hintText: 'Ajouter un email manuellement',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () async {
                                  final text = emailController.text.trim();
                                  if (text.isEmpty) return;
                                  final isValid = RegExp(
                                    r"^[^@\s]+@[^@\s]+\.[^@\s]+$",
                                  ).hasMatch(text);
                                  if (!isValid) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Email invalide'),
                                      ),
                                    );
                                    return;
                                  }
                                  // add to contacts and select
                                  if (!_contacts.any(
                                    (c) => (c['email'] ?? '') == text,
                                  )) {
                                    _contacts.insert(0, {
                                      'email': text,
                                      'name': text,
                                    });
                                    await _saveManualEmail(text);
                                  }
                                  _selectedEmails.add(text);
                                  emailController.clear();
                                  setLocalState(() {});
                                },
                                child: const Text('Ajouter'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _contacts.isEmpty
                              ? const Center(
                                  child: Text('Aucun contact disponible'),
                                )
                              : ListView.builder(
                                  itemCount: _contacts.length,
                                  itemBuilder: (c, i) {
                                    final item = _contacts[i];
                                    final email = item['email'] ?? '';
                                    final name =
                                        (item['name']?.isNotEmpty == true)
                                        ? item['name']!
                                        : email;
                                    final checked = _selectedEmails.contains(
                                      email,
                                    );
                                    return CheckboxListTile(
                                      title: Text(name),
                                      subtitle: Text(
                                        email,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      value: checked,
                                      onChanged: (v) => setLocalState(() {
                                        if (v == true) {
                                          _selectedEmails.add(email);
                                        } else {
                                          _selectedEmails.remove(email);
                                        }
                                      }),
                                    );
                                  },
                                ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  // ouvrir modal de type/message
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: sheetBg,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(16),
                                      ),
                                    ),
                                    builder: (ctx2) {
                                      return Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: DefaultTextStyle(
                                          style: TextStyle(color: sheetText),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text(
                                                'Type de message',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              RadioListTile<String>(
                                                title: const Text(
                                                  "Urgent — Besoin d'aide",
                                                ),
                                                value: 'urgent',
                                                groupValue: _messageType,
                                                onChanged: (v) => setState(
                                                  () => _messageType =
                                                      v ?? 'auto',
                                                ),
                                              ),
                                              RadioListTile<String>(
                                                title: const Text('En danger'),
                                                value: 'danger',
                                                groupValue: _messageType,
                                                onChanged: (v) => setState(
                                                  () => _messageType =
                                                      v ?? 'auto',
                                                ),
                                              ),
                                              RadioListTile<String>(
                                                title: const Text(
                                                  'Infos seulement',
                                                ),
                                                value: 'info',
                                                groupValue: _messageType,
                                                onChanged: (v) => setState(
                                                  () => _messageType =
                                                      v ?? 'auto',
                                                ),
                                              ),
                                              RadioListTile<String>(
                                                title: const Text(
                                                  'Laisser le système décider',
                                                ),
                                                value: 'auto',
                                                groupValue: _messageType,
                                                onChanged: (v) => setState(
                                                  () => _messageType =
                                                      v ?? 'auto',
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              _isSendingAlert
                                                  ? CircularProgressIndicator(
                                                      color: Colors.orange,
                                                    )
                                                  : ElevatedButton(
                                                      onPressed: () async {
                                                        // sauvegarder les réglages pour les prochains envois
                                                        await _saveAlertSettings(
                                                          _selectedEmails
                                                              .toList(),
                                                          _messageType,
                                                        );
                                                        Navigator.of(
                                                          ctx2,
                                                        ).pop();
                                                        await _sendAlertWithSettings(
                                                          _selectedEmails
                                                              .toList(),
                                                          _messageType,
                                                        );
                                                      },
                                                      child: const Text(
                                                        'Signaler à mes proches',
                                                      ),
                                                    ),
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.of(ctx2).pop();
                                                  _openShareAlertMenu();
                                                },
                                                child: Text(
                                                  'Modifier options de partage',
                                                  style: TextStyle(
                                                    color: sheetText,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                                child: const Text('Définir'),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: Text(
                                  'Annuler',
                                  style: TextStyle(color: sheetText),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSOSMenu() {
    final bool isDark = ThemeController.instance.isDark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F171A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 25),
            _buildSOSItem(
              "Police",
              "Intervention rapide",
              "112",
              const Color(0xFF2962FF),
              Icons.shield,
            ),
            const SizedBox(height: 15),
            _buildSOSItem(
              "Ambulance",
              "Secours médical",
              "118",
              const Color(0xFFEF5350),
              Icons.medical_services,
            ),
            const SizedBox(height: 15),
            _buildSOSItem(
              "Pompiers",
              "Incendie & Sauvetage",
              "119",
              const Color(0xFFFF9100),
              Icons.local_fire_department,
            ),
            const SizedBox(height: 30),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _onSignalPressed();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFCDD2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.dangerous, color: Colors.red),
                        SizedBox(width: 10),
                        Text(
                          "Signaler à mes proches",
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'À utiliser seulement si vous vous sentez en danger réel.',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _openShareAlertMenu();
              },
              child: const Text(
                'Réglages',
                style: TextStyle(color: Colors.red),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildSOSItem(
    String title,
    String sub,
    String number,
    Color color,
    IconData icon,
  ) {
    return InkWell(
      onTap: () => _makeCall(number),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    sub,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  void _showFilterMenu(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF012E32) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Filtrer la recherche",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.location_on, color: Colors.orange),
              title: Text(
                "Proximité (Kolwezi Centre)",
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeCtrl = ThemeController.instance;
    return AnimatedBuilder(
      animation: themeCtrl,
      builder: (context, _) {
        final bool isDark = themeCtrl.isDark;
        final Color bgColor = isDark
            ? const Color(0xFF012E32)
            : const Color(0xFFF2F4F5);
        final Color textColor = isDark ? Colors.white : const Color(0xFF012E32);

        // CACHER LA NAVBAR SUR LIVE (2) ET MARKET (3)
        bool isNavBarVisible = _selectedIndex != 2 && _selectedIndex != 3;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_selectedIndex != 0) {
              setState(() => _selectedIndex = 0);
            } else {
              SystemNavigator.pop();
            }
          },
          child: Scaffold(
            backgroundColor: bgColor,
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 414),
                child: Stack(
                  children: [
                    // TRANSITION DE LUXE (ZOOM + FADE)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      switchInCurve: Curves.easeInOutQuart,
                      switchOutCurve: Curves.easeInOutQuart,
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                            final scaleAnimation = Tween<double>(
                              begin: 0.92,
                              end: 1.0,
                            ).animate(animation);
                            final fadeAnimation = CurvedAnimation(
                              parent: animation,
                              curve: const Interval(0.5, 1.0),
                            );
                            return FadeTransition(
                              opacity: fadeAnimation,
                              child: ScaleTransition(
                                scale: scaleAnimation,
                                child: child,
                              ),
                            );
                          },
                      child: _buildCurrentPage(isDark, textColor),
                    ),

                    // NAVBAR ANIMÉE
                    ValueListenableBuilder<bool>(
                      valueListenable: ModernDashboardGlobals.navBarVisible,
                      builder: (context, globalVisible, _) {
                        final visible = isNavBarVisible && globalVisible;
                        final bottomInset = MediaQuery.of(
                          context,
                        ).padding.bottom;
                        final horizontalInset = 16.0;
                        final floatingBottom = bottomInset > 0
                            ? bottomInset + 12
                            : 20.0;
                        return AnimatedPositioned(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.fastOutSlowIn,
                          left: horizontalInset,
                          right: horizontalInset,
                          bottom: visible ? floatingBottom : -120,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: visible ? 1.0 : 0.0,
                            child: FloatingNavBar(
                              isDark: isDark,
                              selectedIndex: _selectedIndex,
                              onIndexChanged: (index) =>
                                  setState(() => _selectedIndex = index),
                              chatKey: _chatKey,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentPage(bool isDark, Color textColor) {
    switch (_selectedIndex) {
      case 0:
        return _buildHomePage(
          isDark,
          textColor,
          key: const ValueKey('home_ui'),
        );
      case 1:
        return ChatListPage(key: _chatKey);
      case 2:
        return LivePage(
          key: const ValueKey('live_ui'),
          onBack: () => setState(() => _selectedIndex = 0),
        );
      case 3:
        return MarketplacePage(
          key: const ValueKey('market_ui'),
          onBack: () => setState(() => _selectedIndex = 0),
          isDark: isDark,
        );
      case 4:
        return _buildProfilePage(
          isDark,
          textColor,
          key: const ValueKey('profile_ui'),
        );
      default:
        return _buildHomePage(
          isDark,
          textColor,
          key: const ValueKey('home_ui'),
        );
    }
  }

  // --- SECTIONS DU DASHBOARD ---
  Widget _buildHomePage(bool isDark, Color textColor, {Key? key}) {
    final Color cardBg = isDark
        ? const Color(0xFF1E3E3B).withOpacity(0.8)
        : Colors.white;
    return SafeArea(
      key: key,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            HeaderWidget(
              isDark: isDark,
              textColor: textColor,
              onSOSPressed: _showSOSMenu,
            ),
            const SizedBox(height: 25),
            WeatherWidget(
              isDark: isDark,
              bg: cardBg,
              text: textColor,
              sub: isDark ? Colors.white70 : Colors.black54,
            ),
            const SizedBox(height: 25),
            MastaCard(onChatSubmit: (q) => debugPrint(q)),
            const SizedBox(height: 25),
            const CopperCard(),
            const SizedBox(height: 30),
            _buildNewsSection(textColor, isDark),
            const SizedBox(height: 30),
            _buildServicesSection(isDark),
            const SizedBox(height: 130),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsSection(Color text, bool isDark) {
    final sub = isDark ? Colors.white70 : Colors.black54;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Actu",
              style: TextStyle(
                color: text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NewsFeedPage()),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: const Text(
                  "Tout voir",
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 250,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('posts')
                .orderBy('createdAt', descending: true)
                .limit(12)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Text(
                    'Erreur chargement actu',
                    style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                  ),
                );
              }
              if (!snap.hasData) {
                return Center(
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'Aucune actu pour le moment',
                    style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                  ),
                );
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final source =
                      (data['category'] ?? data['authorName'] ?? 'Actu')
                          .toString();
                  final rawTitle = (data['text'] ?? '').toString().trim();
                  final title = rawTitle.isEmpty ? 'Publication' : rawTitle;
                  final media = _firstDashboardMedia(data, preferImage: true);
                  final mediaUrl = media?.url ?? '';
                  final mediaIsVideo = media?.isVideo ?? false;
                  final createdAt = data['createdAt'] is Timestamp
                      ? (data['createdAt'] as Timestamp).toDate()
                      : null;

                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(
                      milliseconds: 450 + (index.clamp(0, 10) * 40),
                    ),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, child) => Opacity(
                      opacity: v,
                      child: Transform.translate(
                        offset: Offset(16 * (1 - v), 0),
                        child: child,
                      ),
                    ),
                    child: _newsCard(
                      source,
                      title,
                      isDark,
                      mediaUrl,
                      isVideo: mediaIsVideo,
                      createdAt: createdAt,
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

  Widget _newsCard(
    String source,
    String title,
    bool isDark,
    String mediaUrl, {
    required bool isVideo,
    DateTime? createdAt,
  }) {
    final cardColor = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white70 : Colors.black54;
    final when = createdAt == null ? '' : DateFormat('HH:mm').format(createdAt);

    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.30 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: 130,
              width: double.infinity,
              child: mediaUrl.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? const [Color(0xFF202C33), Color(0xFF111B21)]
                              : const [Color(0xFFFFF3E0), Color(0xFFF6F7F9)],
                        ),
                      ),
                      child: Center(
                        child: Icon(Icons.article_outlined, color: sub),
                      ),
                    )
                  : isVideo
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        _DashboardVideoThumbnail(
                          videoUrl: mediaUrl,
                          fit: BoxFit.cover,
                        ),
                        Container(
                          color: Colors.black26,
                          child: Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: sub,
                              size: 40,
                            ),
                          ),
                        ),
                      ],
                    )
                  : CachedNetworkImage(
                      imageUrl: mediaUrl,
                      fit: BoxFit.cover,
                      placeholder: (c, s) => Container(
                        color: isDark
                            ? const Color(0xFF202C33)
                            : Colors.grey.shade200,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Theme.of(c).colorScheme.primary,
                          ),
                        ),
                      ),
                      errorWidget: (c, s, e) => Container(
                        color: isDark
                            ? const Color(0xFF202C33)
                            : Colors.grey.shade200,
                        child: Center(
                          child: Icon(Icons.broken_image, color: sub),
                        ),
                      ),
                    ),
            ),
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
                        source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: sub,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (when.isNotEmpty)
                      Text(
                        when,
                        style: TextStyle(
                          color: sub,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: text,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesSection(bool isDark) {
    return Column(
      children: [
        RapidServicesTile(isDark: isDark),
        const SizedBox(height: 16),
        const JobAnnouncementTile(),
        const SizedBox(height: 16),
        const DailyTipTile(),
      ],
    );
  }

  Widget _buildProfilePage(bool isDark, Color textColor, {Key? key}) {
    return SafeArea(
      key: key,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. TES TUILES D'ACTION
            ProfilePageWidgets.buildActionTile(
              "Ma Santé",
              "Dossier médical",
              Icons.favorite_border,
              const Color(0xFF00CBA9),
              isDark,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HealthSpacePickerPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            ProfilePageWidgets.buildActionTile(
              "Espace Adultes",
              "Rencontres",
              Icons.whatshot,
              Colors.redAccent,
              isDark,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdultSpacePage()),
                );
              },
            ),

            const SizedBox(height: 25),

            // 2. TA CARTE PREMIUM
            ProfilePageWidgets.buildPremiumCard(
              isDark,
              textColor,
              usedGb: _dataLanUsedGb,
              totalGb: _dataLanTotalGb,
              sourceLabel: _dataLanSource,
              updatedAt: _dataLanUpdatedAt,
              isRefreshing: _isRefreshingLan,
              onRefresh: _loadDataLanUsage,
            ),

            const SizedBox(height: 25),

            // --- SECTION : MON COMPTE ---
            ProfilePageWidgets.sectionTitle("MON COMPTE", Colors.orange),
            ProfilePageWidgets.settingsTile(
              Icons.person_outline,
              "Profil",
              isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              textColor,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProfileSettingsPage(),
                  ),
                );
              },
            ),
            ProfilePageWidgets.settingsTile(
              Icons.account_balance_wallet_outlined,
              "Portefeuille",
              isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              textColor,
              trailing: "CDF",
            ),

            const SizedBox(height: 15),

            if (_adminChecked && _isAdmin) ...[
              ProfilePageWidgets.sectionTitle("ADMIN", Colors.orange),
              ProfilePageWidgets.settingsTile(
                Icons.verified_user_outlined,
                "Validation identité",
                isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                textColor,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const IdentityValidationAdminPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 15),
            ],

            // --- SECTION : PRÉFÉRENCES ---
            ProfilePageWidgets.sectionTitle("PRÉFÉRENCES", Colors.orange),
            ProfilePageWidgets.settingsSwitchTile(
              Icons.notifications_none,
              "Notifications",
              _notificationsEnabled,
              isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              textColor,
              (val) async {
                setState(() => _notificationsEnabled = val);
                try {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('notifications_enabled', val);
                } catch (_) {}
                await NotificationService.setEnabled(val);
              },
            ),
            ProfilePageWidgets.settingsTile(
              Icons.language,
              "Langue",
              isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              textColor,
              trailing: "Français",
            ),
            // RÉINTÉGRATION DU MODE SOMBRE ICI
            ProfilePageWidgets.settingsSwitchTile(
              Icons.dark_mode_outlined,
              "Mode Sombre",
              isDark,
              isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              textColor,
              (val) async {
                await ThemeController.instance.toggle(val);
                if (mounted) setState(() {});
              },
            ),

            const SizedBox(height: 15),

            // --- SECTION : SUPPORT ---
            ProfilePageWidgets.sectionTitle("SUPPORT", Colors.orange),
            ProfilePageWidgets.settingsTile(
              Icons.help_outline,
              "Centre d'aide",
              isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              textColor,
            ),
            ProfilePageWidgets.settingsTile(
              Icons.info_outline,
              "À propos",
              isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              textColor,
            ),

            const SizedBox(height: 30),

            // 3. TON BOUTON DÉCONNEXION
            ProfilePageWidgets.logoutButton(context),

            const SizedBox(height: 140),
          ],
        ),
      ),
    );
  }
}

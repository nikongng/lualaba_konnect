import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:url_launcher/url_launcher.dart';

import 'package:lualaba_konnect/core/config.dart';
import 'package:lualaba_konnect/features/services/presentation/pages/enterprise_jobs_admin_page.dart';
import 'package:lualaba_konnect/features/services/presentation/pages/followed_companies_page.dart';
import 'package:lualaba_konnect/features/services/presentation/pages/my_job_applications_page.dart';

class JobsPage extends StatefulWidget {
  const JobsPage({super.key});

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> with SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFF9D59FF);
  static const Color _ctaBlue = Color(0xFF2D6BFF);

  static const List<(String, String, IconData)> _jobFilters = [
    ('all', 'Tout', Icons.grid_view_rounded),
    ('full_time', 'Temps plein', Icons.work_rounded),
    ('part_time', 'Temps partiel', Icons.schedule_rounded),
    ('freelance', 'Freelance', Icons.handyman_rounded),
    ('internship', 'Stage', Icons.school_rounded),
  ];

  static const List<(String, String, IconData)> _adFilters = [
    ('all', 'Tout', Icons.grid_view_rounded),
    ('sale', 'Vente', Icons.sell_outlined),
    ('rent', 'Location', Icons.home_work_outlined),
    ('service', 'Services', Icons.miscellaneous_services_outlined),
    ('vehicle', 'Vehicule', Icons.directions_car_filled_outlined),
    ('other', 'Autre', Icons.more_horiz_rounded),
  ];

  static const List<(String, String)> _sectors = [
    ('all', 'Tout'),
    ('tech', 'Tech'),
    ('batiment', 'Batiment'),
    ('art', 'Art'),
    ('vie', 'Vie'),
    ('other', 'Autre'),
  ];

  static const List<(String, String)> _experienceLevels = [
    ('all', 'Tout'),
    ('entry', 'Debutant'),
    ('junior', 'Junior'),
    ('mid', 'Intermediaire'),
    ('senior', 'Senior'),
  ];

  static const List<(String, String, IconData)> _sorts = [
    ('relevance', 'Pertinence', Icons.auto_awesome_outlined),
    ('date', 'Date', Icons.schedule_rounded),
    ('salary', 'Salaire', Icons.trending_up_rounded),
  ];

  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  String _jobFilterKey = 'all';
  String _adFilterKey = 'all';

  String _sectorKey = 'all';
  String _experienceKey = 'all';
  bool _remoteOnly = false;
  String _locationQuery = '';
  String _companyQuery = '';
  String _sortKey = 'relevance';

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _enterpriseSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _followsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _followedOffersSub;
  Set<String> _followedEnterprises = {};
  final Set<String> _notifiedOfferIds = {};
  int _offersListenStartedAtMs = 0;
  int _newOffersCount = 0;

  Widget _miniStat({
    required bool isDark,
    required String label,
    required String value,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(isDark ? 0.18 : 0.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: fg.withOpacity(0.85), fontWeight: FontWeight.w800, fontSize: 11.5)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 14)),
        ],
      ),
    );
  }
  bool _canPublish = false;
  bool _publishPermissionReady = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!mounted) return;
        setState(() {});
      });
    _searchCtrl.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    // Only enterprise accounts can publish jobs/ads. We listen in real time so
    // if the user's account is migrated to enterprise_users, the UI updates.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      _enterpriseSub?.cancel();
      _followsSub?.cancel();
      _followedOffersSub?.cancel();
      if (u == null) {
        if (!mounted) return;
        setState(() {
          _canPublish = false;
          _publishPermissionReady = true;
          _followedEnterprises = {};
          _newOffersCount = 0;
        });
        return;
      }
      _enterpriseSub = FirebaseFirestore.instance.collection('enterprise_users').doc(u.uid).snapshots().listen(
        (snap) {
          if (!mounted) return;
          setState(() {
            _canPublish = snap.exists;
            _publishPermissionReady = true;
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _canPublish = false;
            _publishPermissionReady = true;
          });
        },
      );

      _followsSub = FirebaseFirestore.instance
          .collection('company_follows')
          .where('followerUid', isEqualTo: u.uid)
          .snapshots()
          .listen((snap) {
        final ids = <String>{};
        for (final d in snap.docs) {
          final data = d.data();
          final id = (data['enterpriseUid'] ?? '').toString().trim();
          if (id.isNotEmpty) ids.add(id);
        }
        _setupNewOffersWatcher(myUid: u.uid, enterpriseUids: ids);
        if (!mounted) return;
        setState(() => _followedEnterprises = ids);
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _enterpriseSub?.cancel();
    _followsSub?.cancel();
    _followedOffersSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  void _showEnterpriseOnlyDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: bg,
          title: Text('Publication indisponible', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
          content: Text(
            "Seuls les comptes Entreprises peuvent publier des offres d'emploi et des annonces.",
            style: TextStyle(color: sub, fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF111827), fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );
  }

  bool _ensureEnterpriseCanPublish() {
    if (!_publishPermissionReady) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chargement du compte...')));
      return false;
    }
    if (!_canPublish) {
      _showEnterpriseOnlyDialog();
      return false;
    }
    return true;
  }

  int _tsMs(Map<String, dynamic> d) {
    final ts = d['createdAt'];
    if (ts is Timestamp) return ts.millisecondsSinceEpoch;
    final m = d['createdAtMs'];
    if (m is int) return m;
    if (m is num) return m.toInt();
    return 0;
  }

  bool _asBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true' || v == 'True';

  String _norm(String s) => s.trim().toLowerCase();

  int _salaryValue(Map<String, dynamic> d) {
    final v = d['salaryValue'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    final raw = (d['salary'] ?? '').toString();
    final digits = RegExp(r'(\d[\d\s,.]*)').firstMatch(raw)?.group(1) ?? '';
    final cleaned = digits.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  int _relevanceScore(Map<String, dynamic> d) {
    final q = _norm(_searchCtrl.text);
    if (q.isEmpty) return _asBool(d['urgent']) ? 2 : 0;
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.length >= 2).toList();
    final title = _norm((d['title'] ?? '').toString());
    final company = _norm((d['company'] ?? '').toString());
    final location = _norm((d['location'] ?? '').toString());
    final desc = _norm((d['description'] ?? '').toString());
    final req = _norm((d['requirements'] ?? '').toString());
    int score = _asBool(d['urgent']) ? 2 : 0;
    for (final t in tokens) {
      if (title.contains(t)) score += 6;
      if (company.contains(t)) score += 4;
      if (location.contains(t)) score += 2;
      if (desc.contains(t)) score += 1;
      if (req.contains(t)) score += 1;
    }
    // Bonus if location/company filters are set and match.
    if (_locationQuery.trim().isNotEmpty && location.contains(_norm(_locationQuery))) score += 3;
    if (_companyQuery.trim().isNotEmpty && company.contains(_norm(_companyQuery))) score += 3;
    return score;
  }

  bool _matchesJobAdvanced(Map<String, dynamic> d) {
    final status = (d['statusKey'] ?? 'open').toString();
    // Public feed: only open/paused offers are visible (closed are hidden).
    if (status == 'closed') return false;

    if (_sectorKey != 'all') {
      final k = (d['sectorKey'] ?? '').toString();
      if (k != _sectorKey) return false;
    }
    if (_experienceKey != 'all') {
      final k = (d['experienceKey'] ?? '').toString();
      if (k != _experienceKey) return false;
    }
    if (_remoteOnly) {
      final remoteOk = _asBool(d['remoteOk']);
      if (!remoteOk) return false;
    }
    if (_locationQuery.trim().isNotEmpty) {
      final loc = _norm((d['location'] ?? '').toString());
      if (!loc.contains(_norm(_locationQuery))) return false;
    }
    if (_companyQuery.trim().isNotEmpty) {
      final c = _norm((d['company'] ?? '').toString());
      if (!c.contains(_norm(_companyQuery))) return false;
    }
    return true;
  }

  String _appendUrlVersion(String url, int v) => url.contains('?') ? '$url&v=$v' : '$url?v=$v';

  Future<String> _uploadCover({required String folder, required Uint8List bytes}) async {
    final client = Supabase.instance.client;
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = '$folder/$now.jpg';
    await client.storage.from('market').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    final publicUrl = client.storage.from('market').getPublicUrl(path);
    return _appendUrlVersion(publicUrl, now);
  }

  Future<String> _uploadFile({
    required String folder,
    required String filename,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final client = Supabase.instance.client;
    final now = DateTime.now().millisecondsSinceEpoch;
    final safe = filename.trim().isEmpty ? 'file_$now' : filename.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '$folder/${now}_$safe';
    await client.storage.from('market').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    final publicUrl = client.storage.from('market').getPublicUrl(path);
    return _appendUrlVersion(publicUrl, now);
  }

  Future<void> _launchOrSnack(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir.")));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  void _showContactSheet({
    required String title,
    required String phone,
    required String email,
  }) {
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.60 : 0.12),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                )
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5, letterSpacing: -0.2),
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                  ],
                ),
                if (phone.trim().isEmpty && email.trim().isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Text('Aucun contact disponible.', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                  ),
                if (phone.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchOrSnack(Uri.parse('tel:${phone.trim()}'));
                    },
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _ctaBlue.withOpacity(isDark ? 0.18 : 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _ctaBlue.withOpacity(0.25)),
                      ),
                      child: const Icon(Icons.call_rounded, color: _ctaBlue),
                    ),
                    title: Text('Appeler', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                    subtitle: Text(phone.trim(), style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                    trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: sub),
                  ),
                ],
                if (email.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchOrSnack(Uri.parse('mailto:${email.trim()}'));
                    },
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(isDark ? 0.18 : 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _accent.withOpacity(0.25)),
                      ),
                      child: const Icon(Icons.email_rounded, color: _accent),
                    ),
                    title: Text('Envoyer un email', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                    subtitle: Text(email.trim(), style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                    trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: sub),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createNotification({
    required String toUserId,
    required String fromUserId,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final me = FirebaseAuth.instance.currentUser;
      final fromName = (me != null && me.uid == fromUserId) ? ((me.displayName ?? '').trim()) : '';
      final fromAvatar = (me != null && me.uid == fromUserId) ? ((me.photoURL ?? '').trim()) : '';
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await FirebaseFirestore.instance.collection('notifications').add({
        'toUserId': toUserId,
        'fromUserId': fromUserId,
        'fromName': fromName,
        'fromAvatar': fromAvatar,
        'type': type,
        'text': body,
        'seen': false,
        ...(extra ?? {}),
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': nowMs,
      });

      // Push OneSignal via the existing sender endpoint (no Cloud Functions).
      await _sendPush(
        recipients: [toUserId],
        title: fromName.isNotEmpty ? fromName : (title.isNotEmpty ? title : 'Lualaba Konnect'),
        body: body,
        senderAvatarUrl: fromAvatar,
        imageUrl: (extra?['imageUrl'] ?? '').toString(),
        data: <String, dynamic>{'type': type, ...(extra ?? {})},
      );
    } catch (_) {
      // Non bloquant.
    }
  }

  Future<void> _sendPush({
    required List<String> recipients,
    required String title,
    required String body,
    String? senderAvatarUrl,
    String? imageUrl,
    Map<String, dynamic>? data,
  }) async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      final cleanRecipients = recipients.where((e) => e.trim().isNotEmpty && e.trim() != u.uid).toSet().toList();
      if (cleanRecipients.isEmpty) return;

      final idToken = await u.getIdToken();
      await http.post(
        Uri.parse(kNotifierUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'recipients': cleanRecipients,
          'title': title,
          'body': body,
          'senderAvatarUrl': (senderAvatarUrl ?? '').toString(),
          'imageUrl': (imageUrl ?? '').toString(),
          'data': data ?? <String, dynamic>{},
        }),
      );
    } catch (e) {
      // silent best-effort (push should never block UX)
      debugPrint('Notifier push error: $e');
    }
  }

  int _minInt(int a, int b) => a < b ? a : b;

  Future<void> _notifyFollowersNewOffer({
    required String jobId,
    required String jobTitle,
    required String coverUrl,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final fromName = (me.displayName ?? '').trim().isNotEmpty ? (me.displayName ?? '').trim() : 'Entreprise';
    final fromAvatar = (me.photoURL ?? '').trim();

    final snap = await FirebaseFirestore.instance
        .collection('company_follows')
        .where('enterpriseUid', isEqualTo: me.uid)
        .get();

    final followerUids = snap.docs
        .map((d) => (d.data()['followerUid'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty && id != me.uid)
        .toSet()
        .toList();

    if (followerUids.isEmpty) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final body = jobTitle.trim().isEmpty ? 'Une nouvelle offre a ete publiee.' : '"${jobTitle.trim()}" vient d\'etre publiee.';

    // 1) In-app notifications (Firestore) for the notifications list.
    // Firestore WriteBatch is limited to 500 operations.
    const batchLimit = 450;
    for (int i = 0; i < followerUids.length; i += batchLimit) {
      final batch = FirebaseFirestore.instance.batch();
      final chunk = followerUids.sublist(i, _minInt(i + batchLimit, followerUids.length));
      for (final toUid in chunk) {
        final ref = FirebaseFirestore.instance.collection('notifications').doc();
        batch.set(ref, {
          'toUserId': toUid,
          'fromUserId': me.uid,
          'fromName': fromName,
          'fromAvatar': fromAvatar,
          'type': 'new_job_offer',
          'text': body,
          'seen': false,
          'jobId': jobId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdAtMs': nowMs,
        });
      }
      await batch.commit();
    }

    // 2) Push notification via sender endpoint (OneSignal).
    const pushChunk = 80;
    for (int i = 0; i < followerUids.length; i += pushChunk) {
      final chunk = followerUids.sublist(i, _minInt(i + pushChunk, followerUids.length));
      await _sendPush(
        recipients: chunk,
        title: fromName,
        body: body,
        senderAvatarUrl: fromAvatar,
        imageUrl: coverUrl,
        data: {'type': 'new_job_offer', 'jobId': jobId},
      );
    }
  }

  Future<void> _toggleFollowEnterprise(String enterpriseUid) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez vous connecter.')));
      return;
    }
    final id = '${u.uid}_$enterpriseUid';
    final ref = FirebaseFirestore.instance.collection('company_follows').doc(id);
    final isFollowing = _followedEnterprises.contains(enterpriseUid);
    try {
      if (isFollowing) {
        await ref.delete();
      } else {
        await ref.set({
          'followerUid': u.uid,
          'enterpriseUid': enterpriseUid,
          'createdAt': FieldValue.serverTimestamp(),
          'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  void _setupNewOffersWatcher({
    required String myUid,
    required Set<String> enterpriseUids,
  }) {
    _followedOffersSub?.cancel();
    _newOffersCount = 0;
    _notifiedOfferIds.clear();
    _offersListenStartedAtMs = DateTime.now().millisecondsSinceEpoch;

    final list = enterpriseUids.where((e) => e.isNotEmpty && e != myUid).take(10).toList();
    if (list.isEmpty) {
      if (mounted) setState(() => _newOffersCount = 0);
      return;
    }

    // Best-effort in-app counter while the app is running.
    // Push + notification docs are created when the enterprise publishes (via sender + OneSignal).
    final q = FirebaseFirestore.instance
        .collection('job_posts')
        .where('createdByUid', whereIn: list)
        .orderBy('createdAt', descending: true)
        .limit(30);

    _followedOffersSub = q.snapshots().listen((snap) async {
      int newCount = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final id = doc.id;
        if (_notifiedOfferIds.contains(id)) continue;
        final ms = _tsMs(data);
        if (ms <= _offersListenStartedAtMs) continue; // avoid backfilling older offers
        final status = (data['statusKey'] ?? 'open').toString();
        if (status == 'closed') continue;
        _notifiedOfferIds.add(id);
        newCount++;
      }

      if (!mounted) return;
      if (newCount > 0) setState(() => _newOffersCount += newCount);
    });
  }

  void _openApplySheet({
    required String jobId,
    required Map<String, dynamic> job,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez vous connecter.')));
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final jobTitle = (job['title'] ?? '').toString().trim();
    final company = (job['company'] ?? '').toString().trim();
    final toEnterpriseUid = (job['createdByUid'] ?? '').toString().trim();

    final formKey = GlobalKey<FormState>();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController(text: user.email ?? '');
    final skillsCtrl = TextEditingController();
    final educationCtrl = TextEditingController();
    final coverLetterCtrl = TextEditingController();
    String expKey = _experienceKey == 'all' ? 'junior' : _experienceKey;

    PlatformFile? cvFile;
    Uint8List? cvBytes;
    PlatformFile? letterFile;
    Uint8List? letterBytes;
    bool submitting = false;

    Future<void> pickPdf({
      required bool isCv,
      required StateSetter setModal,
    }) async {
      try {
        final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
          withData: true,
        );
        if (res == null || res.files.isEmpty) return;
        final f = res.files.first;
        final b = f.bytes;
        if (b == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de lire le fichier.')));
          return;
        }
        setModal(() {
          if (isCv) {
            cvFile = f;
            cvBytes = b;
          } else {
            letterFile = f;
            letterBytes = b;
          }
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur fichier: $e')));
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: divider),
                ),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Postuler',
                                style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5),
                              ),
                            ),
                            IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                          ],
                        ),
                        Text(
                          jobTitle.isEmpty ? 'Offre' : jobTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        if (company.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(company, style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DropdownField(
                                label: "Niveau d'experience",
                                value: expKey,
                                items: _experienceLevels.where((e) => e.$1 != 'all').map((e) {
                                  return DropdownMenuItem(value: e.$1, child: Text(e.$2));
                                }).toList(),
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                onChanged: (v) => setModal(() => expKey = v ?? 'junior'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _Field(
                                label: 'Telephone',
                                controller: phoneCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _Field(
                                label: 'Email',
                                controller: emailCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _Field(
                          label: 'Competences (mots cles)',
                          controller: skillsCtrl,
                          textColor: text,
                          subColor: sub,
                          divider: divider,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 10),
                        _Field(
                          label: 'Formation',
                          controller: educationCtrl,
                          textColor: text,
                          subColor: sub,
                          divider: divider,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 10),
                        _Field(
                          label: 'Lettre de motivation (optionnel)',
                          controller: coverLetterCtrl,
                          textColor: text,
                          subColor: sub,
                          divider: divider,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _FileTile(
                                label: 'CV (PDF)',
                                filename: cvFile?.name ?? '',
                                isDark: isDark,
                                divider: divider,
                                onTap: () => pickPdf(isCv: true, setModal: setModal),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _FileTile(
                                label: 'Lettre (PDF)',
                                filename: letterFile?.name ?? '',
                                isDark: isDark,
                                divider: divider,
                                onTap: () => pickPdf(isCv: false, setModal: setModal),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: submitting
                                ? null
                                : () async {
                                    if (emailCtrl.text.trim().isEmpty && phoneCtrl.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Ajoutez un email ou un numero de telephone.')),
                                      );
                                      return;
                                    }
                                    setModal(() => submitting = true);
                                    try {
                                      final appRef = FirebaseFirestore.instance.collection('job_applications').doc();
                                      String cvUrl = '';
                                      String letterUrl = '';
                                      if (cvBytes != null) {
                                        cvUrl = await _uploadFile(
                                          folder: 'job_applications/${appRef.id}',
                                          filename: cvFile?.name ?? 'cv.pdf',
                                          bytes: cvBytes!,
                                          contentType: 'application/pdf',
                                        );
                                      }
                                      if (letterBytes != null) {
                                        letterUrl = await _uploadFile(
                                          folder: 'job_applications/${appRef.id}',
                                          filename: letterFile?.name ?? 'lettre.pdf',
                                          bytes: letterBytes!,
                                          contentType: 'application/pdf',
                                        );
                                      }

                                      final nowMs = DateTime.now().millisecondsSinceEpoch;
                                      await appRef.set({
                                        'jobId': jobId,
                                        'jobTitle': jobTitle,
                                        'company': company,
                                        'toEnterpriseUid': toEnterpriseUid,
                                        'applicantUid': user.uid,
                                        'applicantEmail': user.email ?? '',
                                        'applicantName': user.displayName ?? '',
                                        'contactEmail': emailCtrl.text.trim(),
                                        'contactPhone': phoneCtrl.text.trim(),
                                        'experienceKey': expKey,
                                        'skills': skillsCtrl.text.trim(),
                                        'education': educationCtrl.text.trim(),
                                        'coverLetter': coverLetterCtrl.text.trim(),
                                        'cvUrl': cvUrl,
                                        'coverLetterPdfUrl': letterUrl,
                                        'statusKey': 'submitted',
                                        'hiddenByEnterprise': false,
                                        'createdAt': FieldValue.serverTimestamp(),
                                        'createdAtMs': nowMs,
                                        'updatedAt': FieldValue.serverTimestamp(),
                                        'updatedAtMs': nowMs,
                                      });

                                      if (toEnterpriseUid.isNotEmpty) {
                                        await _createNotification(
                                          toUserId: toEnterpriseUid,
                                          fromUserId: user.uid,
                                          type: 'job_application',
                                          title: 'Nouvelle candidature',
                                          body: '${(user.displayName ?? 'Un utilisateur').trim()} a postule a "${jobTitle.isEmpty ? 'Offre' : jobTitle}"',
                                          extra: {'jobId': jobId, 'applicationId': appRef.id},
                                        );
                                      }

                                      if (!mounted) return;
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Candidature envoyee.')));
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                                    } finally {
                                      if (mounted) setModal(() => submitting = false);
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFF111827),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: submitting
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                : const Text('Envoyer', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () => _showContactSheet(
                              title: jobTitle.isEmpty ? 'Offre' : jobTitle,
                              phone: (job['phone'] ?? '').toString(),
                              email: (job['email'] ?? '').toString(),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: text,
                              side: BorderSide(color: divider),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: const Text('Contacter', style: TextStyle(fontWeight: FontWeight.w900)),
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
    ).whenComplete(() {
      phoneCtrl.dispose();
      emailCtrl.dispose();
      skillsCtrl.dispose();
      educationCtrl.dispose();
      coverLetterCtrl.dispose();
    });
  }

  Query _jobsQuery() {
    Query q = FirebaseFirestore.instance.collection('job_posts');
    if (_jobFilterKey != 'all') q = q.where('typeKey', isEqualTo: _jobFilterKey);
    return q;
  }

  Query _adsQuery() {
    Query q = FirebaseFirestore.instance.collection('classified_ads');
    if (_adFilterKey != 'all') q = q.where('categoryKey', isEqualTo: _adFilterKey);
    return q;
  }

  bool _matchesSearch(Map<String, dynamic> d) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      d['title'],
      d['company'],
      d['location'],
      d['salary'],
      d['typeKey'],
      d['sectorKey'],
      d['experienceKey'],
      d['remoteOk'],
      d['price'],
      d['categoryKey'],
      d['description'],
      d['requirements'],
    ].where((e) => e != null).map((e) => e.toString()).join(' ').toLowerCase();
    return hay.contains(q);
  }

  String _labelForJobType(String key) {
    final f = _jobFilters.firstWhere((e) => e.$1 == key, orElse: () => ('', 'Type', Icons.work));
    return f.$2;
  }

  String _labelForAdCategory(String key) {
    final f = _adFilters.firstWhere((e) => e.$1 == key, orElse: () => ('', 'Categorie', Icons.more_horiz));
    return f.$2;
  }

  String _labelForSort(String key) {
    final f = _sorts.firstWhere((e) => e.$1 == key, orElse: () => ('', 'Tri', Icons.sort));
    return f.$2;
  }

  int _activeFiltersCount() {
    int n = 0;
    if (_jobFilterKey != 'all') n++;
    if (_sectorKey != 'all') n++;
    if (_experienceKey != 'all') n++;
    if (_remoteOnly) n++;
    if (_locationQuery.trim().isNotEmpty) n++;
    if (_companyQuery.trim().isNotEmpty) n++;
    return n;
  }

  void _openAdvancedFiltersSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final locCtrl = TextEditingController(text: _locationQuery);
    final companyCtrl = TextEditingController(text: _companyQuery);

    String sectorKey = _sectorKey;
    String expKey = _experienceKey;
    bool remoteOnly = _remoteOnly;
    String sortKey = _sortKey;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: divider),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Filtres avancees', style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5))),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        label: 'Localisation',
                        controller: locCtrl,
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                      ),
                      const SizedBox(height: 10),
                      _Field(
                        label: 'Entreprise (nom)',
                        controller: companyCtrl,
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DropdownField(
                              label: 'Secteur',
                              value: sectorKey,
                              items: _sectors.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              onChanged: (v) => setModal(() => sectorKey = v ?? 'all'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DropdownField(
                              label: "Experience",
                              value: expKey,
                              items: _experienceLevels.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              onChanged: (v) => setModal(() => expKey = v ?? 'all'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : const Color(0xFFF1F3F5),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: divider),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text('Teletravail uniquement', style: TextStyle(color: text, fontWeight: FontWeight.w900))),
                            Switch.adaptive(value: remoteOnly, activeColor: _accent, onChanged: (v) => setModal(() => remoteOnly = v)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _DropdownField(
                        label: 'Tri',
                        value: sortKey,
                        items: _sorts.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
                        textColor: text,
                        subColor: sub,
                        divider: divider,
                        onChanged: (v) => setModal(() => sortKey = v ?? 'relevance'),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModal(() {
                                  locCtrl.text = '';
                                  companyCtrl.text = '';
                                  sectorKey = 'all';
                                  expKey = 'all';
                                  remoteOnly = false;
                                  sortKey = 'relevance';
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: text,
                                side: BorderSide(color: divider),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Reinitialiser', style: TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _locationQuery = locCtrl.text.trim();
                                  _companyQuery = companyCtrl.text.trim();
                                  _sectorKey = sectorKey;
                                  _experienceKey = expKey;
                                  _remoteOnly = remoteOnly;
                                  _sortKey = sortKey;
                                });
                                Navigator.pop(ctx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFF111827),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Appliquer', style: TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      locCtrl.dispose();
      companyCtrl.dispose();
    });
  }

  Widget _coverThumb(String url, {required bool isDark}) {
    if (url.trim().isEmpty) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : const Color(0xFFE9ECEF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
        ),
        child: Icon(Icons.work_outline, color: isDark ? Colors.white54 : Colors.black38),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(
          width: 54,
          height: 54,
          color: isDark ? Colors.white10 : const Color(0xFFE9ECEF),
          child: Icon(Icons.broken_image_outlined, color: isDark ? Colors.white54 : Colors.black38),
        ),
      ),
    );
  }

  void _openAddJobSheet() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez vous connecter.')));
      return;
    }
    if (!_ensureEnterpriseCanPublish()) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController();
    final companyCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final salaryCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController(text: user.email ?? '');
    final descCtrl = TextEditingController();
    final reqCtrl = TextEditingController();
    String typeKey = 'full_time';
    String sectorKey = 'all';
    String experienceKey = 'junior';
    bool remoteOk = false;
    bool urgent = false;
    Uint8List? imageBytes;

    Future<void> pickImage(StateSetter setModal) async {
      try {
        final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (x == null) return;
        final bytes = await x.readAsBytes();
        setModal(() => imageBytes = bytes);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur image: $e')));
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: divider),
                ),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Deposer une offre d'emploi",
                                style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5),
                              ),
                            ),
                            IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () => pickImage(setModal),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            height: 74,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : const Color(0xFFF1F3F5),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: divider),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    width: 54,
                                    height: 54,
                                    color: isDark ? Colors.white10 : const Color(0xFFE9ECEF),
                                    child: imageBytes == null
                                        ? Icon(Icons.image_outlined, color: sub)
                                        : Image.memory(imageBytes!, fit: BoxFit.cover),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Photo (optionnel)', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 2),
                                      Text('Appuyez pour choisir une image', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, color: sub),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          label: 'Titre du poste',
                          controller: titleCtrl,
                          textColor: text,
                          subColor: sub,
                          divider: divider,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Titre requis' : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _Field(label: 'Entreprise (optionnel)', controller: companyCtrl, textColor: text, subColor: sub, divider: divider),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _Field(
                                label: 'Lieu (ex: Centre-Ville)',
                                controller: locationCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Lieu requis' : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _Field(label: r'Salaire (ex: 250$)', controller: salaryCtrl, textColor: text, subColor: sub, divider: divider),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DropdownField(
                                label: 'Type',
                                value: typeKey,
                                items: _jobFilters.where((e) => e.$1 != 'all').map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                onChanged: (v) => setModal(() => typeKey = v ?? 'full_time'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _DropdownField(
                                label: 'Secteur',
                                value: sectorKey,
                                items: _sectors.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                onChanged: (v) => setModal(() => sectorKey = v ?? 'all'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DropdownField(
                                label: "Experience",
                                value: experienceKey,
                                items: _experienceLevels.where((e) => e.$1 != 'all').map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                onChanged: (v) => setModal(() => experienceKey = v ?? 'junior'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : const Color(0xFFF1F3F5),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: divider),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text('Teletravail possible', style: TextStyle(color: text, fontWeight: FontWeight.w900))),
                              Switch.adaptive(value: remoteOk, activeColor: _accent, onChanged: (v) => setModal(() => remoteOk = v)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _Field(
                                label: 'Telephone',
                                controller: phoneCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _Field(
                                label: 'Email',
                                controller: emailCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _Field(label: 'Description (optionnel)', controller: descCtrl, textColor: text, subColor: sub, divider: divider, maxLines: 4),
                        const SizedBox(height: 10),
                        _Field(label: 'Exigences (optionnel)', controller: reqCtrl, textColor: text, subColor: sub, divider: divider, maxLines: 3),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : const Color(0xFFF1F3F5),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: divider),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text('Urgent', style: TextStyle(color: text, fontWeight: FontWeight.w900))),
                              Switch.adaptive(value: urgent, activeColor: _accent, onChanged: (v) => setModal(() => urgent = v)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              try {
                                String coverUrl = '';
                                if (imageBytes != null) {
                                  coverUrl = await _uploadCover(folder: 'job_posts', bytes: imageBytes!);
                                }
                                final nowMs = DateTime.now().millisecondsSinceEpoch;
                                final salaryVal = _salaryValue({'salary': salaryCtrl.text.trim()});
                                final jobRef = await FirebaseFirestore.instance.collection('job_posts').add({
                                  'title': titleCtrl.text.trim(),
                                  'company': companyCtrl.text.trim(),
                                  'location': locationCtrl.text.trim(),
                                  'salary': salaryCtrl.text.trim(),
                                  'salaryValue': salaryVal,
                                  'typeKey': typeKey,
                                  'sectorKey': sectorKey,
                                  'experienceKey': experienceKey,
                                  'remoteOk': remoteOk,
                                  'urgent': urgent,
                                  'phone': phoneCtrl.text.trim(),
                                  'email': emailCtrl.text.trim(),
                                  'description': descCtrl.text.trim(),
                                  'requirements': reqCtrl.text.trim(),
                                  'coverUrl': coverUrl,
                                  'statusKey': 'open',
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'createdAtMs': nowMs,
                                  'createdByUid': user.uid,
                                  'createdByEmail': user.email ?? '',
                                  'createdByName': user.displayName ?? '',
                                  'certified': false,
                                  'isCertified': false,
                                  'certifiedAt': null,
                                });

                                // Notify followers (in-app + OneSignal push) using the existing sender endpoint.
                                unawaited(
                                  _notifyFollowersNewOffer(
                                    jobId: jobRef.id,
                                    jobTitle: titleCtrl.text.trim(),
                                    coverUrl: coverUrl,
                                  ),
                                );
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offre publiee.')));
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFF111827),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: const Text('Publier', style: TextStyle(fontWeight: FontWeight.w900)),
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
    ).whenComplete(() {
      titleCtrl.dispose();
      companyCtrl.dispose();
      locationCtrl.dispose();
      salaryCtrl.dispose();
      phoneCtrl.dispose();
      emailCtrl.dispose();
      descCtrl.dispose();
      reqCtrl.dispose();
    });
  }

  void _openAddAdSheet() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez vous connecter.')));
      return;
    }
    if (!_ensureEnterpriseCanPublish()) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController(text: user.email ?? '');
    final descCtrl = TextEditingController();
    String categoryKey = 'sale';
    Uint8List? imageBytes;

    Future<void> pickImage(StateSetter setModal) async {
      try {
        final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (x == null) return;
        final bytes = await x.readAsBytes();
        setModal(() => imageBytes = bytes);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur image: $e')));
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: divider),
                ),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('Publier une annonce', style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5))),
                            IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () => pickImage(setModal),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            height: 74,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : const Color(0xFFF1F3F5),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: divider),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    width: 54,
                                    height: 54,
                                    color: isDark ? Colors.white10 : const Color(0xFFE9ECEF),
                                    child: imageBytes == null ? Icon(Icons.image_outlined, color: sub) : Image.memory(imageBytes!, fit: BoxFit.cover),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Photo (optionnel)', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 2),
                                      Text('Appuyez pour choisir une image', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, color: sub),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          label: "Titre de l'annonce",
                          controller: titleCtrl,
                          textColor: text,
                          subColor: sub,
                          divider: divider,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Titre requis' : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _DropdownField(
                                label: 'Categorie',
                                value: categoryKey,
                                items: _adFilters.where((e) => e.$1 != 'all').map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                                onChanged: (v) => setModal(() => categoryKey = v ?? 'sale'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: _Field(label: r'Prix (ex: 120$)', controller: priceCtrl, textColor: text, subColor: sub, divider: divider)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _Field(
                          label: 'Lieu (ex: Golf)',
                          controller: locationCtrl,
                          textColor: text,
                          subColor: sub,
                          divider: divider,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Lieu requis' : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _Field(label: 'Telephone', controller: phoneCtrl, textColor: text, subColor: sub, divider: divider, keyboardType: TextInputType.phone)),
                            const SizedBox(width: 10),
                            Expanded(child: _Field(label: 'Email', controller: emailCtrl, textColor: text, subColor: sub, divider: divider, keyboardType: TextInputType.emailAddress)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _Field(label: 'Description (optionnel)', controller: descCtrl, textColor: text, subColor: sub, divider: divider, maxLines: 4),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              try {
                                String coverUrl = '';
                                if (imageBytes != null) {
                                  coverUrl = await _uploadCover(folder: 'classified_ads', bytes: imageBytes!);
                                }
                                final nowMs = DateTime.now().millisecondsSinceEpoch;
                                await FirebaseFirestore.instance.collection('classified_ads').add({
                                  'title': titleCtrl.text.trim(),
                                  'categoryKey': categoryKey,
                                  'price': priceCtrl.text.trim(),
                                  'location': locationCtrl.text.trim(),
                                  'phone': phoneCtrl.text.trim(),
                                  'email': emailCtrl.text.trim(),
                                  'description': descCtrl.text.trim(),
                                  'coverUrl': coverUrl,
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'createdAtMs': nowMs,
                                  'createdByUid': user.uid,
                                  'createdByEmail': user.email ?? '',
                                  'createdByName': user.displayName ?? '',
                                  'certified': false,
                                  'isCertified': false,
                                  'certifiedAt': null,
                                });
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Annonce publiee.')));
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFF111827),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: const Text('Publier', style: TextStyle(fontWeight: FontWeight.w900)),
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
    ).whenComplete(() {
      titleCtrl.dispose();
      locationCtrl.dispose();
      priceCtrl.dispose();
      phoneCtrl.dispose();
      emailCtrl.dispose();
      descCtrl.dispose();
    });
  }

  // TODO: replace placeholder build (next patch)
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final isJobsTab = _tabController.index == 0;

    final String fabKey = '${isJobsTab ? 'job' : 'ad'}_${_publishPermissionReady ? (_canPublish ? 'can' : 'no') : 'loading'}';
    final VoidCallback? fabOnPressed = !_publishPermissionReady
        ? null
        : (_canPublish
            ? (isJobsTab ? _openAddJobSheet : _openAddAdSheet)
            : _showEnterpriseOnlyDialog);
    final Color fabBg = !_publishPermissionReady
        ? _accent.withOpacity(0.85)
        : (_canPublish ? _accent : (isDark ? Colors.white24 : Colors.black26));
    final Widget fabChild = !_publishPermissionReady
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
        : Icon(_canPublish ? Icons.add : Icons.lock_rounded, color: Colors.white);

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: FloatingActionButton(
          key: ValueKey(fabKey),
          backgroundColor: fabBg,
          onPressed: fabOnPressed,
          child: fabChild,
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 46, 16, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF9D59FF), Color(0xFF6A1BFF)],
              ),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.20)),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Emploi & Annonces',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.20)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.white70),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(
                            hintText: 'Job, terrain, vente...',
                            hintStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        GestureDetector(
                          onTap: () => _searchCtrl.clear(),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.close, size: 18, color: Colors.white),
                          ),
                        ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _openAdvancedFiltersSheet,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.tune_rounded, size: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_publishPermissionReady && _canPublish) ...[
                      _QuickAction(
                        icon: Icons.dashboard_customize_outlined,
                        label: 'Gestion',
                        onTap: () {
                          final u = FirebaseAuth.instance.currentUser;
                          if (u == null) return;
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => EnterpriseJobsAdminPage(enterpriseUid: u.uid)));
                        },
                      ),
                      _QuickAction(icon: Icons.business_center_outlined, label: 'Deposer Job', onTap: _openAddJobSheet),
                      _QuickAction(icon: Icons.campaign_outlined, label: 'Publier Annonce', onTap: _openAddAdSheet),
                    ] else ...[
                      _QuickAction(
                        icon: Icons.apartment_rounded,
                        label: 'Entreprises',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FollowedCompaniesPage())),
                      ),
                      _QuickAction(
                        icon: Icons.assignment_turned_in_outlined,
                        label: 'Mes candidatures',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyJobApplicationsPage())),
                      ),
                      _QuickAction(icon: Icons.campaign_outlined, label: 'Annonces', onTap: () => _tabController.animateTo(1)),
                    ],
                  ],
                ),
                if (!(_publishPermissionReady && _canPublish)) ...[
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('job_applications')
                        .where('applicantUid', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
                        .snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? const [];
                      int submitted = 0;
                      int accepted = 0;
                      int rejected = 0;
                      for (final d in docs) {
                        final s = (d.data()['statusKey'] ?? '').toString();
                        if (s == 'submitted') submitted++;
                        if (s == 'accepted') accepted++;
                        if (s == 'rejected') rejected++;
                      }
                      final total = docs.length;
                      final responded = accepted + rejected;
                      final rate = total == 0 ? 0 : ((responded * 100) / total).round();

                      return Row(
                        children: [
                          Expanded(
                            child: _miniStat(
                              isDark: isDark,
                              label: 'Candidatures',
                              value: '$total',
                              bg: Colors.white.withOpacity(0.14),
                              fg: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _miniStat(
                              isDark: isDark,
                              label: 'En attente',
                              value: '$submitted',
                              bg: Colors.white.withOpacity(0.14),
                              fg: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _miniStat(
                              isDark: isDark,
                              label: 'Reponse',
                              value: '$rate%',
                              bg: Colors.white.withOpacity(0.14),
                              fg: Colors.white,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
                if (!(_publishPermissionReady && _canPublish) && _newOffersCount > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.20)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active_outlined, color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$_newOffersCount nouvelle(s) offre(s) depuis votre derniere visite',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _newOffersCount = 0),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: divider),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.28 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: isDark ? _accent.withOpacity(0.35) : const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(18),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: sub,
                labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                tabs: const [
                  Tab(text: "Offres d'emploi"),
                  Tab(text: 'Petites annonces'),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isJobsTab
                  ? _FilterRow(
                      key: const ValueKey('job_filters'),
                      isDark: isDark,
                      selectedKey: _jobFilterKey,
                      filters: _jobFilters,
                      accent: _accent,
                      onSelected: (k) => setState(() => _jobFilterKey = k),
                    )
                  : _FilterRow(
                      key: const ValueKey('ad_filters'),
                      isDark: isDark,
                      selectedKey: _adFilterKey,
                      filters: _adFilters,
                      accent: _accent,
                      onSelected: (k) => setState(() => _adFilterKey = k),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: _jobsQuery().snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}', style: TextStyle(color: sub)));
                    final docs = (snap.data?.docs ?? const <QueryDocumentSnapshot>[]).toList();
                    final items = docs
                        .map((d) => (id: d.id, data: (d.data() as Map<String, dynamic>? ?? const <String, dynamic>{})))
                        .where((x) => _matchesSearch(x.data) && _matchesJobAdvanced(x.data))
                        .toList();

                    items.sort((a, b) {
                      if (_sortKey == 'date') return _tsMs(b.data).compareTo(_tsMs(a.data));
                      if (_sortKey == 'salary') return _salaryValue(b.data).compareTo(_salaryValue(a.data));
                      // relevance
                      final sa = _relevanceScore(a.data);
                      final sb = _relevanceScore(b.data);
                      final cmp = sb.compareTo(sa);
                      if (cmp != 0) return cmp;
                      return _tsMs(b.data).compareTo(_tsMs(a.data));
                    });

                    if (items.isEmpty) {
                      return Center(child: Text("Aucune offre d'emploi", style: TextStyle(color: sub, fontWeight: FontWeight.w700)));
                    }

                    final filtersN = _activeFiltersCount();

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: card,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: divider),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Resultats', style: TextStyle(color: sub, fontWeight: FontWeight.w800, fontSize: 12)),
                                      const SizedBox(height: 6),
                                      Text('${items.length}', style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: card,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: divider),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Tri', style: TextStyle(color: sub, fontWeight: FontWeight.w800, fontSize: 12)),
                                      const SizedBox(height: 6),
                                      Text(_labelForSort(_sortKey), style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: InkWell(
                                  onTap: _openAdvancedFiltersSheet,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: card,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: divider),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Filtres', style: TextStyle(color: sub, fontWeight: FontWeight.w800, fontSize: 12)),
                                        const SizedBox(height: 6),
                                        Text(filtersN == 0 ? 'Aucun' : '$filtersN actif(s)',
                                            style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 14)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              final item = items[i];
                              final data = item.data;
                              final title = (data['title'] ?? '').toString();
                              final company = (data['company'] ?? '').toString();
                              final salary = (data['salary'] ?? '').toString();
                              final location = (data['location'] ?? '').toString();
                              final typeKey = (data['typeKey'] ?? 'full_time').toString();
                              final urgent = _asBool(data['urgent']);
                              final coverUrl = (data['coverUrl'] ?? '').toString();
                              final enterpriseUid = (data['createdByUid'] ?? '').toString().trim();
                              final meUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                              final canFollow = enterpriseUid.isNotEmpty && enterpriseUid != meUid;

                              return _JobCard(
                                isDark: isDark,
                                card: card,
                                text: text,
                                sub: sub,
                                divider: divider,
                                accent: _accent,
                                cover: _coverThumb(coverUrl, isDark: isDark),
                                title: title.isEmpty ? 'Offre' : title,
                                company: company,
                                salary: salary,
                                location: location,
                                typeLabel: _labelForJobType(typeKey),
                                urgent: urgent,
                                isFollowing: canFollow && _followedEnterprises.contains(enterpriseUid),
                                onFollowToggle: canFollow ? () => _toggleFollowEnterprise(enterpriseUid) : null,
                                onApply: () => _openApplySheet(jobId: item.id, job: data),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
                StreamBuilder<QuerySnapshot>(
                  stream: _adsQuery().snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}', style: TextStyle(color: sub)));
                    final docs = (snap.data?.docs ?? const <QueryDocumentSnapshot>[]).toList();
                    final items = docs.map((d) => (d.data() as Map<String, dynamic>? ?? const {})).where(_matchesSearch).toList()
                      ..sort((a, b) => _tsMs(b).compareTo(_tsMs(a)));

                    if (items.isEmpty) {
                      return Center(child: Text('Aucune annonce', style: TextStyle(color: sub, fontWeight: FontWeight.w700)));
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final data = items[i];
                        final title = (data['title'] ?? '').toString();
                        final location = (data['location'] ?? '').toString();
                        final price = (data['price'] ?? '').toString();
                        final categoryKey = (data['categoryKey'] ?? 'other').toString();
                        final coverUrl = (data['coverUrl'] ?? '').toString();
                        final phone = (data['phone'] ?? '').toString();
                        final email = (data['email'] ?? '').toString();

                        return _AdCard(
                          isDark: isDark,
                          card: card,
                          text: text,
                          sub: sub,
                          divider: divider,
                          accent: _accent,
                          cover: _coverThumb(coverUrl, isDark: isDark),
                          title: title.isEmpty ? 'Annonce' : title,
                          location: location,
                          price: price,
                          categoryLabel: _labelForAdCategory(categoryKey),
                          onContact: () => _showContactSheet(title: title.isEmpty ? 'Annonce' : title, phone: phone, email: email),
                        );
                      },
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
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.20)),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    super.key,
    required this.isDark,
    required this.selectedKey,
    required this.filters,
    required this.accent,
    required this.onSelected,
  });

  final bool isDark;
  final String selectedKey;
  final List<(String, String, IconData)> filters;
  final Color accent;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      itemCount: filters.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final f = filters[i];
        final selected = selectedKey == f.$1;
        final bg = selected ? (isDark ? const Color(0xFF111B21) : Colors.white) : (isDark ? Colors.white10 : const Color(0xFFF1F3F5));
        final border = selected ? accent.withOpacity(0.35) : (isDark ? Colors.white12 : Colors.black12);
        final fg = selected ? accent : (isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827));

        return InkWell(
          onTap: () => onSelected(f.$1),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
            child: Row(
              children: [
                Icon(f.$3, size: 18, color: selected ? fg : sub),
                const SizedBox(width: 8),
                Text(f.$2, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12.5)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.isDark,
    required this.card,
    required this.text,
    required this.sub,
    required this.divider,
    required this.accent,
    required this.cover,
    required this.title,
    required this.company,
    required this.salary,
    required this.location,
    required this.typeLabel,
    required this.urgent,
    required this.onApply,
    this.isFollowing = false,
    this.onFollowToggle,
  });

  final bool isDark;
  final Color card;
  final Color text;
  final Color sub;
  final Color divider;
  final Color accent;
  final Widget cover;
  final String title;
  final String company;
  final String salary;
  final String location;
  final String typeLabel;
  final bool urgent;
  final VoidCallback onApply;
  final bool isFollowing;
  final VoidCallback? onFollowToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.28 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: text, letterSpacing: -0.2),
                          ),
                        ),
                        if (urgent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(isDark ? 0.20 : 0.10),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: Colors.redAccent.withOpacity(0.25)),
                            ),
                            child: const Text('URGENT', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w900)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (company.trim().isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.business, size: 16, color: accent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              company,
                              style: TextStyle(color: accent, fontWeight: FontWeight.w900),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (onFollowToggle != null)
                            TextButton(
                              onPressed: onFollowToggle,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                backgroundColor: isFollowing ? Colors.white.withOpacity(0.14) : accent.withOpacity(0.18),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                              ),
                              child: Text(isFollowing ? 'Suivi' : 'Suivre', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                            ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _miniPill(icon: Icons.location_on_outlined, label: location.isEmpty ? '—' : location),
                        _miniPill(icon: Icons.access_time, label: typeLabel),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                salary.trim().isEmpty ? 'Salaire: —' : salary.trim(),
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: text),
              ),
              ElevatedButton(
                onPressed: onApply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Postuler', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: sub),
          Text(' $label', style: TextStyle(color: sub, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _AdCard extends StatelessWidget {
  const _AdCard({
    required this.isDark,
    required this.card,
    required this.text,
    required this.sub,
    required this.divider,
    required this.accent,
    required this.cover,
    required this.title,
    required this.location,
    required this.price,
    required this.categoryLabel,
    required this.onContact,
  });

  final bool isDark;
  final Color card;
  final Color text;
  final Color sub;
  final Color divider;
  final Color accent;
  final Widget cover;
  final String title;
  final String location;
  final String price;
  final String categoryLabel;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.28 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: text, letterSpacing: -0.2)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _pill(label: categoryLabel, fg: accent, bg: accent.withOpacity(isDark ? 0.18 : 0.10)),
                        if (location.trim().isNotEmpty) _pill(label: location.trim(), fg: sub, bg: isDark ? Colors.white10 : const Color(0xFFF1F3F5)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(price.trim().isEmpty ? 'Prix: —' : price.trim(), style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: text)),
              ElevatedButton(
                onPressed: onContact,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Contacter', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill({required String label, required Color fg, required Color bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12)),
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
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final Color textColor;
  final Color subColor;
  final Color divider;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: textColor, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subColor, fontWeight: FontWeight.w700),
        filled: true,
        fillColor: isDark ? Colors.white10 : const Color(0xFFF1F3F5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _JobsPageState._accent.withOpacity(0.40))),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.textColor,
    required this.subColor,
    required this.divider,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final Color textColor;
  final Color subColor;
  final Color divider;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeValue = (value != null && items.any((e) => e.value == value)) ? value : null;
    return DropdownButtonFormField<String>(
      initialValue: safeValue,
      items: items,
      onChanged: onChanged,
      style: TextStyle(color: textColor, fontWeight: FontWeight.w800),
      dropdownColor: isDark ? const Color(0xFF111B21) : Colors.white,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subColor, fontWeight: FontWeight.w700),
        filled: true,
        fillColor: isDark ? Colors.white10 : const Color(0xFFF1F3F5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: _JobsPageState._accent.withOpacity(0.40))),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.label,
    required this.filename,
    required this.isDark,
    required this.divider,
    required this.onTap,
  });

  final String label;
  final String filename;
  final bool isDark;
  final Color divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = filename.trim();
    final has = name.isNotEmpty;
    final bg = isDark ? Colors.white10 : const Color(0xFFF1F3F5);
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: divider),
        ),
        child: Row(
          children: [
            Icon(Icons.attach_file_rounded, color: sub),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: sub, fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    has ? name : 'Choisir un fichier',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: text, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

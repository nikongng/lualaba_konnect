import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config.dart';

class IdentityValidationAdminPage extends StatefulWidget {
  const IdentityValidationAdminPage({super.key});

  @override
  State<IdentityValidationAdminPage> createState() => _IdentityValidationAdminPageState();
}

class _IdentityValidationAdminPageState extends State<IdentityValidationAdminPage> {
  static const List<String> _userCollections = ['classic_users', 'pro_users', 'enterprise_users', 'users'];

  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _searching = false;
  bool _approving = false;
  bool _directAvailable = false;
  bool _directMode = false;
  String? _error;
  List<_IdentityUser> _pending = [];
  List<_IdentityUser> _results = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  Future<void> _init() async {
    await _checkDirectAdmin();
    await _loadPending();
  }

  Future<void> _checkDirectAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('admin_users').doc(user.uid).get();
      final enabled = snap.exists && (snap.data()?['enabled'] ?? true);
      if (mounted) {
        setState(() => _directAvailable = enabled);
      }
    } catch (_) {}
  }

  Uri _apiUri(String path, [Map<String, String>? query]) {
    final base = functionsApiUri.toString().replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Future<void> _loadPending() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Session expirée.');
      final resp = await http.get(
        _apiUri('/identity/pending'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) {
        throw Exception(_readError(resp.body) ?? 'Erreur serveur (${resp.statusCode}).');
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final items = (data['items'] as List? ?? const [])
          .map((e) => _IdentityUser.fromMap(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _pending = items;
        _directMode = false;
        _loading = false;
      });
    } catch (e) {
      if (_directAvailable) {
        final ok = await _loadPendingDirect();
        if (ok) return;
      }
      setState(() {
        _error = '${e.toString()}\nMode direct indisponible. Ajoutez votre UID dans /admin_users.';
        _loading = false;
      });
    }
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Session expirée.');
      final resp = await http.get(
        _apiUri('/identity/search', {'q': q}),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) {
        throw Exception(_readError(resp.body) ?? 'Erreur serveur (${resp.statusCode}).');
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final items = (data['items'] as List? ?? const [])
          .map((e) => _IdentityUser.fromMap(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _results = items;
        _directMode = false;
        _searching = false;
      });
    } catch (e) {
      if (_directAvailable) {
        final ok = await _searchDirect(q);
        if (ok) return;
      }
      setState(() {
        _error = e.toString();
        _searching = false;
      });
    }
  }

  Future<void> _approve(_IdentityUser user) async {
    if (_approving) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Valider l’identité'),
        content: Text('Valider le compte de ${user.displayName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Valider')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _approving = true);
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Session expirée.');
      final resp = await http.post(
        _apiUri('/identity/approve'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: json.encode({'uid': user.uid, 'collection': user.collection}),
      );
      if (resp.statusCode != 200) {
        throw Exception(_readError(resp.body) ?? 'Erreur serveur (${resp.statusCode}).');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Validation effectuée')));
      }
      setState(() {
        _pending.removeWhere((u) => u.uid == user.uid && u.collection == user.collection);
        _results = _results.map((u) => u.matches(user) ? u.copyWith(isValidated: true) : u).toList();
        _directMode = false;
      });
    } catch (e) {
      if (_directAvailable) {
        final okDirect = await _approveDirect(user);
        if (okDirect) return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<bool> _loadPendingDirect() async {
    try {
      final items = <_IdentityUser>[];
      for (final col in _userCollections) {
        final snap = await FirebaseFirestore.instance
            .collection(col)
            .where('isValidated', isEqualTo: false)
            .limit(50)
            .get();
        for (final doc in snap.docs) {
          items.add(_IdentityUser.fromDoc(doc, col));
        }
      }
      items.sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0) - (a.createdAt?.millisecondsSinceEpoch ?? 0));
      if (mounted) {
        setState(() {
          _pending = items;
          _directMode = true;
          _loading = false;
          _error = null;
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
      return false;
    }
  }

  Future<bool> _searchDirect(String q) async {
    try {
      final results = <String, _IdentityUser>{};
      final looksLikeEmail = q.contains('@');
      final phoneVariants = _phoneVariants(q);

      for (final col in _userCollections) {
        try {
          final direct = await FirebaseFirestore.instance.collection(col).doc(q).get();
          if (direct.exists) {
            results['$col/${direct.id}'] = _IdentityUser.fromDoc(direct, col);
          }
        } catch (_) {}
      }

      if (looksLikeEmail) {
        for (final col in _userCollections) {
          final snap = await FirebaseFirestore.instance.collection(col).where('email', isEqualTo: q).limit(10).get();
          for (final doc in snap.docs) {
            results['$col/${doc.id}'] = _IdentityUser.fromDoc(doc, col);
          }
        }
      } else if (phoneVariants.isNotEmpty) {
        for (final col in _userCollections) {
          for (final variant in phoneVariants) {
            final snap = await FirebaseFirestore.instance.collection(col).where('phone', isEqualTo: variant).limit(10).get();
            for (final doc in snap.docs) {
              results['$col/${doc.id}'] = _IdentityUser.fromDoc(doc, col);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _results = results.values.toList();
          _directMode = true;
          _searching = false;
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _searching = false;
        });
      }
      return false;
    }
  }

  Future<bool> _approveDirect(_IdentityUser user) async {
    try {
      final current = FirebaseAuth.instance.currentUser;
      if (current == null) throw Exception('Session expirÃ©e.');
      await FirebaseFirestore.instance.collection(user.collection).doc(user.uid).set({
        'isValidated': true,
        'validatedAt': FieldValue.serverTimestamp(),
        'validatedBy': current.uid,
        'uploadStatus': 'validated',
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Validation effectuÃ©e')));
        setState(() {
          _pending.removeWhere((u) => u.uid == user.uid && u.collection == user.collection);
          _results = _results.map((u) => u.matches(user) ? u.copyWith(isValidated: true) : u).toList();
          _directMode = true;
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return false;
    }
  }

  List<String> _phoneVariants(String q) {
    final digits = q.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return const [];
    final out = <String>{digits};
    if (!digits.startsWith('+')) {
      out.add('+$digits');
      if (digits.length == 9) out.add('+243$digits');
    }
    return out.toList();
  }

  String? _readError(String body) {
    try {
      final data = json.decode(body);
      if (data is Map<String, dynamic>) {
        return data['message']?.toString();
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1416) : const Color(0xFFF7F8FA);
    final card = isDark ? Colors.white10 : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Validation identité', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: text),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadPending,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'UID, email ou téléphone',
                      filled: true,
                      fillColor: card,
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _searching ? null : _search,
                  child: _searching ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Rechercher'),
                ),
              ],
            ),
          ),
          if (_directMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Mode direct (Firestore). Assurez‑vous que les règles autorisent les admins.',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildLists(text: text, sub: sub, card: card),
          ),
        ],
      ),
    );
  }

  Widget _buildLists({required Color text, required Color sub, required Color card}) {
    final hasSearch = _results.isNotEmpty || _searchCtrl.text.trim().isNotEmpty;
    if (hasSearch) {
      return _results.isEmpty
          ? Center(child: Text('Aucun résultat', style: TextStyle(color: sub)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _results.length,
              itemBuilder: (c, i) => _userCard(_results[i], text: text, sub: sub, card: card),
            );
    }
    if (_pending.isEmpty) {
      return Center(child: Text('Aucune validation en attente', style: TextStyle(color: sub)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _pending.length,
      itemBuilder: (c, i) => _userCard(_pending[i], text: text, sub: sub, card: card),
    );
  }

  Widget _userCard(_IdentityUser user, {required Color text, required Color sub, required Color card}) {
    final name = user.displayName;
    final created = user.createdAt == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(user.createdAt!);
    final birth = user.birthDate == null ? '' : DateFormat('yyyy-MM-dd').format(user.birthDate!);
    final profileType = user.profileTypeLabel;
    final docs = <Widget>[];
    if (user.identityPdf.isNotEmpty) {
      docs.add(_docButton('PDF identité', user.identityPdf));
    }
    if (user.selfie.isNotEmpty) {
      docs.add(_docButton('Selfie', user.selfie));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name, style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: user.isValidated ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  user.isValidated ? 'Validé' : 'En attente',
                  style: TextStyle(color: user.isValidated ? Colors.green : Colors.orange, fontWeight: FontWeight.w700, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${user.collectionLabel} • $profileType', style: TextStyle(color: sub)),
          if (user.email.isNotEmpty) Text(user.email, style: TextStyle(color: sub)),
          if (user.phone.isNotEmpty) Text(user.phone, style: TextStyle(color: sub)),
          if (birth.isNotEmpty) Text('Naissance: $birth', style: TextStyle(color: sub)),
          if (created.isNotEmpty) Text('Créé: $created', style: TextStyle(color: sub)),
          if (user.uploadStatus.isNotEmpty) Text('Upload: ${user.uploadStatus}', style: TextStyle(color: sub)),
          if (docs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: docs),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  user.uid,
                  style: TextStyle(color: sub, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (!user.isValidated)
                ElevatedButton.icon(
                  onPressed: _approving ? null : () => _approve(user),
                  icon: const Icon(Icons.verified, size: 18),
                  label: const Text('Valider'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _docButton(String label, String url) {
    return OutlinedButton.icon(
      onPressed: () => _openUrl(url),
      icon: const Icon(Icons.open_in_new, size: 16),
      label: Text(label),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d’ouvrir le lien')));
      }
    }
  }
}

class _IdentityUser {
  final String uid;
  final String collection;
  final String firstName;
  final String lastName;
  final String phone;
  final String email;
  final int? profileType;
  final DateTime? createdAt;
  final DateTime? birthDate;
  final String uploadStatus;
  final String identityPdf;
  final String selfie;
  final bool isValidated;

  _IdentityUser({
    required this.uid,
    required this.collection,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.profileType,
    required this.createdAt,
    required this.birthDate,
    required this.uploadStatus,
    required this.identityPdf,
    required this.selfie,
    required this.isValidated,
  });

  factory _IdentityUser.fromMap(Map<String, dynamic> map) {
    final uid = (map['uid'] ?? '').toString();
    final collection = (map['collection'] ?? '').toString();
    return _IdentityUser._fromData(uid, collection, map);
  }

  factory _IdentityUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc, String collection) {
    return _IdentityUser._fromData(doc.id, collection, doc.data() ?? <String, dynamic>{});
  }

  factory _IdentityUser._fromData(String uid, String collection, Map<String, dynamic> data) {
    final docs = data['documents'] as Map<String, dynamic>? ?? const {};
    return _IdentityUser(
      uid: uid,
      collection: collection,
      firstName: (data['firstName'] ?? '').toString(),
      lastName: (data['lastName'] ?? '').toString(),
      phone: (data['phone'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      profileType: data['profileType'] is int ? data['profileType'] as int : int.tryParse('${data['profileType'] ?? ''}'),
      createdAt: _parseDate(data['createdAt']),
      birthDate: _parseDate(data['birthDate']),
      uploadStatus: (data['uploadStatus'] ?? '').toString(),
      identityPdf: (docs['identityPdf'] ?? '').toString(),
      selfie: (docs['selfie'] ?? '').toString(),
      isValidated: data['isValidated'] == true,
    );
  }

  String get displayName {
    final name = '${firstName.trim()} ${lastName.trim()}'.trim();
    return name.isEmpty ? uid : name;
  }

  String get profileTypeLabel {
    if (profileType == 1) return 'Pro';
    if (profileType == 2) return 'Entreprise';
    return 'Classique';
  }

  String get collectionLabel {
    if (collection == 'pro_users') return 'Pro';
    if (collection == 'enterprise_users') return 'Entreprise';
    if (collection == 'classic_users') return 'Classique';
    return collection;
  }

  bool matches(_IdentityUser other) => uid == other.uid && collection == other.collection;

  _IdentityUser copyWith({bool? isValidated}) {
    return _IdentityUser(
      uid: uid,
      collection: collection,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      email: email,
      profileType: profileType,
      createdAt: createdAt,
      birthDate: birthDate,
      uploadStatus: uploadStatus,
      identityPdf: identityPdf,
      selfie: selfie,
      isValidated: isValidated ?? this.isValidated,
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

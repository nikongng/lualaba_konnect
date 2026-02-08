import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:timeago/timeago.dart' as timeago;
import 'package:timeago/src/messages/fr_messages.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lualaba_konnect/core/config.dart';

class EnterpriseJobsAdminPage extends StatefulWidget {
  final String enterpriseUid;
  const EnterpriseJobsAdminPage({super.key, required this.enterpriseUid});

  @override
  State<EnterpriseJobsAdminPage> createState() => _EnterpriseJobsAdminPageState();
}

class _EnterpriseJobsAdminPageState extends State<EnterpriseJobsAdminPage> with SingleTickerProviderStateMixin {
  static const List<(String, String)> _sectors = [
    ('all', 'Tout'),
    ('tech', 'Tech'),
    ('batiment', 'Batiment'),
    ('art', 'Art'),
    ('vie', 'Vie'),
    ('other', 'Autre'),
  ];

  static const List<(String, String)> _experienceLevels = [
    ('entry', 'Debutant'),
    ('junior', 'Junior'),
    ('mid', 'Intermediaire'),
    ('senior', 'Senior'),
  ];

  static const List<(String, String)> _contractTypes = [
    ('full_time', 'Temps plein'),
    ('part_time', 'Temps partiel'),
    ('freelance', 'Freelance'),
    ('internship', 'Stage'),
  ];

  late final TabController _tab;
  String _candidateFilter = 'all';
  String _offersFilter = 'all';
  final TextEditingController _candSearchCtrl = TextEditingController();

  Widget _statCard({
    required bool isDark,
    required Color card,
    required Color text,
    required Color sub,
    required Color divider,
    required String label,
    required String value,
    required Color glow,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
        boxShadow: [BoxShadow(color: glow.withOpacity(isDark ? 0.18 : 0.10), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: sub, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16)),
        ],
      ),
    );
  }

  Map<String, int> _countByStatus(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String key) {
    final out = <String, int>{};
    for (final d in docs) {
      final s = (d.data()[key] ?? '').toString().trim();
      out[s] = (out[s] ?? 0) + 1;
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('fr', FrMessages());
    _tab = TabController(length: 2, vsync: this);
    _candSearchCtrl.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _candSearchCtrl.dispose();
    super.dispose();
  }

  bool _matchesCandidateSearch(Map<String, dynamic> d) {
    final q = _candSearchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      d['applicantName'],
      d['contactEmail'],
      d['contactPhone'],
      d['experienceKey'],
      d['skills'],
      d['education'],
      d['jobTitle'],
    ].where((e) => e != null).map((e) => e.toString()).join(' ').toLowerCase();
    return hay.contains(q);
  }

  String _when(Timestamp? ts, int? ms) {
    DateTime? dt;
    if (ts != null) dt = ts.toDate();
    if (dt == null && ms != null) dt = DateTime.fromMillisecondsSinceEpoch(ms);
    if (dt == null) return '';
    return timeago.format(dt, locale: 'fr');
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'open':
        return 'Ouverte';
      case 'paused':
        return 'En pause';
      case 'closed':
        return 'Fermee';
      case 'submitted':
        return 'Envoyee';
      case 'reviewed':
        return 'Vue';
      case 'shortlisted':
        return 'Selection';
      case 'rejected':
        return 'Refusee';
      case 'accepted':
        return 'Acceptee';
      default:
        return s.isEmpty ? '—' : s;
    }
  }

  Color _statusColor(String s, bool isDark) {
    switch (s) {
      case 'open':
      case 'accepted':
        return const Color(0xFF2ECC71);
      case 'paused':
      case 'shortlisted':
        return const Color(0xFFFB8C00);
      case 'closed':
      case 'rejected':
        return Colors.redAccent;
      case 'reviewed':
        return const Color(0xFF64B5F6);
      default:
        return isDark ? Colors.white60 : Colors.black54;
    }
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

  Future<void> _notify({
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

      await _sendPush(
        recipients: [toUserId],
        title: fromName.isNotEmpty ? fromName : (title.isNotEmpty ? title : 'Lualaba Konnect'),
        body: body,
        senderAvatarUrl: fromAvatar,
        imageUrl: (extra?['imageUrl'] ?? '').toString(),
        data: <String, dynamic>{'type': type, ...(extra ?? {})},
      );
    } catch (_) {}
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
      debugPrint('Notifier push error: $e');
    }
  }

  Future<void> _changeApplicationStatus({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    required String newStatus,
  }) async {
    final applicantUid = (data['applicantUid'] ?? '').toString();
    final jobTitle = (data['jobTitle'] ?? '').toString().trim();

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await ref.set(
      {
        'statusKey': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtMs': nowMs,
      },
      SetOptions(merge: true),
    );

    if (applicantUid.isNotEmpty) {
      await _notify(
        toUserId: applicantUid,
        fromUserId: widget.enterpriseUid,
        type: 'job_application_update',
        title: 'Reponse recruteur',
        body: 'Votre candidature pour "${jobTitle.isEmpty ? 'Offre' : jobTitle}" est maintenant: ${_statusLabel(newStatus)}',
        extra: {'applicationId': ref.id, 'jobId': (data['jobId'] ?? '').toString()},
      );
    }
  }

  void _openOfferMenu({
    required bool isDark,
    required Color card,
    required Color text,
    required Color sub,
    required Color divider,
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.5 : 0.12), blurRadius: 24, offset: const Offset(0, 12))],
              border: Border.all(color: divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(99)),
                ),
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: sub),
                  title: Text('Modifier', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openEditOfferSheet(ref: ref, data: data);
                  },
                ),
                Divider(height: 1, color: divider),
                ListTile(
                  leading: Icon(Icons.pause_circle_outline, color: sub),
                  title: Text('Mettre en pause', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.set({'statusKey': 'paused', 'updatedAt': FieldValue.serverTimestamp(), 'updatedAtMs': DateTime.now().millisecondsSinceEpoch},
                        SetOptions(merge: true));
                  },
                ),
                Divider(height: 1, color: divider),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline, color: Color(0xFF2ECC71)),
                  title: Text('Ouvrir', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.set({'statusKey': 'open', 'updatedAt': FieldValue.serverTimestamp(), 'updatedAtMs': DateTime.now().millisecondsSinceEpoch},
                        SetOptions(merge: true));
                  },
                ),
                Divider(height: 1, color: divider),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                  title: Text('Fermer', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.set({'statusKey': 'closed', 'updatedAt': FieldValue.serverTimestamp(), 'updatedAtMs': DateTime.now().millisecondsSinceEpoch},
                        SetOptions(merge: true));
                  },
                ),
                Divider(height: 1, color: divider),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: Text('Supprimer', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  subtitle: Text("Supprime l'offre (les candidatures restent).", style: TextStyle(color: sub)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: card,
                        title: Text('Supprimer ?', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                        content: Text('Confirmer la suppression de cette offre.', style: TextStyle(color: sub)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Annuler', style: TextStyle(color: text))),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent))),
                        ],
                      ),
                    );
                    if (ok == true) await ref.delete();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openEditOfferSheet({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;
    const accent = Color(0xFFFB8C00);

    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: (data['title'] ?? '').toString());
    final companyCtrl = TextEditingController(text: (data['company'] ?? '').toString());
    final locationCtrl = TextEditingController(text: (data['location'] ?? '').toString());
    final salaryCtrl = TextEditingController(text: (data['salary'] ?? '').toString());
    final phoneCtrl = TextEditingController(text: (data['phone'] ?? '').toString());
    final emailCtrl = TextEditingController(text: (data['email'] ?? '').toString());
    final descCtrl = TextEditingController(text: (data['description'] ?? '').toString());
    final reqCtrl = TextEditingController(text: (data['requirements'] ?? '').toString());

    String typeKey = (data['typeKey'] ?? 'full_time').toString();
    String sectorKey = (data['sectorKey'] ?? 'all').toString();
    String expKey = (data['experienceKey'] ?? 'junior').toString();
    bool remoteOk = (data['remoteOk'] == true);
    bool urgent = (data['urgent'] == true);
    String statusKey = (data['statusKey'] ?? 'open').toString();

    int salaryValueFrom(String raw) {
      final digits = RegExp(r'(\d[\d\s,.]*)').firstMatch(raw)?.group(1) ?? '';
      final cleaned = digits.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(cleaned) ?? 0;
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
                  color: card,
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
                            Expanded(child: Text('Modifier offre', style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5))),
                            IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _field('Titre', titleCtrl, text, sub, divider, validator: (v) => (v == null || v.trim().isEmpty) ? 'Titre requis' : null),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _field('Entreprise', companyCtrl, text, sub, divider)),
                            const SizedBox(width: 10),
                            Expanded(child: _field('Lieu', locationCtrl, text, sub, divider)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _field(r'Salaire (ex: 250$)', salaryCtrl, text, sub, divider)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _dropdown(
                                'Contrat',
                                typeKey,
                                _contractTypes,
                                text,
                                sub,
                                divider,
                                (v) => setModal(() => typeKey = v ?? 'full_time'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _dropdown(
                                'Secteur',
                                sectorKey,
                                _sectors,
                                text,
                                sub,
                                divider,
                                (v) => setModal(() => sectorKey = v ?? 'all'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _dropdown(
                                'Experience',
                                expKey,
                                _experienceLevels,
                                text,
                                sub,
                                divider,
                                (v) => setModal(() => expKey = v ?? 'junior'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _field('Telephone', phoneCtrl, text, sub, divider)),
                            const SizedBox(width: 10),
                            Expanded(child: _field('Email', emailCtrl, text, sub, divider)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _switchTile('Teletravail possible', remoteOk, text, divider, (v) => setModal(() => remoteOk = v)),
                        const SizedBox(height: 8),
                        _switchTile('Urgent', urgent, text, divider, (v) => setModal(() => urgent = v)),
                        const SizedBox(height: 10),
                        _dropdown(
                          'Statut',
                          statusKey,
                          const [('open', 'Ouverte'), ('paused', 'En pause'), ('closed', 'Fermee')],
                          text,
                          sub,
                          divider,
                          (v) => setModal(() => statusKey = v ?? 'open'),
                        ),
                        const SizedBox(height: 10),
                        _field('Description', descCtrl, text, sub, divider, maxLines: 4),
                        const SizedBox(height: 10),
                        _field('Exigences', reqCtrl, text, sub, divider, maxLines: 3),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              final nowMs = DateTime.now().millisecondsSinceEpoch;
                              await ref.set(
                                {
                                  'title': titleCtrl.text.trim(),
                                  'company': companyCtrl.text.trim(),
                                  'location': locationCtrl.text.trim(),
                                  'salary': salaryCtrl.text.trim(),
                                  'salaryValue': salaryValueFrom(salaryCtrl.text.trim()),
                                  'typeKey': typeKey,
                                  'sectorKey': sectorKey,
                                  'experienceKey': expKey,
                                  'remoteOk': remoteOk,
                                  'urgent': urgent,
                                  'statusKey': statusKey,
                                  'phone': phoneCtrl.text.trim(),
                                  'email': emailCtrl.text.trim(),
                                  'description': descCtrl.text.trim(),
                                  'requirements': reqCtrl.text.trim(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                  'updatedAtMs': nowMs,
                                },
                                SetOptions(merge: true),
                              );
                              if (!mounted) return;
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offre mise a jour.')));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFF111827),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          r'Astuce: pour un tri par salaire, renseignez un salaire avec un nombre (ex: 250$).',
                          style: TextStyle(color: sub, fontWeight: FontWeight.w700, fontSize: 12),
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

  static Widget _switchTile(String label, bool value, Color text, Color divider, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: divider),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: text, fontWeight: FontWeight.w900))),
          Switch.adaptive(value: value, onChanged: onChanged, activeColor: const Color(0xFFFB8C00)),
        ],
      ),
    );
  }

  static Widget _field(
    String label,
    TextEditingController ctrl,
    Color text,
    Color sub,
    Color divider, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      maxLines: maxLines,
      style: TextStyle(color: text, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: sub, fontWeight: FontWeight.w700),
        filled: true,
        fillColor: Colors.transparent,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: const Color(0xFFFB8C00).withOpacity(0.40))),
      ),
    );
  }

  static Widget _dropdown(
    String label,
    String value,
    List<(String, String)> items,
    Color text,
    Color sub,
    Color divider,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
      onChanged: onChanged,
      style: TextStyle(color: text, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: sub, fontWeight: FontWeight.w700),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: const Color(0xFFFB8C00).withOpacity(0.40))),
      ),
    );
  }

  void _openCandidateMenu({
    required bool isDark,
    required Color card,
    required Color text,
    required Color sub,
    required Color divider,
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cvUrl = (data['cvUrl'] ?? '').toString();
        final letterUrl = (data['coverLetterPdfUrl'] ?? '').toString();
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.5 : 0.12), blurRadius: 24, offset: const Offset(0, 12))],
              border: Border.all(color: divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(99)),
                ),
                if (cvUrl.trim().isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.picture_as_pdf_outlined, color: sub),
                    title: Text('Voir le CV', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchOrSnack(Uri.parse(cvUrl.trim()));
                    },
                  ),
                if (letterUrl.trim().isNotEmpty) ...[
                  Divider(height: 1, color: divider),
                  ListTile(
                    leading: Icon(Icons.mail_outline_rounded, color: sub),
                    title: Text('Voir la lettre (PDF)', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchOrSnack(Uri.parse(letterUrl.trim()));
                    },
                  ),
                ],
                Divider(height: 1, color: divider),
                _statusTile(ctx, 'reviewed', 'Marquer comme vue', isDark, text, sub, divider, () => _changeApplicationStatus(ref: ref, data: data, newStatus: 'reviewed')),
                Divider(height: 1, color: divider),
                _statusTile(
                    ctx, 'shortlisted', 'Selectionner', isDark, text, sub, divider, () => _changeApplicationStatus(ref: ref, data: data, newStatus: 'shortlisted')),
                Divider(height: 1, color: divider),
                _statusTile(ctx, 'accepted', 'Accepter', isDark, text, sub, divider, () => _changeApplicationStatus(ref: ref, data: data, newStatus: 'accepted')),
                Divider(height: 1, color: divider),
                _statusTile(ctx, 'rejected', 'Refuser', isDark, text, sub, divider, () => _changeApplicationStatus(ref: ref, data: data, newStatus: 'rejected')),
                Divider(height: 1, color: divider),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined, color: Colors.redAccent),
                  title: Text('Masquer candidat', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  subtitle: Text("N'affichera plus ce candidat dans la liste.", style: TextStyle(color: sub)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.set({'hiddenByEnterprise': true, 'updatedAt': FieldValue.serverTimestamp(), 'updatedAtMs': DateTime.now().millisecondsSinceEpoch},
                        SetOptions(merge: true));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusTile(
    BuildContext ctx,
    String key,
    String label,
    bool isDark,
    Color text,
    Color sub,
    Color divider,
    Future<void> Function() action,
  ) {
    return ListTile(
      leading: Icon(Icons.circle, size: 14, color: _statusColor(key, isDark)),
      title: Text(label, style: TextStyle(color: text, fontWeight: FontWeight.w800)),
      onTap: () async {
        Navigator.pop(ctx);
        await action();
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
    const accent = Color(0xFFFB8C00);

    // Guard: allow only enterprise owner (soft guard)
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || me.uid != widget.enterpriseUid) {
      return Scaffold(backgroundColor: bg, body: Center(child: Text('Acces refuse.', style: TextStyle(color: sub, fontWeight: FontWeight.w700))));
    }

    Query<Map<String, dynamic>> offersQ = FirebaseFirestore.instance
        .collection('job_posts')
        .where('createdByUid', isEqualTo: widget.enterpriseUid)
        .orderBy('createdAt', descending: true);
    if (_offersFilter != 'all') offersQ = offersQ.where('statusKey', isEqualTo: _offersFilter);

    final offersAllQ = FirebaseFirestore.instance.collection('job_posts').where('createdByUid', isEqualTo: widget.enterpriseUid);

    Query<Map<String, dynamic>> candQ = FirebaseFirestore.instance
        .collection('job_applications')
        .where('toEnterpriseUid', isEqualTo: widget.enterpriseUid)
        .orderBy('createdAt', descending: true);
    if (_candidateFilter != 'all') candQ = candQ.where('statusKey', isEqualTo: _candidateFilter);

    final candAllQ = FirebaseFirestore.instance.collection('job_applications').where('toEnterpriseUid', isEqualTo: widget.enterpriseUid);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        title: const Text('Gestion Emploi'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: divider),
              ),
              child: TabBar(
                controller: _tab,
                indicator: BoxDecoration(
                  color: accent.withOpacity(isDark ? 0.35 : 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                labelColor: text,
                unselectedLabelColor: sub,
                labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                tabs: const [
                  Tab(text: 'Offres'),
                  Tab(text: 'Candidats'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: offersAllQ.snapshots(),
                  builder: (context, snap) {
                    final docs = snap.data?.docs ?? const [];
                    final by = _countByStatus(docs, 'statusKey');
                    final total = docs.length;
                    final open = by['open'] ?? 0;
                    final paused = by['paused'] ?? 0;
                    final closed = by['closed'] ?? 0;
                    return Row(
                      children: [
                        Expanded(child: _statCard(isDark: isDark, card: card, text: text, sub: sub, divider: divider, label: 'Offres', value: '$total', glow: accent)),
                        const SizedBox(width: 10),
                        Expanded(child: _statCard(isDark: isDark, card: card, text: text, sub: sub, divider: divider, label: 'Ouvertes', value: '$open', glow: const Color(0xFF2ECC71))),
                        const SizedBox(width: 10),
                        Expanded(child: _statCard(isDark: isDark, card: card, text: text, sub: sub, divider: divider, label: 'Fermees', value: '$closed', glow: Colors.redAccent)),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chipOffer('all', 'Toutes', isDark, card, text, sub, divider, accent),
                      const SizedBox(width: 8),
                      _chipOffer('open', 'Ouvertes', isDark, card, text, sub, divider, accent),
                      const SizedBox(width: 8),
                      _chipOffer('paused', 'En pause', isDark, card, text, sub, divider, accent),
                      const SizedBox(width: 8),
                      _chipOffer('closed', 'Fermees', isDark, card, text, sub, divider, accent),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: offersQ.snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}', style: TextStyle(color: sub)));
                    final docs = snap.data?.docs ?? const [];
                    if (docs.isEmpty) return Center(child: Text("Aucune offre", style: TextStyle(color: sub, fontWeight: FontWeight.w700)));
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final d = doc.data();
                        final title = (d['title'] ?? '').toString().trim();
                        final statusKey = (d['statusKey'] ?? 'open').toString();
                        final when = _when(d['createdAt'] as Timestamp?, d['createdAtMs'] as int?);
                        final loc = (d['location'] ?? '').toString();
                        final type = (d['typeKey'] ?? '').toString();

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: card,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: divider),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.28 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title.isEmpty ? 'Offre' : title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 15.5, letterSpacing: -0.2)),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        _pill('${_statusLabel(statusKey)}', _statusColor(statusKey, isDark), isDark),
                                        if (loc.trim().isNotEmpty) _pill(loc.trim(), sub, isDark),
                                        if (type.trim().isNotEmpty) _pill(type.trim(), sub, isDark),
                                        if (when.isNotEmpty) _pill(when, sub, isDark),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _openOfferMenu(
                                  isDark: isDark,
                                  card: card,
                                  text: text,
                                  sub: sub,
                                  divider: divider,
                                  ref: doc.reference,
                                  data: d,
                                ),
                                icon: Icon(Icons.more_vert, color: sub),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: candAllQ.snapshots(),
                  builder: (context, snap) {
                    final docs = (snap.data?.docs ?? const []).where((d) => d.data()['hiddenByEnterprise'] == true ? false : true);
                    final by = _countByStatus(docs, 'statusKey');
                    final total = docs.length;
                    final submitted = by['submitted'] ?? 0;
                    final shortlisted = by['shortlisted'] ?? 0;
                    final accepted = by['accepted'] ?? 0;
                    final rejected = by['rejected'] ?? 0;
                    final responded = accepted + rejected;
                    final rate = total == 0 ? 0 : ((responded * 100) / total).round();
                    return Row(
                      children: [
                        Expanded(child: _statCard(isDark: isDark, card: card, text: text, sub: sub, divider: divider, label: 'Candidats', value: '$total', glow: accent)),
                        const SizedBox(width: 10),
                        Expanded(child: _statCard(isDark: isDark, card: card, text: text, sub: sub, divider: divider, label: 'Nouvelles', value: '$submitted', glow: const Color(0xFF64B5F6))),
                        const SizedBox(width: 10),
                        Expanded(child: _statCard(isDark: isDark, card: card, text: text, sub: sub, divider: divider, label: 'Reponse', value: '$rate%', glow: const Color(0xFF2ECC71))),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chipCand('all', 'Toutes', isDark, card, text, sub, divider, accent),
                      const SizedBox(width: 8),
                      _chipCand('submitted', 'Envoyees', isDark, card, text, sub, divider, accent),
                      const SizedBox(width: 8),
                      _chipCand('reviewed', 'Vues', isDark, card, text, sub, divider, accent),
                      const SizedBox(width: 8),
                      _chipCand('shortlisted', 'Selection', isDark, card, text, sub, divider, accent),
                      const SizedBox(width: 8),
                      _chipCand('accepted', 'Acceptees', isDark, card, text, sub, divider, accent),
                      const SizedBox(width: 8),
                      _chipCand('rejected', 'Refusees', isDark, card, text, sub, divider, accent),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Container(
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: divider),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: sub),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _candSearchCtrl,
                          style: TextStyle(color: text, fontWeight: FontWeight.w800),
                          decoration: InputDecoration(
                            hintText: 'Rechercher candidat (competences, formation...)',
                            hintStyle: TextStyle(color: sub),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_candSearchCtrl.text.trim().isNotEmpty)
                        IconButton(
                          onPressed: () => _candSearchCtrl.clear(),
                          icon: Icon(Icons.close, color: sub, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: candQ.snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}', style: TextStyle(color: sub)));
                    final docs = (snap.data?.docs ?? const [])
                        .where((d) => (d.data()['hiddenByEnterprise'] == true) ? false : true)
                        .where((d) => _matchesCandidateSearch(d.data()))
                        .toList();
                    if (docs.isEmpty) return Center(child: Text('Aucune candidature', style: TextStyle(color: sub, fontWeight: FontWeight.w700)));
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final d = doc.data();
                        final applicantName = (d['applicantName'] ?? '').toString().trim();
                        final contactEmail = (d['contactEmail'] ?? '').toString().trim();
                        final contactPhone = (d['contactPhone'] ?? '').toString().trim();
                        final jobTitle = (d['jobTitle'] ?? '').toString().trim();
                        final statusKey = (d['statusKey'] ?? '').toString().trim();
                        final when = _when(d['createdAt'] as Timestamp?, d['createdAtMs'] as int?);
                        final exp = (d['experienceKey'] ?? '').toString().trim();
                        final skills = (d['skills'] ?? '').toString().trim();

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: card,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: divider),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.28 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      applicantName.isEmpty ? 'Candidat' : applicantName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 15.5),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _statusColor(statusKey, isDark).withOpacity(isDark ? 0.18 : 0.10),
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(color: _statusColor(statusKey, isDark).withOpacity(0.25)),
                                    ),
                                    child: Text(
                                      _statusLabel(statusKey),
                                      style: TextStyle(color: _statusColor(statusKey, isDark), fontSize: 11.5, fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _openCandidateMenu(
                                      isDark: isDark,
                                      card: card,
                                      text: text,
                                      sub: sub,
                                      divider: divider,
                                      ref: doc.reference,
                                      data: d,
                                    ),
                                    icon: Icon(Icons.more_vert, color: sub),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(jobTitle.isEmpty ? 'Offre' : jobTitle, style: TextStyle(color: sub, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (exp.isNotEmpty) _pill(exp, sub, isDark),
                                  if (when.isNotEmpty) _pill(when, sub, isDark),
                                ],
                              ),
                              if (skills.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text('Competences: $skills', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                              ],
                              if (contactPhone.isNotEmpty || contactEmail.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: contactPhone.isEmpty ? null : () => _launchOrSnack(Uri.parse('tel:$contactPhone')),
                                        icon: const Icon(Icons.call_rounded, size: 18),
                                        label: const Text('Appeler'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: text,
                                          side: BorderSide(color: divider),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: contactEmail.isEmpty ? null : () => _launchOrSnack(Uri.parse('mailto:$contactEmail')),
                                        icon: const Icon(Icons.email_rounded, size: 18),
                                        label: const Text('Email'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: text,
                                          side: BorderSide(color: divider),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  Widget _chipOffer(
    String key,
    String label,
    bool isDark,
    Color card,
    Color text,
    Color sub,
    Color divider,
    Color accent,
  ) {
    final selected = _offersFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: accent.withOpacity(isDark ? 0.35 : 0.18),
      backgroundColor: card,
      side: BorderSide(color: divider),
      labelStyle: TextStyle(color: selected ? text : sub, fontWeight: FontWeight.w800),
      onSelected: (_) => setState(() => _offersFilter = key),
    );
  }

  Widget _chipCand(
    String key,
    String label,
    bool isDark,
    Color card,
    Color text,
    Color sub,
    Color divider,
    Color accent,
  ) {
    final selected = _candidateFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: accent.withOpacity(isDark ? 0.35 : 0.18),
      backgroundColor: card,
      side: BorderSide(color: divider),
      labelStyle: TextStyle(color: selected ? text : sub, fontWeight: FontWeight.w800),
      onSelected: (_) => setState(() => _candidateFilter = key),
    );
  }
}

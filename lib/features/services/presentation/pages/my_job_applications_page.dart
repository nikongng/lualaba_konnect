import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:timeago/src/messages/fr_messages.dart';
import 'package:url_launcher/url_launcher.dart';

class MyJobApplicationsPage extends StatefulWidget {
  const MyJobApplicationsPage({super.key});

  @override
  State<MyJobApplicationsPage> createState() => _MyJobApplicationsPageState();
}

class _MyJobApplicationsPageState extends State<MyJobApplicationsPage> {
  String _filter = 'all';

  String _friendlyFirestoreError(Object? error) {
    final s = (error ?? '').toString();
    if (s.contains('cloud_firestore/failed-precondition') && s.toLowerCase().contains('requires an index')) {
      return "Erreur Firestore: index manquant. (Solution: créer l'index dans Firebase console)";
    }
    return 'Erreur: $s';
  }

  Map<String, int> _countByStatus(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <String, int>{};
    for (final d in docs) {
      final s = (d.data()['statusKey'] ?? '').toString().trim();
      out[s] = (out[s] ?? 0) + 1;
    }
    return out;
  }

  Widget _statChip({
    required bool isDark,
    required Color card,
    required Color text,
    required Color sub,
    required Color divider,
    required Color accent,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.22 : 0.05), blurRadius: 14, offset: const Offset(0, 8))],
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

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('fr', FrMessages());
  }

  DateTime? _dateFrom(Map<String, dynamic> d, String keyTs, String keyMs) {
    final ts = d[keyTs];
    if (ts is Timestamp) return ts.toDate();
    final ms = d[keyMs];
    if (ms is int) return DateTime.fromMillisecondsSinceEpoch(ms);
    if (ms is num) return DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    return null;
  }

  String _when(DateTime? dt) {
    if (dt == null) return '';
    return timeago.format(dt, locale: 'fr');
  }

  Color _statusColor(String s, bool isDark) {
    switch (s) {
      case 'accepted':
        return const Color(0xFF2ECC71);
      case 'rejected':
        return Colors.redAccent;
      case 'shortlisted':
        return const Color(0xFFFB8C00);
      case 'reviewed':
        return const Color(0xFF64B5F6);
      default:
        return isDark ? Colors.white60 : Colors.black54;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;
    const accent = Color(0xFFFB8C00);

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Veuillez vous connecter.')));
    }

    final statsQ = FirebaseFirestore.instance.collection('job_applications').where('applicantUid', isEqualTo: user.uid);

    // Avoid composite-index requirements by doing ordering/filtering client-side.
    // (Firestore would require a composite index for `where(applicantUid)` + `orderBy(createdAt)` and even more with status filters.)
    final Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('job_applications')
        .where('applicantUid', isEqualTo: user.uid);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        title: const Text('Mes candidatures'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: statsQ.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(_friendlyFirestoreError(snap.error), style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                  );
                }
                final docs = snap.data?.docs ?? const [];
                final by = _countByStatus(docs);
                final total = docs.length;
                final accepted = by['accepted'] ?? 0;
                final rejected = by['rejected'] ?? 0;
                final reviewed = by['reviewed'] ?? 0;
                final shortlisted = by['shortlisted'] ?? 0;
                final responded = accepted + rejected;
                final rate = total == 0 ? 0 : ((responded * 100) / total).round();

                return Row(
                  children: [
                    Expanded(
                      child: _statChip(
                        isDark: isDark,
                        card: card,
                        text: text,
                        sub: sub,
                        divider: divider,
                        accent: accent,
                        label: 'Total',
                        value: '$total',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statChip(
                        isDark: isDark,
                        card: card,
                        text: text,
                        sub: sub,
                        divider: divider,
                        accent: accent,
                        label: 'Reponses',
                        value: '$rate%',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statChip(
                        isDark: isDark,
                        card: card,
                        text: text,
                        sub: sub,
                        divider: divider,
                        accent: accent,
                        label: 'Selection',
                        value: '${shortlisted + reviewed}',
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('all', 'Tout', isDark, card, text, sub, divider, accent),
                  const SizedBox(width: 8),
                  _chip('submitted', 'Envoyees', isDark, card, text, sub, divider, accent),
                  const SizedBox(width: 8),
                  _chip('reviewed', 'Vues', isDark, card, text, sub, divider, accent),
                  const SizedBox(width: 8),
                  _chip('shortlisted', 'Selection', isDark, card, text, sub, divider, accent),
                  const SizedBox(width: 8),
                  _chip('accepted', 'Acceptees', isDark, card, text, sub, divider, accent),
                  const SizedBox(width: 8),
                  _chip('rejected', 'Refusees', isDark, card, text, sub, divider, accent),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text(_friendlyFirestoreError(snap.error), style: TextStyle(color: sub)));
                final docs = (snap.data?.docs ?? const []).toList();

                if (_filter != 'all') {
                  docs.removeWhere((d) => (d.data()['statusKey'] ?? '').toString().trim() != _filter);
                }

                // newest first
                docs.sort((a, b) {
                  final da = _dateFrom(a.data(), 'createdAt', 'createdAtMs') ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final db = _dateFrom(b.data(), 'createdAt', 'createdAtMs') ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return db.compareTo(da);
                });
                if (docs.isEmpty) {
                  return Center(child: Text('Aucune candidature', style: TextStyle(color: sub, fontWeight: FontWeight.w700)));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final title = (d['jobTitle'] ?? '').toString().trim();
                    final company = (d['company'] ?? '').toString().trim();
                    final statusKey = (d['statusKey'] ?? '').toString().trim();
                    final when = _when(_dateFrom(d, 'updatedAt', 'updatedAtMs') ?? _dateFrom(d, 'createdAt', 'createdAtMs'));
                    final cvUrl = (d['cvUrl'] ?? '').toString();
                    final letterUrl = (d['coverLetterPdfUrl'] ?? '').toString();
                    final coverLetter = (d['coverLetter'] ?? '').toString().trim();

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
                                  title.isEmpty ? 'Offre' : title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 15.5, letterSpacing: -0.2),
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
                            ],
                          ),
                          if (company.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(company, style: TextStyle(color: sub, fontWeight: FontWeight.w800)),
                          ],
                          if (when.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('Mis a jour: $when', style: TextStyle(color: sub, fontWeight: FontWeight.w700, fontSize: 12)),
                          ],
                          if (coverLetter.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              coverLetter,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: cvUrl.trim().isEmpty ? null : () => _launchOrSnack(Uri.parse(cvUrl.trim())),
                                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                                  label: const Text('CV'),
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
                                  onPressed: letterUrl.trim().isEmpty ? null : () => _launchOrSnack(Uri.parse(letterUrl.trim())),
                                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                                  label: const Text('Lettre'),
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
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String key,
    String label,
    bool isDark,
    Color card,
    Color text,
    Color sub,
    Color divider,
    Color accent,
  ) {
    final selected = _filter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: accent.withOpacity(isDark ? 0.35 : 0.18),
      backgroundColor: card,
      side: BorderSide(color: divider),
      labelStyle: TextStyle(color: selected ? text : sub, fontWeight: FontWeight.w700),
      onSelected: (_) => setState(() => _filter = key),
    );
  }
}

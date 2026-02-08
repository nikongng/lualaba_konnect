import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CarBookingRequestsPage extends StatefulWidget {
  const CarBookingRequestsPage({super.key});

  @override
  State<CarBookingRequestsPage> createState() => _CarBookingRequestsPageState();
}

class _CarBookingRequestsPageState extends State<CarBookingRequestsPage> {
  static const Color _accent = Color(0xFFFB8C00);
  String _filter = 'all';
  final Map<String, bool> _notifyDisabledCache = {};

  DateTime? _dateFrom(dynamic v) => v is Timestamp ? v.toDate() : null;
  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  bool _rangesOverlap(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    final aS = DateTime(aStart.year, aStart.month, aStart.day);
    final aE = DateTime(aEnd.year, aEnd.month, aEnd.day);
    final bS = DateTime(bStart.year, bStart.month, bStart.day);
    final bE = DateTime(bEnd.year, bEnd.month, bEnd.day);
    return !(aE.isBefore(bS) || bE.isBefore(aS));
  }

  Future<bool> _notificationsEnabledForUser(String uid) async {
    if (uid.isEmpty) return false;
    final cached = _notifyDisabledCache[uid];
    if (cached != null) return cached != true;
    try {
      final snap = await FirebaseFirestore.instance.collection('notification_settings').doc(uid).get();
      final data = snap.data() ?? <String, dynamic>{};
      final disabled = data['disabled'] == true || data['disabled'] == 1 || data['disabled'] == '1' || data['disabled'] == 'true';
      _notifyDisabledCache[uid] = disabled;
      return !disabled;
    } catch (_) {
      return true;
    }
  }

  String _firstName(String nameOrEmail) {
    final s = nameOrEmail.trim();
    if (s.isEmpty) return 'Utilisateur';
    final x = s.contains('@') ? s.split('@').first : s;
    final parts = x.split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.first : x;
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'accepted':
        return const Color(0xFF00CBA9);
      case 'rejected':
        return Colors.redAccent;
      case 'cancelled':
        return const Color(0xFF94A3B8);
      case 'pending':
      default:
        return _accent;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'accepted':
        return 'Acceptée';
      case 'rejected':
        return 'Refusée';
      case 'cancelled':
        return 'Annulée';
      case 'pending':
      default:
        return 'En attente';
    }
  }

  Future<bool> _canAccept(String rentalId, DateTime start, DateTime end, String currentBookingId) async {
    // Manual availability blocks
    try {
      final blocks = await FirebaseFirestore.instance.collection('car_availability_blocks').where('rentalId', isEqualTo: rentalId).get();
      for (final d in blocks.docs) {
        final data = d.data();
        final active = data['active'] != false;
        if (!active) continue;
        final s = data['startDate'];
        final e = data['endDate'];
        if (s is! Timestamp || e is! Timestamp) continue;
        if (_rangesOverlap(start, end, s.toDate(), e.toDate())) return false;
      }
    } catch (_) {}

    final snap = await FirebaseFirestore.instance
        .collection('car_bookings')
        .where('rentalId', isEqualTo: rentalId)
        .where('status', isEqualTo: 'accepted')
        .get();

    for (final d in snap.docs) {
      if (d.id == currentBookingId) continue;
      final data = d.data();
      final s = data['startDate'];
      final e = data['endDate'];
      if (s is! Timestamp || e is! Timestamp) continue;
      if (_rangesOverlap(start, end, s.toDate(), e.toDate())) return false;
    }
    return true;
  }

  Future<void> _notifyRenterUpdate({
    required String renterUid,
    required String bookingId,
    required String rentalId,
    required String rentalName,
    required String status,
    required DateTime? start,
    required DateTime? end,
  }) async {
    if (renterUid.isEmpty) return;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    if (me.uid == renterUid) return;
    if (!await _notificationsEnabledForUser(renterUid)) return;

    final when = (start != null && end != null) ? ' (${_fmt(start)} → ${_fmt(end)})' : '';
    final text = status == 'accepted'
        ? 'Votre reservation pour $rentalName$when a été acceptée.'
        : status == 'rejected'
            ? 'Votre reservation pour $rentalName$when a été refusée.'
            : 'Mise à jour reservation: $rentalName$when';

    await FirebaseFirestore.instance.collection('notifications').add({
      'type': 'car_booking_update',
      'toUserId': renterUid,
      'fromUserId': me.uid,
      'fromName': _firstName(me.displayName ?? me.email ?? ''),
      'fromAvatar': (me.photoURL ?? '').toString(),
      'text': text,
      'bookingId': bookingId,
      'rentalId': rentalId,
      'rentalName': rentalName,
      'startDate': start == null ? null : Timestamp.fromDate(start),
      'endDate': end == null ? null : Timestamp.fromDate(end),
      'status': status,
      'seen': false,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _setStatus({
    required DocumentReference ref,
    required Map<String, dynamic> data,
    required String status,
  }) async {
    final rentalId = (data['rentalId'] ?? '').toString();
    final rentalName = (data['rentalName'] ?? 'Voiture').toString();
    final renterUid = (data['createdByUid'] ?? '').toString();
    final start = _dateFrom(data['startDate']);
    final end = _dateFrom(data['endDate']);

    if (status == 'accepted' && (start != null && end != null) && rentalId.isNotEmpty) {
      final ok = await _canAccept(rentalId, start, end, ref.id);
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conflit: ces dates sont déjà réservées.')));
        return;
      }
    }

    await ref.update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      if (status == 'accepted') ...{
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedAtMs': DateTime.now().millisecondsSinceEpoch,
      },
      if (status == 'rejected') ...{
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedAtMs': DateTime.now().millisecondsSinceEpoch,
      },
    });

    try {
      await _notifyRenterUpdate(
        renterUid: renterUid,
        bookingId: ref.id,
        rentalId: rentalId,
        rentalName: rentalName,
        status: status,
        start: start,
        end: end,
      );
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == 'accepted' ? 'Reservation acceptée.' : 'Reservation refusée.')));
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);

    if (me == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, foregroundColor: text, elevation: 0, title: const Text('Demandes')),
        body: Center(child: Text('Veuillez vous connecter.', style: TextStyle(color: sub, fontWeight: FontWeight.w700))),
      );
    }

    Query q = FirebaseFirestore.instance.collection('car_bookings').where('ownerUid', isEqualTo: me.uid);
    if (_filter != 'all') q = q.where('status', isEqualTo: _filter);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        title: const Text('Demandes', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                _FilterChip(
                  label: 'Tout',
                  selected: _filter == 'all',
                  isDark: isDark,
                  onTap: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'En attente',
                  selected: _filter == 'pending',
                  isDark: isDark,
                  onTap: () => setState(() => _filter = 'pending'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Acceptées',
                  selected: _filter == 'accepted',
                  isDark: isDark,
                  onTap: () => setState(() => _filter = 'accepted'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Refusées',
                  selected: _filter == 'rejected',
                  isDark: isDark,
                  onTap: () => setState(() => _filter = 'rejected'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Erreur: ${snap.error}', style: TextStyle(color: sub)));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = (snap.data?.docs ?? const <QueryDocumentSnapshot>[]).toList()
                  ..sort((a, b) {
                    int ms(QueryDocumentSnapshot d) {
                      final data = d.data() as Map<String, dynamic>? ?? const {};
                      final m = data['createdAtMs'];
                      if (m is int) return m;
                      if (m is num) return m.toInt();
                      final ts = data['createdAt'];
                      if (ts is Timestamp) return ts.millisecondsSinceEpoch;
                      return 0;
                    }

                    return ms(b).compareTo(ms(a));
                  });

                if (docs.isEmpty) {
                  return Center(child: Text('Aucune demande', style: TextStyle(color: sub, fontWeight: FontWeight.w700)));
                }

                return ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final status = (data['status'] ?? 'pending').toString();
                    final rentalName = (data['rentalName'] ?? 'Voiture').toString();
                    final renterName = _firstName((data['createdByName'] ?? data['createdByEmail'] ?? '').toString());
                    final start = _dateFrom(data['startDate']);
                    final end = _dateFrom(data['endDate']);
                    final msg = (data['message'] ?? '').toString().trim();

                    final chipColor = _statusColor(status);
                    final chipLabel = _statusLabel(status);

                    final canAct = status == 'pending';

                    Widget tile = Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.35 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  rentalName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 15.5),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: chipColor.withOpacity(isDark ? 0.28 : 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: chipColor.withOpacity(0.35)),
                                ),
                                child: Text(chipLabel, style: TextStyle(color: chipColor, fontWeight: FontWeight.w900, fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.person_outline_rounded, size: 16, color: sub),
                              const SizedBox(width: 6),
                              Expanded(child: Text(renterName, style: TextStyle(color: sub, fontWeight: FontWeight.w700))),
                            ],
                          ),
                          if (start != null && end != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.date_range_rounded, size: 16, color: sub),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text('${_fmt(start)} → ${_fmt(end)}', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ],
                          if (msg.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(msg, style: TextStyle(color: sub, fontWeight: FontWeight.w600, height: 1.25)),
                          ],
                          const SizedBox(height: 12),
                          if (canAct)
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 46,
                                    child: ElevatedButton(
                                      onPressed: () => _setStatus(ref: doc.reference, data: data, status: 'rejected'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.redAccent.withOpacity(isDark ? 0.85 : 0.90),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      child: const Text('Refuser', style: TextStyle(fontWeight: FontWeight.w900)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SizedBox(
                                    height: 46,
                                    child: ElevatedButton(
                                      onPressed: () => _setStatus(ref: doc.reference, data: data, status: 'accepted'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00CBA9).withOpacity(isDark ? 0.86 : 0.92),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      child: const Text('Accepter', style: TextStyle(fontWeight: FontWeight.w900)),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Statut: $chipLabel', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
                    );

                    tile = TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 420 + (i.clamp(0, 10) * 30)),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child)),
                      child: tile,
                    );

                    return tile;
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.isDark, required this.onTap});

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFB8C00);
    final bg = selected ? accent.withOpacity(isDark ? 0.30 : 0.18) : (isDark ? const Color(0xFF111B21) : Colors.white);
    final fg = selected ? (isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827)) : (isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280));
    final border = selected ? accent.withOpacity(0.45) : (isDark ? Colors.white12 : Colors.black12);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: border)),
        child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12)),
      ),
    );
  }
}

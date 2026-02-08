import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MyCarBookingsPage extends StatefulWidget {
  const MyCarBookingsPage({super.key});

  @override
  State<MyCarBookingsPage> createState() => _MyCarBookingsPageState();
}

class _MyCarBookingsPageState extends State<MyCarBookingsPage> {
  static const Color _accent = Color(0xFFFB8C00);
  final Map<String, bool> _notifyDisabledCache = {};

  DateTime? _dateFrom(dynamic v) => v is Timestamp ? v.toDate() : null;

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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

  String _safeDisplayName(User? u) {
    final name = (u?.displayName ?? '').trim();
    if (name.isNotEmpty && !name.contains('@')) return name;
    final email = (u?.email ?? '').trim();
    if (email.isNotEmpty && email.contains('@')) return email.split('@').first;
    return 'Utilisateur';
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

  Future<void> _notifyOwnerCancelled({
    required String ownerUid,
    required String bookingId,
    required String rentalId,
    required String rentalName,
    required DateTime? start,
    required DateTime? end,
  }) async {
    if (ownerUid.isEmpty) return;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    if (me.uid == ownerUid) return;
    if (!await _notificationsEnabledForUser(ownerUid)) return;

    final fromName = _safeDisplayName(me);
    final fromAvatar = (me.photoURL ?? '').toString();
    final when = (start != null && end != null) ? ' (${_fmt(start)} → ${_fmt(end)})' : '';

    await FirebaseFirestore.instance.collection('notifications').add({
      'type': 'car_booking_cancelled',
      'toUserId': ownerUid,
      'fromUserId': me.uid,
      'fromName': fromName,
      'fromAvatar': fromAvatar,
      'text': '$fromName a annulé une reservation pour $rentalName$when',
      'bookingId': bookingId,
      'rentalId': rentalId,
      'rentalName': rentalName,
      'startDate': start == null ? null : Timestamp.fromDate(start),
      'endDate': end == null ? null : Timestamp.fromDate(end),
      'seen': false,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _cancelBooking(DocumentReference ref, Map<String, dynamic> data) async {
    final status = (data['status'] ?? 'pending').toString();
    if (status != 'pending' && status != 'accepted') return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF111B21) : Colors.white;
        final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
        final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
        return AlertDialog(
          backgroundColor: bg,
          title: Text('Annuler la reservation ?', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
          content: Text('Le proprietaire sera notifie.', style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, annuler')),
          ],
        );
      },
    );
    if (ok != true) return;

    final ownerUid = (data['ownerUid'] ?? '').toString();
    final rentalId = (data['rentalId'] ?? '').toString();
    final rentalName = (data['rentalName'] ?? '').toString();
    final start = _dateFrom(data['startDate']);
    final end = _dateFrom(data['endDate']);

    await ref.update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledAtMs': DateTime.now().millisecondsSinceEpoch,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    });

    try {
      await _notifyOwnerCancelled(
        ownerUid: ownerUid,
        bookingId: ref.id,
        rentalId: rentalId,
        rentalName: rentalName,
        start: start,
        end: end,
      );
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reservation annulée.')));
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
        appBar: AppBar(backgroundColor: bg, foregroundColor: text, elevation: 0, title: const Text('Mes reservations')),
        body: Center(child: Text('Veuillez vous connecter.', style: TextStyle(color: sub, fontWeight: FontWeight.w700))),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('car_bookings')
        .where('createdByUid', isEqualTo: me.uid)
        .snapshots();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        title: const Text('Mes reservations', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
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
            return Center(child: Text('Aucune reservation', style: TextStyle(color: sub, fontWeight: FontWeight.w700)));
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
              final start = _dateFrom(data['startDate']);
              final end = _dateFrom(data['endDate']);
              final msg = (data['message'] ?? '').toString().trim();

              final chipColor = _statusColor(status);
              final chipLabel = _statusLabel(status);

              Widget tile = Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {},
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(isDark ? 0.35 : 0.06), blurRadius: 18, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: chipColor.withOpacity(isDark ? 0.25 : 0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: chipColor.withOpacity(0.35)),
                          ),
                          child: Icon(Icons.directions_car_rounded, color: chipColor),
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
                                  const SizedBox(width: 6),
                                  InkResponse(
                                    radius: 22,
                                    onTap: () => _cancelBooking(doc.reference, data),
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Icon(
                                        (status == 'pending' || status == 'accepted') ? Icons.cancel_outlined : Icons.more_horiz_rounded,
                                        size: 20,
                                        color: sub,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (start != null && end != null)
                                Row(
                                  children: [
                                    Icon(Icons.date_range_rounded, size: 16, color: sub),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${_fmt(start)} → ${_fmt(end)}',
                                        style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              if (msg.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  msg,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: sub, fontWeight: FontWeight.w600, height: 1.25),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
    );
  }
}


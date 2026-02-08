import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CarRentalCalendarPage extends StatefulWidget {
  const CarRentalCalendarPage({
    super.key,
    required this.rentalId,
    required this.rentalName,
  });

  final String rentalId;
  final String rentalName;

  @override
  State<CarRentalCalendarPage> createState() => _CarRentalCalendarPageState();
}

class _CarRentalCalendarPageState extends State<CarRentalCalendarPage> {
  static const Color _accent = Color(0xFFFB8C00);

  DateTime? _dateFrom(dynamic v) => v is Timestamp ? v.toDate() : null;

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  bool _rangesOverlap(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    final aS = DateTime(aStart.year, aStart.month, aStart.day);
    final aE = DateTime(aEnd.year, aEnd.month, aEnd.day);
    final bS = DateTime(bStart.year, bStart.month, bStart.day);
    final bE = DateTime(bEnd.year, bEnd.month, bEnd.day);
    return !(aE.isBefore(bS) || bE.isBefore(aS));
  }

  Future<bool> _overlapsAcceptedBookings(DateTimeRange range) async {
    final snap = await FirebaseFirestore.instance
        .collection('car_bookings')
        .where('rentalId', isEqualTo: widget.rentalId)
        .where('status', isEqualTo: 'accepted')
        .get();
    for (final d in snap.docs) {
      final data = d.data();
      final s = data['startDate'];
      final e = data['endDate'];
      if (s is! Timestamp || e is! Timestamp) continue;
      if (_rangesOverlap(range.start, range.end, s.toDate(), e.toDate())) return true;
    }
    return false;
  }

  Future<void> _addBlock() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      helpText: 'Bloquer des dates',
      confirmText: 'Continuer',
      saveText: 'OK',
    );
    if (range == null) return;

    final overlaps = await _overlapsAcceptedBookings(range);
    if (overlaps) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible: ces dates ont déjà une réservation acceptée.')));
      return;
    }

    final reasonCtrl = TextEditingController();
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF111B21) : Colors.white;
        final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
        final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);

        return SafeArea(
          top: false,
          child: StatefulBuilder(builder: (context, setModal) {
            Future<void> submit() async {
              if (saving) return;
              setModal(() => saving = true);
              try {
                await FirebaseFirestore.instance.collection('car_availability_blocks').add({
                  'rentalId': widget.rentalId,
                  'rentalName': widget.rentalName,
                  'ownerUid': me.uid,
                  'startDate': Timestamp.fromDate(range.start),
                  'endDate': Timestamp.fromDate(range.end),
                  'reason': reasonCtrl.text.trim(),
                  'active': true,
                  'createdAt': FieldValue.serverTimestamp(),
                  'createdAtMs': DateTime.now().millisecondsSinceEpoch,
                });
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dates bloquées.')));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                setModal(() => saving = false);
              }
            }

            return Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 4,
                    margin: const EdgeInsets.only(top: 6, bottom: 10),
                    decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(99)),
                  ),
                  Row(
                    children: [
                      Expanded(child: Text('Bloquer', style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5))),
                      IconButton(onPressed: saving ? null : () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${_fmt(range.start)}  →  ${_fmt(range.end)}', style: TextStyle(color: sub, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    style: TextStyle(color: text, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: 'Raison (optionnel)',
                      hintStyle: TextStyle(color: sub),
                      filled: true,
                      fillColor: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: saving ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: saving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                          : const Text('Confirmer', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );

    reasonCtrl.dispose();
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
        appBar: AppBar(backgroundColor: bg, foregroundColor: text, elevation: 0, title: const Text('Calendrier')),
        body: Center(child: Text('Veuillez vous connecter.', style: TextStyle(color: sub, fontWeight: FontWeight.w700))),
      );
    }

    final blocksQ = FirebaseFirestore.instance
        .collection('car_availability_blocks')
        .where('rentalId', isEqualTo: widget.rentalId)
        .where('ownerUid', isEqualTo: me.uid)
        .snapshots();

    final bookingsQ = FirebaseFirestore.instance
        .collection('car_bookings')
        .where('rentalId', isEqualTo: widget.rentalId)
        .where('status', isEqualTo: 'accepted')
        .snapshots();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        title: Text(widget.rentalName, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Bloquer des dates',
            onPressed: _addBlock,
            icon: const Icon(Icons.block_rounded),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SectionTitle(title: 'Bloquages', icon: Icons.event_busy_rounded, text: text, sub: sub),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: blocksQ,
            builder: (context, snap) {
              if (snap.hasError) return Text('Erreur: ${snap.error}', style: TextStyle(color: sub));
              if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));

              final docs = (snap.data?.docs ?? const <QueryDocumentSnapshot>[]).toList()
                ..sort((a, b) {
                  int ms(QueryDocumentSnapshot d) {
                    final data = d.data() as Map<String, dynamic>? ?? const {};
                    final s = data['startDate'];
                    if (s is Timestamp) return s.millisecondsSinceEpoch;
                    final m = data['createdAtMs'];
                    if (m is int) return m;
                    if (m is num) return m.toInt();
                    return 0;
                  }

                  return ms(a).compareTo(ms(b));
                });

              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text('Aucun blocage', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                );
              }

              return Column(
                children: [
                  for (final d in docs)
                    _BlockTile(
                      card: card,
                      isDark: isDark,
                      text: text,
                      sub: sub,
                      data: d.data() as Map<String, dynamic>? ?? const {},
                      onDelete: () async {
                        await d.reference.delete();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Blocage supprimé.')));
                      },
                      fmt: _fmt,
                      dateFrom: _dateFrom,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _SectionTitle(title: 'Réservations acceptées', icon: Icons.verified_rounded, text: text, sub: sub),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: bookingsQ,
            builder: (context, snap) {
              if (snap.hasError) return Text('Erreur: ${snap.error}', style: TextStyle(color: sub));
              if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));

              final docs = (snap.data?.docs ?? const <QueryDocumentSnapshot>[]).toList()
                ..sort((a, b) {
                  int ms(QueryDocumentSnapshot d) {
                    final data = d.data() as Map<String, dynamic>? ?? const {};
                    final s = data['startDate'];
                    if (s is Timestamp) return s.millisecondsSinceEpoch;
                    final m = data['createdAtMs'];
                    if (m is int) return m;
                    if (m is num) return m.toInt();
                    return 0;
                  }

                  return ms(a).compareTo(ms(b));
                });

              if (docs.isEmpty) {
                return Text('Aucune réservation acceptée', style: TextStyle(color: sub, fontWeight: FontWeight.w700));
              }

              return Column(
                children: [
                  for (final d in docs)
                    _BookingTile(
                      card: card,
                      isDark: isDark,
                      text: text,
                      sub: sub,
                      data: d.data() as Map<String, dynamic>? ?? const {},
                      fmt: _fmt,
                      dateFrom: _dateFrom,
                    ),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        onPressed: _addBlock,
        icon: const Icon(Icons.add),
        label: const Text('Bloquer', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon, required this.text, required this.sub});

  final String title;
  final IconData icon;
  final Color text;
  final Color sub;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: sub),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 15.5)),
      ],
    );
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({
    required this.card,
    required this.isDark,
    required this.text,
    required this.sub,
    required this.data,
    required this.onDelete,
    required this.fmt,
    required this.dateFrom,
  });

  final Color card;
  final bool isDark;
  final Color text;
  final Color sub;
  final Map<String, dynamic> data;
  final VoidCallback onDelete;
  final String Function(DateTime) fmt;
  final DateTime? Function(dynamic) dateFrom;

  @override
  Widget build(BuildContext context) {
    final start = dateFrom(data['startDate']);
    final end = dateFrom(data['endDate']);
    final reason = (data['reason'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.35 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(isDark ? 0.25 : 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
            ),
            child: const Icon(Icons.event_busy_rounded, color: Colors.redAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (start != null && end != null) ? '${fmt(start)} → ${fmt(end)}' : 'Dates',
                  style: TextStyle(color: text, fontWeight: FontWeight.w900),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(reason, style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Supprimer',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({
    required this.card,
    required this.isDark,
    required this.text,
    required this.sub,
    required this.data,
    required this.fmt,
    required this.dateFrom,
  });

  final Color card;
  final bool isDark;
  final Color text;
  final Color sub;
  final Map<String, dynamic> data;
  final String Function(DateTime) fmt;
  final DateTime? Function(dynamic) dateFrom;

  @override
  Widget build(BuildContext context) {
    final start = dateFrom(data['startDate']);
    final end = dateFrom(data['endDate']);
    final renter = (data['createdByName'] ?? data['createdByEmail'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.35 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF00CBA9).withOpacity(isDark ? 0.25 : 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF00CBA9).withOpacity(0.35)),
            ),
            child: const Icon(Icons.verified_rounded, color: Color(0xFF00CBA9)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (start != null && end != null) ? '${fmt(start)} → ${fmt(end)}' : 'Dates',
                  style: TextStyle(color: text, fontWeight: FontWeight.w900),
                ),
                if (renter.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(renter, style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}


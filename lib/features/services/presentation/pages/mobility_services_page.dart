import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:url_launcher/url_launcher.dart';

import 'package:lualaba_konnect/features/services/presentation/pages/my_car_rentals_page.dart';
import 'package:lualaba_konnect/features/services/presentation/pages/my_car_bookings_page.dart';
import 'package:lualaba_konnect/features/services/presentation/pages/car_booking_requests_page.dart';

class MobilityServicesPage extends StatefulWidget {
  const MobilityServicesPage({super.key, this.initialFilterKey = 'all'});

  final String initialFilterKey;

  @override
  State<MobilityServicesPage> createState() => _MobilityServicesPageState();
}

class _MobilityServicesPageState extends State<MobilityServicesPage> {
  static const Color _accent = Color(0xFFFB8C00);
  static const Color _ctaBlue = Color(0xFF2D6BFF);

  late String _filterKey = widget.initialFilterKey;
  final TextEditingController _qCtrl = TextEditingController();
  final Map<String, bool> _notifyDisabledCache = {};

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  bool _asBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true' || v == 'True';

  List<String> _asTags(dynamic v) {
    if (v is List) return List<String>.from(v.map((e) => e.toString()));
    return const [];
  }

  Query _query() {
    Query q = FirebaseFirestore.instance.collection('car_rentals');
    if (_filterKey != 'all') q = q.where('tags', arrayContains: _filterKey);
    return q;
  }

  _CarRental _fromDoc(QueryDocumentSnapshot<Object?> doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return _CarRental(
      id: doc.id,
      name: (d['name'] ?? d['title'] ?? d['model'] ?? 'Voiture').toString(),
      cityLabel: (d['cityLabel'] ?? d['city'] ?? '').toString(),
      priceLabel: (d['priceLabel'] ?? d['price'] ?? d['pricePerDay'] ?? '').toString(),
      coverUrl: (d['coverUrl'] ?? d['imageUrl'] ?? d['photoUrl'] ?? '').toString(),
      phone: (d['phone'] ?? d['phoneNumber'] ?? '').toString(),
      email: (d['email'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      certified: _asBool(d['certified'] ?? d['isCertified']),
      active: _asBool(d['active'] ?? d['isActive'] ?? true),
      tags: _asTags(d['tags']),
      ownerUid: (d['createdByUid'] ?? d['ownerUid'] ?? '').toString(),
      ownerEmail: (d['createdByEmail'] ?? d['ownerEmail'] ?? '').toString(),
      ownerName: (d['createdByName'] ?? d['ownerName'] ?? '').toString(),
    );
  }

  bool _matchesQuery(_CarRental p, String q) {
    final x = q.trim().toLowerCase();
    if (x.isEmpty) return true;
    final hay = [p.name, p.cityLabel, p.description, p.tags.join(' ')].join(' ').toLowerCase();
    return hay.contains(x);
  }

  String _appendUrlVersion(String url, int v) => url.contains('?') ? '$url&v=$v' : '$url?v=$v';

  Future<String> _uploadCover(Uint8List bytes) async {
    // Reuse bucket `market` (already used by marketplace/food).
    final client = Supabase.instance.client;
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = 'car_rentals/$now.jpg';
    await client.storage.from('market').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    final publicUrl = client.storage.from('market').getPublicUrl(path);
    return _appendUrlVersion(publicUrl, now);
  }

  Future<void> _launchOrSnack(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir.")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  bool _rangesOverlap(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    final aS = DateTime(aStart.year, aStart.month, aStart.day);
    final aE = DateTime(aEnd.year, aEnd.month, aEnd.day);
    final bS = DateTime(bStart.year, bStart.month, bStart.day);
    final bE = DateTime(bEnd.year, bEnd.month, bEnd.day);
    return !(aE.isBefore(bS) || bE.isBefore(aS));
  }

  Future<bool> _isRangeAvailable(String rentalId, DateTimeRange range) async {
    try {
      // Availability blocks (manual)
      try {
        final blocks = await FirebaseFirestore.instance
            .collection('car_availability_blocks')
            .where('rentalId', isEqualTo: rentalId)
            .get();
        for (final d in blocks.docs) {
          final data = d.data();
          final active = data['active'] != false;
          if (!active) continue;
          final s = data['startDate'];
          final e = data['endDate'];
          if (s is! Timestamp || e is! Timestamp) continue;
          if (_rangesOverlap(range.start, range.end, s.toDate(), e.toDate())) return false;
        }
      } catch (_) {
        // ignore
      }

      final snap = await FirebaseFirestore.instance
          .collection('car_bookings')
          .where('rentalId', isEqualTo: rentalId)
          .where('status', isEqualTo: 'accepted')
          .get();

      for (final d in snap.docs) {
        final data = d.data();
        final s = data['startDate'];
        final e = data['endDate'];
        if (s is! Timestamp || e is! Timestamp) continue;
        if (_rangesOverlap(range.start, range.end, s.toDate(), e.toDate())) return false;
      }
      return true;
    } catch (_) {
      // Fail-open: if we can't read availability, don't block the booking.
      return true;
    }
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
      // Fail-open: if settings cannot be read, keep notifications enabled.
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

  Future<void> _notifyOwnerBooking({
    required _CarRental rental,
    required String bookingId,
    required DateTimeRange range,
    required String message,
  }) async {
    final ownerUid = rental.ownerUid.trim();
    if (ownerUid.isEmpty) return;

    final me = FirebaseAuth.instance.currentUser;
    if (me != null && ownerUid == me.uid) return; // don't notify self

    final enabled = await _notificationsEnabledForUser(ownerUid);
    if (!enabled) return;

    final fromName = _safeDisplayName(me);
    final fromAvatar = (me?.photoURL ?? '').toString();
    final text = '$fromName a demande une reservation pour ${rental.name} (${_fmt(range.start)} → ${_fmt(range.end)})';

    await FirebaseFirestore.instance.collection('notifications').add({
      'type': 'car_booking',
      'toUserId': ownerUid,
      'fromUserId': me?.uid,
      'fromName': fromName,
      'fromAvatar': fromAvatar,
      'text': text,
      'rentalId': rental.id,
      'rentalName': rental.name,
      'bookingId': bookingId,
      'startDate': Timestamp.fromDate(range.start),
      'endDate': Timestamp.fromDate(range.end),
      'message': message,
      'seen': false,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _showContactSheet(_CarRental p) {
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
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 46, height: 4, margin: const EdgeInsets.only(top: 6, bottom: 10), decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(99))),
                Row(
                  children: [
                    Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5))),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                  ],
                ),
                if (p.phone.trim().isEmpty && p.email.trim().isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Text('Aucun contact disponible.', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                  ),
                if (p.phone.trim().isNotEmpty)
                  ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchOrSnack(Uri.parse('tel:${p.phone.trim()}'));
                    },
                    leading: const Icon(Icons.call_rounded, color: _ctaBlue),
                    title: Text('Appeler', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                    subtitle: Text(p.phone.trim(), style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                  ),
                if (p.email.trim().isNotEmpty)
                  ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchOrSnack(Uri.parse('mailto:${p.email.trim()}'));
                    },
                    leading: const Icon(Icons.email_rounded, color: _accent),
                    title: Text('Envoyer un email', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                    subtitle: Text(p.email.trim(), style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _reserve(_CarRental p) async {
    if (!p.active) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cette voiture est indisponible pour le moment.')));
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      helpText: 'Choisir les dates',
      confirmText: 'Continuer',
      saveText: 'OK',
    );
    if (range == null) return;

    final available = await _isRangeAvailable(p.id, range);
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ces dates ne sont pas disponibles.')));
      return;
    }

    final msgCtrl = TextEditingController();
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
                final me = FirebaseAuth.instance.currentUser;
                final bookingRef = await FirebaseFirestore.instance.collection('car_bookings').add({
                  'rentalId': p.id,
                  'rentalName': p.name,
                  'startDate': Timestamp.fromDate(range.start),
                  'endDate': Timestamp.fromDate(range.end),
                  'message': msgCtrl.text.trim(),
                  'status': 'pending',
                  'createdAt': FieldValue.serverTimestamp(),
                  'createdAtMs': DateTime.now().millisecondsSinceEpoch,
                  'createdByUid': me?.uid,
                  'createdByEmail': me?.email,
                  'createdByName': me?.displayName,
                  'ownerUid': p.ownerUid.isEmpty ? null : p.ownerUid,
                  'ownerEmail': p.ownerEmail.isEmpty ? null : p.ownerEmail,
                  'ownerName': p.ownerName.isEmpty ? null : p.ownerName,
                });

                try {
                  await _notifyOwnerBooking(
                    rental: p,
                    bookingId: bookingRef.id,
                    range: range,
                    message: msgCtrl.text.trim(),
                  );
                } catch (_) {
                  // Notification failure should not block the booking.
                }
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demande envoyee.')));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur reservation: $e')));
                setModal(() => saving = false);
              }
            }

            return Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22), border: Border.all(color: isDark ? Colors.white12 : Colors.black12)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 46, height: 4, margin: const EdgeInsets.only(top: 6, bottom: 10), decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(99))),
                  Row(
                    children: [
                      Expanded(child: Text('Reserver', style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5))),
                      IconButton(onPressed: saving ? null : () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                    ],
                  ),
                  Align(alignment: Alignment.centerLeft, child: Text('${_fmt(range.start)}  →  ${_fmt(range.end)}', style: TextStyle(color: sub, fontWeight: FontWeight.w800))),
                  const SizedBox(height: 12),
                  TextField(
                    controller: msgCtrl,
                    maxLines: 3,
                    style: TextStyle(color: text, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: 'Message (optionnel)',
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
                      style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                      child: saving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                          : const Text('Envoyer la demande', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );

    msgCtrl.dispose();
  }

  Future<void> _openAddCarSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final nameCtrl = TextEditingController();
    final cityCtrl = TextEditingController(text: 'Kolwezi, Centre');
    final priceCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final picker = ImagePicker();
    Uint8List? coverBytes;

    const tagOptions = <(String, String)>[
      ('berline', 'Berline'),
      ('suv', 'SUV'),
      ('4x4', '4x4'),
      ('pickup', 'Pickup'),
      ('van_bus', 'Van/Bus'),
      ('lux', 'Lux'),
    ];
    final selectedTags = <String>{'berline'};

    final formKey = GlobalKey<FormState>();
    bool saving = false;

    Future<void> submit(StateSetter setModal) async {
      if (saving) return;
      if (!(formKey.currentState?.validate() ?? false)) return;
      if (coverBytes == null || coverBytes!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajoute une photo.')));
        return;
      }
      setModal(() => saving = true);
      try {
        final me = FirebaseAuth.instance.currentUser;
        final coverUrl = await _uploadCover(coverBytes!);
        await FirebaseFirestore.instance.collection('car_rentals').add({
          'name': nameCtrl.text.trim(),
          'cityLabel': cityCtrl.text.trim(),
          'priceLabel': priceCtrl.text.trim(),
          'coverUrl': coverUrl,
          'phone': phoneCtrl.text.trim(),
          'email': emailCtrl.text.trim(),
          'description': descCtrl.text.trim(),
          'tags': selectedTags.toList(),
          'createdByUid': me?.uid,
          'createdByEmail': me?.email,
          'createdByName': me?.displayName,
          'certified': false,
          'isCertified': false,
          'certifiedAt': null,
          'active': true,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        });
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voiture ajoutee.')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur ajout: $e')));
        setModal(() => saving = false);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: StatefulBuilder(builder: (context, setModal) {
            return DraggableScrollableSheet(
              initialChildSize: 0.92,
              minChildSize: 0.55,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, controller) {
                return Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22), border: Border.all(color: divider)),
                  child: ListView(
                    controller: controller,
                    padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
                    children: [
                      Center(child: Container(width: 46, height: 4, margin: const EdgeInsets.only(top: 6, bottom: 10), decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(99)))),
                      Row(
                        children: [
                          Expanded(child: Text('Ajouter une voiture', style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5))),
                          IconButton(onPressed: saving ? null : () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Form(
                        key: formKey,
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: saving
                                  ? null
                                  : () async {
                                      final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                                      if (x == null) return;
                                      final bytes = await x.readAsBytes();
                                      setModal(() => coverBytes = bytes);
                                    },
                              child: Container(
                                height: 92,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: isDark ? Colors.white10 : const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(18), border: Border.all(color: divider)),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        width: 78,
                                        height: 72,
                                        color: isDark ? Colors.white12 : Colors.black12,
                                        child: coverBytes == null ? const Icon(Icons.add_a_photo_outlined, color: _accent) : Image.memory(coverBytes!, fit: BoxFit.cover),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text('Photo', style: TextStyle(color: text, fontWeight: FontWeight.w900)), const SizedBox(height: 2), Text('Appuyez pour choisir une image', style: TextStyle(color: sub, fontWeight: FontWeight.w700))])),
                                    Icon(Icons.chevron_right_rounded, color: sub),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _Field(label: 'Modele / Titre (ex: Toyota Rav4)', controller: nameCtrl, textColor: text, subColor: sub, divider: divider, validator: (v) => (v == null || v.trim().isEmpty) ? 'Titre requis' : null),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _Field(label: 'Ville', controller: cityCtrl, textColor: text, subColor: sub, divider: divider)),
                                const SizedBox(width: 10),
                                Expanded(child: _Field(label: 'Prix (ex: 50 / jour)', controller: priceCtrl, textColor: text, subColor: sub, divider: divider)),
                              ],
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
                            _Field(label: 'Description', controller: descCtrl, textColor: text, subColor: sub, divider: divider, maxLines: 3),
                            const SizedBox(height: 12),
                            Align(alignment: Alignment.centerLeft, child: Text('Tags', style: TextStyle(color: text, fontWeight: FontWeight.w900))),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final t in tagOptions)
                                    _TagChip(
                                      label: t.$2,
                                      selected: selectedTags.contains(t.$1),
                                      isDark: isDark,
                                      onTap: saving
                                          ? null
                                          : () {
                                              setModal(() {
                                                if (selectedTags.contains(t.$1)) {
                                                  if (selectedTags.length > 1) selectedTags.remove(t.$1);
                                                } else {
                                                  selectedTags.add(t.$1);
                                                }
                                              });
                                            },
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: saving ? null : () => submit(setModal),
                                style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                                child: saving
                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                                    : const Text('Ajouter', style: TextStyle(fontWeight: FontWeight.w900)),
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
          }),
        );
      },
    );

    nameCtrl.dispose();
    cityCtrl.dispose();
    priceCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    descCtrl.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;
    const appBarFg = Colors.white;

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accent,
        onPressed: _openAddCarSheet,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: true,
            snap: true,
            elevation: 0,
            backgroundColor: bg,
            surfaceTintColor: Colors.transparent,
            foregroundColor: appBarFg,
            iconTheme: const IconThemeData(color: appBarFg),
            actionsIconTheme: const IconThemeData(color: appBarFg),
            titleSpacing: 0,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(28))),
            leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: appBarFg)),
            title: const Text('Mobilite', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2, color: appBarFg)),
            actions: [
              IconButton(
                tooltip: 'Demandes',
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CarBookingRequestsPage()));
                },
                icon: const Icon(Icons.inbox_rounded, color: appBarFg),
              ),
              IconButton(
                tooltip: 'Mes reservations',
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCarBookingsPage()));
                },
                icon: const Icon(Icons.event_available_rounded, color: appBarFg),
              ),
              IconButton(
                tooltip: 'Mes annonces',
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MyCarRentalsPage()));
                },
                icon: const Icon(Icons.directions_car_filled_rounded, color: appBarFg),
              ),
            ],
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1F2A33), Color(0xFF0B141A)],
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.white70),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _qCtrl,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          decoration: const InputDecoration(
                            hintText: 'SUV, 4x4, Pickup...',
                            hintStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_qCtrl.text.trim().isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _qCtrl.clear();
                            setState(() {});
                          },
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.close, size: 18, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _MobilityFilterRow(
                isDark: isDark,
                selectedKey: _filterKey,
                onSelected: (k) => setState(() => _filterKey = k),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            sliver: StreamBuilder<QuerySnapshot>(
              stream: _query().limit(80).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _skeleton(isDark),
                        const SizedBox(height: 14),
                        _skeleton(isDark),
                      ],
                    ),
                  );
                }
                if (snap.hasError) {
                  return SliverToBoxAdapter(
                    child: Center(child: Text('Erreur: ${snap.error}', style: TextStyle(color: sub, fontWeight: FontWeight.w700))),
                  );
                }

                final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Object?>>[];
                final q = _qCtrl.text.trim().toLowerCase();
                final items = <_CarRental>[];
                for (final d in docs) {
                  final p = _fromDoc(d);
                  final me = FirebaseAuth.instance.currentUser;
                  final isOwner = me != null && p.ownerUid.isNotEmpty && me.uid == p.ownerUid;
                  if (!p.active && !isOwner) continue;
                  if (!_matchesQuery(p, q)) continue;
                  items.add(p);
                }

                if (items.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 36),
                      child: Center(child: Text('Aucun resultat', style: TextStyle(color: sub, fontWeight: FontWeight.w800))),
                    ),
                  );
                }

                return SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final p = items[i];
                    return _CarCard(
                      rental: p,
                      isDark: isDark,
                      card: card,
                      text: text,
                      sub: sub,
                      divider: divider,
                      onContact: () => _showContactSheet(p),
                      onReserve: () => _reserve(p),
                    );
                  },
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _skeleton(bool isDark) {
    return Container(
      height: 230,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFE9ECEF),
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}

class _MobilityFilterRow extends StatelessWidget {
  const _MobilityFilterRow({required this.isDark, required this.selectedKey, required this.onSelected});

  final bool isDark;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  static const filters = [
    ('all', 'Tout', Icons.grid_view_rounded),
    ('berline', 'Berline', Icons.directions_car_rounded),
    ('suv', 'SUV', Icons.airport_shuttle_rounded),
    ('4x4', '4x4', Icons.terrain_rounded),
    ('pickup', 'Pickup', Icons.local_shipping_rounded),
    ('van_bus', 'Van/Bus', Icons.directions_bus_rounded),
    ('lux', 'Lux', Icons.workspace_premium_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final f = filters[i];
          final selected = selectedKey == f.$1;
          final bg = selected ? (isDark ? const Color(0xFF111B21) : Colors.white) : (isDark ? Colors.white10 : const Color(0xFFF1F3F5));
          final border = selected ? _MobilityServicesPageState._accent.withOpacity(0.35) : (isDark ? Colors.white12 : Colors.black12);
          final fg = selected ? _MobilityServicesPageState._accent : (isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827));

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
      ),
    );
  }
}

class _CarCard extends StatelessWidget {
  const _CarCard({
    required this.rental,
    required this.isDark,
    required this.card,
    required this.text,
    required this.sub,
    required this.divider,
    required this.onContact,
    required this.onReserve,
  });

  final _CarRental rental;
  final bool isDark;
  final Color card;
  final Color text;
  final Color sub;
  final Color divider;
  final VoidCallback onContact;
  final VoidCallback onReserve;

  ({String amount, String suffix}) _splitPrice(String input) {
    final s0 = input.trim();
    if (s0.isEmpty) return (amount: '', suffix: '');
    final s = s0.replaceAll(RegExp(r'\s+'), ' ');
    final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*\$?\s*(.*)$').firstMatch(s);
    if (m != null) {
      final amount0 = (m.group(1) ?? '').trim();
      var rest = (m.group(2) ?? '').trim();
      if (rest.startsWith('/')) rest = '/ ${rest.substring(1).trim()}';
      return (amount: amount0.isEmpty ? '' : '$amount0 \$', suffix: rest);
    }
    return (amount: s, suffix: '');
  }

  String _tagLabel(String key) {
    switch (key) {
      case 'berline':
        return 'Berline';
      case 'suv':
        return 'SUV';
      case '4x4':
        return '4x4';
      case 'pickup':
        return 'Pickup';
      case 'van_bus':
        return 'Van/Bus';
      case 'lux':
        return 'Lux';
      default:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = _splitPrice(rental.priceLabel);
    final hasImg = rental.coverUrl.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.55 : 0.10), blurRadius: 26, offset: const Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 160,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasImg)
                    CachedNetworkImage(imageUrl: rental.coverUrl, fit: BoxFit.cover)
                  else
                    Container(
                      color: isDark ? Colors.white10 : const Color(0xFFE9ECEF),
                      child: const Icon(Icons.directions_car_rounded, size: 54, color: _MobilityServicesPageState._accent),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withOpacity(0.10), Colors.black.withOpacity(0.60)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: rental.certified
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: _MobilityServicesPageState._ctaBlue.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded, size: 18, color: Colors.white),
                                SizedBox(width: 6),
                                Text('Certifie', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Positioned(
                    left: 12,
                    top: 54,
                    child: rental.active
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white.withOpacity(0.20)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.pause_circle_filled_rounded, size: 16, color: Colors.white),
                                SizedBox(width: 6),
                                Text('Indisponible', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11.5)),
                              ],
                            ),
                          ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: price.amount.isEmpty
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _MobilityServicesPageState._accent.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(price.amount, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                                if (price.suffix.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text(price.suffix, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 11)),
                                ],
                              ],
                            ),
                          ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rental.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 16, color: Colors.white70),
                            const SizedBox(width: 4),
                            Expanded(child: Text(rental.cityLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rental.tags.isNotEmpty) ...[
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final t in rental.tags.take(3))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0x22FB8C00) : const Color(0x14FB8C00),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0x33FB8C00)),
                            ),
                            child: Text(_tagLabel(t), style: const TextStyle(color: _MobilityServicesPageState._accent, fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: onContact,
                            icon: const Icon(Icons.call_outlined, color: Colors.white),
                            label: const Text('Contacter'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _MobilityServicesPageState._ctaBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: rental.active ? onReserve : null,
                            icon: const Icon(Icons.event_available_rounded, color: Colors.white),
                            label: const Text('Reserver'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _MobilityServicesPageState._accent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.selected, required this.isDark, required this.onTap});

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _MobilityServicesPageState._accent.withOpacity(isDark ? 0.22 : 0.14) : (isDark ? Colors.white10 : const Color(0xFFF1F3F5));
    final border = selected ? _MobilityServicesPageState._accent.withOpacity(0.50) : (isDark ? Colors.white12 : Colors.black12);
    final fg = selected ? _MobilityServicesPageState._accent : (isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827));

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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.textColor,
    required this.subColor,
    required this.divider,
    this.validator,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final Color textColor;
  final Color subColor;
  final Color divider;
  final String? Function(String?)? validator;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subColor, fontWeight: FontWeight.w700),
        filled: true,
        fillColor: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _MobilityServicesPageState._accent, width: 1.2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent)),
      ),
    );
  }
}

class _CarRental {
  final String id;
  final String name;
  final String cityLabel;
  final String priceLabel;
  final String coverUrl;
  final String phone;
  final String email;
  final String description;
  final bool certified;
  final bool active;
  final List<String> tags;
  final String ownerUid;
  final String ownerEmail;
  final String ownerName;

  const _CarRental({
    required this.id,
    required this.name,
    required this.cityLabel,
    required this.priceLabel,
    required this.coverUrl,
    required this.phone,
    required this.email,
    required this.description,
    required this.certified,
    required this.active,
    required this.tags,
    required this.ownerUid,
    required this.ownerEmail,
    required this.ownerName,
  });
}

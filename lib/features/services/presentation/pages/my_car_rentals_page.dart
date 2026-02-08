import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:lualaba_konnect/features/services/presentation/pages/car_rental_calendar_page.dart';

class MyCarRentalsPage extends StatefulWidget {
  const MyCarRentalsPage({super.key});

  @override
  State<MyCarRentalsPage> createState() => _MyCarRentalsPageState();
}

class _MyCarRentalsPageState extends State<MyCarRentalsPage> {
  static const Color _accent = Color(0xFFFB8C00);

  String _appendUrlVersion(String url, int v) => url.contains('?') ? '$url&v=$v' : '$url?v=$v';

  Future<String> _uploadCover(Uint8List bytes) async {
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

  Future<void> _confirmDelete(DocumentReference ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF111B21) : Colors.white;
        final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
        final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
        return AlertDialog(
          backgroundColor: bg,
          title: Text('Supprimer cette annonce ?', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
          content: Text('Cette action est irreversible.', style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
          ],
        );
      },
    );
    if (ok != true) return;
    await ref.delete();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Annonce supprimée.')));
  }

  Future<void> _editRental(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    final cityCtrl = TextEditingController(text: (data['cityLabel'] ?? '').toString());
    final priceCtrl = TextEditingController(text: (data['priceLabel'] ?? '').toString());
    final phoneCtrl = TextEditingController(text: (data['phone'] ?? '').toString());
    final emailCtrl = TextEditingController(text: (data['email'] ?? '').toString());
    final descCtrl = TextEditingController(text: (data['description'] ?? '').toString());
    final currentCover = (data['coverUrl'] ?? '').toString();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final picker = ImagePicker();
    Uint8List? coverBytes;
    bool saving = false;

    Future<void> submit(StateSetter setModal) async {
      if (saving) return;
      setModal(() => saving = true);
      try {
        String coverUrl = currentCover;
        if (coverBytes != null && coverBytes!.isNotEmpty) {
          coverUrl = await _uploadCover(coverBytes!);
        }
        await doc.reference.update({
          'name': nameCtrl.text.trim(),
          'cityLabel': cityCtrl.text.trim(),
          'priceLabel': priceCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'email': emailCtrl.text.trim(),
          'description': descCtrl.text.trim(),
          if (coverUrl.trim().isNotEmpty) 'coverUrl': coverUrl.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        });
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Annonce mise à jour.')));
      } catch (e) {
        setModal(() => saving = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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
                      Center(
                        child: Container(
                          width: 46,
                          height: 4,
                          margin: const EdgeInsets.only(top: 6, bottom: 10),
                          decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(99)),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(child: Text('Modifier', style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5))),
                          IconButton(onPressed: saving ? null : () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                                  child: coverBytes != null
                                      ? Image.memory(coverBytes!, fit: BoxFit.cover)
                                      : (currentCover.trim().isNotEmpty ? CachedNetworkImage(imageUrl: currentCover, fit: BoxFit.cover) : const Icon(Icons.add_a_photo_outlined, color: _accent)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Photo', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
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
                      _Field(label: 'Titre', controller: nameCtrl, textColor: text, subColor: sub, divider: divider),
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
                          Expanded(child: _Field(label: 'Téléphone', controller: phoneCtrl, textColor: text, subColor: sub, divider: divider, keyboardType: TextInputType.phone)),
                          const SizedBox(width: 10),
                          Expanded(child: _Field(label: 'Email', controller: emailCtrl, textColor: text, subColor: sub, divider: divider, keyboardType: TextInputType.emailAddress)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _Field(label: 'Description', controller: descCtrl, textColor: text, subColor: sub, divider: divider, maxLines: 4),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: saving ? null : () => submit(setModal),
                          style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                          child: saving
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                              : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w900)),
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
    final me = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);

    if (me == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, foregroundColor: text, elevation: 0, title: const Text('Mes annonces')),
        body: Center(child: Text('Veuillez vous connecter.', style: TextStyle(color: sub, fontWeight: FontWeight.w700))),
      );
    }

    final stream = FirebaseFirestore.instance.collection('car_rentals').where('createdByUid', isEqualTo: me.uid).snapshots();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        title: const Text('Mes annonces', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}', style: TextStyle(color: sub)));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

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
            return Center(child: Text('Aucune annonce', style: TextStyle(color: sub, fontWeight: FontWeight.w700)));
          }

          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>? ?? {};
              final name = (data['name'] ?? 'Voiture').toString();
              final city = (data['cityLabel'] ?? '').toString();
              final price = (data['priceLabel'] ?? '').toString();
              final cover = (data['coverUrl'] ?? '').toString();
              final certified = data['certified'] == true || data['isCertified'] == true;
              final active = (data['active'] == false || data['isActive'] == false) ? false : true;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.35 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 74,
                        height: 74,
                        color: isDark ? Colors.white10 : Colors.black12,
                        child: cover.trim().isNotEmpty ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover) : const Icon(Icons.directions_car_rounded, color: _accent),
                      ),
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
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 15.5),
                                ),
                              ),
                              if (certified) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2D6BFF).withOpacity(isDark ? 0.30 : 0.16),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: const Color(0xFF2D6BFF).withOpacity(0.35)),
                                  ),
                                  child: const Text('Certifié', style: TextStyle(color: Color(0xFF2D6BFF), fontWeight: FontWeight.w900, fontSize: 12)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (city.trim().isNotEmpty)
                            Row(
                              children: [
                                Icon(Icons.location_on_outlined, size: 16, color: sub),
                                const SizedBox(width: 6),
                                Expanded(child: Text(city, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub, fontWeight: FontWeight.w700))),
                              ],
                            ),
                          if (price.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              price,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _accent, fontWeight: FontWeight.w900),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Text('Disponible', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                                    const SizedBox(width: 8),
                                    Switch(
                                      value: active,
                                      activeThumbColor: _accent,
                                      onChanged: (v) async {
                                        await doc.reference.update({
                                          'active': v,
                                          'isActive': v,
                                          'updatedAt': FieldValue.serverTimestamp(),
                                          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Calendrier',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CarRentalCalendarPage(
                                        rentalId: doc.id,
                                        rentalName: name,
                                      ),
                                    ),
                                  );
                                },
                                icon: Icon(Icons.calendar_month_rounded, color: sub),
                              ),
                              IconButton(
                                tooltip: 'Modifier',
                                onPressed: () => _editRental(doc),
                                icon: Icon(Icons.edit_outlined, color: sub),
                              ),
                              IconButton(
                                tooltip: 'Supprimer',
                                onPressed: () => _confirmDelete(doc.reference),
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              ),
                            ],
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
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFFB8C00), width: 1.2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent)),
      ),
    );
  }
}

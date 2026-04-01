import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:url_launcher/url_launcher.dart';

class TrainingServicesPage extends StatefulWidget {
  const TrainingServicesPage({super.key, this.initialFilterKey = 'all'});

  final String initialFilterKey;

  @override
  State<TrainingServicesPage> createState() => _TrainingServicesPageState();
}

class _TrainingServicesPageState extends State<TrainingServicesPage> {
  static const Color _accent = Color(0xFF2ECC71);
  static const Color _ctaBlue = Color(0xFF2D6BFF);

  late String _filterKey = widget.initialFilterKey;
  final TextEditingController _qCtrl = TextEditingController();

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

  String _formatLocationLabelFromPlacemark(Placemark place, Position position) {
    final parts = <String?>[
      place.street,
      place.subLocality,
      place.locality,
      place.administrativeArea,
    ].map((value) => (value ?? '').trim()).where((value) => value.isNotEmpty).toList();

    if (parts.isNotEmpty) return parts.join(', ');
    return '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
  }

  Future<_TrainingLocationResult?> _resolveCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Activez la localisation pour continuer.')),
          );
        }
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Autorisation de localisation refusee.')),
          );
        }
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      var label =
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      try {
        final places = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (places.isNotEmpty) {
          label = _formatLocationLabelFromPlacemark(places.first, position);
        }
      } catch (_) {}

      return _TrainingLocationResult(label: label);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de recuperer la localisation: $e')),
        );
      }
      return null;
    }
  }

  Query _query() {
    Query q = FirebaseFirestore.instance.collection('training_offers');
    if (_filterKey != 'all') q = q.where('tags', arrayContains: _filterKey);
    return q;
  }

  _TrainingOffer _fromDoc(QueryDocumentSnapshot<Object?> doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return _TrainingOffer(
      id: doc.id,
      title: (d['title'] ?? d['name'] ?? d['courseTitle'] ?? 'Formation').toString(),
      cityLabel: (d['cityLabel'] ?? d['city'] ?? '').toString(),
      priceLabel: (d['priceLabel'] ?? d['price'] ?? '').toString(),
      durationLabel: (d['durationLabel'] ?? d['duration'] ?? '').toString(),
      coverUrl: (d['coverUrl'] ?? d['imageUrl'] ?? d['photoUrl'] ?? '').toString(),
      phone: (d['phone'] ?? d['phoneNumber'] ?? '').toString(),
      email: (d['email'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      certified: _asBool(d['certified'] ?? d['isCertified']),
      tags: _asTags(d['tags']),
      ownerUid: (d['createdByUid'] ?? '').toString(),
    );
  }

  bool _matchesQuery(_TrainingOffer p, String q) {
    final x = q.trim().toLowerCase();
    if (x.isEmpty) return true;
    final hay = [p.title, p.cityLabel, p.durationLabel, p.description, p.tags.join(' ')].join(' ').toLowerCase();
    return hay.contains(x);
  }

  String _appendUrlVersion(String url, int v) => url.contains('?') ? '$url&v=$v' : '$url?v=$v';

  Future<String> _uploadCover(Uint8List bytes) async {
    final client = Supabase.instance.client;
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = 'training_offers/$now.jpg';
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
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir.")));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  void _showContactSheet(_TrainingOffer p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final me = FirebaseAuth.instance.currentUser;
    final isOwner =
        me != null && p.ownerUid.trim().isNotEmpty && p.ownerUid.trim() == me.uid;

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
                Container(
                  width: 46,
                  height: 4,
                  margin: const EdgeInsets.only(top: 6, bottom: 10),
                  decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(99)),
                ),
                Row(
                  children: [
                    Expanded(child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5))),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: sub)),
                  ],
                ),
                if (isOwner)
                  ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _openAddOfferSheet(existing: p);
                    },
                    leading: const Icon(Icons.edit_outlined, color: _ctaBlue),
                    title: Text('Modifier', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                    subtitle: Text('Mettre a jour cette formation', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                  ),
                if (isOwner)
                  ListTile(
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Supprimer la formation'),
                          content: const Text('Cette publication sera retiree definitivement.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              child: const Text('Annuler'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, true),
                              child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true || !mounted) return;
                      Navigator.pop(ctx);
                      await _deleteTrainingOffer(p);
                    },
                    leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    title: const Text('Supprimer', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800)),
                    subtitle: Text('Retirer cette publication', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
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

  Future<void> _deleteTrainingOffer(_TrainingOffer offer) async {
    try {
      await FirebaseFirestore.instance.collection('training_offers').doc(offer.id).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Formation supprimee.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suppression impossible: $e')),
      );
    }
  }

  static const List<(String, String, IconData)> _filters = [
    ('all', 'Tout', Icons.grid_view_rounded),
    ('scolaire', 'Scolaire', Icons.menu_book_rounded),
    ('langues', 'Langues', Icons.translate_rounded),
    ('informatique', 'Info', Icons.computer_rounded),
    ('conduite', 'Conduite', Icons.directions_car_rounded),
    ('business', 'Business', Icons.work_outline_rounded),
    ('art', 'Art', Icons.brush_outlined),
  ];

  Future<void> _openAddOfferSheet({_TrainingOffer? existing}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final cityCtrl = TextEditingController(
      text: existing != null && existing.cityLabel.isNotEmpty
          ? existing.cityLabel
          : 'Kolwezi, Centre',
    );
    final priceCtrl = TextEditingController(text: existing?.priceLabel ?? '');
    final durationCtrl = TextEditingController(
      text: existing != null && existing.durationLabel.isNotEmpty
          ? existing.durationLabel
          : '4 semaines',
    );
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final picker = ImagePicker();
    Uint8List? coverBytes;

    final formKey = GlobalKey<FormState>();
    bool saving = false;
    bool locating = false;
    final selectedTags = existing != null
        ? <String>{...existing.tags}
        : <String>{'informatique'};

    Future<void> submit(StateSetter setModal) async {
      if (saving) return;
      if (!(formKey.currentState?.validate() ?? false)) return;
      if ((coverBytes == null || coverBytes!.isEmpty) &&
          (existing?.coverUrl.isEmpty ?? true)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajoute une photo.')));
        return;
      }

      setModal(() => saving = true);
      try {
        final me = FirebaseAuth.instance.currentUser;
        String coverUrl = existing?.coverUrl ?? '';
        if (coverBytes != null) {
          coverUrl = await _uploadCover(coverBytes!);
        }
        final payload = <String, dynamic>{
          'title': titleCtrl.text.trim(),
          'cityLabel': cityCtrl.text.trim(),
          'priceLabel': priceCtrl.text.trim(),
          'durationLabel': durationCtrl.text.trim(),
          'coverUrl': coverUrl,
          'phone': phoneCtrl.text.trim(),
          'email': emailCtrl.text.trim(),
          'description': descCtrl.text.trim(),
          'tags': selectedTags.toList(),
          'createdByUid': me?.uid,
          'createdByEmail': me?.email,
          'createdByName': me?.displayName,
          // Admin dashboard should certify.
          'certified': false,
          'isCertified': false,
          'certifiedAt': null,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        };
        if (existing == null) {
          payload['createdAt'] = FieldValue.serverTimestamp();
          payload['createdAtMs'] = DateTime.now().millisecondsSinceEpoch;
          await FirebaseFirestore.instance.collection('training_offers').add(payload);
        } else {
          await FirebaseFirestore.instance
              .collection('training_offers')
              .doc(existing.id)
              .update(payload);
        }

        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existing == null ? 'Formation ajoutee.' : 'Formation mise a jour.',
            ),
          ),
        );
        return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Formation ajoutée.')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existing == null ? 'Erreur ajout: $e' : 'Erreur mise a jour: $e',
            ),
          ),
        );
        setModal(() => saving = false);
        return;
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
                          Expanded(child: Text(existing == null ? 'Ajouter une formation' : 'Modifier la formation', style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5))),
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
                                        child: coverBytes != null
                                            ? Image.memory(coverBytes!, fit: BoxFit.cover)
                                            : existing != null && existing.coverUrl.trim().isNotEmpty
                                                ? CachedNetworkImage(
                                                    imageUrl: existing.coverUrl,
                                                    fit: BoxFit.cover,
                                                  )
                                                : const Icon(Icons.add_photo_alternate_outlined, color: _accent),
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
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: saving || locating
                                    ? null
                                    : () async {
                                        setModal(() => locating = true);
                                        final result = await _resolveCurrentLocation();
                                        if (!context.mounted) return;
                                        if (result != null) {
                                          cityCtrl.text = result.label;
                                        }
                                        setModal(() => locating = false);
                                      },
                                icon: locating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.my_location_outlined),
                                label: Text(
                                  locating ? 'Localisation...' : 'Utiliser ma position',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            _Field(label: 'Titre (ex: Informatique de base)', controller: titleCtrl, textColor: text, subColor: sub, divider: divider, validator: (v) => (v == null || v.trim().isEmpty) ? 'Titre requis' : null),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _Field(label: 'Ville', controller: cityCtrl, textColor: text, subColor: sub, divider: divider)),
                                const SizedBox(width: 10),
                                Expanded(child: _Field(label: r'Prix (ex: 50$)', controller: priceCtrl, textColor: text, subColor: sub, divider: divider)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _Field(label: 'Durée (ex: 4 semaines)', controller: durationCtrl, textColor: text, subColor: sub, divider: divider),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _Field(label: 'Téléphone', controller: phoneCtrl, textColor: text, subColor: sub, divider: divider, keyboardType: TextInputType.phone)),
                                const SizedBox(width: 10),
                                Expanded(child: _Field(label: 'Email', controller: emailCtrl, textColor: text, subColor: sub, divider: divider, keyboardType: TextInputType.emailAddress)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Align(alignment: Alignment.centerLeft, child: Text('Catégories', style: TextStyle(color: text, fontWeight: FontWeight.w900))),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final t in _filters.where((e) => e.$1 != 'all'))
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
                            const SizedBox(height: 12),
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
                                    : Text(existing == null ? 'Ajouter' : 'Enregistrer', style: const TextStyle(fontWeight: FontWeight.w900)),
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

    titleCtrl.dispose();
    cityCtrl.dispose();
    priceCtrl.dispose();
    durationCtrl.dispose();
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
        onPressed: _openAddOfferSheet,
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
            title: const Text('Formation', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2, color: appBarFg)),
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
                            hintText: 'Scolaire, langues, conduite...',
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
              child: _TrainingFilterRow(
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
                final items = <_TrainingOffer>[];
                for (final d in docs) {
                  final p = _fromDoc(d);
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
                    return _TrainingCard(
                      offer: p,
                      isDark: isDark,
                      card: card,
                      text: text,
                      sub: sub,
                      divider: divider,
                      onContact: () => _showContactSheet(p),
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

class _TrainingFilterRow extends StatelessWidget {
  const _TrainingFilterRow({required this.isDark, required this.selectedKey, required this.onSelected});

  final bool isDark;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _TrainingServicesPageState._filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final f = _TrainingServicesPageState._filters[i];
          final selected = selectedKey == f.$1;
          final bg = selected ? (isDark ? const Color(0xFF111B21) : Colors.white) : (isDark ? Colors.white10 : const Color(0xFFF1F3F5));
          final border = selected ? _TrainingServicesPageState._accent.withOpacity(0.35) : (isDark ? Colors.white12 : Colors.black12);
          final fg = selected ? _TrainingServicesPageState._accent : (isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827));
          return InkWell(
            onTap: () => onSelected(f.$1),
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: border)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(f.$3, size: 18, color: selected ? _TrainingServicesPageState._accent : sub),
                  const SizedBox(width: 8),
                  Text(f.$2, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12)),
                ],
              ),
            ),
          );
        },
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
    final bg = selected ? _TrainingServicesPageState._accent.withOpacity(isDark ? 0.22 : 0.14) : (isDark ? Colors.white10 : const Color(0xFFF1F3F5));
    final border = selected ? _TrainingServicesPageState._accent.withOpacity(0.50) : (isDark ? Colors.white12 : Colors.black12);
    final fg = selected ? _TrainingServicesPageState._accent : (isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827));

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
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _TrainingServicesPageState._accent, width: 1.2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent)),
      ),
    );
  }
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({
    required this.offer,
    required this.isDark,
    required this.card,
    required this.text,
    required this.sub,
    required this.divider,
    required this.onContact,
  });

  final _TrainingOffer offer;
  final bool isDark;
  final Color card;
  final Color text;
  final Color sub;
  final Color divider;
  final VoidCallback onContact;

  ({String amount, String suffix}) _splitPrice(String input) {
    final s0 = input.trim();
    if (s0.isEmpty) return (amount: '', suffix: '');
    final s = s0.replaceAll(RegExp(r'\s+'), ' ');
    final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*\$?\s*(.*)$').firstMatch(s);
    if (m != null) {
      final amount0 = (m.group(1) ?? '').trim();
      var rest = (m.group(2) ?? '').trim();
      return (amount: amount0.isEmpty ? '' : '$amount0 \$', suffix: rest);
    }
    return (amount: s, suffix: '');
  }

  @override
  Widget build(BuildContext context) {
    final price = _splitPrice(offer.priceLabel);
    final hasImg = offer.coverUrl.trim().isNotEmpty;

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
                    CachedNetworkImage(imageUrl: offer.coverUrl, fit: BoxFit.cover)
                  else
                    Container(
                      color: isDark ? Colors.white10 : const Color(0xFFE9ECEF),
                      child: const Icon(Icons.school_rounded, size: 54, color: _TrainingServicesPageState._accent),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withOpacity(0.10), Colors.black.withOpacity(0.62)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: offer.certified
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: _TrainingServicesPageState._ctaBlue.withOpacity(0.92),
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
                    right: 12,
                    top: 12,
                    child: price.amount.isEmpty
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _TrainingServicesPageState._accent.withOpacity(0.92),
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
                        Text(offer.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 16, color: Colors.white70),
                            const SizedBox(width: 4),
                            Expanded(child: Text(offer.cityLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700))),
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
                  if (offer.durationLabel.trim().isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 16, color: sub),
                        const SizedBox(width: 6),
                        Expanded(child: Text(offer.durationLabel.trim(), style: TextStyle(color: sub, fontWeight: FontWeight.w700))),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (offer.tags.isNotEmpty) ...[
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final t in offer.tags.take(3))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0x222ECC71) : const Color(0x142ECC71),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0x332ECC71)),
                            ),
                            child: Text(t, style: const TextStyle(color: _TrainingServicesPageState._accent, fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: onContact,
                      icon: const Icon(Icons.call_outlined, color: Colors.white),
                      label: const Text('Contacter'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _TrainingServicesPageState._ctaBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
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

class _TrainingOffer {
  final String id;
  final String title;
  final String cityLabel;
  final String priceLabel;
  final String durationLabel;
  final String coverUrl;
  final String phone;
  final String email;
  final String description;
  final bool certified;
  final List<String> tags;
  final String ownerUid;

  const _TrainingOffer({
    required this.id,
    required this.title,
    required this.cityLabel,
    required this.priceLabel,
    required this.durationLabel,
    required this.coverUrl,
    required this.phone,
    required this.email,
    required this.description,
    required this.certified,
    required this.tags,
    required this.ownerUid,
  });
}

class _TrainingLocationResult {
  final String label;

  const _TrainingLocationResult({
    required this.label,
  });
}

import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class FreelanceProsPage extends StatefulWidget {
  const FreelanceProsPage({super.key, this.initialFilterKey = 'all'});

  final String initialFilterKey;

  @override
  State<FreelanceProsPage> createState() => _FreelanceProsPageState();
}

class _FreelanceProsPageState extends State<FreelanceProsPage> {
  static const Color _accent = Color(0xFFFB8C00);
  static const Color _ctaBlue = Color(0xFF2D6BFF);

  late String _filterKey = widget.initialFilterKey;
  final TextEditingController _qCtrl = TextEditingController();

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  // Parsing helpers
  bool _asBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true' || v == 'True';

  double _asDouble(dynamic v, {double def = 0}) {
    if (v == null) return def;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? def;
  }

  int _asInt(dynamic v, {int def = 0}) {
    if (v == null) return def;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? def;
  }

  List<String> _asTags(dynamic v) {
    if (v is List) return List<String>.from(v.map((e) => e.toString()));
    return const [];
  }

  Query _query() {
    Query q = FirebaseFirestore.instance.collection('freelance_pros');
    if (_filterKey != 'all') q = q.where('tags', arrayContains: _filterKey);
    return q;
  }

  _FreelancePro _fromDoc(QueryDocumentSnapshot<Object?> doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return _FreelancePro(
      id: doc.id,
      name: (d['name'] ?? d['displayName'] ?? 'Profil').toString(),
      role: (d['role'] ?? d['title'] ?? '').toString(),
      cityLabel: (d['cityLabel'] ?? d['city'] ?? '').toString(),
      priceLabel: (d['priceLabel'] ?? d['price'] ?? '').toString(),
      avatarUrl: (d['avatarUrl'] ?? d['photoUrl'] ?? '').toString(),
      phone: (d['phone'] ?? d['phoneNumber'] ?? '').toString(),
      email: (d['email'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      rating: _asDouble(d['rating'], def: 0),
      reviews: _asInt(d['reviews'], def: 0),
      certified: _asBool(d['certified'] ?? d['isCertified']),
      tags: _asTags(d['tags']),
    );
  }

  bool _matchesQuery(_FreelancePro p, String q) {
    final x = q.trim().toLowerCase();
    if (x.isEmpty) return true;
    final hay = [p.name, p.role, p.cityLabel, p.description, p.tags.join(' ')].join(' ').toLowerCase();
    return hay.contains(x);
  }

  String _appendUrlVersion(String url, int v) {
    if (url.contains('?')) return '$url&v=$v';
    return '$url?v=$v';
  }

  Future<String> _uploadAvatar(Uint8List bytes) async {
    final client = Supabase.instance.client;
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = 'freelance_pros/$now.jpg';

    await client.storage.from('profiles').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true, contentType: 'image/jpeg'),
        );

    final publicUrl = client.storage.from('profiles').getPublicUrl(path);
    return _appendUrlVersion(publicUrl, now);
  }

  Future<void> _launchOrSnack(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'ouvrir.")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  // UI actions (filled below)
  void _showContactSheet(_FreelancePro p) {
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
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.60 : 0.12), blurRadius: 26, offset: const Offset(0, 14))],
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
                    Expanded(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5, letterSpacing: -0.2),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: sub),
                    ),
                  ],
                ),
                if (p.phone.trim().isEmpty && p.email.trim().isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Text('Aucun contact disponible.', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                  ),
                if (p.phone.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchOrSnack(Uri.parse('tel:${p.phone.trim()}'));
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
                    subtitle: Text(p.phone.trim(), style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                    trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: sub),
                  ),
                ],
                if (p.email.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _launchOrSnack(Uri.parse('mailto:${p.email.trim()}'));
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
                    subtitle: Text(p.email.trim(), style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
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

  Future<void> _openAddSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController();
    final cityCtrl = TextEditingController(text: 'Kolwezi, Centre');
    final priceCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ratingCtrl = TextEditingController(text: '');
    final reviewsCtrl = TextEditingController(text: '');

    final picker = ImagePicker();
    Uint8List? avatarBytes;

    final formKey = GlobalKey<FormState>();
    bool saving = false;

    const tagOptions = <(String, String)>[
      ('tech', 'Tech'),
      ('batiment', 'Batiment'),
      ('art', 'Art'),
      ('vie', 'Vie'),
    ];
    final selectedTags = <String>{'tech'};

    Future<void> submit(StateSetter setModal) async {
      if (saving) return;
      if (!(formKey.currentState?.validate() ?? false)) return;

      setModal(() => saving = true);
      try {
        String avatarUrl = '';
        if (avatarBytes != null) {
          avatarUrl = await _uploadAvatar(avatarBytes!);
        }

        final me = FirebaseAuth.instance.currentUser;

        await FirebaseFirestore.instance.collection('freelance_pros').add({
          'name': nameCtrl.text.trim(),
          'role': roleCtrl.text.trim(),
          'cityLabel': cityCtrl.text.trim(),
          'priceLabel': priceCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'email': emailCtrl.text.trim(),
          'description': descCtrl.text.trim(),
          'avatarUrl': avatarUrl,
          'rating': _asDouble(ratingCtrl.text.trim(), def: 0),
          'reviews': _asInt(reviewsCtrl.text.trim(), def: 0),
          'createdByUid': me?.uid,
          'createdByEmail': me?.email,
          'createdByName': me?.displayName,
          // Only admin dashboard certifies profiles.
          'certified': false,
          'isCertified': false,
          'certifiedAt': null,
          'tags': selectedTags.toList(),
          'createdAt': FieldValue.serverTimestamp(),
          'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        });

        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil ajoute.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur ajout: $e')),
        );
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
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: divider),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.60 : 0.12), blurRadius: 26, offset: const Offset(0, 14))],
                  ),
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
                          Expanded(
                            child: Text(
                              'Ajouter un profil',
                              style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16.5, letterSpacing: -0.2),
                            ),
                          ),
                          IconButton(
                            onPressed: saving ? null : () => Navigator.pop(ctx),
                            icon: Icon(Icons.close, color: sub),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Form(
                        key: formKey,
                        child: Column(
                          children: [
                            // Avatar picker
                            GestureDetector(
                              onTap: saving
                                  ? null
                                  : () async {
                                      final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                                      if (x == null) return;
                                      final bytes = await x.readAsBytes();
                                      setModal(() => avatarBytes = bytes);
                                    },
                              child: Container(
                                height: 86,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: divider),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        width: 66,
                                        height: 66,
                                        color: isDark ? Colors.white12 : Colors.black12,
                                        child: avatarBytes == null
                                            ? const Icon(Icons.add_a_photo_outlined, color: _accent)
                                            : Image.memory(avatarBytes!, fit: BoxFit.cover),
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
                            _Field(
                              label: 'Nom',
                              controller: nameCtrl,
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                            ),
                            const SizedBox(height: 10),
                            _Field(
                              label: 'Metier / Role',
                              controller: roleCtrl,
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Role requis' : null,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _Field(
                                    label: 'Ville',
                                    controller: cityCtrl,
                                    textColor: text,
                                    subColor: sub,
                                    divider: divider,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _Field(
                                    label: 'Prix (ex: 10 / jour)',
                                    controller: priceCtrl,
                                    textColor: text,
                                    subColor: sub,
                                    divider: divider,
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
                              label: 'Description',
                              controller: descCtrl,
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              maxLines: 3,
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Tags', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                            ),
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
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _Field(
                                    label: 'Note (optionnel)',
                                    controller: ratingCtrl,
                                    textColor: text,
                                    subColor: sub,
                                    divider: divider,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _Field(
                                    label: 'Avis (optionnel)',
                                    controller: reviewsCtrl,
                                    textColor: text,
                                    subColor: sub,
                                    divider: divider,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: saving ? null : () => submit(setModal),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                ),
                                child: saving
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                                      )
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
    roleCtrl.dispose();
    cityCtrl.dispose();
    priceCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    descCtrl.dispose();
    ratingCtrl.dispose();
    reviewsCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton(
        backgroundColor: _accent,
        onPressed: _openAddSheet,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 170,
            elevation: 0,
            backgroundColor: const Color(0xFF0B141A),
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(28))),
            leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
            title: const Text('Freelance & Pros', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2)),
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
                            hintText: 'Plombier, Tech, Macon...',
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
              child: _FilterRow(
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
                    child: Center(
                      child: Text('Erreur: ${snap.error}', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                    ),
                  );
                }

                final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Object?>>[];
                final q = _qCtrl.text.trim().toLowerCase();
                final items = <_FreelancePro>[];
                for (final d in docs) {
                  final p = _fromDoc(d);
                  if (!_matchesQuery(p, q)) continue;
                  items.add(p);
                }

                if (items.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 36),
                      child: Center(
                        child: Text('Aucun resultat', style: TextStyle(color: sub, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final p = items[i];
                      return TweenAnimationBuilder<double>(
                        key: ValueKey('${_filterKey}_${p.id}'),
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 420 + (i.clamp(0, 10) * 35)),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, child) => Opacity(
                          opacity: v,
                          child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
                        ),
                        child: _ProCard(
                          isDark: isDark,
                          card: card,
                          text: text,
                          sub: sub,
                          divider: divider,
                          pro: p,
                          onContact: () => _showContactSheet(p),
                        ),
                      );
                    },
                    childCount: items.length,
                  ),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }

  Widget _skeleton(bool isDark) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFE9ECEF),
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.isDark, required this.selectedKey, required this.onSelected});

  final bool isDark;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  static const filters = [
    ('all', 'Tout', Icons.grid_view_rounded),
    ('tech', 'Tech', Icons.laptop_mac_rounded),
    ('batiment', 'Batiment', Icons.home_repair_service_rounded),
    ('art', 'Art', Icons.palette_rounded),
    ('vie', 'Vie', Icons.favorite_rounded),
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
          final border = selected ? _FreelanceProsPageState._accent.withOpacity(0.35) : (isDark ? Colors.white12 : Colors.black12);
          final fg = selected ? _FreelanceProsPageState._accent : (isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827));

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

class _ProCard extends StatelessWidget {
  const _ProCard({
    required this.isDark,
    required this.card,
    required this.text,
    required this.sub,
    required this.divider,
    required this.pro,
    required this.onContact,
  });

  final bool isDark;
  final Color card;
  final Color text;
  final Color sub;
  final Color divider;
  final _FreelancePro pro;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.35 : 0.08), blurRadius: 22, offset: const Offset(0, 14))],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: pro.avatarUrl.trim().isEmpty
                          ? Container(color: isDark ? Colors.white10 : Colors.black12, child: Icon(Icons.person, color: sub))
                          : Image(image: CachedNetworkImageProvider(pro.avatarUrl), fit: BoxFit.cover),
                    ),
                  ),
                  if (pro.certified)
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _FreelanceProsPageState._ctaBlue,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: card, width: 3),
                          boxShadow: [BoxShadow(color: _FreelanceProsPageState._ctaBlue.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 8))],
                        ),
                        child: const Icon(Icons.shield_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                ],
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
                            pro.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                        ),
                        if (pro.priceLabel.trim().isNotEmpty) ...[
                          const SizedBox(width: 10),
                          _PricePill(
                            raw: pro.priceLabel,
                            isDark: isDark,
                          ),
                        ],
                      ],
                    ),
                    if (pro.role.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(pro.role, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _FreelanceProsPageState._accent, fontWeight: FontWeight.w900, fontSize: 12)),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (pro.rating > 0)
                          _SmallPill(
                            bg: isDark ? Colors.white10 : const Color(0xFFF1F3F5),
                            icon: Icons.star_rounded,
                            iconColor: const Color(0xFFFFC107),
                            text: pro.rating.toStringAsFixed(1),
                            textColor: text,
                          ),
                        if (pro.rating > 0) const SizedBox(width: 8),
                        Expanded(child: Text(pro.cityLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub, fontWeight: FontWeight.w700))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pro.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final t in pro.tags.take(2))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0x22FB8C00) : const Color(0x14FB8C00),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x33FB8C00)),
                      ),
                      child: Text(t, style: const TextStyle(color: _FreelanceProsPageState._accent, fontWeight: FontWeight.w900, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onContact,
              icon: const Icon(Icons.call_outlined, color: Colors.white),
              label: const Text('Contacter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _FreelanceProsPageState._ctaBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.bg, required this.icon, required this.iconColor, required this.text, required this.textColor});
  final Color bg;
  final IconData icon;
  final Color iconColor;
  final String text;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 14, offset: const Offset(0, 10))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  const _PricePill({required this.raw, required this.isDark});

  final String raw;
  final bool isDark;

  ({String amount, String suffix}) _split(String input) {
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

  @override
  Widget build(BuildContext context) {
    final parts = _split(raw);
    if (parts.amount.isEmpty) return const SizedBox.shrink();

    final bg = isDark ? const Color(0x22FB8C00) : const Color(0x14FB8C00);
    final border = const Color(0x55FB8C00);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
        boxShadow: [BoxShadow(color: _FreelanceProsPageState._accent.withOpacity(0.22), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(parts.amount, style: const TextStyle(color: _FreelanceProsPageState._accent, fontWeight: FontWeight.w900, fontSize: 12.5, height: 1)),
          if (parts.suffix.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(parts.suffix, style: TextStyle(color: isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280), fontWeight: FontWeight.w800, fontSize: 11, height: 1)),
          ],
        ],
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
    final bg = selected ? _FreelanceProsPageState._accent.withOpacity(isDark ? 0.22 : 0.14) : (isDark ? Colors.white10 : const Color(0xFFF1F3F5));
    final border = selected ? _FreelanceProsPageState._accent.withOpacity(0.50) : (isDark ? Colors.white12 : Colors.black12);
    final fg = selected ? _FreelanceProsPageState._accent : (isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827));

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
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _FreelanceProsPageState._accent, width: 1.2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent)),
      ),
    );
  }
}

class _FreelancePro {
  final String id;
  final String name;
  final String role;
  final String cityLabel;
  final String priceLabel;
  final String avatarUrl;
  final String phone;
  final String email;
  final String description;
  final double rating;
  final int reviews;
  final bool certified;
  final List<String> tags;

  const _FreelancePro({
    required this.id,
    required this.name,
    required this.role,
    required this.cityLabel,
    required this.priceLabel,
    required this.avatarUrl,
    required this.phone,
    required this.email,
    required this.description,
    required this.rating,
    required this.reviews,
    required this.certified,
    required this.tags,
  });
}

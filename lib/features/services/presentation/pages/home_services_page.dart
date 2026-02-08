import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';

class HomeServicesPage extends StatefulWidget {
  const HomeServicesPage({super.key, this.initialFilterKey = 'all'});

  final String initialFilterKey;

  @override
  State<HomeServicesPage> createState() => _HomeServicesPageState();
}

class _HomeServicesPageState extends State<HomeServicesPage> {
  late String _filterKey = widget.initialFilterKey;
  static const Color _headerBlue = Color(0xFF2D6BFF);

  Query _providersQuery() {
    // Collection: `service_providers`
    // Fields:
    // - name (string), role (string), avatarUrl (string)
    // - cityLabel (string), priceLabel (string)
    // - rating (number), reviews (number)
    // - certified (bool)
    // - tags (array<string>) => menage, babysitting, jardinier, vigile, ...
    Query q = FirebaseFirestore.instance.collection('service_providers');
    if (_filterKey != 'all') q = q.where('tags', arrayContains: _filterKey);
    return q;
  }

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

  bool _asBool(dynamic v) {
    return v == true || v == 1 || v == '1' || v == 'true' || v == 'True';
  }

  _ServicePro _fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    final tags = (d['tags'] is List) ? List<String>.from(d['tags'] ?? const []) : const <String>[];
    return _ServicePro(
      id: doc.id,
      name: (d['name'] ?? d['displayName'] ?? 'Utilisateur').toString(),
      role: (d['role'] ?? d['title'] ?? '').toString(),
      rating: _asDouble(d['rating']),
      reviews: _asInt(d['reviews'] ?? d['reviewsCount']),
      priceLabel: (d['priceLabel'] ?? d['price'] ?? '').toString(),
      cityLabel: (d['cityLabel'] ?? d['city'] ?? '').toString(),
      description: (d['description'] ?? d['bio'] ?? '').toString(),
      avatarUrl: (d['avatarUrl'] ?? d['photoUrl'] ?? d['photo'] ?? d['avatar'] ?? '').toString(),
      // Service providers have their own certification flag (separate from user classic/pro/enterprise badges).
      // We accept both field names for compatibility with the admin dashboard.
      certified: _asBool(d['certified'] ?? d['isCertified']),
      tags: tags,
      phone: (d['phone'] ?? d['phoneNumber'] ?? '').toString(),
      email: (d['email'] ?? '').toString(),
    );
  }

  String _appendUrlVersion(String url, int v) {
    if (url.contains('?')) return '$url&v=$v';
    return '$url?v=$v';
  }

  Future<String> _uploadProviderAvatar(Uint8List bytes) async {
    final client = Supabase.instance.client;
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = 'service_providers/$now.jpg';
    await client.storage.from('profiles').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    final publicUrl = client.storage.from('profiles').getPublicUrl(path);
    return _appendUrlVersion(publicUrl, now);
  }

  Future<void> _openAddProviderSheet() async {
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
    final ratingCtrl = TextEditingController(text: '4.8');
    final reviewsCtrl = TextEditingController(text: '0');
    final picker = ImagePicker();
    Uint8List? avatarBytes;

    final formKey = GlobalKey<FormState>();
    final availableTags = const [
      ('menage', 'Menage'),
      ('babysitting', 'Babysitting'),
      ('jardinier', 'Jardinier'),
      ('vigile', 'Vigile'),
    ];
    final selectedTags = <String>{'menage'};
    bool saving = false;

    Future<void> submit(StateSetter setModal) async {
      if (saving) return;
      if (!(formKey.currentState?.validate() ?? false)) return;
      if (selectedTags.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selectionne au moins un tag.')),
        );
        return;
      }

      setModal(() => saving = true);
      try {
        final me = FirebaseAuth.instance.currentUser;
        String avatarUrl = '';
        if (avatarBytes != null && avatarBytes!.isNotEmpty) {
          avatarUrl = await _uploadProviderAvatar(avatarBytes!);
        }

        await FirebaseFirestore.instance.collection('service_providers').add({
          'name': nameCtrl.text.trim(),
          'role': roleCtrl.text.trim(),
          'cityLabel': cityCtrl.text.trim(),
          'priceLabel': priceCtrl.text.trim(),
          'avatarUrl': avatarUrl,
          'phone': phoneCtrl.text.trim(),
          'email': emailCtrl.text.trim(),
          'description': descCtrl.text.trim(),
          'rating': _asDouble(ratingCtrl.text.trim(), def: 0),
          'reviews': _asInt(reviewsCtrl.text.trim(), def: 0),
          // Creator info (who added this profile from the app).
          'createdByUid': me?.uid,
          'createdByEmail': me?.email,
          'createdByName': me?.displayName,
          // Only the admin dashboard should certify a profile.
          // We always create providers as non-certified by default.
          'certified': false,
          'isCertified': false,
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
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.55 : 0.12), blurRadius: 26, offset: const Offset(0, 14))],
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
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white24 : Colors.black12,
                            borderRadius: BorderRadius.circular(99),
                          ),
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
                      const SizedBox(height: 8),
                      Form(
                        key: formKey,
                        child: Column(
                          children: [
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
                              label: 'Role (ex: FEMME DE MENAGE)',
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
                                    label: 'Prix',
                                    controller: priceCtrl,
                                    textColor: text,
                                    subColor: sub,
                                    divider: divider,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: divider),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 54,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white10 : Colors.black12,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: divider),
                                    ),
                                    child: avatarBytes == null
                                        ? Icon(Icons.person, color: sub)
                                        : ClipRRect(
                                            borderRadius: BorderRadius.circular(16),
                                            child: Image.memory(avatarBytes!, fit: BoxFit.cover),
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Photo', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                                        const SizedBox(height: 2),
                                        Text('Uploader une photo du profil', style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton(
                                    tooltip: 'Galerie',
                                    onPressed: saving
                                        ? null
                                        : () async {
                                            final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
                                            if (x == null) return;
                                            final b = await x.readAsBytes();
                                            setModal(() => avatarBytes = b);
                                          },
                                    icon: Icon(Icons.photo_library_outlined, color: sub),
                                  ),
                                  IconButton(
                                    tooltip: 'Camera',
                                    onPressed: saving
                                        ? null
                                        : () async {
                                            final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 75);
                                            if (x == null) return;
                                            final b = await x.readAsBytes();
                                            setModal(() => avatarBytes = b);
                                          },
                                    icon: Icon(Icons.photo_camera_outlined, color: sub),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            _Field(
                              label: 'Telephone',
                              controller: phoneCtrl,
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                            ),
                            const SizedBox(height: 10),
                            _Field(
                              label: 'Email',
                              controller: emailCtrl,
                              textColor: text,
                              subColor: sub,
                              divider: divider,
                              keyboardType: TextInputType.emailAddress,
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
                              child: Text('Tags', style: TextStyle(color: sub, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final t in availableTags)
                                  FilterChip(
                                    label: Text(t.$2),
                                    selected: selectedTags.contains(t.$1),
                                    onSelected: (v) => setModal(() {
                                      if (v) {
                                        selectedTags.add(t.$1);
                                      } else {
                                        selectedTags.remove(t.$1);
                                      }
                                    }),
                                    labelStyle: TextStyle(
                                      color: selectedTags.contains(t.$1) ? Colors.white : sub,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    backgroundColor: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                                    selectedColor: _headerBlue,
                                    side: BorderSide(color: divider),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _Field(
                                    label: 'Note',
                                    controller: ratingCtrl,
                                    textColor: text,
                                    subColor: sub,
                                    divider: divider,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _Field(
                                    label: 'Avis',
                                    controller: reviewsCtrl,
                                    textColor: text,
                                    subColor: sub,
                                    divider: divider,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: saving ? null : () => submit(setModal),
                                icon: saving
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.add, color: Colors.white),
                                label: Text(saving ? 'Ajout...' : 'Ajouter', style: const TextStyle(fontWeight: FontWeight.w900)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _headerBlue,
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
        backgroundColor: _headerBlue,
        onPressed: _openAddProviderSheet,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 170,
            backgroundColor: _headerBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Services Maison', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2)),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  colors: [_headerBlue, Color(0xFF1E4BFF)],
                ),
              ),
            ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(82),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _SelectionCard(
                  isDark: isDark,
                  card: card,
                  divider: divider,
                  text: text,
                  sub: sub,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: _FilterRow(
                isDark: isDark,
                card: card,
                text: text,
                sub: sub,
                divider: divider,
                selectedKey: _filterKey,
                onSelected: (k) => setState(() => _filterKey = k),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  // Render the whole list inside one StreamBuilder (to avoid sliver complexity).
                  if (index != 0) return null;
                  return StreamBuilder<QuerySnapshot>(
                    stream: _providersQuery().snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text('Erreur de chargement', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                          ),
                        );
                      }
                      if (!snap.hasData) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(child: CircularProgressIndicator(color: _headerBlue)),
                        );
                      }

                      final docs = snap.data!.docs.cast<QueryDocumentSnapshot>();
                      final items = docs.map(_fromDoc).toList();
                      if (_filterKey != 'all') {
                        // Extra safety if some docs have malformed `tags`.
                        items.removeWhere((p) => !p.tags.contains(_filterKey));
                      }

                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text('Aucun profil pour ce filtre', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                          ),
                        );
                      }

                      // Sort client-side (avoid composite indexes).
                      items.sort((a, b) {
                        final byRating = b.rating.compareTo(a.rating);
                        if (byRating != 0) return byRating;
                        return b.reviews.compareTo(a.reviews);
                      });

                      return Column(
                        children: [
                          for (int i = 0; i < items.length; i++) ...[
                            TweenAnimationBuilder<double>(
                              key: ValueKey('${_filterKey}_${items[i].id}'),
                              tween: Tween(begin: 0, end: 1),
                              duration: Duration(milliseconds: 420 + (i.clamp(0, 10) * 40)),
                              curve: Curves.easeOutCubic,
                              builder: (context, v, child) => Opacity(
                                opacity: v,
                                child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
                              ),
                              child: _ProCard(
                                isDark: isDark,
                                card: card,
                                text: text,
                                sub: sub,
                                divider: divider,
                                pro: items[i],
                                onContact: () => _showContactSheet(items[i]),
                              ),
                            ),
                            if (i != items.length - 1) const SizedBox(height: 14),
                          ],
                        ],
                      );
                    },
                  );
                },
                childCount: 1,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }

  void _showContactSheet(_ServicePro p) {
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
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.55 : 0.12), blurRadius: 26, offset: const Offset(0, 14))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundImage: p.avatarUrl.isNotEmpty ? CachedNetworkImageProvider(p.avatarUrl) : null,
                    child: p.avatarUrl.isEmpty ? const Icon(Icons.person) : null,
                  ),
                  title: Text(p.name, style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                  subtitle: Text('Contacter', style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
                ),
                Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
                ListTile(
                  leading: const Icon(Icons.call_outlined),
                  title: Text('Appeler', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  subtitle: Text('Bientot disponible', style: TextStyle(color: sub)),
                  onTap: () => Navigator.pop(ctx),
                ),
                Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
                ListTile(
                  leading: const Icon(Icons.message_outlined),
                  title: Text('Envoyer un message', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  subtitle: Text('Bientot disponible', style: TextStyle(color: sub)),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.isDark,
    required this.card,
    required this.divider,
    required this.text,
    required this.sub,
  });

  final bool isDark;
  final Color card;
  final Color divider;
  final Color text;
  final Color sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.28 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF2D6BFF).withOpacity(isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2D6BFF).withOpacity(0.25)),
            ),
            child: const Icon(Icons.shield_outlined, color: Color(0xFF2D6BFF)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selection LB Konnect',
                  style: TextStyle(color: text, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 3),
                Text(
                  'Les profils avec badges ont ete identifies et valides par notre equipe pour garantir votre securite.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: sub, fontWeight: FontWeight.w600, height: 1.2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.isDark,
    required this.card,
    required this.text,
    required this.sub,
    required this.divider,
    required this.selectedKey,
    required this.onSelected,
  });

  final bool isDark;
  final Color card;
  final Color text;
  final Color sub;
  final Color divider;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  static const _filters = [
    ('all', 'Tout', Icons.auto_awesome),
    ('menage', 'Menage', Icons.cleaning_services_outlined),
    ('babysitting', 'Babysitting', Icons.child_friendly_outlined),
    ('jardinier', 'Jardinier', Icons.grass_outlined),
    ('vigile', 'Vigile', Icons.security_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final f = _filters[i];
          final selected = selectedKey == f.$1;
          return GestureDetector(
            onTap: () => onSelected(f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF111827) : card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? Colors.transparent : divider),
                boxShadow: selected
                    ? [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.55 : 0.12), blurRadius: 18, offset: const Offset(0, 10))]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(f.$3, size: 18, color: selected ? Colors.white : sub),
                  const SizedBox(width: 8),
                  Text(
                    f.$2,
                    style: TextStyle(
                      color: selected ? Colors.white : text,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.1,
                    ),
                  ),
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
  final _ServicePro pro;
  final VoidCallback onContact;

  _PriceParts _priceParts(String raw) {
    final s0 = raw.trim();
    if (s0.isEmpty) return const _PriceParts('', '');
    final s = s0.replaceAll(RegExp(r'\s+'), ' ');

    // Prefer "amount $ + suffix" (e.g. "10 $ / jour").
    final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*\$?\s*(.*)$').firstMatch(s);
    if (m != null) {
      final amount = (m.group(1) ?? '').trim();
      var rest = (m.group(2) ?? '').trim();
      if (rest.startsWith('/')) rest = '/ ${rest.substring(1).trim()}';
      return _PriceParts('$amount \$', rest);
    }

    // If we can't parse an amount, keep the label as-is.
    return _PriceParts(s, '');
  }

  @override
  Widget build(BuildContext context) {
    final price = _priceParts(pro.priceLabel);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.30 : 0.06), blurRadius: 20, offset: const Offset(0, 12))],
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
                          ? Container(
                              color: isDark ? Colors.white10 : Colors.black12,
                              child: Icon(Icons.person, color: sub),
                            )
                          : Image(
                              image: CachedNetworkImageProvider(pro.avatarUrl),
                              fit: BoxFit.cover,
                            ),
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
                          color: const Color(0xFF2D6BFF),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: card, width: 3),
                          boxShadow: [BoxShadow(color: const Color(0xFF2D6BFF).withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 8))],
                        ),
                        // Rapid services badge: distinct from classic/pro/enterprise user badges.
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
                            style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.2),
                          ),
                        ),
                        if (price.amount.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0x22FF7A1A) : const Color(0x14FF7A1A),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0x40FF7A1A)),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0x66FF7A1A).withOpacity(isDark ? 0.20 : 0.14),
                                  blurRadius: 16,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  price.amount,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFFF7A1A),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 19,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                if (price.suffix.isNotEmpty)
                                  Text(
                                    price.suffix,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: sub, fontWeight: FontWeight.w700, fontSize: 12, height: 1.1),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(pro.role, style: TextStyle(color: const Color(0xFF2D6BFF), fontWeight: FontWeight.w900, letterSpacing: 0.6, fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFC107)),
                        Text('${pro.rating.toStringAsFixed(1)}', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 6),
                        Text('(${pro.reviews})', style: TextStyle(color: sub, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 18, color: sub),
              const SizedBox(width: 6),
              Expanded(child: Text(pro.cityLabel, style: TextStyle(color: sub, fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '"${pro.description}"',
              style: TextStyle(color: sub, fontWeight: FontWeight.w600, height: 1.25),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onContact,
              icon: const Icon(Icons.call_outlined, color: Colors.white),
              label: const Text('Contacter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D6BFF),
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

class _ServicePro {
  final String id;
  final String name;
  final String role;
  final double rating;
  final int reviews;
  final String priceLabel;
  final String cityLabel;
  final String description;
  final String avatarUrl;
  final bool certified;
  final List<String> tags;
  final String phone;
  final String email;

  const _ServicePro({
    required this.id,
    required this.name,
    required this.role,
    required this.rating,
    required this.reviews,
    required this.priceLabel,
    required this.cityLabel,
    required this.description,
    required this.avatarUrl,
    required this.certified,
    required this.tags,
    required this.phone,
    required this.email,
  });
}

class _PriceParts {
  final String amount;
  final String suffix;
  const _PriceParts(this.amount, this.suffix);
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
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final Color textColor;
  final Color subColor;
  final Color divider;
  final String? Function(String?)? validator;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subColor, fontWeight: FontWeight.w700),
        filled: true,
        fillColor: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _HomeServicesPageState._headerBlue, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
      ),
    );
  }
}

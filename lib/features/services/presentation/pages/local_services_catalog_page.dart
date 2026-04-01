import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';

class LodgingServicesPage extends StatelessWidget {
  const LodgingServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LocalServicesCatalogPage(
      config: _LocalCatalogConfig(
        title: 'Hebergement',
        heroTitle: 'Lieux de repos',
        heroSubtitle: 'Hotel, auberge, residence et maison d accueil.',
        collection: 'rapid_lodgings',
        addTitle: 'Ajouter un lieu de repos',
        emptyTitle: 'Aucun hebergement disponible',
        emptySubtitle: 'Ajoutez le premier lieu de repos pour lancer la section.',
        locationHint: 'Quartier, avenue, commune',
        priceHint: 'Prix / nuit ou tarif',
        icon: Icons.hotel_rounded,
        accent: Color(0xFF8E24AA),
        allowGallery: true,
        typeOptions: [
          'Hotel',
          'Auberge',
          'Residence',
          'Maison d accueil',
          'Guest house',
        ],
      ),
    );
  }
}

class LivingServicesPage extends StatelessWidget {
  const LivingServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LocalServicesCatalogPage(
      config: _LocalCatalogConfig(
        title: 'Vivre',
        heroTitle: 'Services du quotidien',
        heroSubtitle: 'Boutique, alimentation, cabine d utilite et plus.',
        collection: 'rapid_living_services',
        addTitle: 'Ajouter un service',
        emptyTitle: 'Aucun service disponible',
        emptySubtitle: 'Ajoutez un service utile pour remplir cette section.',
        locationHint: 'Quartier, avenue, commune',
        priceHint: 'Prix, gamme ou info utile',
        icon: Icons.storefront_rounded,
        accent: Color(0xFF43A047),
        allowGallery: false,
        typeOptions: [
          'Boutique',
          'Alimentation',
          'Cabine d utilite',
          'Salon',
          'Electronique',
          'Autre',
        ],
      ),
    );
  }
}

class _LocalCatalogConfig {
  final String title;
  final String heroTitle;
  final String heroSubtitle;
  final String collection;
  final String addTitle;
  final String emptyTitle;
  final String emptySubtitle;
  final String locationHint;
  final String priceHint;
  final IconData icon;
  final Color accent;
  final bool allowGallery;
  final List<String> typeOptions;

  const _LocalCatalogConfig({
    required this.title,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.collection,
    required this.addTitle,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.locationHint,
    required this.priceHint,
    required this.icon,
    required this.accent,
    required this.allowGallery,
    required this.typeOptions,
  });
}

class _LocalServicesCatalogPage extends StatefulWidget {
  const _LocalServicesCatalogPage({required this.config});

  final _LocalCatalogConfig config;

  @override
  State<_LocalServicesCatalogPage> createState() =>
      _LocalServicesCatalogPageState();
}

class _LocalServicesCatalogPageState extends State<_LocalServicesCatalogPage> {
  final TextEditingController _qCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  List<String> _asTags(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  String _appendUrlVersion(String url, int version) {
    if (url.contains('?')) return '$url&v=$version';
    return '$url?v=$version';
  }

  Future<String> _uploadMarketImage(
    Uint8List bytes, {
    required String folder,
    required String prefix,
  }) async {
    final client = Supabase.instance.client;
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = '$folder/${prefix}_$now.jpg';
    await client.storage.from('market').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    final publicUrl = client.storage.from('market').getPublicUrl(path);
    return _appendUrlVersion(publicUrl, now);
  }

  String _formatLocationLabelFromPlacemark(
    Placemark place,
    Position position,
  ) {
    final parts = <String?>[
      place.street,
      place.subLocality,
      place.locality,
      place.administrativeArea,
    ]
        .map((value) => (value ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toList();

    if (parts.isNotEmpty) return parts.join(', ');
    return '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
  }

  Future<_LocalLocationResult?> _resolveCurrentLocation() async {
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

      return _LocalLocationResult(
        label: label,
        lat: position.latitude,
        lng: position.longitude,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de recuperer la localisation: $e')),
        );
      }
      return null;
    }
  }

  _LocalItem _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return _LocalItem(
      id: doc.id,
      name: (data['name'] ?? data['title'] ?? 'Service').toString(),
      type: (data['type'] ?? data['category'] ?? '').toString(),
      location: (data['locationLabel'] ?? data['cityLabel'] ?? '').toString(),
      lat: _asDouble(data['lat']),
      lng: _asDouble(data['lng']),
      price: (data['priceLabel'] ?? data['price'] ?? '').toString(),
      phone: (data['phone'] ?? data['phoneNumber'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      description: (data['description'] ?? data['details'] ?? '').toString(),
      imageUrl:
          (data['imageUrl'] ?? data['photoUrl'] ?? data['coverUrl'] ?? '')
              .toString(),
      galleryUrls: _asTags(data['galleryUrls'] ?? data['photos']),
      tags: _asTags(data['tags'] ?? data['amenities']),
      createdBy: (data['createdByName'] ?? '').toString(),
      createdByUid: (data['createdByUid'] ?? '').toString(),
      createdAtMs: _asInt(data['createdAtMs']),
    );
  }

  bool _matches(_LocalItem item) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = [
      item.name,
      item.type,
      item.location,
      item.price,
      item.description,
      item.tags.join(' '),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  Future<void> _launch(String raw) async {
    try {
      final ok = await launchUrl(
        Uri.parse(raw),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d ouvrir ce lien.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  Future<void> _deleteItem(_LocalItem item) async {
    try {
      await FirebaseFirestore.instance
          .collection(widget.config.collection)
          .doc(item.id)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.config.title} supprime.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur suppression: $e')),
      );
    }
  }

  Future<void> _openAddSheet({_LocalItem? existing}) async {
    final config = widget.config;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final picker = ImagePicker();
    final defaultType = existing != null &&
            config.typeOptions.contains(existing.type.trim()) &&
            existing.type.trim().isNotEmpty
        ? existing.type.trim()
        : config.typeOptions.first;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final typeCtrl = TextEditingController(text: defaultType);
    final locationCtrl = TextEditingController(text: existing?.location ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final priceCtrl = TextEditingController(text: existing?.price ?? '');
    final tagsCtrl = TextEditingController(text: existing?.tags.join(', ') ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final formKey = GlobalKey<FormState>();

    var selectedType = defaultType;
    var saving = false;
    var locating = false;
    Uint8List? coverBytes;
    final galleryBytes = <Uint8List>[];
    final existingGalleryUrls = List<String>.from(existing?.galleryUrls ?? const []);
    final existingCoverUrl = existing?.imageUrl ?? '';
    double? selectedLat = existing?.lat;
    double? selectedLng = existing?.lng;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return SafeArea(
            top: false,
            child: StatefulBuilder(
              builder: (context, setModal) {
                Future<void> pickCover() async {
                  final file = await picker.pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 85,
                  );
                  if (file == null) return;
                  final bytes = await file.readAsBytes();
                  setModal(() => coverBytes = bytes);
                }

                Future<void> pickGallery() async {
                  if (!config.allowGallery) return;
                  final files = await picker.pickMultiImage(imageQuality: 85);
                  if (files.isEmpty) return;
                  final next = <Uint8List>[];
                  for (final file in files.take(10)) {
                    next.add(await file.readAsBytes());
                  }
                  setModal(() {
                    galleryBytes
                      ..clear()
                      ..addAll(next);
                  });
                }

                Future<void> useCurrentLocation() async {
                  setModal(() => locating = true);
                  final result = await _resolveCurrentLocation();
                  if (!mounted) return;
                  setModal(() {
                    locating = false;
                    if (result != null) {
                      selectedLat = result.lat;
                      selectedLng = result.lng;
                      locationCtrl.text = result.label;
                    }
                  });
                }

                Future<void> submit() async {
                  if (saving) return;
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  if ((coverBytes == null || coverBytes!.isEmpty) &&
                      existingCoverUrl.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ajoute une photo principale.')),
                    );
                    return;
                  }
                  setModal(() => saving = true);
                  try {
                    final user = FirebaseAuth.instance.currentUser;
                    var coverUrl = existingCoverUrl;
                    if (coverBytes != null && coverBytes!.isNotEmpty) {
                      coverUrl = await _uploadMarketImage(
                        coverBytes!,
                        folder: config.collection,
                        prefix: 'cover',
                      );
                    }
                    var galleryUrls = List<String>.from(existingGalleryUrls);
                    if (config.allowGallery) {
                      if (galleryBytes.isNotEmpty) {
                        galleryUrls = <String>[];
                        for (var i = 0; i < galleryBytes.length; i++) {
                          galleryUrls.add(
                            await _uploadMarketImage(
                              galleryBytes[i],
                              folder: '${config.collection}/gallery',
                              prefix: 'gallery_$i',
                            ),
                          );
                        }
                      }
                    }
                    final payload = <String, dynamic>{
                      'name': nameCtrl.text.trim(),
                      'type': typeCtrl.text.trim(),
                      'locationLabel': locationCtrl.text.trim(),
                      'lat': selectedLat,
                      'lng': selectedLng,
                      'phone': phoneCtrl.text.trim(),
                      'email': emailCtrl.text.trim(),
                      'priceLabel': priceCtrl.text.trim(),
                      'imageUrl': coverUrl,
                      'coverUrl': coverUrl,
                      'galleryUrls': galleryUrls,
                      'description': descCtrl.text.trim(),
                      'tags': _asTags(tagsCtrl.text.trim()),
                      'createdByUid': user?.uid,
                      'createdByEmail': user?.email,
                      'createdByName': user?.displayName,
                      'updatedAt': FieldValue.serverTimestamp(),
                      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
                    };
                    if (existing == null) {
                      payload['createdAt'] = FieldValue.serverTimestamp();
                      payload['createdAtMs'] = DateTime.now().millisecondsSinceEpoch;
                      await FirebaseFirestore.instance
                          .collection(config.collection)
                          .add(payload);
                    } else {
                      await FirebaseFirestore.instance
                          .collection(config.collection)
                          .doc(existing.id)
                          .update(payload);
                    }
                    if (!mounted) return;
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          existing == null
                              ? '${config.title} ajoute.'
                              : '${config.title} mis a jour.',
                        ),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    setModal(() => saving = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur ajout: $e')),
                    );
                  }
                }

                return Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 10,
                    bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: divider),
                  ),
                  child: SingleChildScrollView(
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 46,
                              height: 4,
                              margin: const EdgeInsets.only(top: 6, bottom: 12),
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
                                  existing == null
                                      ? config.addTitle
                                      : 'Modifier ${config.title.toLowerCase()}',
                                  style: TextStyle(
                                    color: text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: saving
                                    ? null
                                    : () => Navigator.pop(sheetContext),
                                icon: Icon(Icons.close, color: sub),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: config.typeOptions.map((option) {
                              final selected = selectedType == option;
                              return ChoiceChip(
                                label: Text(option),
                                selected: selected,
                                selectedColor: config.accent,
                                labelStyle: TextStyle(
                                  color: selected ? Colors.white : text,
                                  fontWeight: FontWeight.w700,
                                ),
                                onSelected: (_) {
                                  setModal(() => selectedType = option);
                                  typeCtrl.text = option;
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Photo principale',
                            style: TextStyle(
                              color: text,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: saving ? null : pickCover,
                            icon: const Icon(Icons.photo_camera_back_outlined),
                            label: Text(
                              coverBytes == null
                                  ? existingCoverUrl.trim().isEmpty
                                      ? 'Uploader une photo'
                                      : 'Changer la photo'
                                  : 'Changer la photo',
                            ),
                          ),
                          if (coverBytes != null) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.memory(
                                coverBytes!,
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ] else if (existingCoverUrl.trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _cover(
                              existingCoverUrl,
                              config.icon,
                              config.accent,
                              150,
                            ),
                          ],
                          if (config.allowGallery) ...[
                            const SizedBox(height: 14),
                            Text(
                              'Catalogue photos',
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: saving ? null : pickGallery,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: Text(
                                galleryBytes.isEmpty
                                    ? existingGalleryUrls.isEmpty
                                        ? 'Ajouter plusieurs photos'
                                        : 'Remplacer les photos'
                                    : '${galleryBytes.length} photo(s) choisie(s)',
                              ),
                            ),
                            if (galleryBytes.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 82,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: galleryBytes.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.memory(
                                        galleryBytes[index],
                                        width: 82,
                                        height: 82,
                                        fit: BoxFit.cover,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                            if (galleryBytes.isEmpty &&
                                existingGalleryUrls.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 82,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: existingGalleryUrls.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    return _cover(
                                      existingGalleryUrls[index],
                                      config.icon,
                                      config.accent,
                                      82,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 12),
                          _field(
                            controller: nameCtrl,
                            label: 'Nom',
                            text: text,
                            sub: sub,
                            divider: divider,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Nom requis'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          _field(
                            controller: typeCtrl,
                            label: 'Type',
                            text: text,
                            sub: sub,
                            divider: divider,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Type requis'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          _field(
                            controller: locationCtrl,
                            label: 'Localisation',
                            hint: config.locationHint,
                            text: text,
                            sub: sub,
                            divider: divider,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Localisation requise'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: saving || locating
                                ? null
                                : useCurrentLocation,
                            icon: Icon(
                              locating
                                  ? Icons.hourglass_top_rounded
                                  : Icons.my_location_rounded,
                            ),
                            label: Text(
                              locating
                                  ? 'Localisation...'
                                  : 'Utiliser ma position',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _field(
                                  controller: phoneCtrl,
                                  label: 'Telephone',
                                  text: text,
                                  sub: sub,
                                  divider: divider,
                                  keyboardType: TextInputType.phone,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _field(
                                  controller: emailCtrl,
                                  label: 'Email',
                                  text: text,
                                  sub: sub,
                                  divider: divider,
                                  keyboardType: TextInputType.emailAddress,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _field(
                            controller: priceCtrl,
                            label: 'Prix / info',
                            hint: config.priceHint,
                            text: text,
                            sub: sub,
                            divider: divider,
                          ),
                          const SizedBox(height: 10),
                          _field(
                            controller: tagsCtrl,
                            label: 'Tags',
                            hint: 'wifi, parking, boutique, cabine...',
                            text: text,
                            sub: sub,
                            divider: divider,
                          ),
                          const SizedBox(height: 10),
                          _field(
                            controller: descCtrl,
                            label: 'Description',
                            text: text,
                            sub: sub,
                            divider: divider,
                            minLines: 4,
                            maxLines: 6,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: saving ? null : submit,
                              icon: Icon(
                                saving
                                    ? Icons.hourglass_top_rounded
                                    : Icons.add_business_rounded,
                              ),
                              label: Text(
                                saving
                                    ? 'Enregistrement...'
                                    : existing == null
                                        ? 'Publier'
                                        : 'Enregistrer',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: config.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    } finally {
      nameCtrl.dispose();
      typeCtrl.dispose();
      locationCtrl.dispose();
      phoneCtrl.dispose();
      emailCtrl.dispose();
      priceCtrl.dispose();
      tagsCtrl.dispose();
      descCtrl.dispose();
    }
  }

  void _openDetails(_LocalItem item) {
    final config = widget.config;
    final me = FirebaseAuth.instance.currentUser;
    final isOwner = me != null &&
        item.createdByUid.trim().isNotEmpty &&
        item.createdByUid.trim() == me.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(22),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 4,
                      margin: const EdgeInsets.only(top: 6, bottom: 12),
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
                          item.name,
                          style: TextStyle(
                            color: text,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: Icon(Icons.close, color: sub),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _cover(item.imageUrl, config.icon, config.accent, 180),
                  if (item.galleryUrls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 86,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: item.galleryUrls.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          return _cover(
                            item.galleryUrls[index],
                            config.icon,
                            config.accent,
                            86,
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (item.type.trim().isNotEmpty)
                        _chip(item.type.trim(), config.icon, config.accent),
                      if (item.location.trim().isNotEmpty)
                        _chip(
                          item.location.trim(),
                          Icons.location_on_outlined,
                          const Color(0xFF2D6BFF),
                        ),
                      if (item.price.trim().isNotEmpty)
                        _chip(
                          item.price.trim(),
                          Icons.payments_outlined,
                          const Color(0xFFFF8A00),
                        ),
                    ],
                  ),
                  if (item.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Description',
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.description.trim(),
                      style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: item.tags
                          .map((tag) => _tag(tag, config.accent, isDark))
                          .toList(),
                    ),
                  ],
                  if (item.createdBy.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Ajoute par ${item.createdBy.trim()}',
                      style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (isOwner) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _openAddSheet(existing: item);
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Modifier'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(sheetContext);
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) {
                                  return AlertDialog(
                                    title: const Text('Supprimer la publication'),
                                    content: Text(
                                      'Voulez-vous vraiment supprimer ${item.name} ?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(
                                          dialogContext,
                                          false,
                                        ),
                                        child: const Text('Annuler'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(
                                          dialogContext,
                                          true,
                                        ),
                                        child: const Text(
                                          'Supprimer',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                              if (confirmed != true) return;
                              await _deleteItem(item);
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                            label: const Text(
                              'Supprimer',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (item.phone.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _launch('tel:${item.phone.trim()}');
                        },
                        icon: const Icon(Icons.call_rounded),
                        label: Text('Appeler ${item.phone.trim()}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: config.accent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  if (item.email.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _launch('mailto:${item.email.trim()}');
                        },
                        icon: const Icon(Icons.email_outlined),
                        label: Text(item.email.trim()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        title: Text(
          config.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: '${config.collection}_fab',
        onPressed: _openAddSheet,
        backgroundColor: config.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_business_rounded),
        label: Text(config.addTitle),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    config.accent,
                    config.accent.withOpacity(isDark ? 0.58 : 0.78),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(config.icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.heroTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          config.heroSubtitle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: divider),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: sub),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _qCtrl,
                      onChanged: (value) => setState(() => _q = value),
                      style: TextStyle(color: text, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: 'Rechercher',
                        hintStyle: TextStyle(color: sub),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_q.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        _qCtrl.clear();
                        setState(() => _q = '');
                      },
                      icon: Icon(Icons.close, color: sub),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(config.collection)
                  .limit(120)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Impossible de charger ${config.title.toLowerCase()}.',
                      style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items =
                    snapshot.data?.docs.map(_fromDoc).where(_matches).toList() ??
                        <_LocalItem>[];
                items.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));

                if (items.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 40, 16, 120),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: card,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: divider),
                        ),
                        child: Column(
                          children: [
                            Icon(config.icon, color: config.accent, size: 42),
                            const SizedBox(height: 14),
                            Text(
                              config.emptyTitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              config.emptySubtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: sub,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 120),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final currentUid = FirebaseAuth.instance.currentUser?.uid;
                    final isOwner = currentUid != null &&
                        item.createdByUid.trim().isNotEmpty &&
                        item.createdByUid.trim() == currentUid;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openDetails(item),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: divider),
                          ),
                          child: Row(
                            children: [
                              _cover(item.imageUrl, config.icon, config.accent, 84),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: text,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15.5,
                                      ),
                                    ),
                                    if (item.type.trim().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              item.type.trim(),
                                              style: TextStyle(
                                                color: config.accent,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          if (isOwner) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: config.accent.withOpacity(
                                                  isDark ? 0.18 : 0.10,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                'Vous',
                                                style: TextStyle(
                                                  color: config.accent,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                    if (item.location.trim().isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        item.location.trim(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: sub,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                    if (item.price.trim().isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        item.price.trim(),
                                        style: TextStyle(
                                          color: text,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: sub,
                              ),
                            ],
                          ),
                        ),
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    required Color text,
    required Color sub,
    required Color divider,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      style: TextStyle(color: text, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: sub),
        hintStyle: TextStyle(color: sub),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: sub.withOpacity(0.5)),
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _tag(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _cover(String imageUrl, IconData icon, Color accent, double size) {
    final width = size >= 160 ? double.infinity : size;
    if (imageUrl.trim().isEmpty) {
      return _coverFallback(icon, accent, size, width);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: width,
        height: size,
        child: CachedNetworkImage(
          imageUrl: imageUrl.trim(),
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: accent.withOpacity(0.10),
            alignment: Alignment.center,
            child: CircularProgressIndicator(color: accent),
          ),
          errorWidget: (_, __, ___) => _coverFallback(icon, accent, size, width),
        ),
      ),
    );
  }

  Widget _coverFallback(
    IconData icon,
    Color accent,
    double size,
    double width,
  ) {
    return Container(
      width: width,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withOpacity(0.16),
            accent.withOpacity(0.28),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: accent, size: 32),
    );
  }
}

class _LocalItem {
  final String id;
  final String name;
  final String type;
  final String location;
  final double? lat;
  final double? lng;
  final String price;
  final String phone;
  final String email;
  final String description;
  final String imageUrl;
  final List<String> galleryUrls;
  final List<String> tags;
  final String createdBy;
  final String createdByUid;
  final int createdAtMs;

  const _LocalItem({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    required this.lat,
    required this.lng,
    required this.price,
    required this.phone,
    required this.email,
    required this.description,
    required this.imageUrl,
    required this.galleryUrls,
    required this.tags,
    required this.createdBy,
    required this.createdByUid,
    required this.createdAtMs,
  });
}

class _LocalLocationResult {
  final String label;
  final double lat;
  final double lng;

  const _LocalLocationResult({
    required this.label,
    required this.lat,
    required this.lng,
  });
}

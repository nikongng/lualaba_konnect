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

class FoodServicesPage extends StatefulWidget {
  const FoodServicesPage({super.key, this.initialFilterKey = 'all'});

  final String initialFilterKey;

  @override
  State<FoodServicesPage> createState() => _FoodServicesPageState();
}

class _FoodServicesPageState extends State<FoodServicesPage> {
  static const Color _orange = Color(0xFFFF7A1A);
  static const Color _orangeDeep = Color(0xFFE86610);

  late String _filterKey = widget.initialFilterKey;
  final _qCtrl = TextEditingController();

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  String _appendUrlVersion(String url, int v) {
    if (url.contains('?')) return '$url&v=$v';
    return '$url?v=$v';
  }

  Future<String> _uploadFoodImage(
    Uint8List bytes, {
    required String folder,
  }) async {
    final client = Supabase.instance.client;
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = '$folder/$now.jpg';
    await client.storage
        .from('market')
        .uploadBinary(
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

  Future<String> _uploadCover(Uint8List bytes) async {
    return _uploadFoodImage(bytes, folder: 'food_places');
  }

  String _formatCatalogPrice(dynamic raw) {
    final price = _asDouble(raw, def: 0);
    if (price <= 0) return 'Prix non renseigne';
    if (price == price.roundToDouble()) return '${price.toInt()} FC';
    return '${price.toStringAsFixed(2)} FC';
  }

  List<_FoodCatalogItem> _catalogFromRaw(dynamic raw) {
    if (raw is! List) return const <_FoodCatalogItem>[];
    final out = <_FoodCatalogItem>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final name = (map['name'] ?? map['product'] ?? map['label'] ?? '')
          .toString()
          .trim();
      if (name.isEmpty) continue;
      final price = _asDouble(map['price'], def: 0);
      out.add(
        _FoodCatalogItem(
          name: name,
          imageUrl: (map['imageUrl'] ?? map['image'] ?? map['photoUrl'] ?? '')
              .toString()
              .trim(),
          price: price,
          priceLabel: (map['priceLabel'] ?? '').toString().trim().isNotEmpty
              ? (map['priceLabel'] ?? '').toString().trim()
              : _formatCatalogPrice(price),
        ),
      );
    }
    return out;
  }

  String _formatLocationLabelFromPlacemark(Placemark place, Position position) {
    final parts =
        <String?>[
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

  Future<_FoodLocationResult?> _resolveCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Activez la localisation pour continuer.'),
            ),
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
            const SnackBar(
              content: Text('Autorisation de localisation refusee.'),
            ),
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

      return _FoodLocationResult(
        label: label,
        lat: position.latitude,
        lng: position.longitude,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossible de recuperer la localisation: $e'),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _openAddPlaceSheet({
    String initialType = 'fast_food',
    _FoodPlace? existing,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final cityCtrl = TextEditingController(text: existing?.cityLabel ?? '');
    final etaCtrl = TextEditingController(
      text: existing != null && existing.etaLabel.trim().isNotEmpty
          ? existing.etaLabel
          : '30-45 min',
    );
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final ratingCtrl = TextEditingController(
      text: existing != null && existing.rating > 0
          ? existing.rating.toString()
          : '4.5',
    );
    final tagsCtrl = TextEditingController(
      text: existing != null ? existing.tags.join(', ') : '',
    );
    final picker = ImagePicker();
    Uint8List? coverBytes;
    final catalogDrafts = existing != null
        ? existing.catalog
              .map(
                (item) => <String, dynamic>{
                  'name': item.name,
                  'price': item.price,
                  'priceLabel': item.priceLabel,
                  'imageUrl': item.imageUrl,
                },
              )
              .toList()
        : <Map<String, dynamic>>[];

    String typeKey = existing != null && existing.type.trim().isNotEmpty
        ? existing.type
        : initialType;
    bool isOpen = existing?.isOpen ?? true;
    bool saving = false;
    bool locating = false;
    double? selectedLat;
    double? selectedLng;
    final formKey = GlobalKey<FormState>();

    Future<void> submit(StateSetter setModal) async {
      if (saving) return;
      if (!(formKey.currentState?.validate() ?? false)) return;
      if ((coverBytes == null || coverBytes!.isEmpty) &&
          (existing?.coverUrl.isEmpty ?? true)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajoute une photo de couverture.')),
        );
        return;
      }
      if (catalogDrafts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ajoute au moins un produit au catalogue.'),
          ),
        );
        return;
      }

      setModal(() => saving = true);
      try {
        final me = FirebaseAuth.instance.currentUser;
        var coverUrl = existing?.coverUrl ?? '';
        if (coverBytes != null && coverBytes!.isNotEmpty) {
          coverUrl = await _uploadCover(coverBytes!);
        }
        final rawTags = tagsCtrl.text.trim();
        final tags = rawTags.isEmpty
            ? <String>[]
            : rawTags
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
        final catalog = <Map<String, dynamic>>[];
        for (final item in catalogDrafts) {
          String imageUrl = (item['imageUrl'] ?? '').toString().trim();
          final bytes = item['imageBytes'];
          if (bytes is Uint8List && bytes.isNotEmpty) {
            imageUrl = await _uploadFoodImage(bytes, folder: 'food_catalog');
          }
          final price = _asDouble(item['price'], def: 0);
          catalog.add(<String, dynamic>{
            'name': (item['name'] ?? '').toString().trim(),
            'price': price,
            'priceLabel': _formatCatalogPrice(price),
            'imageUrl': imageUrl,
          });
        }

        final payload = <String, dynamic>{
          'name': nameCtrl.text.trim(),
          'type': typeKey,
          'coverUrl': coverUrl,
          'cityLabel': cityCtrl.text.trim(),
          'location': cityCtrl.text.trim(),
          'etaLabel': etaCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'email': emailCtrl.text.trim(),
          'rating': _asDouble(ratingCtrl.text.trim(), def: 0),
          'tags': tags,
          'isOpen': isOpen,
          'catalog': catalog,
          'products': catalog,
          if (selectedLat != null) 'lat': selectedLat,
          if (selectedLng != null) 'lng': selectedLng,
          // Creator info (who added this place from the app).
          'createdByUid': me?.uid,
          'createdByEmail': me?.email,
          'createdByName': me?.displayName,
          // Only the admin dashboard should certify a place.
          'certified': false,
          'isCertified': false,
          'certifiedAt': null,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        };
        if (existing == null) {
          payload['createdAt'] = FieldValue.serverTimestamp();
          payload['createdAtMs'] = DateTime.now().millisecondsSinceEpoch;
          await FirebaseFirestore.instance
              .collection('food_places')
              .add(payload);
        } else {
          await FirebaseFirestore.instance
              .collection('food_places')
              .doc(existing.id)
              .update(payload);
        }

        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existing == null
                  ? 'Service restaure ajoute.'
                  : 'Service restaure mis a jour.',
            ),
          ),
        );
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
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModal) {
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.55 : 0.12),
                          blurRadius: 26,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ListView(
                      controller: controller,
                      padding: EdgeInsets.only(
                        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                      ),
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
                                existing == null
                                    ? 'Ajouter un service resto'
                                    : 'Modifier le service',
                                style: TextStyle(
                                  color: text,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16.5,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(ctx),
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
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Nom requis'
                                    : null,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _Field(
                                      label: 'Localisation',
                                      controller: cityCtrl,
                                      textColor: text,
                                      subColor: sub,
                                      divider: divider,
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                          ? 'Localisation requise'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _Field(
                                      label: 'Livraison (ex: 30-45 min)',
                                      controller: etaCtrl,
                                      textColor: text,
                                      subColor: sub,
                                      divider: divider,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: saving || locating
                                      ? null
                                      : () async {
                                          setModal(() => locating = true);
                                          final result =
                                              await _resolveCurrentLocation();
                                          if (!context.mounted) return;
                                          if (result != null) {
                                            cityCtrl.text = result.label;
                                            selectedLat = result.lat;
                                            selectedLng = result.lng;
                                          }
                                          setModal(() => locating = false);
                                        },
                                  icon: locating
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.my_location_outlined),
                                  label: Text(
                                    locating
                                        ? 'Localisation...'
                                        : 'Utiliser ma position',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
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
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                          ? 'Telephone requis'
                                          : null,
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
                                      validator: (v) {
                                        final x = (v ?? '').trim();
                                        if (x.isEmpty) return 'Email requis';
                                        if (!x.contains('@')) {
                                          return 'Email invalide';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white10
                                      : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: divider),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white10
                                            : Colors.black12,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: divider),
                                      ),
                                      child: coverBytes != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: Image.memory(
                                                coverBytes!,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : existing != null &&
                                                existing.coverUrl
                                                    .trim()
                                                    .isNotEmpty
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: CachedNetworkImage(
                                                imageUrl: existing.coverUrl,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : Icon(
                                              Icons.image_outlined,
                                              color: sub,
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Couverture',
                                            style: TextStyle(
                                              color: text,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Uploader une photo',
                                            style: TextStyle(
                                              color: sub,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    IconButton(
                                      tooltip: 'Galerie',
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              final x = await picker.pickImage(
                                                source: ImageSource.gallery,
                                                imageQuality: 75,
                                              );
                                              if (x == null) return;
                                              final b = await x.readAsBytes();
                                              setModal(() => coverBytes = b);
                                            },
                                      icon: Icon(
                                        Icons.photo_library_outlined,
                                        color: sub,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Camera',
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              final x = await picker.pickImage(
                                                source: ImageSource.camera,
                                                imageQuality: 75,
                                              );
                                              if (x == null) return;
                                              final b = await x.readAsBytes();
                                              setModal(() => coverBytes = b);
                                            },
                                      icon: Icon(
                                        Icons.photo_camera_outlined,
                                        color: sub,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _Field(
                                      label: 'Note (ex: 4.5)',
                                      controller: ratingCtrl,
                                      textColor: text,
                                      subColor: sub,
                                      divider: divider,
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _TypeDropdown(
                                      value: typeKey,
                                      onChanged: saving
                                          ? null
                                          : (v) => setModal(() => typeKey = v),
                                      isDark: isDark,
                                      text: text,
                                      sub: sub,
                                      divider: divider,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                label: 'Tags (separes par virgule)',
                                controller: tagsCtrl,
                                textColor: text,
                                subColor: sub,
                                divider: divider,
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white10
                                      : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: divider),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Catalogue',
                                                style: TextStyle(
                                                  color: text,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Ajoutez image, produit et prix.',
                                                style: TextStyle(
                                                  color: sub,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: saving
                                              ? null
                                              : () async {
                                                  final created =
                                                      await _openAddCatalogItemDialog();
                                                  if (created == null) return;
                                                  setModal(
                                                    () => catalogDrafts.add(
                                                      created,
                                                    ),
                                                  );
                                                },
                                          icon: const Icon(Icons.add),
                                          label: const Text('Produit'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _orange,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if (catalogDrafts.isEmpty)
                                      Text(
                                        'Aucun produit ajoute pour le moment.',
                                        style: TextStyle(
                                          color: sub,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      )
                                    else
                                      ...List.generate(catalogDrafts.length, (
                                        index,
                                      ) {
                                        final item = catalogDrafts[index];
                                        final imageBytes =
                                            item['imageBytes'] as Uint8List?;
                                        final imageUrl =
                                            (item['imageUrl'] ?? '')
                                                .toString()
                                                .trim();
                                        return Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.black.withOpacity(0.12)
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            border: Border.all(color: divider),
                                          ),
                                          child: Row(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: imageBytes != null
                                                    ? Image.memory(
                                                        imageBytes,
                                                        width: 56,
                                                        height: 56,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : imageUrl.isNotEmpty
                                                    ? CachedNetworkImage(
                                                        imageUrl: imageUrl,
                                                        width: 56,
                                                        height: 56,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : Container(
                                                        width: 56,
                                                        height: 56,
                                                        color: isDark
                                                            ? Colors.white10
                                                            : Colors.black12,
                                                        child: Icon(
                                                          Icons
                                                              .fastfood_outlined,
                                                          color: sub,
                                                        ),
                                                      ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      (item['name'] ?? '')
                                                          .toString(),
                                                      style: TextStyle(
                                                        color: text,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      _formatCatalogPrice(
                                                        item['price'],
                                                      ),
                                                      style: const TextStyle(
                                                        color: _orange,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Modifier',
                                                onPressed: saving
                                                    ? null
                                                    : () async {
                                                        final updated =
                                                            await _openAddCatalogItemDialog(
                                                              existing: item,
                                                            );
                                                        if (updated == null) {
                                                          return;
                                                        }
                                                        setModal(
                                                          () =>
                                                              catalogDrafts[index] =
                                                                  updated,
                                                        );
                                                      },
                                                icon: Icon(
                                                  Icons.edit_outlined,
                                                  color: sub,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Supprimer',
                                                onPressed: saving
                                                    ? null
                                                    : () => setModal(
                                                        () => catalogDrafts
                                                            .removeAt(index),
                                                      ),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              SwitchListTile.adaptive(
                                value: isOpen,
                                activeColor: _orange,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'Ouvert',
                                  style: TextStyle(
                                    color: text,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  'Affiche OUVERT sur la carte',
                                  style: TextStyle(
                                    color: sub,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onChanged: saving
                                    ? null
                                    : (v) => setModal(() => isOpen = v),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () => submit(setModal),
                                  icon: saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Icon(
                                          existing == null
                                              ? Icons.add
                                              : Icons.save_outlined,
                                          color: Colors.white,
                                        ),
                                  label: Text(
                                    saving
                                        ? (existing == null
                                              ? 'Ajout...'
                                              : 'Enregistrement...')
                                        : (existing == null
                                              ? 'Ajouter'
                                              : 'Enregistrer'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _orange,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
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
            },
          ),
        );
      },
    );

    nameCtrl.dispose();
    cityCtrl.dispose();
    etaCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    ratingCtrl.dispose();
    tagsCtrl.dispose();
  }

  Future<Map<String, dynamic>?> _openAddCatalogItemDialog({
    Map<String, dynamic>? existing,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final nameCtrl = TextEditingController(
      text: (existing?['name'] ?? '').toString(),
    );
    final priceCtrl = TextEditingController(
      text: _asDouble(existing?['price'], def: 0) > 0
          ? '${_asDouble(existing?['price'], def: 0)}'
          : '',
    );
    final picker = ImagePicker();
    Uint8List? imageBytes = existing?['imageBytes'] as Uint8List?;
    String imageUrl = (existing?['imageUrl'] ?? existing?['image'] ?? '')
        .toString()
        .trim();
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModal) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: divider),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.55 : 0.12),
                        blurRadius: 26,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          existing == null
                              ? 'Ajouter un produit'
                              : 'Modifier le produit',
                          style: TextStyle(
                            color: text,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white10
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: divider),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.black12,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: divider),
                                ),
                                child: imageBytes != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.memory(
                                          imageBytes!,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : imageUrl.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: CachedNetworkImage(
                                          imageUrl: imageUrl,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Icon(Icons.fastfood_outlined, color: sub),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Image du produit',
                                      style: TextStyle(
                                        color: text,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Ajoutez une photo claire du produit.',
                                      style: TextStyle(
                                        color: sub,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Galerie',
                                onPressed: () async {
                                  final x = await picker.pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 75,
                                  );
                                  if (x == null) return;
                                  final b = await x.readAsBytes();
                                  setModal(() {
                                    imageBytes = b;
                                    imageUrl = '';
                                  });
                                },
                                icon: Icon(
                                  Icons.photo_library_outlined,
                                  color: sub,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          label: 'Produit',
                          controller: nameCtrl,
                          textColor: text,
                          subColor: sub,
                          divider: divider,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Produit requis'
                              : null,
                        ),
                        const SizedBox(height: 10),
                        _Field(
                          label: 'Prix',
                          controller: priceCtrl,
                          textColor: text,
                          subColor: sub,
                          divider: divider,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return 'Prix requis';
                            return _asDouble(value, def: -1) < 0
                                ? 'Prix invalide'
                                : null;
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (!(formKey.currentState?.validate() ?? false)) {
                                return;
                              }
                              if (imageBytes == null && imageUrl.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Ajoute une image pour ce produit.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final price = _asDouble(
                                priceCtrl.text.trim(),
                                def: 0,
                              );
                              Navigator.of(ctx).pop(<String, dynamic>{
                                'name': nameCtrl.text.trim(),
                                'price': price,
                                'priceLabel': _formatCatalogPrice(price),
                                'imageUrl': imageUrl,
                                'imageBytes': imageBytes,
                              });
                            },
                            icon: const Icon(
                              Icons.save_outlined,
                              color: Colors.white,
                            ),
                            label: Text(
                              existing == null
                                  ? 'Ajouter au catalogue'
                                  : 'Mettre a jour',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _orange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
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

    nameCtrl.dispose();
    priceCtrl.dispose();
    return result;
  }

  void _showCatalogSheet(_FoodPlace p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final div = isDark ? Colors.white12 : Colors.black12;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: DraggableScrollableSheet(
            initialChildSize: 0.76,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            expand: false,
            builder: (context, controller) {
              return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: div),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.55 : 0.12),
                      blurRadius: 26,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Text(
                      'Catalogue',
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${p.name} • ${p.isOpen ? 'Ouvert' : 'Ferme'}',
                      style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    if (p.catalog.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: Center(
                          child: Text(
                            'Aucun produit dans le catalogue pour le moment.',
                            style: TextStyle(
                              color: sub,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ...p.catalog.map((item) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white10
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: div),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: item.imageUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: item.imageUrl,
                                        width: 72,
                                        height: 72,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        width: 72,
                                        height: 72,
                                        color: isDark
                                            ? Colors.white10
                                            : Colors.black12,
                                        child: Icon(
                                          Icons.fastfood_outlined,
                                          color: sub,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: TextStyle(
                                        color: text,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.priceLabel,
                                      style: const TextStyle(
                                        color: _orange,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _launchOrSnack(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Impossible d’ouvrir.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  void _showContactSheet(_FoodPlace p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final div = isDark ? Colors.white12 : Colors.black12;
    final me = FirebaseAuth.instance.currentUser;
    final isOwner =
        me != null &&
        p.ownerUid.trim().isNotEmpty &&
        p.ownerUid.trim() == me.uid;

    final phone = p.phone.trim();
    final email = p.email.trim();

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
              border: Border.all(color: div),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.55 : 0.12),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
              ],
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
                    backgroundImage: p.coverUrl.isNotEmpty
                        ? CachedNetworkImageProvider(p.coverUrl)
                        : null,
                    child: p.coverUrl.isEmpty
                        ? const Icon(Icons.storefront_outlined)
                        : null,
                  ),
                  title: Text(
                    p.name,
                    style: TextStyle(color: text, fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    'Contacter • ${p.isOpen ? 'Ouvert' : 'Ferme'}',
                    style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                  ),
                ),
                if (isOwner) ...[
                  Divider(height: 1, color: div),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined, color: _orange),
                    title: Text(
                      'Modifier',
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      'Mettre a jour cette publication',
                      style: TextStyle(color: sub),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openAddPlaceSheet(existing: p, initialType: p.type);
                    },
                  ),
                  Divider(height: 1, color: div),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    title: const Text(
                      'Supprimer',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      'Retirer cette publication',
                      style: TextStyle(color: sub),
                    ),
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Supprimer la publication'),
                          content: const Text(
                            'Cette publication sera retiree definitivement.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Annuler'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text(
                                'Supprimer',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true || !mounted) return;
                      Navigator.pop(ctx);
                      await _deletePlace(p);
                    },
                  ),
                ],
                Divider(height: 1, color: div),
                ListTile(
                  leading: const Icon(Icons.menu_book_rounded),
                  title: Text(
                    'Voir catalogue',
                    style: TextStyle(color: text, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    p.catalog.isEmpty
                        ? 'Aucun produit renseigne'
                        : '${p.catalog.length} produit(s) disponible(s)',
                    style: TextStyle(color: sub),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCatalogSheet(p);
                  },
                ),
                Divider(height: 1, color: div),
                ListTile(
                  leading: const Icon(Icons.call_outlined),
                  title: Text(
                    'Appeler',
                    style: TextStyle(color: text, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    phone.isEmpty ? 'Numero non fourni' : phone,
                    style: TextStyle(color: sub),
                  ),
                  enabled: phone.isNotEmpty,
                  onTap: phone.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _launchOrSnack(Uri.parse('tel:$phone'));
                        },
                ),
                Divider(height: 1, color: div),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(
                    'Envoyer un email',
                    style: TextStyle(color: text, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    email.isEmpty ? 'Email non fourni' : email,
                    style: TextStyle(color: sub),
                  ),
                  enabled: email.isNotEmpty,
                  onTap: email.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _launchOrSnack(Uri.parse('mailto:$email'));
                        },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deletePlace(_FoodPlace place) async {
    try {
      await FirebaseFirestore.instance
          .collection('food_places')
          .doc(place.id)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Publication supprimee.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Suppression impossible: $e')));
    }
  }

  double _asDouble(dynamic v, {double def = 0}) {
    if (v == null) return def;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? def;
  }

  bool _asBool(dynamic v) =>
      v == true || v == 1 || v == '1' || v == 'true' || v == 'True';

  List<String> _asTags(dynamic v) {
    if (v is List) return List<String>.from(v.map((e) => e.toString()));
    return const [];
  }

  _FoodPlace _fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    final eta = (d['etaLabel'] ?? d['eta'] ?? '').toString().trim();
    final etaMin = d['etaMin'];
    final etaMax = d['etaMax'];
    final etaLabel = eta.isNotEmpty
        ? eta
        : (etaMin is num && etaMax is num)
        ? '${etaMin.toInt()}-${etaMax.toInt()} min'
        : '';

    return _FoodPlace(
      id: doc.id,
      name: (d['name'] ?? d['title'] ?? 'Restaurant').toString(),
      type: (d['type'] ?? d['category'] ?? '')
          .toString(), // restaurants, fast_food, delivery
      coverUrl: (d['coverUrl'] ?? d['imageUrl'] ?? d['photoUrl'] ?? '')
          .toString(),
      cityLabel: (d['cityLabel'] ?? d['location'] ?? d['city'] ?? '')
          .toString(),
      isOpen: _asBool(d['isOpen'] ?? d['open'] ?? d['opened']),
      certified: _asBool(d['certified'] ?? d['isCertified']),
      rating: _asDouble(d['rating'], def: 0),
      etaLabel: etaLabel,
      tags: _asTags(d['tags']),
      phone: (d['phone'] ?? d['phoneNumber'] ?? '').toString(),
      email: (d['email'] ?? '').toString(),
      ownerUid: (d['createdByUid'] ?? '').toString(),
      catalog: _catalogFromRaw(d['catalog'] ?? d['menu'] ?? d['products']),
    );
  }

  String _typeLabel(String t) {
    final x = t.trim().toLowerCase();
    if (x == 'restaurants' || x == 'restaurant') return 'RESTAURANT';
    if (x == 'fast_food' || x == 'fastfood' || x == 'fast-food') {
      return 'FAST-FOOD';
    }
    if (x == 'delivery' || x == 'livraison') return 'LIVRAISON';
    return x.isEmpty ? '' : x.toUpperCase();
  }

  bool _matchesFilter(_FoodPlace p) {
    if (_filterKey == 'all') return true;
    return p.type.trim().toLowerCase() == _filterKey;
  }

  bool _matchesQuery(_FoodPlace p, String q) {
    if (q.isEmpty) return true;
    final hay = [
      p.name,
      p.cityLabel,
      p.type,
      ...p.catalog.map((item) => item.name),
      ...p.tags,
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;

    final searchFill = isDark
        ? const Color(0xFF0F1A20)
        : Colors.white.withOpacity(0.96);
    final searchText = isDark
        ? const Color(0xFFE9EDF0)
        : const Color(0xFF111827);
    final searchHint = isDark
        ? const Color(0xFFAAB2B8)
        : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton(
        backgroundColor: _orange,
        onPressed: () => _openAddPlaceSheet(initialType: 'fast_food'),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 180,
            elevation: 0,
            backgroundColor: _orange,
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Resto & Fast-Food',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_orange, _orangeDeep],
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(110),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: searchFill,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withOpacity(isDark ? 0.10 : 0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _qCtrl,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          color: searchText,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Rechercher...',
                          hintStyle: TextStyle(
                            color: searchHint,
                            fontWeight: FontWeight.w700,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: searchHint,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _FoodFilterRow(
                      isDark: isDark,
                      selectedKey: _filterKey,
                      onSelected: (k) => setState(() => _filterKey = k),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            sliver: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('food_places')
                  .limit(60)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _skeletonCard(isDark),
                        const SizedBox(height: 14),
                        _skeletonCard(isDark),
                      ],
                    ),
                  );
                }
                if (snap.hasError) {
                  return SliverToBoxAdapter(
                    child: Center(
                      child: Text(
                        'Erreur: ${snap.error}',
                        style: TextStyle(
                          color: sub,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }

                final docs =
                    snap.data?.docs ?? const <QueryDocumentSnapshot<Object?>>[];
                final q = _qCtrl.text.trim().toLowerCase();
                final items = <_FoodPlace>[];
                for (final d in docs) {
                  final p = _fromDoc(d);
                  if (!_matchesFilter(p)) continue;
                  if (!_matchesQuery(p, q)) continue;
                  items.add(p);
                }

                if (items.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 36),
                      child: Center(
                        child: Text(
                          'Aucun resultat',
                          style: TextStyle(
                            color: sub,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final p = items[i];
                    return TweenAnimationBuilder<double>(
                      key: ValueKey('${_filterKey}_${p.id}'),
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(
                        milliseconds: 420 + (i.clamp(0, 10) * 35),
                      ),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - v)),
                          child: child,
                        ),
                      ),
                      child: _FoodCard(
                        isDark: isDark,
                        card: card,
                        text: text,
                        sub: sub,
                        divider: divider,
                        place: p,
                        typeLabel: _typeLabel(p.type),
                        onViewCatalog: () => _showCatalogSheet(p),
                        onContact: () => _showContactSheet(p),
                      ),
                    );
                  }, childCount: items.length),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }

  Widget _skeletonCard(bool isDark) {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFE9ECEF),
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}

class _FoodFilterRow extends StatelessWidget {
  const _FoodFilterRow({
    required this.isDark,
    required this.selectedKey,
    required this.onSelected,
  });

  final bool isDark;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  static const _filters = [
    ('all', 'Tout', null),
    ('restaurants', 'Restaurants', Icons.restaurant_rounded),
    ('fast_food', 'Fast-Food', Icons.fastfood_rounded),
    ('delivery', 'Livraison', Icons.delivery_dining_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final f = _filters[i];
          final selected = selectedKey == f.$1;

          final bg = selected
              ? (isDark ? const Color(0xFF111B21) : Colors.white)
              : (isDark
                    ? Colors.black.withOpacity(0.20)
                    : Colors.black.withOpacity(0.16));
          final fg = selected
              ? (isDark ? Colors.white : const Color(0xFFB84E00))
              : Colors.white;
          final border = selected
              ? Colors.white.withOpacity(isDark ? 0.14 : 0.22)
              : Colors.transparent;

          return GestureDetector(
            onTap: () => onSelected(f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
                boxShadow: selected && !isDark
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.10),
                          blurRadius: 14,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (f.$3 != null) ...[
                    Icon(f.$3, size: 18, color: fg),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    f.$2,
                    style: TextStyle(
                      color: fg,
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

class _FoodCard extends StatelessWidget {
  const _FoodCard({
    required this.isDark,
    required this.card,
    required this.text,
    required this.sub,
    required this.divider,
    required this.place,
    required this.typeLabel,
    required this.onViewCatalog,
    required this.onContact,
  });

  final bool isDark;
  final Color card;
  final Color text;
  final Color sub;
  final Color divider;
  final _FoodPlace place;
  final String typeLabel;
  final VoidCallback onViewCatalog;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final openPillBg = place.isOpen
        ? const Color(0xFF27AE60)
        : const Color(0xFF5C6B78);
    final openText = place.isOpen ? 'OUVERT' : 'FERME';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 150,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (place.coverUrl.trim().isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: place.coverUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 220),
                      errorWidget: (_, __, ___) => Container(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                    )
                  else
                    Container(color: isDark ? Colors.white10 : Colors.black12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.00),
                          Colors.black.withOpacity(0.28),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: openPillBg,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: openPillBg.withOpacity(0.25),
                            blurRadius: 14,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Text(
                        openText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  if (place.certified)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D6BFF),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: card, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2D6BFF).withOpacity(0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Row(
                      children: [
                        if (place.rating > 0)
                          _InfoPill(
                            bg: Colors.white.withOpacity(0.96),
                            icon: Icons.star_rounded,
                            iconColor: const Color(0xFFFFC107),
                            text: place.rating.toStringAsFixed(1),
                          ),
                        if (place.rating > 0 && place.etaLabel.isNotEmpty)
                          const SizedBox(width: 8),
                        if (place.etaLabel.isNotEmpty)
                          _InfoPill(
                            bg: Colors.white.withOpacity(0.96),
                            icon: Icons.schedule_rounded,
                            iconColor: const Color(0xFF6B7280),
                            text: place.etaLabel,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: text,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (typeLabel.isNotEmpty)
                        Text(
                          typeLabel,
                          style: TextStyle(
                            color: sub,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (place.cityLabel.trim().isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: const Color(
                            0xFFB84E00,
                          ).withOpacity(isDark ? 0.90 : 0.85),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            place.cityLabel,
                            style: TextStyle(
                              color: sub,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: place.isOpen
                              ? const Color(0x1627AE60)
                              : (isDark
                                    ? Colors.white10
                                    : const Color(0x145C6B78)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: place.isOpen
                                ? const Color(0x3327AE60)
                                : (isDark
                                      ? Colors.white12
                                      : const Color(0x225C6B78)),
                          ),
                        ),
                        child: Text(
                          place.isOpen
                              ? 'Ouvert maintenant'
                              : 'Ferme actuellement',
                          style: TextStyle(
                            color: place.isOpen ? const Color(0xFF27AE60) : sub,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0x22FF7A1A)
                              : const Color(0x14FF7A1A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0x33FF7A1A)),
                        ),
                        child: Text(
                          '${place.catalog.length} produit(s)',
                          style: const TextStyle(
                            color: _FoodServicesPageState._orange,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (place.tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final t in place.tags.take(2))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0x22FF7A1A)
                                  : const Color(0x14FF7A1A),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0x33FF7A1A),
                              ),
                            ),
                            child: Text(
                              t,
                              style: const TextStyle(
                                color: _FoodServicesPageState._orange,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: onViewCatalog,
                      icon: const Icon(Icons.menu_book_rounded),
                      label: const Text('Voir catalogue'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB84E00),
                        side: BorderSide(
                          color: const Color(0xFFB84E00).withOpacity(0.28),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: onContact,
                      icon: const Icon(
                        Icons.call_outlined,
                        color: Colors.white,
                      ),
                      label: const Text('Contacter'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D6BFF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.bg,
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final Color bg;
  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeDropdown extends StatelessWidget {
  const _TypeDropdown({
    required this.value,
    required this.onChanged,
    required this.isDark,
    required this.text,
    required this.sub,
    required this.divider,
  });

  final String value;
  final ValueChanged<String>? onChanged;
  final bool isDark;
  final Color text;
  final Color sub;
  final Color divider;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Type',
        labelStyle: TextStyle(color: sub, fontWeight: FontWeight.w700),
        filled: true,
        fillColor: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: _FoodServicesPageState._orange,
            width: 1.2,
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          iconEnabledColor: sub,
          dropdownColor: isDark ? const Color(0xFF111B21) : Colors.white,
          style: TextStyle(color: text, fontWeight: FontWeight.w800),
          onChanged: onChanged == null ? null : (v) => onChanged!(v ?? value),
          items: const [
            DropdownMenuItem(value: 'restaurants', child: Text('Restaurants')),
            DropdownMenuItem(value: 'fast_food', child: Text('Fast-Food')),
            DropdownMenuItem(value: 'delivery', child: Text('Livraison')),
          ],
        ),
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
          borderSide: const BorderSide(
            color: _FoodServicesPageState._orange,
            width: 1.2,
          ),
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

class _FoodPlace {
  final String id;
  final String name;
  final String type;
  final String coverUrl;
  final String cityLabel;
  final bool isOpen;
  final bool certified;
  final double rating;
  final String etaLabel;
  final List<String> tags;
  final String phone;
  final String email;
  final String ownerUid;
  final List<_FoodCatalogItem> catalog;

  const _FoodPlace({
    required this.id,
    required this.name,
    required this.type,
    required this.coverUrl,
    required this.cityLabel,
    required this.isOpen,
    required this.certified,
    required this.rating,
    required this.etaLabel,
    required this.tags,
    required this.phone,
    required this.email,
    required this.ownerUid,
    required this.catalog,
  });
}

class _FoodCatalogItem {
  final String name;
  final String imageUrl;
  final double price;
  final String priceLabel;

  const _FoodCatalogItem({
    required this.name,
    required this.imageUrl,
    required this.price,
    required this.priceLabel,
  });
}

class _FoodLocationResult {
  final String label;
  final double lat;
  final double lng;

  const _FoodLocationResult({
    required this.label,
    required this.lat,
    required this.lng,
  });
}

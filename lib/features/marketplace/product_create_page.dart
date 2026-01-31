import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'categories.dart';

class ProductCreatePage extends StatefulWidget {
  final Map<String, dynamic>? product;
  final String? docId;
  const ProductCreatePage({super.key, this.product, this.docId});

  @override
  State<ProductCreatePage> createState() => _ProductCreatePageState();
}

class _ProductCreatePageState extends State<ProductCreatePage> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _stockCtrl = TextEditingController(text: '1');
  final TextEditingController _locationCtrl = TextEditingController();
  final TextEditingController _lotSizeCtrl = TextEditingController(text: '1');

  final List<Uint8List> _images = [];
  static const int _maxImages = 6;
  static const int _maxImageBytes = 2 * 1024 * 1024; // 2 MB
  bool _uploading = false;
  double _uploadProgress = 0;

  String _currency = 'USD';
  late String _selectedMainCategory = Categories.mainCategories().first;
  String? _selectedSubCategory;
  String _visibility = 'Tout le monde';
  String _etat = 'neuf';
  bool _byLot = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _nameCtrl.text = p['name'] ?? '';
      _descCtrl.text = p['desc'] ?? '';
      _priceCtrl.text = (p['price'] ?? '').toString();
      _stockCtrl.text = (p['stock'] ?? '').toString();
      _locationCtrl.text = p['location'] ?? '';
      _lotSizeCtrl.text = (p['lotSize'] ?? '').toString();
      _currency = p['currency'] ?? _currency;
      final cat = p['category'] as String?;
      if (cat != null && cat.isNotEmpty) {
        bool found = false;
        Categories.map.forEach((main, subs) {
          if (main.toLowerCase() == cat.toLowerCase()) {
            _selectedMainCategory = main;
            _selectedSubCategory = null;
            found = true;
          }
          for (final s in subs) {
            if (s.toLowerCase() == cat.toLowerCase()) {
              _selectedMainCategory = main;
              _selectedSubCategory = s;
              found = true;
            }
          }
        });
        if (!found) {
          _selectedMainCategory = Categories.mainCategories().first;
          _selectedSubCategory = null;
        }
      }
      // Restore visibility label for the dropdown UI.
      final visRaw = p['visibilityLabel'] ?? p['visibility'];
      if (visRaw != null) {
        final s = visRaw is String ? visRaw : visRaw.toString();
        if (s == 'public' || s.toLowerCase() == 'tout le monde') {
          _visibility = 'Tout le monde';
        } else if (s == 'contacts' || s.toLowerCase().contains('contact')) {
          _visibility = 'Mes contacts Uniquement';
        } else {
          _visibility = s;
        }
      }
      _etat = p['etat'] ?? _etat;
    }
  }

  @override
  void dispose() {
    for (var c in [_nameCtrl, _descCtrl, _priceCtrl, _stockCtrl, _locationCtrl, _lotSizeCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // --- LOGIQUE TECHNIQUE (COMPRESSION & UPLOAD) ---

  Future<Uint8List> _compressImage(Uint8List list) async {
    try {
      var result = await FlutterImageCompress.compressWithList(
        list,
        minHeight: 1080,
        minWidth: 1080,
        quality: 85,
      );
      return Uint8List.fromList(result);
    } catch (e) {
      debugPrint('Compression failed: $e');
      return list;
    }
  }

  Future<void> _submit() async {
    if (_uploading) return;

    final existingImages = (widget.product != null) ? (widget.product!['images'] as List?) : null;
    final bool hasExistingImages = (widget.docId != null) && (existingImages != null) && existingImages.isNotEmpty;
    if (!_formKey.currentState!.validate() || (_images.isEmpty && !hasExistingImages)) {
      _notify("Infos manquantes ou photos oubliées", isError: true);
      return;
    }

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final ownerId = user?.uid ?? 'anon';
      final productId = DateTime.now().millisecondsSinceEpoch.toString();
      List<String> imageUrls = [];

      final storage = Supabase.instance.client.storage.from('market');

      // If editing and no new images selected, preserve existing images
      if ((widget.docId != null) && _images.isEmpty) {
        final imgs = (widget.product != null) ? (widget.product!['images'] as List?) : null;
        imageUrls = List<String>.from(imgs ?? []);
      } else {
        for (int i = 0; i < _images.length; i++) {
          Uint8List compressedData;
          try {
            compressedData = await _compressImage(_images[i]);
          } catch (e) {
            debugPrint('Compression for upload failed: $e');
            compressedData = _images[i];
          }
          final path = 'products/$ownerId/${productId}_$i.jpg';
          try {
            await storage.uploadBinary(
              path,
              compressedData,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            );
            imageUrls.add(storage.getPublicUrl(path));
          } catch (e) {
            debugPrint('Upload failed for $path: $e');
          }
          setState(() => _uploadProgress = (i + 1) / _images.length);
        }
      }

      final data = {
        'name': _nameCtrl.text.trim(),
        'desc': _descCtrl.text.trim(),
        'price': double.tryParse(_priceCtrl.text) ?? 0,
        'currency': _currency,
        'category': _selectedSubCategory ?? _selectedMainCategory,
        'categoryMain': _selectedMainCategory,
        'categorySub': _selectedSubCategory,
        'location': _locationCtrl.text.trim(),
        'visibility': (_visibility == 'Tout le monde') ? 'public' : 'contacts',
        'visibilityLabel': _visibility,
        'etat': _etat,
        'byLot': _byLot,
        'lotSize': int.tryParse(_lotSizeCtrl.text) ?? 1,
        'stock': int.tryParse(_stockCtrl.text) ?? 1,
        'images': imageUrls,
        'owner': ownerId,
        'sellerName': user?.displayName ?? 'Vendeur',
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (widget.docId != null) {
        await FirebaseFirestore.instance.collection('market_products').doc(widget.docId).update(data);
        _notify("Publication mise à jour !");

        // Propager la modification vers les commandes contenant cet article
        try {
          final ordersSnap = await FirebaseFirestore.instance.collection('market_orders').get();
          for (final od in ordersSnap.docs) {
            final odData = od.data();
            final items = List.from(odData['items'] ?? []);
            bool changed = false;
            final imgs = (data['images'] is List) ? List.from(data['images'] as List) : null;
            final updatedItems = items.map((it) {
              try {
                if (it['id'] == widget.docId) {
                  changed = true;
                  return {
                    ...Map<String, dynamic>.from(it),
                    'name': data['name'],
                    'price': data['price'],
                    'image': (imgs != null && imgs.isNotEmpty) ? imgs[0] : it['image'],
                  };
                }
              } catch (_) {}
              return it;
            }).toList();

            if (changed) {
              await FirebaseFirestore.instance.collection('market_orders').doc(od.id).update({'items': updatedItems});
            }
          }
        } catch (e) {
          debugPrint('Erreur propagation modification aux commandes depuis ProductCreatePage: $e');
        }
      } else {
        await FirebaseFirestore.instance.collection('market_products').add(data);
        _notify("Annonce publiée !");
      }
      Navigator.pop(context);
    } catch (e, st) {
      debugPrint('Erreur lors de la publication: $e\n$st');
      _notify("Erreur lors de la publication", isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _notify(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.teal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // --- UI COMPONENTS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120.0,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text("Vendre un article", 
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 18)),
              centerTitle: true,
            ),
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (_uploading)
            SliverToBoxAdapter(
              child: LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: Colors.grey.shade50,
                color: Colors.orange,
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(key: _formKey, child: _buildFormContent()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Galerie photos", "Vos images seront optimisées automatiquement"),
        _buildImageGallery(),
        const SizedBox(height: 30),
        _buildSectionCard("Détails principaux", [
          _customTextField(_nameCtrl, "Titre de l'article", Icons.shopping_bag_outlined, validator: (v) => v == null || v.trim().isEmpty ? 'Le titre est requis' : null),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(flex: 2, child: _customTextField(_priceCtrl, "Prix", Icons.payments_outlined, isNumeric: true, validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Le prix est requis';
                final val = double.tryParse(v.replaceAll(',', '.'));
                if (val == null || val <= 0) return 'Le prix doit être un nombre positif';
                return null;
              })),
              const SizedBox(width: 12),
              Expanded(flex: 1, child: _customDropdown(_currency, ['USD', 'FC', 'EUR'], (v) => setState(() => _currency = v!))),
            ],
          ),
        ]),
        const SizedBox(height: 25),
        _buildSectionCard("Classification", [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Catégorie', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: const Color(0xFFF5F7F9), borderRadius: BorderRadius.circular(16)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedMainCategory,
                          isExpanded: true,
                          items: Categories.mainCategories().map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (v) => setState(() {
                            _selectedMainCategory = v!;
                            final subs = Categories.subCategories(_selectedMainCategory);
                            _selectedSubCategory = (subs.isNotEmpty) ? subs.first : null;
                          }),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: const Color(0xFFF5F7F9), borderRadius: BorderRadius.circular(16)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSubCategory,
                          isExpanded: true,
                          hint: const Text('Aucune'),
                          items: (Categories.subCategories(_selectedMainCategory) ?? []).map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (Categories.subCategories(_selectedMainCategory).isEmpty) ? null : (v) => setState(() => _selectedSubCategory = v),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),
          _customTextField(_locationCtrl, "Localisation", Icons.location_on_outlined),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(child: _customLabelDropdown("État", _etat, ['neuf','Presque neuf', 'occasion', 'usé'], (v) => setState(() => _etat = v!))),
              const SizedBox(width: 14),
              Expanded(child: _customLabelDropdown("Visibilité", _visibility, ['Tout le monde', 'Mes contacts Uniquement'], (v) => setState(() => _visibility = v!))),
            ],
          ),
        ]),
        const SizedBox(height: 25),
        _buildSectionCard("Description & Stock", [
          _customTextField(_descCtrl, "Description détaillée...", Icons.notes, maxLines: 4, validator: (v) => v == null || v.trim().isEmpty ? 'La description est requise' : null),
          const SizedBox(height: 15),
          Row(
            children: [
              const Text("Vendre par lot ?", style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Switch.adaptive(
                activeColor: Colors.orange.shade800,
                value: _byLot, 
                onChanged: (v) => setState(() => _byLot = v)
              ),
            ],
          ),
          if (_byLot) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _customTextField(_lotSizeCtrl, "Taille du lot", Icons.layers, isNumeric: true, validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Taille du lot requise';
              final n = int.tryParse(v);
              if (n == null || n <= 0) return 'Doit être un entier positif';
              return null;
            }),
          ),
        ]),
        const SizedBox(height: 40),
        _buildGradientButton(),
        const SizedBox(height: 50),
      ],
    );
  }

  // --- HELPERS UI (Correction des erreurs de méthodes non définies) ---

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.black45)),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _buildSectionCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.orange.shade800)),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildImageGallery() {
    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _images.length + 1,
        itemBuilder: (context, index) {
          if (index == _images.length) {
            return GestureDetector(
              onTap: () async {
                if (_images.length >= _maxImages) {
                  _notify("Maximum $_maxImages images atteinte", isError: true);
                  return;
                }
                final f = await ImagePicker().pickImage(source: ImageSource.gallery);
                if (f != null) {
                  final bytes = await f.readAsBytes();
                  final compressed = await _compressImage(bytes);
                  if (compressed.lengthInBytes > _maxImageBytes) {
                    _notify('Image trop volumineuse (max 2MB)', isError: true);
                    return;
                  }
                  setState(() => _images.add(compressed));
                }
              },
              child: Container(
                width: 100,
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.shade100, width: 2),
                ),
                child: Icon(Icons.add_a_photo_outlined, color: Colors.orange.shade800),
              ),
            );
          }
          return Container(
            width: 100,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              image: DecorationImage(image: MemoryImage(_images[index]), fit: BoxFit.cover),
            ),
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.cancel, color: Colors.white),
                onPressed: () => setState(() => _images.removeAt(index)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _customTextField(TextEditingController ctrl, String hint, IconData icon, {bool isNumeric = false, int maxLines = 1, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: const Color(0xFFF5F7F9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _customDropdown(String value, List<String> items, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFFF5F7F9), borderRadius: BorderRadius.circular(16)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _customLabelDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(height: 8),
        _customDropdown(value, items, onChanged),
      ],
    );
  }

  Widget _buildGradientButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _uploading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _uploading ? Colors.grey : Colors.orange.shade800,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 6,
        ),
        child: _uploading
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)), const SizedBox(width: 12), const Text("Publication...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))])
          : const Text("PUBLIER L'ANNONCE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}
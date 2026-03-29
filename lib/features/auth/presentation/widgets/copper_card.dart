import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../screnns/metal_detail_page.dart';

class CopperCard extends StatefulWidget {
  const CopperCard({super.key});

  @override
  State<CopperCard> createState() => _CopperCardState();
}

class _CopperCardState extends State<CopperCard> {
  static const int _collapsedMineralCount = 2;

  final ImagePicker _picker = ImagePicker();

  String copperPrice = '---';
  String cobaltPrice = '---';
  String copperChange = '+0.00%';
  String cobaltChange = '+0.00%';
  String lastUpdate = 'Jamais';
  bool isCopperUp = true;
  bool isCobaltUp = true;
  bool isLoading = false;
  bool _identifying = false;

  Uint8List? _pickedMineralBytes;
  String _pickedMineralPath = '';
  String _identificationText = '';
  _MineralProfile? _identifiedMineral;
  String _catalogQuery = '';
  bool _catalogExpanded = false;

  final String copperUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/f/f0/NatCopper.jpg/200px-NatCopper.jpg';
  final String cobaltUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/6/62/Cobalt_ore_2.jpg/200px-Cobalt_ore_2.jpg';
  final String coltanUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/0/03/Columbite-tantalite_211144.jpg/200px-Columbite-tantalite_211144.jpg';
  final String goldUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d7/Gold_nuggets.jpg/200px-Gold_nuggets.jpg';
  final String tinUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/2/27/Cassiterite-280998.jpg/200px-Cassiterite-280998.jpg';
  final String lithiumUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b8/Spodumene-tumbled.jpg/200px-Spodumene-tumbled.jpg';
  final String manganeseUrl =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/89/Pyrolusite-Denton_Mine.jpg/200px-Pyrolusite-Denton_Mine.jpg';

  @override
  void initState() {
    super.initState();
    fetchPrices();
  }

  List<_MineralProfile> get _minerals => <_MineralProfile>[
        _MineralProfile(
          key: 'copper',
          label: 'Cuivre',
          marketLabel: copperPrice == '---' ? 'Prix en attente' : '\$$copperPrice / t',
          changeLabel: copperChange,
          isUp: isCopperUp,
          color: Colors.orange.shade800,
          history: const <double>[10, 12, 9, 15, 14, 18, 20],
          imageUrl: copperUrl,
          summary: 'Minerai clé.',
          locations: const <String>['Kolwezi', 'Fungurume', 'Kambove', 'Tenke'],
          identifiers: const <String>[
            'Couleur rouge brun a saumon',
            'Aspect metallique ou masse native',
            'Oxydation verdatre possible',
          ],
          aliases: const <String>['cuivre', 'copper', 'malachite', 'chalcopyrite'],
        ),
        _MineralProfile(
          key: 'cobalt',
          label: 'Cobalt',
          marketLabel: cobaltPrice == '---' ? 'Prix en attente' : '\$$cobaltPrice / t',
          changeLabel: cobaltChange,
          isUp: isCobaltUp,
          color: Colors.blue.shade900,
          history: const <double>[18, 17, 19, 16, 15, 14, 13],
          imageUrl: cobaltUrl,
          summary: 'Minerai strategique pour batteries, alliages et industrie chimique.',
          locations: const <String>['Kolwezi', 'Mutshatsha', 'Likasi', 'Kakanda'],
          identifiers: const <String>[
            'Teintes gris bleute a noir',
            'Souvent melange a cuivre ou nickel',
            'Eclat metallique dense',
          ],
          aliases: const <String>['cobalt', 'carrollite', 'cobaltite'],
        ),
        _MineralProfile(
          key: 'coltan',
          label: 'Coltan',
          marketLabel: 'Indice terrain eleve',
          changeLabel: '+Prospection',
          isUp: true,
          color: const Color(0xFF5D4037),
          history: const <double>[9, 10, 11, 11, 12, 13, 14],
          imageUrl: coltanUrl,
          summary: 'Source de tantale et niobium pour composants electroniques.',
          locations: const <String>['Manono', 'Kalehe', 'Masisi', 'Lubudi'],
          identifiers: const <String>[
            'Grains noirs a brun fonce',
            'Tres dense en main',
            'Souvent dans concentrats alluvionnaires',
          ],
          aliases: const <String>['coltan', 'tantalite', 'columbite'],
        ),
        _MineralProfile(
          key: 'gold',
          label: 'Or',
          marketLabel: 'Valeur refuge',
          changeLabel: '+Stable',
          isUp: true,
          color: const Color(0xFFB8860B),
          history: const <double>[11, 12, 12, 13, 14, 15, 16],
          imageUrl: goldUrl,
          summary: 'Minerai precieux exploite en filons ou alluvions.',
          locations: const <String>['Kamituga', 'Mongbwalu', 'Namoya', 'Mitwaba'],
          identifiers: const <String>[
            'Reflet jaune vif',
            'Ne rouille pas',
            'Souvent en paillettes ou veines',
          ],
          aliases: const <String>['or', 'gold', 'aurifere'],
        ),
        _MineralProfile(
          key: 'tin',
          label: 'Etain',
          marketLabel: 'Circuit fonderie',
          changeLabel: '+Demande',
          isUp: true,
          color: const Color(0xFF607D8B),
          history: const <double>[8, 8.5, 9, 9.2, 9.4, 10, 10.5],
          imageUrl: tinUrl,
          summary: 'Souvent extrait de la cassiterite pour soudure et alliages.',
          locations: const <String>['Walikale', 'Shabunda', 'Bukavu', 'Kipushi'],
          identifiers: const <String>[
            'Grains brun a noir',
            'Tres lourd pour sa taille',
            'Cristaux dans pegmatites ou alluvions',
          ],
          aliases: const <String>['etain', 'tin', 'cassiterite'],
        ),
        _MineralProfile(
          key: 'lithium',
          label: 'Lithium',
          marketLabel: 'Surveillance batterie',
          changeLabel: '+Transition',
          isUp: true,
          color: const Color(0xFF8E24AA),
          history: const <double>[7, 8, 8.2, 8.5, 9.2, 9.6, 10],
          imageUrl: lithiumUrl,
          summary: 'Observe surtout dans spodumene et pegmatites pour la chaine batterie.',
          locations: const <String>['Manono', 'Bukama', 'Mitwaba'],
          identifiers: const <String>[
            'Cristaux clairs a roses',
            'Souvent dans pegmatites granitiques',
            'Association possible avec quartz',
          ],
          aliases: const <String>['lithium', 'spodumene', 'pegmatite'],
        ),
        _MineralProfile(
          key: 'manganese',
          label: 'Manganese',
          marketLabel: 'Usage metallurgie',
          changeLabel: '+Industrie',
          isUp: true,
          color: const Color(0xFF4E342E),
          history: const <double>[6, 6.5, 7, 6.8, 7.2, 7.4, 7.9],
          imageUrl: manganeseUrl,
          summary: 'Utilise pour acier, batteries et melanges metallurgiques.',
          locations: const <String>['Kisenge', 'Dilolo', 'Sakania'],
          identifiers: const <String>[
            'Noir a gris sombre',
            'Trace noire sur roche',
            'Aspect terreux ou nodulaire',
          ],
          aliases: const <String>['manganese', 'pyrolusite', 'manganite'],
        ),
      ];

  List<_MineralProfile> get _filteredMinerals {
    final query = _catalogQuery.trim().toLowerCase();
    if (query.isEmpty) return _minerals;
    return _minerals.where((mineral) {
      final hay = [
        mineral.label,
        mineral.summary,
        ...mineral.locations,
        ...mineral.identifiers,
        ...mineral.aliases,
      ].join(' ').toLowerCase();
      return hay.contains(query);
    }).toList(growable: false);
  }

  List<_MineralProfile> get _visibleMinerals {
    final hasQuery = _catalogQuery.trim().isNotEmpty;
    if (hasQuery || _catalogExpanded || _filteredMinerals.length <= _collapsedMineralCount) {
      return _filteredMinerals;
    }
    return _filteredMinerals.take(_collapsedMineralCount).toList(growable: false);
  }

  bool get _canToggleCatalog =>
      _catalogQuery.trim().isEmpty && _filteredMinerals.length > _collapsedMineralCount;

  Future<void> fetchPrices() async {
    if (isLoading) return;
    setState(() => isLoading = true);

    final String proxyBase = (dotenv.env['METALS_PROXY_URL'] ?? '').trim();
    if (proxyBase.isEmpty) {
      debugPrint('METALS_PROXY_URL manquant (.env)');
      if (mounted) setState(() => isLoading = false);
      return;
    }

    final base = proxyBase.endsWith('/')
        ? proxyBase.substring(0, proxyBase.length - 1)
        : proxyBase;
    final url = Uri.parse('$base/metals-lme');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      final data = json.decode(response.body);
      final metals = (data is Map && data['metals'] is Map)
          ? Map<String, dynamic>.from(data['metals'] as Map)
          : (data is Map && data['data'] is Map && data['data']['metals'] is Map)
              ? Map<String, dynamic>.from(data['data']['metals'] as Map)
              : <String, dynamic>{};
      final changes = (data is Map && data['changes'] is Map)
          ? Map<String, dynamic>.from(data['changes'] as Map)
          : (data is Map && data['data'] is Map && data['data']['changes'] is Map)
              ? Map<String, dynamic>.from(data['data']['changes'] as Map)
              : <String, dynamic>{};

      final now = DateTime.now();
      var updateLabel =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      if (data is Map && data['asOf'] is String && (data['asOf'] as String).trim().isNotEmpty) {
        updateLabel = (data['asOf'] as String).trim();
      }

      if (!mounted) return;
      setState(() {
        final copperValue = _asNum(metals['copper']);
        final cobaltValue = _asNum(metals['cobalt']);
        final copperPct = _percentString(changes['copper'] ?? metals['copperChange']);
        final cobaltPct = _percentString(changes['cobalt'] ?? metals['cobaltChange']);

        if (copperValue != null) copperPrice = _formatNumber(copperValue);
        if (cobaltValue != null) cobaltPrice = _formatNumber(cobaltValue);

        copperChange = copperPct;
        cobaltChange = cobaltPct;
        isCopperUp = !copperPct.trim().startsWith('-');
        isCobaltUp = !cobaltPct.trim().startsWith('-');
        lastUpdate = updateLabel;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Erreur API Metals: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  num? _asNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  String _percentString(dynamic value) {
    final number = _asNum(value);
    if (number == null) return '+0.00%';
    final fixed = number.toStringAsFixed(2);
    return number >= 0 ? '+$fixed%' : '$fixed%';
  }

  String _formatNumber(num value) {
    return value.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match match) => '${match[1]} ',
    );
  }

  Future<void> _pickMineralPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1800,
        imageQuality: 92,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedMineralBytes = bytes;
        _pickedMineralPath = picked.path;
        _identificationText = '';
        _identifiedMineral = null;
      });
    } catch (e) {
      _showSnack('Impossible de charger la photo: $e');
    }
  }

  Future<void> _identifyMineralFromPhoto() async {
    if (_pickedMineralBytes == null || _pickedMineralBytes!.isEmpty) {
      _showSnack('Prenez ou importez une photo avant l identification.');
      return;
    }

    final apiKey = dotenv.maybeGet('GEMINI_API_KEY') ?? '';
    if (apiKey.isEmpty) {
      _showSnack('GEMINI_API_KEY manquant pour l identification.');
      return;
    }

    setState(() => _identifying = true);
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      final prompt = [
        'Tu es un assistant geologique pour le Grand Katanga.',
        'Analyse la photo de minerai envoyee.',
        'Reponds en francais simple.',
        'Donne une identification visuelle probable, jamais une certitude de laboratoire.',
        'Liste: minerai probable, niveau de confiance sur 100, indices visuels, risques de confusion,',
        'zones de RDC ou il est souvent observe, conseil de verification terrain.',
        'Si la photo est insuffisante, dis-le clairement.',
      ].join('\n');

      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart(_guessMimeType(_pickedMineralPath), _pickedMineralBytes!),
        ]),
      ]);

      final text = response.text?.trim();
      if (!mounted) return;
      setState(() {
        _identificationText = text?.isNotEmpty == true
            ? text!
            : 'Aucune identification claire n a ete retournee.';
        _identifiedMineral = _matchMineralFromText(text ?? '');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _identificationText =
            'Identification indisponible pour le moment. Verifiez la connexion ou la configuration Gemini.';
        _identifiedMineral = null;
      });
      _showSnack('Erreur identification: $e');
    } finally {
      if (mounted) setState(() => _identifying = false);
    }
  }

  _MineralProfile? _matchMineralFromText(String text) {
    final lower = text.toLowerCase();
    for (final mineral in _minerals) {
      if (lower.contains(mineral.label.toLowerCase())) return mineral;
      for (final alias in mineral.aliases) {
        if (lower.contains(alias.toLowerCase())) return mineral;
      }
    }
    return null;
  }

  String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _openMapForMineral(_MineralProfile mineral) async {
    final query = Uri.encodeComponent('${mineral.label} mine ${mineral.locations.first} RDC');
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showSnack('Impossible d ouvrir la localisation.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;
    final subText = isDark ? Colors.white70 : const Color(0xFF5B6473);
    final divider = isDark ? Colors.white12 : Colors.black12;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.24 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OBSERVATOIRE MINIER',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: subText),
                      ),
                      const SizedBox(height: 3),
                      const SizedBox(height: 2),
                      Text(
                        'Mise a jour marche: $lastUpdate',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: subText),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: isLoading ? null : fetchPrices,
                  visualDensity: VisualDensity.compact,
                  icon: isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.refresh_rounded, color: scheme.primary),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: _buildIdentificationPanel(context, subText),
          ),
          if (_filteredMinerals.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _catalogQuery.trim().isNotEmpty
                          ? '${_filteredMinerals.length} minerai(s) trouves'
                          : '${_visibleMinerals.length} sur ${_filteredMinerals.length} minerais affiches',
                      style: TextStyle(
                        color: subText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_canToggleCatalog)
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _catalogExpanded = !_catalogExpanded);
                      },
                      icon: Icon(
                        _catalogExpanded
                            ? Icons.unfold_less_rounded
                            : Icons.unfold_more_rounded,
                        size: 18,
                      ),
                      label: Text(_catalogExpanded ? 'Reduire' : 'Agrandir la liste'),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          ..._visibleMinerals.asMap().entries.map((entry) {
            final index = entry.key;
            final mineral = entry.value;
            return Column(
              children: [
                _buildMetalRow(context, mineral),
                if (index != _visibleMinerals.length - 1)
                  Divider(height: 1, color: divider, indent: 20, endIndent: 20),
              ],
            );
          }),
          if (_filteredMinerals.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Aucun minerai ne correspond a la recherche actuelle.',
                  style: TextStyle(color: subText, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (_filteredMinerals.isNotEmpty) const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildIdentificationPanel(BuildContext context, Color subText) {
    final scheme = Theme.of(context).colorScheme;
    final hasPhoto = _pickedMineralBytes != null;
    final statusText = _identifiedMineral?.label ??
        (_identificationText.isNotEmpty ? 'Analyse disponible' : 'Photo ajoutee');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFF2E1),
            Theme.of(context).brightness == Brightness.dark ? const Color(0xFF24211C) : Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFC27A).withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildIdentificationAction(
                tooltip: 'Prendre photo',
                background: const Color(0xFFFFB74D).withOpacity(0.16),
                onTap: () => _pickMineralPhoto(ImageSource.camera),
                child: const Icon(Icons.photo_camera_outlined, color: Color(0xFFC77700), size: 18),
              ),
              _buildIdentificationAction(
                tooltip: 'Importer',
                background: scheme.primary.withOpacity(0.10),
                onTap: () => _pickMineralPhoto(ImageSource.gallery),
                child: Icon(Icons.photo_library_outlined, color: scheme.primary, size: 18),
              ),
              if (hasPhoto)
                _buildIdentificationAction(
                  tooltip: _identifying ? 'Analyse en cours' : 'Lancer l analyse',
                  background: scheme.primary.withOpacity(0.16),
                  onTap: _identifying ? null : _identifyMineralFromPhoto,
                  child: _identifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.auto_awesome_outlined, color: scheme.primary, size: 18),
                ),
            ],
          ),
          if (hasPhoto) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_pickedMineralBytes!, width: 56, height: 56, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: scheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIdentificationAction({
    required String tooltip,
    required Color background,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildMetalRow(BuildContext context, _MineralProfile mineral) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final labelText = isDark ? Colors.white60 : Colors.black45;
    final priceText = scheme.onSurface;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MetalDetailPage(
              metalName: mineral.label,
              price: mineral.marketLabel,
              change: mineral.changeLabel,
              history: mineral.history,
              color: mineral.color,
              imageUrl: mineral.imageUrl,
              summary: mineral.summary,
              locations: mineral.locations,
              identificationTips: mineral.identifiers,
              marketName: mineral.marketLabel.contains('/ t')
                  ? 'London Metal Exchange (LME)'
                  : 'Observation terrain et prospection',
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(30),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: mineral.color.withOpacity(0.10),
                border: Border.all(color: mineral.color.withOpacity(0.20)),
              ),
              child: ClipOval(
                child: Image.network(
                  mineral.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(Icons.layers_rounded, color: mineral.color),
                ),
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
                          mineral.label.toUpperCase(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: labelText),
                        ),
                      ),
                      InkWell(
                        onTap: () => _openMapForMineral(mineral),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: mineral.color.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.place_outlined, size: 14, color: mineral.color),
                              const SizedBox(width: 3),
                              Text(
                                'Zones',
                                style: TextStyle(color: mineral.color, fontWeight: FontWeight.w800, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mineral.marketLabel,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: priceText),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 48,
                  height: 24,
                  child: CustomPaint(
                    painter: SparklinePainter(mineral.history, mineral.isUp ? Colors.green : Colors.red),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: (mineral.isUp ? Colors.green : Colors.red).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    mineral.changeLabel,
                    style: TextStyle(
                      color: mineral.isUp ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MineralProfile {
  final String key;
  final String label;
  final String marketLabel;
  final String changeLabel;
  final bool isUp;
  final Color color;
  final List<double> history;
  final String imageUrl;
  final String summary;
  final List<String> locations;
  final List<String> identifiers;
  final List<String> aliases;

  const _MineralProfile({
    required this.key,
    required this.label,
    required this.marketLabel,
    required this.changeLabel,
    required this.isUp,
    required this.color,
    required this.history,
    required this.imageUrl,
    required this.summary,
    required this.locations,
    required this.identifiers,
    required this.aliases,
  });
}

class SparklinePainter extends CustomPainter {
  final List<double> points;
  final Color color;

  SparklinePainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final stepX = size.width / (points.length - 1);
    final maxY = points.reduce((a, b) => a > b ? a : b);
    final minY = points.reduce((a, b) => a < b ? a : b);
    final range = (maxY - minY) == 0 ? 1.0 : (maxY - minY);

    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final y = size.height - ((points[i] - minY) / range * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'health_user_context.dart';

class HealthHeightMeasurePage extends StatefulWidget {
  const HealthHeightMeasurePage({
    super.key,
    required this.contextRef,
  });

  final HealthUserContext contextRef;

  @override
  State<HealthHeightMeasurePage> createState() => _HealthHeightMeasurePageState();
}

class _HealthHeightMeasurePageState extends State<HealthHeightMeasurePage> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _imageBytes;
  String _imageName = '';
  _PointTarget _target = _PointTarget.head;
  _ReferencePreset _preset = _ReferencePreset.a4Height;

  Offset? _headPoint;
  Offset? _feetPoint;
  Offset? _refStart;
  Offset? _refEnd;

  double? _estimatedHeightCm;
  bool _saving = false;

  CollectionReference<Map<String, dynamic>> get _metricsRef =>
      widget.contextRef.subCollection('health_measurements');

  CollectionReference<Map<String, dynamic>> get _sessionsRef =>
      widget.contextRef.subCollection('health_stress_sessions');

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 90);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = picked.name;
        _headPoint = null;
        _feetPoint = null;
        _refStart = null;
        _refEnd = null;
        _estimatedHeightCm = null;
        _target = _PointTarget.head;
      });
    } catch (e) {
      _snack('Impossible de charger la photo: $e', error: true);
    }
  }

  void _registerTap(Offset position) {
    setState(() {
      switch (_target) {
        case _PointTarget.head:
          _headPoint = position;
          _target = _PointTarget.feet;
          break;
        case _PointTarget.feet:
          _feetPoint = position;
          _target = _PointTarget.referenceStart;
          break;
        case _PointTarget.referenceStart:
          _refStart = position;
          _target = _PointTarget.referenceEnd;
          break;
        case _PointTarget.referenceEnd:
          _refEnd = position;
          break;
      }
      _recompute();
    });
  }

  void _recompute() {
    if (_headPoint == null || _feetPoint == null || _refStart == null || _refEnd == null) {
      _estimatedHeightCm = null;
      return;
    }

    final personPx = (_headPoint! - _feetPoint!).distance;
    final refPx = (_refStart! - _refEnd!).distance;
    if (personPx <= 0 || refPx <= 0) {
      _estimatedHeightCm = null;
      return;
    }

    _estimatedHeightCm = (personPx / refPx) * _preset.cm;
  }

  Future<void> _saveMeasurement() async {
    final heightCm = _estimatedHeightCm;
    if (heightCm == null) {
      _snack('Placez les 4 reperes avant d enregistrer.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.contextRef.userRef.set(
        {
          'health': {
            'height': heightCm,
            'heightCm': heightCm,
            'heightMeasurement': {
              'valueCm': heightCm,
              'method': 'camera_reference',
              'referenceLabel': _preset.label,
              'imageName': _imageName,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          },
        },
        SetOptions(merge: true),
      );

      await _metricsRef.add({
        'type': 'height',
        'value': heightCm,
        'unit': 'cm',
        'recordedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _sessionsRef.add({
        'type': 'height',
        'title': 'Mesure de ma taille',
        'summary':
            'Votre taille est estimee a ${heightCm.toStringAsFixed(1)} cm via photo + reference ${_preset.label}.',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _snack('Taille enregistree: ${heightCm.toStringAsFixed(1)} cm');
    } catch (e) {
      _snack('Enregistrement impossible: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? Colors.white : const Color(0xFF102127);
    final sub = isDark ? Colors.white70 : const Color(0xFF5E7077);
    const accent = Color(0xFF7A4DFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesurer ma taille'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withOpacity(0.12)),
            ),
            child: Text(
              'Prenez une photo plein pied avec un objet de taille connue dans le meme plan '
              '(feuille A4 ou carte bancaire). Touchez ensuite le sommet de la tete, le bas des pieds, puis les deux extremites de l objet.',
              style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Prendre photo'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galerie'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<_ReferencePreset>(
            initialValue: _preset,
            items: _ReferencePreset.values
                .map(
                  (preset) => DropdownMenuItem<_ReferencePreset>(
                    value: preset,
                    child: Text('${preset.label} (${preset.cm.toStringAsFixed(2)} cm)'),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _preset = value;
                _recompute();
              });
            },
            decoration: const InputDecoration(
              labelText: 'Objet de reference',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _PointTarget.values.map((target) {
              final selected = _target == target;
              return ChoiceChip(
                label: Text(target.label),
                selected: selected,
                onSelected: (_) => setState(() => _target = target),
                showCheckmark: false,
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 12),
          if (_imageBytes == null)
            Container(
              height: 320,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: accent.withOpacity(0.12)),
              ),
              child: Text(
                'Ajoutez une photo pour commencer.',
                style: TextStyle(color: text, fontWeight: FontWeight.w700),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = math.min(560.0, width * 1.35);
                return GestureDetector(
                  onTapDown: (details) => _registerTap(details.localPosition),
                  child: Container(
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: accent.withOpacity(0.14)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: isDark ? const Color(0xFF070B10) : const Color(0xFFF3F5F7),
                        ),
                        Image.memory(
                          _imageBytes!,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                        ),
                        CustomPaint(
                          painter: _HeightOverlayPainter(
                            head: _headPoint,
                            feet: _feetPoint,
                            refStart: _refStart,
                            refEnd: _refEnd,
                            accent: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          if (_imageName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _imageName,
              style: TextStyle(color: sub, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(isDark ? 0.04 : 0.76),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: accent.withOpacity(0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Etapes',
                  style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Sommet de la tete\n2. Bas des pieds\n3. Debut de l objet\n4. Fin de l objet',
                  style: TextStyle(color: sub, height: 1.6, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  _estimatedHeightCm == null
                      ? 'Mesure en attente.'
                      : 'Votre taille estimee: ${_estimatedHeightCm!.toStringAsFixed(1)} cm',
                  style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'Precision meilleure si la personne et l objet de reference sont sur le meme plan, '
                  'avec une camera bien droite et le corps entier visible.',
                  style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _headPoint = null;
                            _feetPoint = null;
                            _refStart = null;
                            _refEnd = null;
                            _estimatedHeightCm = null;
                            _target = _PointTarget.head;
                          });
                        },
                        child: const Text('Reinitialiser'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _saveMeasurement,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('Enregistrer'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _PointTarget {
  head('Sommet de la tete'),
  feet('Bas des pieds'),
  referenceStart('Debut de l objet'),
  referenceEnd('Fin de l objet');

  const _PointTarget(this.label);
  final String label;
}

enum _ReferencePreset {
  a4Height('Feuille A4 hauteur', 29.7),
  a4Width('Feuille A4 largeur', 21.0),
  bankCardWidth('Carte bancaire largeur', 8.56),
  bankCardHeight('Carte bancaire hauteur', 5.398);

  const _ReferencePreset(this.label, this.cm);
  final String label;
  final double cm;
}

class _HeightOverlayPainter extends CustomPainter {
  const _HeightOverlayPainter({
    required this.head,
    required this.feet,
    required this.refStart,
    required this.refEnd,
    required this.accent,
  });

  final Offset? head;
  final Offset? feet;
  final Offset? refStart;
  final Offset? refEnd;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final refPaint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    void drawPoint(Offset? point, Color color) {
      if (point == null) return;
      canvas.drawCircle(
        point,
        8,
        Paint()..color = color,
      );
      canvas.drawCircle(
        point,
        13,
        Paint()
          ..color = color.withOpacity(0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    if (head != null && feet != null) {
      canvas.drawLine(head!, feet!, linePaint);
    }
    if (refStart != null && refEnd != null) {
      canvas.drawLine(refStart!, refEnd!, refPaint);
    }

    drawPoint(head, accent);
    drawPoint(feet, accent);
    drawPoint(refStart, Colors.orangeAccent);
    drawPoint(refEnd, Colors.orangeAccent);
  }

  @override
  bool shouldRepaint(covariant _HeightOverlayPainter oldDelegate) {
    return oldDelegate.head != head ||
        oldDelegate.feet != feet ||
        oldDelegate.refStart != refStart ||
        oldDelegate.refEnd != refEnd ||
        oldDelegate.accent != accent;
  }
}

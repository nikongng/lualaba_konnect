import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'health_user_context.dart';

class HealthMetricsPage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthMetricsPage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthMetricsPage> createState() => _HealthMetricsPageState();
}

class _HealthMetricsPageState extends State<HealthMetricsPage> {
  CollectionReference<Map<String, dynamic>> get _metricsRef =>
      widget.contextRef.subCollection('health_measurements');

  String _selectedType = 'weight';

  static const _typeOptions = <Map<String, String>>[
    {'value': 'weight', 'label': 'Poids', 'unit': 'kg'},
    {'value': 'bloodPressure', 'label': 'Tension', 'unit': 'mmHg'},
    {'value': 'glucose', 'label': 'Glycemie', 'unit': 'mg/dL'},
    {'value': 'heartRate', 'label': 'Frequence cardiaque', 'unit': 'bpm'},
    {'value': 'activity', 'label': 'Activite', 'unit': 'min'},
    {'value': 'stressContext', 'label': 'Stress contextuel', 'unit': '/100'},
    {'value': 'stressFace', 'label': 'Stress facial', 'unit': '/100'},
    {'value': 'stressExperimental', 'label': 'Stress experimental', 'unit': '/100'},
    {'value': 'hrv', 'label': 'HRV', 'unit': 'ms'},
    {'value': 'height', 'label': 'Taille', 'unit': 'cm'},
  ];

  String _unitFor(String type) {
    return _typeOptions.firstWhere((e) => e['value'] == type)['unit'] ?? '';
  }

  String _labelFor(String type) {
    return _typeOptions.firstWhere((e) => e['value'] == type)['label'] ?? type;
  }

  String _healthFieldForType(String type) {
    switch (type) {
      case 'weight':
        return 'weight';
      case 'bloodPressure':
        return 'bloodPressure';
      case 'glucose':
        return 'glucose';
      case 'heartRate':
        return 'heartRate';
      case 'activity':
        return 'activity';
      case 'hrv':
        return 'hrv';
      case 'height':
        return 'heightCm';
      default:
        return '';
    }
  }

  Future<void> _openForm() async {
    final valueCtrl = TextEditingController();
    DateTime? recordedAt = DateTime.now();
    String type = _selectedType;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: recordedAt ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setSheet(() {
                  recordedAt = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    recordedAt?.hour ?? 9,
                    recordedAt?.minute ?? 0,
                  );
                });
              }
            }

            Future<void> pickTime() async {
              final picked = await showTimePicker(
                context: ctx,
                initialTime: TimeOfDay.fromDateTime(recordedAt ?? DateTime.now()),
              );
              if (picked != null) {
                setSheet(() {
                  final base = recordedAt ?? DateTime.now();
                  recordedAt = DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ajouter une mesure', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      items: _typeOptions
                          .map((opt) => DropdownMenuItem(
                                value: opt['value'],
                                child: Text(opt['label'] ?? ''),
                              ))
                          .toList(),
                      onChanged: (v) => setSheet(() => type = v ?? _selectedType),
                      decoration: const InputDecoration(labelText: 'Type'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: valueCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Valeur (${_unitFor(type)})'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: pickDate,
                            child: Text(recordedAt != null ? _fmtDate(recordedAt!) : 'Date'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: pickTime,
                            child: Text(recordedAt != null ? _fmtTime(recordedAt!) : 'Heure'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final value = double.tryParse(valueCtrl.text.replaceAll(',', '.'));
                              if (value == null) return;
                              await _metricsRef.add({
                                'type': type,
                                'value': value,
                                'unit': _unitFor(type),
                                'recordedAt': recordedAt != null
                                    ? Timestamp.fromDate(recordedAt!)
                                    : FieldValue.serverTimestamp(),
                                'createdAt': FieldValue.serverTimestamp(),
                              });

                              final field = _healthFieldForType(type);
                              if (field.isNotEmpty) {
                                await widget.contextRef.userRef.set(
                                  {'health.$field': value},
                                  SetOptions(merge: true),
                                );
                              }
                              if (mounted) Navigator.of(ctx).pop();
                            },
                            child: const Text('Enregistrer'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi sante'),
        actions: [
          IconButton(onPressed: _openForm, icon: const Icon(Icons.add)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedType,
              items: _typeOptions
                  .map((opt) => DropdownMenuItem(
                        value: opt['value'],
                        child: Text(opt['label'] ?? ''),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedType = v ?? _selectedType),
              decoration: const InputDecoration(labelText: 'Type de mesure'),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _metricsRef.orderBy('recordedAt', descending: false).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data!.docs;
                final filtered = all
                    .map((d) => _HealthPoint.fromDoc(d))
                    .where((p) => p.type == _selectedType && p.value != null && p.recordedAt != null)
                    .toList();
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _HealthLineChart(points: filtered),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final p = filtered[i];
                          return ListTile(
                            title: Text('${_labelFor(p.type)}: ${p.value?.toStringAsFixed(1)} ${p.unit ?? ''}'),
                            subtitle: Text(p.recordedAt != null ? _fmtDateTime(p.recordedAt!) : ''),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year}';
  }

  String _fmtTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _fmtDateTime(DateTime dt) => '${_fmtDate(dt)} ${_fmtTime(dt)}';
}

class _HealthPoint {
  final String type;
  final double? value;
  final DateTime? recordedAt;
  final String? unit;

  _HealthPoint({
    required this.type,
    required this.value,
    required this.recordedAt,
    required this.unit,
  });

  factory _HealthPoint.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final raw = data['value'];
    double? value;
    if (raw is num) value = raw.toDouble();
    final ts = data['recordedAt'];
    final recordedAt = ts is Timestamp ? ts.toDate() : null;
    return _HealthPoint(
      type: (data['type'] ?? '').toString(),
      value: value,
      recordedAt: recordedAt,
      unit: (data['unit'] ?? '').toString(),
    );
  }
}

class _HealthLineChart extends StatelessWidget {
  final List<_HealthPoint> points;

  const _HealthLineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Pas assez de donnees'),
      );
    }
    return SizedBox(
      height: 160,
      child: CustomPaint(
        painter: _LineChartPainter(points),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_HealthPoint> points;

  _LineChartPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final values = points.map((e) => e.value ?? 0).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).abs() < 0.0001 ? 1.0 : (maxVal - minVal);

    final linePaint = Paint()
      ..color = Colors.teal
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final x = (size.width / (points.length - 1)) * i;
      final v = points[i].value ?? 0;
      final norm = (v - minVal) / range;
      final y = size.height - (norm * (size.height - 8)) - 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

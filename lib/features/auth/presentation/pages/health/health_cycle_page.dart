import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'health_user_context.dart';

class HealthCyclePage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthCyclePage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthCyclePage> createState() => _HealthCyclePageState();
}

class _HealthCyclePageState extends State<HealthCyclePage> {
  CollectionReference<Map<String, dynamic>> get _cyclesRef =>
      widget.contextRef.subCollection('health_cycles');

  Future<void> _openForm({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final data = doc?.data() ?? <String, dynamic>{};
    DateTime? startDate = _toDate(data['startDate']) ?? DateTime.now();
    final durationCtrl = TextEditingController(text: (data['duration'] ?? '').toString());
    final lengthCtrl = TextEditingController(text: (data['cycleLength'] ?? '').toString());
    final phaseCtrl = TextEditingController(text: (data['phase'] ?? '').toString());
    final symptomsCtrl = TextEditingController(text: _listToString(data['symptoms']));
    final notesCtrl = TextEditingController(text: (data['notes'] ?? '').toString());

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
                initialDate: startDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) setSheet(() => startDate = picked);
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
                    Text(
                      doc == null ? 'Ajouter un cycle' : 'Modifier le cycle',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: pickDate,
                      child: Text(startDate != null ? _fmtDate(startDate!) : 'Date de debut'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: durationCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Duree (jours)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: lengthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Longueur du cycle (jours)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phaseCtrl,
                      decoration: const InputDecoration(labelText: 'Phase'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: symptomsCtrl,
                      decoration: const InputDecoration(labelText: 'Symptomes (separes par virgule)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      minLines: 1,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final duration = int.tryParse(durationCtrl.text.trim());
                              final length = int.tryParse(lengthCtrl.text.trim());
                              final payload = <String, dynamic>{
                                'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
                                'duration': duration,
                                'cycleLength': length,
                                'phase': phaseCtrl.text.trim(),
                                'symptoms': _stringToList(symptomsCtrl.text),
                                'notes': notesCtrl.text.trim(),
                                'updatedAt': FieldValue.serverTimestamp(),
                              };
                              if (doc == null) {
                                payload['createdAt'] = FieldValue.serverTimestamp();
                                await _cyclesRef.add(payload);
                              } else {
                                await doc.reference.set(payload, SetOptions(merge: true));
                              }

                              if (startDate != null && length != null) {
                                final next = startDate!.add(Duration(days: length));
                                await widget.contextRef.userRef.set(
                                  {
                                    'health.cycle': {
                                      'startDate': _fmtDate(startDate!),
                                      'duration': duration,
                                      'phase': phaseCtrl.text.trim(),
                                    },
                                    'health.nextPeriod': _fmtDate(next),
                                    'health.cycleHistory': FieldValue.arrayUnion([_fmtDate(startDate!)]),
                                  },
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

  Future<void> _deleteDoc(DocumentSnapshot<Map<String, dynamic>> doc) async {
    await doc.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycle feminin'),
        actions: [
          IconButton(onPressed: _openForm, icon: const Icon(Icons.add)),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _cyclesRef.orderBy('startDate', descending: true).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Aucun cycle'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12),
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final data = doc.data();
              final start = _toDate(data['startDate']);
              final duration = data['duration'];
              final phase = (data['phase'] ?? '').toString();
              final subtitle = _joinParts([
                start != null ? _fmtDate(start) : '',
                duration != null ? 'duree $duration j' : '',
                phase,
              ]);
              return ListTile(
                title: Text(start != null ? _fmtDate(start) : 'Cycle'),
                subtitle: Text(subtitle),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _openForm(doc: doc),
                      icon: const Icon(Icons.edit),
                    ),
                    IconButton(
                      onPressed: () => _deleteDoc(doc),
                      icon: const Icon(Icons.delete_outline),
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

  DateTime? _toDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    final s = raw?.toString() ?? '';
    return DateTime.tryParse(s);
  }

  String _fmtDate(DateTime dt) {
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year}';
  }

  String _listToString(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).join(', ');
    }
    return (raw ?? '').toString();
  }

  List<String> _stringToList(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _joinParts(List<String> parts) {
    final out = parts.where((p) => p.trim().isNotEmpty).toList();
    return out.isEmpty ? 'Aucun detail' : out.join(' / ');
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'health_notification_scheduler.dart';
import 'health_user_context.dart';

class HealthMedicationsPage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthMedicationsPage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthMedicationsPage> createState() => _HealthMedicationsPageState();
}

class _HealthMedicationsPageState extends State<HealthMedicationsPage> {
  CollectionReference<Map<String, dynamic>> get _medsRef =>
      widget.contextRef.subCollection('health_medications');

  Future<void> _openForm({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final data = doc?.data() ?? <String, dynamic>{};
    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    final doseCtrl = TextEditingController(text: (data['dose'] ?? '').toString());
    final scheduleCtrl = TextEditingController(text: (data['schedule'] ?? '').toString());
    final notesCtrl = TextEditingController(text: (data['notes'] ?? '').toString());
    DateTime? startDate = _toDate(data['startDate']);
    DateTime? endDate = _toDate(data['endDate']);
    bool active = data['active'] == true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> pickStart() async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: startDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setSheet(() => startDate = picked);
              }
            }

            Future<void> pickEnd() async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: endDate ?? (startDate ?? DateTime.now()),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setSheet(() => endDate = picked);
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
                    Text(
                      doc == null ? 'Ajouter un medicament' : 'Modifier le medicament',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: doseCtrl,
                      decoration: const InputDecoration(labelText: 'Dose'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: scheduleCtrl,
                      decoration: const InputDecoration(labelText: 'Horaire / Frequence'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      minLines: 1,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: pickStart,
                            child: Text(startDate != null ? _fmtDate(startDate!) : 'Date debut'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: pickEnd,
                            child: Text(endDate != null ? _fmtDate(endDate!) : 'Date fin'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: active,
                      onChanged: (v) => setSheet(() => active = v),
                      title: const Text('Actif'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final name = nameCtrl.text.trim();
                              if (name.isEmpty) return;

                              final payload = <String, dynamic>{
                                'name': name,
                                'dose': doseCtrl.text.trim(),
                                'schedule': scheduleCtrl.text.trim(),
                                'notes': notesCtrl.text.trim(),
                                'active': active,
                                'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
                                'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
                                'updatedAt': FieldValue.serverTimestamp(),
                              };

                              if (doc == null) {
                                payload['createdAt'] = FieldValue.serverTimestamp();
                                await _medsRef.add(payload);
                              } else {
                                await doc.reference.set(payload, SetOptions(merge: true));
                              }

                              final summary = _joinParts([name, doseCtrl.text, scheduleCtrl.text]);
                              await widget.contextRef.userRef.set(
                                {
                                  'health.medications': FieldValue.arrayUnion([summary]),
                                },
                                SetOptions(merge: true),
                              );

                              if (mounted) Navigator.of(ctx).pop();
                              await HealthNotificationScheduler.refreshForUser(widget.contextRef);
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
        title: const Text('Medicaments'),
        actions: [
          IconButton(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _medsRef.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Aucun medicament'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12),
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final data = doc.data();
              final name = (data['name'] ?? '').toString();
              final dose = (data['dose'] ?? '').toString();
              final schedule = (data['schedule'] ?? '').toString();
              final active = data['active'] == true;
              return ListTile(
                title: Text(name.isEmpty ? 'Sans nom' : name),
                subtitle: Text(_joinParts([dose, schedule])),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(active ? Icons.check_circle : Icons.radio_button_unchecked, size: 18),
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

  String _joinParts(List<String> parts) {
    final out = parts.where((p) => p.trim().isNotEmpty).toList();
    return out.isEmpty ? 'Aucun detail' : out.join(' / ');
  }
}

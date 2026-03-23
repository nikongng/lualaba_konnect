import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'health_notification_scheduler.dart';
import 'health_user_context.dart';

class HealthAppointmentsPage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthAppointmentsPage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthAppointmentsPage> createState() => _HealthAppointmentsPageState();
}

class _HealthAppointmentsPageState extends State<HealthAppointmentsPage> {
  CollectionReference<Map<String, dynamic>> get _apptsRef =>
      widget.contextRef.subCollection('health_appointments');

  Future<void> _openForm({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final data = doc?.data() ?? <String, dynamic>{};
    final doctorCtrl = TextEditingController(text: (data['doctor'] ?? '').toString());
    final hospitalCtrl = TextEditingController(text: (data['hospital'] ?? '').toString());
    final reasonCtrl = TextEditingController(text: (data['reason'] ?? '').toString());
    final notesCtrl = TextEditingController(text: (data['notes'] ?? '').toString());
    DateTime? dateTime = _toDate(data['dateTime']) ?? DateTime.now();
    String status = (data['status'] ?? 'scheduled').toString();

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
                initialDate: dateTime ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setSheet(() {
                  dateTime = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    dateTime?.hour ?? 9,
                    dateTime?.minute ?? 0,
                  );
                });
              }
            }

            Future<void> pickTime() async {
              final picked = await showTimePicker(
                context: ctx,
                initialTime: TimeOfDay.fromDateTime(dateTime ?? DateTime.now()),
              );
              if (picked != null) {
                setSheet(() {
                  final base = dateTime ?? DateTime.now();
                  dateTime = DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
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
                    Text(
                      doc == null ? 'Ajouter un rendez-vous' : 'Modifier le rendez-vous',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: doctorCtrl,
                      decoration: const InputDecoration(labelText: 'Medecin'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: hospitalCtrl,
                      decoration: const InputDecoration(labelText: 'Hopital / Lieu'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonCtrl,
                      decoration: const InputDecoration(labelText: 'Motif'),
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
                            onPressed: pickDate,
                            child: Text(dateTime != null ? _fmtDate(dateTime!) : 'Date'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: pickTime,
                            child: Text(dateTime != null ? _fmtTime(dateTime!) : 'Heure'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      items: const [
                        DropdownMenuItem(value: 'scheduled', child: Text('Planifie')),
                        DropdownMenuItem(value: 'completed', child: Text('Termine')),
                        DropdownMenuItem(value: 'canceled', child: Text('Annule')),
                      ],
                      onChanged: (v) => setSheet(() => status = v ?? 'scheduled'),
                      decoration: const InputDecoration(labelText: 'Statut'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final payload = <String, dynamic>{
                                'doctor': doctorCtrl.text.trim(),
                                'hospital': hospitalCtrl.text.trim(),
                                'reason': reasonCtrl.text.trim(),
                                'notes': notesCtrl.text.trim(),
                                'status': status,
                                'dateTime': dateTime != null ? Timestamp.fromDate(dateTime!) : null,
                                'updatedAt': FieldValue.serverTimestamp(),
                              };
                              if (doc == null) {
                                payload['createdAt'] = FieldValue.serverTimestamp();
                                await _apptsRef.add(payload);
                              } else {
                                await doc.reference.set(payload, SetOptions(merge: true));
                              }

                              final when = dateTime != null ? '${_fmtDate(dateTime!)} ${_fmtTime(dateTime!)}' : '';
                              final summary = _joinParts([when, doctorCtrl.text, hospitalCtrl.text, reasonCtrl.text]);
                              await widget.contextRef.userRef.set(
                                {
                                  'health.appointments': FieldValue.arrayUnion([summary]),
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
        title: const Text('Rendez-vous'),
        actions: [
          IconButton(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _apptsRef.orderBy('dateTime', descending: false).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Aucun rendez-vous'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12),
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final data = doc.data();
              final doctor = (data['doctor'] ?? '').toString();
              final hospital = (data['hospital'] ?? '').toString();
              final reason = (data['reason'] ?? '').toString();
              final when = _toDate(data['dateTime']);
              final status = (data['status'] ?? 'scheduled').toString();
              final subtitle = _joinParts([
                when != null ? '${_fmtDate(when)} ${_fmtTime(when)}' : '',
                doctor,
                hospital,
                reason,
                _statusLabel(status),
              ]);
              return ListTile(
                title: Text(reason.isEmpty ? 'Rendez-vous' : reason),
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

  String _fmtTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _joinParts(List<String> parts) {
    final out = parts.where((p) => p.trim().isNotEmpty).toList();
    return out.isEmpty ? 'Aucun detail' : out.join(' / ');
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Termine';
      case 'canceled':
        return 'Annule';
      default:
        return 'Planifie';
    }
  }
}

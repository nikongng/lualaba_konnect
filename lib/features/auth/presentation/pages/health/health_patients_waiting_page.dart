import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'health_user_context.dart';

class HealthPatientsWaitingPage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthPatientsWaitingPage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthPatientsWaitingPage> createState() => _HealthPatientsWaitingPageState();
}

class _HealthPatientsWaitingPageState extends State<HealthPatientsWaitingPage> {
  CollectionReference<Map<String, dynamic>> get _patientsRef =>
      widget.contextRef.subCollection('health_patients');
  String _statusFilter = 'waiting';

  Future<void> _openForm({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final data = doc?.data() ?? <String, dynamic>{};
    final nameCtrl = TextEditingController(text: (data['name'] ?? '').toString());
    final ageCtrl = TextEditingController(text: (data['age'] ?? '').toString());
    final phoneCtrl = TextEditingController(text: (data['phone'] ?? '').toString());
    final conditionCtrl = TextEditingController(text: (data['condition'] ?? '').toString());
    final notesCtrl = TextEditingController(text: (data['notes'] ?? '').toString());
    String status = _statusKey(data['status']);
    if (status.isEmpty) status = 'waiting';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
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
                      doc == null ? 'Ajouter un patient' : 'Modifier le patient',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom')),
                    const SizedBox(height: 8),
                    TextField(controller: ageCtrl, decoration: const InputDecoration(labelText: 'Age')),
                    const SizedBox(height: 8),
                    TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Telephone')),
                    const SizedBox(height: 8),
                    TextField(controller: conditionCtrl, decoration: const InputDecoration(labelText: 'Maladie / Etat')),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes'),
                      minLines: 1,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      items: const [
                        DropdownMenuItem(value: 'waiting', child: Text('En attente')),
                        DropdownMenuItem(value: 'in_care', child: Text('En soins')),
                        DropdownMenuItem(value: 'done', child: Text('Termine')),
                      ],
                      onChanged: (v) => setSheet(() => status = v ?? 'waiting'),
                      decoration: const InputDecoration(labelText: 'Statut'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final payload = <String, dynamic>{
                                'name': nameCtrl.text.trim(),
                                'age': ageCtrl.text.trim(),
                                'phone': phoneCtrl.text.trim(),
                                'condition': conditionCtrl.text.trim(),
                                'notes': notesCtrl.text.trim(),
                                'status': status,
                                'updatedAt': FieldValue.serverTimestamp(),
                              };
                              if (doc == null) {
                                payload['createdAt'] = FieldValue.serverTimestamp();
                                await _patientsRef.add(payload);
                              } else {
                                await doc.reference.set(payload, SetOptions(merge: true));
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
        title: const Text('Patients en attente'),
        actions: [
          IconButton(onPressed: () => _openForm(), icon: const Icon(Icons.add)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'waiting', label: Text('En attente')),
                ButtonSegment(value: 'in_care', label: Text('En soins')),
                ButtonSegment(value: 'done', label: Text('Termine')),
                ButtonSegment(value: 'all', label: Text('Tous')),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (s) => setState(() => _statusFilter = s.first),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _patientsRef.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                final filtered = docs.where((d) => _matchesFilter(d.data())).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(_emptyLabel()),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12),
                  itemBuilder: (ctx, i) {
                    final doc = filtered[i];
                    final data = doc.data();
                    final name = (data['name'] ?? '').toString().trim();
                    final age = (data['age'] ?? '').toString().trim();
                    final phone = (data['phone'] ?? '').toString().trim();
                    final condition = (data['condition'] ?? '').toString().trim();
                    final notes = (data['notes'] ?? '').toString().trim();
                    final subtitle = _joinParts([
                      if (age.isNotEmpty) 'Age $age',
                      if (phone.isNotEmpty) phone,
                      if (condition.isNotEmpty) condition,
                      if (notes.isNotEmpty) notes,
                    ]);
                    return ListTile(
                      title: Text(name.isNotEmpty ? name : 'Patient'),
                      subtitle: Text(subtitle),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(onPressed: () => _openForm(doc: doc), icon: const Icon(Icons.edit_outlined)),
                          IconButton(onPressed: () => _deleteDoc(doc), icon: const Icon(Icons.delete_outline)),
                        ],
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

  bool _isWaiting(Map<String, dynamic> data) {
    final status = _statusKey(data['status']);
    if (status == 'waiting' || status == 'pending' || status == 'en_attente') return true;
    if (data['waiting'] == true || data['needsCare'] == true) return true;
    return false;
  }

  bool _matchesFilter(Map<String, dynamic> data) {
    if (_statusFilter == 'all') return true;
    final status = _statusKey(data['status']);
    if (_statusFilter == 'waiting') return _isWaiting(data);
    if (_statusFilter == 'in_care') return status == 'in_care' || status == 'en_soins';
    if (_statusFilter == 'done') return status == 'done' || status == 'termine';
    return false;
  }

  String _emptyLabel() {
    switch (_statusFilter) {
      case 'in_care':
        return 'Aucun patient en soins';
      case 'done':
        return 'Aucun patient termine';
      case 'all':
        return 'Aucun patient';
      default:
        return 'Aucun patient en attente';
    }
  }

  String _statusKey(dynamic raw) {
    if (raw == null) return '';
    return raw.toString().trim().toLowerCase();
  }

  String _joinParts(List<String> parts) {
    final out = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    return out.isEmpty ? '' : out.join(' / ');
  }
}

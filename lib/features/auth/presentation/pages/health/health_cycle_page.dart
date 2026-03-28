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
  static const List<String> _phaseOptions = <String>[
    'Menstruation',
    'Folliculaire',
    'Ovulation',
    'Luteale',
  ];

  static const List<String> _flowOptions = <String>[
    'Leger',
    'Modere',
    'Abondant',
  ];

  static const List<String> _moodOptions = <String>[
    'Calme',
    'Fatiguee',
    'Sensible',
    'Energetique',
  ];

  static const List<String> _energyOptions = <String>[
    'Basse',
    'Stable',
    'Elevee',
  ];

  static const List<String> _symptomOptions = <String>[
    'Crampes',
    'Ballonnements',
    'Douleurs lombaires',
    'Maux de tete',
    'Fatigue',
    'Acne',
    'Nausees',
    'Sensibilite mammaire',
  ];

  CollectionReference<Map<String, dynamic>> get _cyclesRef =>
      widget.contextRef.subCollection('health_cycles');

  Future<void> _openForm({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final data = doc?.data() ?? <String, dynamic>{};
    DateTime startDate = _toDate(data['startDate']) ?? DateTime.now();
    final durationCtrl = TextEditingController(text: (data['duration'] ?? 5).toString());
    final lengthCtrl = TextEditingController(text: (data['cycleLength'] ?? 28).toString());
    String selectedPhase = (data['phase'] ?? '').toString().trim();
    String selectedFlow = (data['flow'] ?? '').toString().trim();
    String selectedMood = (data['mood'] ?? '').toString().trim();
    String selectedEnergy = (data['energy'] ?? '').toString().trim();
    final existingSymptoms = _stringList(data['symptoms']);
    final selectedSymptoms = <String>{
      ...existingSymptoms.where((item) => _symptomOptions.contains(item)),
    };
    final symptomsCtrl = TextEditingController(
      text: existingSymptoms
          .where((item) => !_symptomOptions.contains(item))
          .join(', '),
    );
    final notesCtrl = TextEditingController(text: (data['notes'] ?? '').toString());

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final text = isDark ? Colors.white : const Color(0xFF1B2333);
        final sub = isDark ? Colors.white70 : const Color(0xFF687082);
        final cardBg = isDark ? const Color(0xFF171B2B) : Colors.white;
        const accent = Color(0xFFE84C88);

        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: startDate,
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
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(isDark ? 0.18 : 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF472B6), Color(0xFFE84C88)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.water_drop_outlined, color: Colors.white),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    doc == null
                                        ? 'Nouveau suivi menstruel'
                                        : 'Mettre a jour le cycle',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Enregistrez votre phase, votre ressenti et vos symptomes dans un parcours plus simple.',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.92),
                                      height: 1.4,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _sheetLabel('Date de debut'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: pickDate,
                        borderRadius: BorderRadius.circular(18),
                        child: Ink(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: accent.withOpacity(0.14)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month_outlined, color: accent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _fmtDate(startDate),
                                  style: TextStyle(
                                    color: text,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Icon(Icons.edit_calendar_outlined, color: accent),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: durationCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Duree des regles'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: lengthCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Longueur du cycle'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _sheetLabel('Phase'),
                      const SizedBox(height: 8),
                      _choiceWrap(
                        options: _phaseOptions,
                        selected: selectedPhase,
                        accent: accent,
                        text: text,
                        onSelected: (value) => setSheet(() => selectedPhase = value),
                      ),
                      const SizedBox(height: 18),
                      _sheetLabel('Flux'),
                      const SizedBox(height: 8),
                      _choiceWrap(
                        options: _flowOptions,
                        selected: selectedFlow,
                        accent: accent,
                        text: text,
                        onSelected: (value) => setSheet(() => selectedFlow = value),
                      ),
                      const SizedBox(height: 18),
                      _sheetLabel('Humeur'),
                      const SizedBox(height: 8),
                      _choiceWrap(
                        options: _moodOptions,
                        selected: selectedMood,
                        accent: accent,
                        text: text,
                        onSelected: (value) => setSheet(() => selectedMood = value),
                      ),
                      const SizedBox(height: 18),
                      _sheetLabel('Niveau d energie'),
                      const SizedBox(height: 8),
                      _choiceWrap(
                        options: _energyOptions,
                        selected: selectedEnergy,
                        accent: accent,
                        text: text,
                        onSelected: (value) => setSheet(() => selectedEnergy = value),
                      ),
                      const SizedBox(height: 18),
                      _sheetLabel('Symptomes'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _symptomOptions.map((item) {
                          final isSelected = selectedSymptoms.contains(item);
                          return FilterChip(
                            label: Text(item),
                            selected: isSelected,
                            showCheckmark: false,
                            backgroundColor: accent.withOpacity(0.06),
                            selectedColor: accent.withOpacity(0.18),
                            labelStyle: TextStyle(
                              color: text,
                              fontWeight: FontWeight.w700,
                            ),
                            onSelected: (_) {
                              setSheet(() {
                                if (isSelected) {
                                  selectedSymptoms.remove(item);
                                } else {
                                  selectedSymptoms.add(item);
                                }
                              });
                            },
                          );
                        }).toList(growable: false),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: symptomsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Autres symptomes (separes par virgule)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(labelText: 'Notes'),
                        minLines: 3,
                        maxLines: 5,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final duration = int.tryParse(durationCtrl.text.trim());
                            final length = int.tryParse(lengthCtrl.text.trim());
                            final payload = <String, dynamic>{
                              'startDate': Timestamp.fromDate(startDate),
                              'duration': duration,
                              'cycleLength': length,
                              'phase': selectedPhase,
                              'flow': selectedFlow,
                              'mood': selectedMood,
                              'energy': selectedEnergy,
                              'symptoms': <String>{
                                ...selectedSymptoms,
                                ..._stringToList(symptomsCtrl.text),
                              }.toList(growable: false),
                              'notes': notesCtrl.text.trim(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            };
                            if (doc == null) {
                              payload['createdAt'] = FieldValue.serverTimestamp();
                              await _cyclesRef.add(payload);
                            } else {
                              await doc.reference.set(payload, SetOptions(merge: true));
                            }
                            await _syncCycleProfile();
                            if (mounted) Navigator.of(ctx).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text(
                            'Enregistrer le suivi',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Le resume et les previsions du cycle seront actualises automatiquement.',
                        style: TextStyle(
                          color: sub,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    durationCtrl.dispose();
    lengthCtrl.dispose();
    symptomsCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _deleteDoc(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Supprimer ce cycle ?'),
          content: const Text(
            'Cette entree sera retiree et le resume du cycle sera recalcule.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await doc.reference.delete();
    await _syncCycleProfile();
    _snack('Cycle supprime');
  }

  Future<void> _syncCycleProfile() async {
    final snap = await _cyclesRef.orderBy('startDate', descending: true).get();
    final entries = snap.docs.map(_entryFromDoc).toList(growable: false);

    if (entries.isEmpty) {
      await widget.contextRef.userRef.set(
        {
          'health.cycle': <String, dynamic>{},
          'health.nextPeriod': '',
          'health.cycleHistory': <String>[],
          'health.cycleSymptoms': <String>[],
          'health.fertileWindow': '',
          'health.cycleMood': '',
          'health.cycleFlow': '',
          'health.cyclePhase': '',
        },
        SetOptions(merge: true),
      );
      return;
    }

    final latest = entries.first;
    final cycleLengths = entries.map((e) => e.cycleLength).whereType<int>().toList();
    final nextDate = _predictedNext(
      latest.startDate,
      latest.cycleLength ?? _average(cycleLengths),
    );

    await widget.contextRef.userRef.set(
      {
        'health.cycle': {
          'startDate': latest.startDate != null ? _fmtDate(latest.startDate!) : '',
          'duration': latest.duration,
          'phase': latest.displayPhase,
          'flow': latest.flow,
          'mood': latest.mood,
          'energy': latest.energy,
        },
        'health.nextPeriod': nextDate != null ? _fmtDate(nextDate) : '',
        'health.cycleHistory': entries
            .where((e) => e.startDate != null)
            .take(12)
            .map((e) => _fmtDate(e.startDate!))
            .toList(growable: false),
        'health.cycleSymptoms': latest.symptoms,
        'health.fertileWindow': _fertileWindowLabel(
          latest.startDate,
          latest.cycleLength ?? _average(cycleLengths),
        ),
        'health.cycleMood': latest.mood,
        'health.cycleFlow': latest.flow,
        'health.cyclePhase': latest.displayPhase,
      },
      SetOptions(merge: true),
    );
  }

  _CycleEntry _entryFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final startDate = _toDate(data['startDate']);
    final duration = _toInt(data['duration']);
    final cycleLength = _toInt(data['cycleLength']);
    final phase = (data['phase'] ?? '').toString().trim();
    return _CycleEntry(
      doc: doc,
      startDate: startDate,
      duration: duration,
      cycleLength: cycleLength,
      phase: phase,
      flow: (data['flow'] ?? '').toString().trim(),
      mood: (data['mood'] ?? '').toString().trim(),
      energy: (data['energy'] ?? '').toString().trim(),
      symptoms: _stringList(data['symptoms']),
      notes: (data['notes'] ?? '').toString().trim(),
      inferredPhase: phase.isNotEmpty
          ? phase
          : _inferPhase(
              startDate,
              duration: duration,
              cycleLength: cycleLength,
            ),
    );
  }

  String _inferPhase(
    DateTime? startDate, {
    int? duration,
    int? cycleLength,
  }) {
    if (startDate == null) return '';
    final now = _dateOnly(DateTime.now());
    final start = _dateOnly(startDate);
    final days = now.difference(start).inDays;
    final periodDays = duration ?? 5;
    final totalLength = cycleLength ?? 28;
    if (days < periodDays) return 'Menstruation';
    if (days < totalLength ~/ 2 - 2) return 'Folliculaire';
    if (days <= totalLength ~/ 2 + 1) return 'Ovulation';
    return 'Luteale';
  }

  DateTime? _predictedNext(DateTime? startDate, int? cycleLength) {
    if (startDate == null || cycleLength == null) return null;
    return _dateOnly(startDate).add(Duration(days: cycleLength));
  }

  String _fertileWindowLabel(DateTime? startDate, int? cycleLength) {
    if (startDate == null || cycleLength == null) return '';
    final ovulation = _dateOnly(startDate).add(Duration(days: cycleLength - 14));
    final fertileStart = ovulation.subtract(const Duration(days: 4));
    final fertileEnd = ovulation.add(const Duration(days: 1));
    return '${_fmtDate(fertileStart)} - ${_fmtDate(fertileEnd)}';
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  int? _average(List<int> values) {
    if (values.isEmpty) return null;
    final total = values.fold<int>(0, (sum, item) => sum + item);
    return (total / values.length).round();
  }

  int? _toInt(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse((raw ?? '').toString());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1220) : const Color(0xFFF8F2F6);
    final cardBg = isDark ? const Color(0xFF171B2B) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF1B2333);
    final sub = isDark ? Colors.white70 : const Color(0xFF687082);
    const accent = Color(0xFFE84C88);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: text),
        title: Text(
          'Cycle feminin',
          style: TextStyle(color: text, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(onPressed: _openForm, icon: const Icon(Icons.add)),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        backgroundColor: accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text(
          'Ajouter un suivi',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _cyclesRef.orderBy('startDate', descending: true).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snap.data!.docs.map(_entryFromDoc).toList(growable: false);
          final latest = entries.isNotEmpty ? entries.first : null;
          final averageCycle = _average(
            entries.map((e) => e.cycleLength).whereType<int>().toList(),
          );
          final averageDuration = _average(
            entries.map((e) => e.duration).whereType<int>().toList(),
          );
          final nextDate = latest == null
              ? null
              : _predictedNext(latest.startDate, latest.cycleLength ?? averageCycle);
          final fertileWindow = latest == null
              ? ''
              : _fertileWindowLabel(latest.startDate, latest.cycleLength ?? averageCycle);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
            children: [
              _reveal(
                0,
                _buildHeroCard(
                  isDark: isDark,
                  accent: accent,
                  latest: latest,
                  nextDate: nextDate,
                ),
              ),
              const SizedBox(height: 14),
              if (entries.isEmpty)
                _reveal(
                  1,
                  _buildEmptyState(
                    cardBg: cardBg,
                    text: text,
                    sub: sub,
                    accent: accent,
                  ),
                )
              else ...[
                _reveal(
                  1,
                  _buildStatsStrip(
                    cardBg: cardBg,
                    text: text,
                    sub: sub,
                    accent: accent,
                    nextDate: nextDate,
                    averageCycle: averageCycle,
                    averageDuration: averageDuration,
                    latest: latest!,
                  ),
                ),
                const SizedBox(height: 14),
                _reveal(
                  2,
                  _buildHighlightsCard(
                    cardBg: cardBg,
                    text: text,
                    sub: sub,
                    accent: accent,
                    latest: latest,
                    fertileWindow: fertileWindow,
                    nextDate: nextDate,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Historique recent',
                  style: TextStyle(
                    color: text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                ...entries.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _reveal(
                      3 + entry.key,
                      _buildCycleCard(
                        cardBg: cardBg,
                        text: text,
                        sub: sub,
                        accent: accent,
                        entry: entry.value,
                      ),
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroCard({
    required bool isDark,
    required Color accent,
    required _CycleEntry? latest,
    required DateTime? nextDate,
  }) {
    final headline = nextDate == null
        ? 'Commencez votre suivi menstruel'
        : 'Votre rythme devient plus lisible';
    final subtitle = nextDate == null
        ? 'Ajoutez vos cycles pour obtenir des reperes sur les prochaines dates, la phase et les symptomes les plus frequents.'
        : 'Prochaine date estimee: ${_fmtDate(nextDate)}. Gardez un suivi plus clair, plus doux et plus utile au quotidien.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF472B6), Color(0xFFE84C88), Color(0xFFC026D3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(isDark ? 0.24 : 0.18),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -14,
            right: -6,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.water_drop_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headline,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latest?.displayPhase.isNotEmpty == true
                              ? 'Phase actuelle: ${latest!.displayPhase}'
                              : 'Suivi menstruel intelligent',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.92),
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (nextDate != null) _heroChip(_fmtDate(nextDate)),
                  if (latest?.flow.isNotEmpty == true) _heroChip(latest!.flow),
                  if (latest?.mood.isNotEmpty == true) _heroChip(latest!.mood),
                  if (latest?.symptoms.isNotEmpty == true)
                    _heroChip('${latest!.symptoms.length} symptome(s)'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip({
    required Color cardBg,
    required Color text,
    required Color sub,
    required Color accent,
    required DateTime? nextDate,
    required int? averageCycle,
    required int? averageDuration,
    required _CycleEntry latest,
  }) {
    final items = <Map<String, dynamic>>[
      {
        'label': 'Prochain cycle',
        'value': nextDate != null ? _fmtDate(nextDate) : '--',
        'icon': Icons.event_note_outlined,
      },
      {
        'label': 'Cycle moyen',
        'value': averageCycle != null ? '$averageCycle j' : '--',
        'icon': Icons.sync_alt_outlined,
      },
      {
        'label': 'Duree moyenne',
        'value': averageDuration != null ? '$averageDuration j' : '--',
        'icon': Icons.timelapse_outlined,
      },
      {
        'label': 'Symptomes',
        'value': '${latest.symptoms.length}',
        'icon': Icons.spa_outlined,
      },
    ];

    return SizedBox(
      height: 134,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return SizedBox(
            width: 172,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color.lerp(cardBg, accent, 0.05),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: accent.withOpacity(0.10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(item['icon'] as IconData, color: accent),
                  ),
                  const Spacer(),
                  Text(
                    item['value'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['label'] as String,
                    style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHighlightsCard({
    required Color cardBg,
    required Color text,
    required Color sub,
    required Color accent,
    required _CycleEntry latest,
    required String fertileWindow,
    required DateTime? nextDate,
  }) {
    final items = <Map<String, String>>[
      {
        'label': 'Dernier debut',
        'value': latest.startDate != null ? _fmtDate(latest.startDate!) : '--',
      },
      {
        'label': 'Phase',
        'value': latest.displayPhase.isNotEmpty ? latest.displayPhase : '--',
      },
      {
        'label': 'Fenetre fertile',
        'value': fertileWindow.isNotEmpty ? fertileWindow : 'A estimer',
      },
      {
        'label': 'Ressenti',
        'value': _joinParts([
          if (latest.flow.isNotEmpty) latest.flow,
          if (latest.mood.isNotEmpty) latest.mood,
          if (latest.energy.isNotEmpty) 'energie ${latest.energy}',
          if (latest.flow.isEmpty && latest.mood.isEmpty && latest.energy.isEmpty) 'Non renseigne',
        ]),
      },
      {
        'label': 'Prochaine date',
        'value': nextDate != null ? _fmtDate(nextDate) : 'A estimer',
      },
      {
        'label': 'Symptomes',
        'value': latest.symptoms.isNotEmpty
            ? latest.symptoms.take(3).join(', ')
            : 'Aucun symptome',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, Color.lerp(accent, Colors.purple, 0.30)!],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.auto_graph_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reperes du cycle',
                      style: TextStyle(
                        color: text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Une lecture plus claire pour anticiper vos prochaines etapes et garder un historique utile.',
                      style: TextStyle(
                        color: sub,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 560;
              final itemWidth = wide
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: items.map((item) {
                  return SizedBox(
                    width: itemWidth,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: accent.withOpacity(0.10)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['label']!,
                            style: TextStyle(
                              color: sub,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item['value']!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: text,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCycleCard({
    required Color cardBg,
    required Color text,
    required Color sub,
    required Color accent,
    required _CycleEntry entry,
  }) {
    final nextDate = _predictedNext(entry.startDate, entry.cycleLength);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent.withOpacity(0.90), accent.withOpacity(0.55)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.water_drop_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.startDate != null ? _fmtDate(entry.startDate!) : 'Cycle sans date',
                      style: TextStyle(
                        color: text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _joinParts([
                        if (entry.duration != null) 'duree ${entry.duration} j',
                        if (entry.cycleLength != null) 'cycle ${entry.cycleLength} j',
                        entry.displayPhase,
                      ]),
                      style: TextStyle(
                        color: sub,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (entry.flow.isNotEmpty) _chipPill(entry.flow, accent, text),
              if (entry.mood.isNotEmpty) _chipPill(entry.mood, accent, text),
              if (entry.energy.isNotEmpty) _chipPill('Energie ${entry.energy}', accent, text),
              if (nextDate != null) _chipPill('Prochaine ${_fmtDate(nextDate)}', accent, text),
            ],
          ),
          if (entry.symptoms.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.symptoms
                  .map((item) => _chipPill(item, accent, sub))
                  .toList(growable: false),
            ),
          ],
          if (entry.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              entry.notes,
              style: TextStyle(
                color: sub,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openForm(doc: entry.doc),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier'),
              ),
              OutlinedButton.icon(
                onPressed: () => _deleteDoc(entry.doc),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required Color cardBg,
    required Color text,
    required Color sub,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.water_drop_outlined, color: accent, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            'Aucun cycle enregistre',
            style: TextStyle(
              color: text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ajoutez un premier suivi pour visualiser vos prochaines dates, votre phase et vos symptomes dans une interface plus claire.',
            style: TextStyle(
              color: sub,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
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

  List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return _stringToList((raw ?? '').toString());
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _reveal(int index, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + (index * 90)),
      curve: Curves.easeOutCubic,
      builder: (context, value, builtChild) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 14),
          child: Opacity(opacity: value, child: builtChild),
        );
      },
      child: child,
    );
  }

  Widget _chipPill(String label, Color accent, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.10)),
      ),
      child: Text(
        label,
        style: TextStyle(color: text, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _sheetLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 15,
      ),
    );
  }

  Widget _choiceWrap({
    required List<String> options,
    required String selected,
    required Color accent,
    required Color text,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((item) {
        final isSelected = item == selected;
        return ChoiceChip(
          label: Text(item),
          selected: isSelected,
          showCheckmark: false,
          backgroundColor: accent.withOpacity(0.06),
          selectedColor: accent.withOpacity(0.18),
          labelStyle: TextStyle(
            color: text,
            fontWeight: FontWeight.w700,
          ),
          onSelected: (_) => onSelected(isSelected ? '' : item),
        );
      }).toList(growable: false),
    );
  }
}

class _CycleEntry {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final DateTime? startDate;
  final int? duration;
  final int? cycleLength;
  final String phase;
  final String flow;
  final String mood;
  final String energy;
  final List<String> symptoms;
  final String notes;
  final String inferredPhase;

  const _CycleEntry({
    required this.doc,
    required this.startDate,
    required this.duration,
    required this.cycleLength,
    required this.phase,
    required this.flow,
    required this.mood,
    required this.energy,
    required this.symptoms,
    required this.notes,
    required this.inferredPhase,
  });

  String get displayPhase => phase.isNotEmpty ? phase : inferredPhase;
}

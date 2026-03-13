import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'health_user_context.dart';

class HealthAiPage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthAiPage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthAiPage> createState() => _HealthAiPageState();
}

class _HealthAiPageState extends State<HealthAiPage> {
  bool _loading = true;
  bool _analyzing = false;
  String _report = '';
  DateTime? _reportAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await widget.contextRef.userRef.get();
    final data = snap.data() ?? <String, dynamic>{};
    final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};
    _report = (health['aiReport'] ?? '').toString();
    final ts = health['aiReportAt'];
    if (ts is Timestamp) _reportAt = ts.toDate();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _analyze() async {
    if (_analyzing) return;
    final apiKey = dotenv.maybeGet('GEMINI_API_KEY') ?? '';
    if (apiKey.isEmpty) {
      _snack('GEMINI_API_KEY manquant', error: true);
      return;
    }
    setState(() => _analyzing = true);
    try {
      final snap = await widget.contextRef.userRef.get();
      final data = snap.data() ?? <String, dynamic>{};
      final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};

      final summary = _buildSummary(health);
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      final prompt = [
        'Tu es un assistant medical.',
        'Fais un bref bilan en francais (5 a 7 points) sur ces donnees de sante.',
        'Ajoute 3 recommandations pratiques.',
        'Donnees:',
        summary,
      ].join('\n');
      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';
      final recs = _extractRecommendations(text);

      await widget.contextRef.userRef.set(
        {
          'health.aiReport': text,
          'health.aiRecommendations': recs,
          'health.aiReportAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (mounted) {
        setState(() {
          _report = text;
          _reportAt = DateTime.now();
        });
      }
    } catch (e) {
      _snack('Erreur IA: $e', error: true);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  String _buildSummary(Map<String, dynamic> health) {
    final weight = health['weight'] ?? health['weightKg'];
    final height = health['height'] ?? health['heightCm'];
    final bloodType = health['bloodType'] ?? health['groupe'];
    final allergies = _listToString(health['allergies']);
    final conditions = _listToString(health['chronicConditions'] ?? health['conditions']);
    final tension = health['bloodPressure'] ?? health['tension'];
    final glycemie = health['glucose'] ?? health['glycemie'];
    final heartRate = health['heartRate'] ?? health['frequenceCardiaque'];
    return [
      'poids: ${weight ?? 'n/d'}',
      'taille: ${height ?? 'n/d'}',
      'groupe sanguin: ${bloodType ?? 'n/d'}',
      'allergies: ${allergies.isEmpty ? 'n/d' : allergies}',
      'conditions: ${conditions.isEmpty ? 'n/d' : conditions}',
      'tension: ${tension ?? 'n/d'}',
      'glycemie: ${glycemie ?? 'n/d'}',
      'frequence cardiaque: ${heartRate ?? 'n/d'}',
    ].join('\n');
  }

  String _listToString(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).join(', ');
    }
    return (raw ?? '').toString();
  }

  List<String> _extractRecommendations(String raw) {
    final lines = raw
        .split('\n')
        .map((e) => e.replaceAll(RegExp(r'^[-*\\d\\.\\s]+'), '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];
    final recs = lines.length > 5 ? lines.sublist(0, 5) : lines;
    return recs;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check IA'),
        actions: [
          if (_analyzing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            IconButton(onPressed: _analyze, icon: const Icon(Icons.psychology_outlined)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_reportAt != null ? 'Dernier rapport: ${_fmtDate(_reportAt!)}' : 'Aucun rapport'),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_report.isEmpty ? 'Lance une analyse pour generer un bilan.' : _report),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _analyzing ? null : _analyze,
              child: const Text('Lancer analyse'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year}';
  }
}

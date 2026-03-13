import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'health_user_context.dart';

class HealthPreventionPage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthPreventionPage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthPreventionPage> createState() => _HealthPreventionPageState();
}

class _HealthPreventionPageState extends State<HealthPreventionPage> {
  bool _loading = true;
  bool _generating = false;
  List<String> _tips = [];
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await widget.contextRef.userRef.get();
    final data = snap.data() ?? <String, dynamic>{};
    final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};
    _tips = _stringList(health['preventionTips'] ?? health['tips']);
    final ts = health['preventionUpdatedAt'];
    if (ts is Timestamp) _updatedAt = ts.toDate();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _generate() async {
    if (_generating) return;
    final apiKey = dotenv.maybeGet('GEMINI_API_KEY') ?? '';
    if (apiKey.isEmpty) {
      _snack('GEMINI_API_KEY manquant', error: true);
      return;
    }
    setState(() => _generating = true);
    try {
      final snap = await widget.contextRef.userRef.get();
      final data = snap.data() ?? <String, dynamic>{};
      final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};

      final prompt = [
        'Tu es un assistant medical.',
        'Donne 6 a 8 conseils de prevention personnalises en francais.',
        'Base-toi sur les donnees suivantes:',
        _buildSummary(health),
      ].join('\n');

      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';
      final tips = _extractTips(text);

      await widget.contextRef.userRef.set(
        {
          'health.preventionTips': tips,
          'health.preventionUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (mounted) {
        setState(() {
          _tips = tips;
          _updatedAt = DateTime.now();
        });
      }
    } catch (e) {
      _snack('Erreur IA: $e', error: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String _buildSummary(Map<String, dynamic> health) {
    final weight = health['weight'] ?? health['weightKg'];
    final height = health['height'] ?? health['heightCm'];
    final bloodType = health['bloodType'] ?? health['groupe'];
    final allergies = _listToString(health['allergies']);
    final conditions = _listToString(health['chronicConditions'] ?? health['conditions']);
    return [
      'poids: ${weight ?? 'n/d'}',
      'taille: ${height ?? 'n/d'}',
      'groupe sanguin: ${bloodType ?? 'n/d'}',
      'allergies: ${allergies.isEmpty ? 'n/d' : allergies}',
      'conditions: ${conditions.isEmpty ? 'n/d' : conditions}',
    ].join('\n');
  }

  List<String> _extractTips(String raw) {
    final lines = raw
        .split('\n')
        .map((e) => e.replaceAll(RegExp(r'^[-*\\d\\.\\s]+'), '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];
    return lines.length > 8 ? lines.sublist(0, 8) : lines;
  }

  List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    final s = (raw ?? '').toString();
    if (s.isEmpty) return const [];
    return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  String _listToString(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).join(', ');
    return (raw ?? '').toString();
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
        title: const Text('Prevention & conseils'),
        actions: [
          if (_generating)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            IconButton(onPressed: _generate, icon: const Icon(Icons.auto_awesome)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_updatedAt != null ? 'Mise a jour: ${_fmtDate(_updatedAt!)}' : 'Aucun conseil'),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _tips.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (ctx, i) => ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(_tips[i]),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: _generating ? null : _generate,
              child: const Text('Generer des conseils'),
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

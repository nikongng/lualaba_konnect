import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'health_user_context.dart';

class HealthQrPage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthQrPage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthQrPage> createState() => _HealthQrPageState();
}

class _HealthQrPageState extends State<HealthQrPage> {
  bool _loading = true;
  String _payload = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await widget.contextRef.userRef.get();
    final data = snap.data() ?? <String, dynamic>{};
    final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};

    final payload = {
      'userId': widget.contextRef.userId,
      'bloodType': health['bloodType'] ?? '',
      'allergies': _stringList(health['allergies']),
      'conditions': _stringList(health['chronicConditions'] ?? health['conditions']),
      'emergencyName': health['emergencyName'] ?? health['emergencyContact'] ?? '',
      'emergencyPhone': health['emergencyPhone'] ?? health['emergencyNumber'] ?? '',
      'updatedAt': DateTime.now().toIso8601String(),
    };
    _payload = jsonEncode(payload);
    if (mounted) setState(() => _loading = false);
  }

  List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    final s = (raw ?? '').toString();
    if (s.isEmpty) return const [];
    return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('QR Code sante')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('Scannez pour acceder aux infos essentielles'),
            const SizedBox(height: 16),
            QrImageView(
              data: _payload,
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 16),
            const Text(
              'Contenu: groupe sanguin, allergies, conditions, contact urgence.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

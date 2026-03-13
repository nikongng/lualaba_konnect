import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'health_notification_scheduler.dart';
import 'health_user_context.dart';

class HealthNotificationsPage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthNotificationsPage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthNotificationsPage> createState() => _HealthNotificationsPageState();
}

class _HealthNotificationsPageState extends State<HealthNotificationsPage> {
  bool _loading = true;
  bool _meds = false;
  bool _appointments = false;
  bool _cycle = false;
  bool _ai = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await widget.contextRef.userRef.get();
    final data = snap.data() ?? <String, dynamic>{};
    final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};
    _meds = health['medicationNotifications'] == true;
    _appointments = health['appointmentNotifications'] == true;
    _cycle = health['cycleNotifications'] == true;
    _ai = (health['aiNotifications'] ?? health['aiAlertsEnabled']) == true;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    await widget.contextRef.userRef.set(
      {
        'health.medicationNotifications': _meds,
        'health.appointmentNotifications': _appointments,
        'health.cycleNotifications': _cycle,
        'health.aiNotifications': _ai,
        'health.updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await HealthNotificationScheduler.refreshForUser(widget.contextRef);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications mises a jour')));
    }
  }

  Future<void> _testNotification() async {
    await NotificationService.showNotification(
      'Rappel sante',
      'Test notification intelligente',
      payload: 'health_test',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications intelligentes'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: _meds,
            onChanged: (v) => setState(() => _meds = v),
            title: const Text('Prise de medicaments'),
          ),
          SwitchListTile(
            value: _appointments,
            onChanged: (v) => setState(() => _appointments = v),
            title: const Text('Rendez-vous medicaux'),
          ),
          SwitchListTile(
            value: _cycle,
            onChanged: (v) => setState(() => _cycle = v),
            title: const Text('Cycle menstruel'),
          ),
          SwitchListTile(
            value: _ai,
            onChanged: (v) => setState(() => _ai = v),
            title: const Text('Alertes IA'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _testNotification,
            child: const Text('Tester une notification'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _save,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

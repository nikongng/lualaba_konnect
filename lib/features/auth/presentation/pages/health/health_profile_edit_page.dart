import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'health_user_context.dart';

class HealthProfileEditPage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthProfileEditPage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthProfileEditPage> createState() => _HealthProfileEditPageState();
}

class _HealthProfileEditPageState extends State<HealthProfileEditPage> {
  bool _loading = true;

  final _bloodTypeCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _tensionCtrl = TextEditingController();
  final _glycemieCtrl = TextEditingController();
  final _heartRateCtrl = TextEditingController();
  final _activityCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();
  final _historyCtrl = TextEditingController();
  final _hospitalizationsCtrl = TextEditingController();
  final _vaccinationsCtrl = TextEditingController();

  bool _medNotif = false;
  bool _apptNotif = false;
  bool _cycleNotif = false;
  bool _aiNotif = false;
  bool _smartReminders = false;
  bool _thresholdAlerts = false;
  bool _sosGps = false;
  bool _sosNotif = false;
  bool _teleconsult = false;
  bool _pharmacy = false;
  bool _vaccinationAlerts = false;
  bool _screeningAlerts = false;
  bool _aiEnabled = false;
  bool _aiDocAnalysis = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bloodTypeCtrl.dispose();
    _allergiesCtrl.dispose();
    _conditionsCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _tensionCtrl.dispose();
    _glycemieCtrl.dispose();
    _heartRateCtrl.dispose();
    _activityCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _historyCtrl.dispose();
    _hospitalizationsCtrl.dispose();
    _vaccinationsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final snap = await widget.contextRef.userRef.get();
    final data = snap.data() ?? <String, dynamic>{};
    final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};

    _bloodTypeCtrl.text = (health['bloodType'] ?? '').toString();
    _allergiesCtrl.text = _listToString(health['allergies']);
    _conditionsCtrl.text = _listToString(health['chronicConditions'] ?? health['conditions']);
    _weightCtrl.text = (health['weight'] ?? health['weightKg'] ?? '').toString();
    _heightCtrl.text = (health['height'] ?? health['heightCm'] ?? '').toString();
    _tensionCtrl.text = (health['bloodPressure'] ?? health['tension'] ?? '').toString();
    _glycemieCtrl.text = (health['glucose'] ?? health['glycemie'] ?? '').toString();
    _heartRateCtrl.text = (health['heartRate'] ?? health['frequenceCardiaque'] ?? '').toString();
    _activityCtrl.text = (health['activity'] ?? health['activitePhysique'] ?? '').toString();
    _emergencyNameCtrl.text = (health['emergencyName'] ?? health['emergencyContact'] ?? '').toString();
    _emergencyPhoneCtrl.text = (health['emergencyPhone'] ?? health['emergencyNumber'] ?? '').toString();
    _historyCtrl.text = _listToString(health['medicalHistory'] ?? health['history']);
    _hospitalizationsCtrl.text = _listToString(health['hospitalizations']);
    _vaccinationsCtrl.text = _listToString(health['vaccinations']);

    _medNotif = health['medicationNotifications'] == true;
    _apptNotif = health['appointmentNotifications'] == true;
    _cycleNotif = health['cycleNotifications'] == true;
    _aiNotif = (health['aiNotifications'] ?? health['aiAlertsEnabled']) == true;
    _smartReminders = health['smartReminders'] == true;
    _thresholdAlerts = health['thresholdAlerts'] == true;
    _sosGps = health['sosGpsEnabled'] == true;
    _sosNotif = health['sosNotifications'] == true;
    _teleconsult = health['teleconsultationEnabled'] == true;
    _pharmacy = health['pharmacyEnabled'] == true;
    _vaccinationAlerts = health['vaccinationAlerts'] == true;
    _screeningAlerts = health['screeningAlerts'] == true;
    _aiEnabled = (health['aiEnabled'] ?? health['checkIa']) == true;
    _aiDocAnalysis = (health['aiDocAnalysis'] ?? health['aiDocuments']) == true;

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final payload = <String, dynamic>{
      'bloodType': _bloodTypeCtrl.text.trim(),
      'allergies': _stringToList(_allergiesCtrl.text),
      'chronicConditions': _stringToList(_conditionsCtrl.text),
      'weight': _toDouble(_weightCtrl.text),
      'height': _toDouble(_heightCtrl.text),
      'bloodPressure': _tensionCtrl.text.trim(),
      'glucose': _glycemieCtrl.text.trim(),
      'heartRate': _heartRateCtrl.text.trim(),
      'activity': _activityCtrl.text.trim(),
      'emergencyName': _emergencyNameCtrl.text.trim(),
      'emergencyPhone': _emergencyPhoneCtrl.text.trim(),
      'medicalHistory': _stringToList(_historyCtrl.text),
      'hospitalizations': _stringToList(_hospitalizationsCtrl.text),
      'vaccinations': _stringToList(_vaccinationsCtrl.text),
      'medicationNotifications': _medNotif,
      'appointmentNotifications': _apptNotif,
      'cycleNotifications': _cycleNotif,
      'aiNotifications': _aiNotif,
      'smartReminders': _smartReminders,
      'thresholdAlerts': _thresholdAlerts,
      'sosGpsEnabled': _sosGps,
      'sosNotifications': _sosNotif,
      'teleconsultationEnabled': _teleconsult,
      'pharmacyEnabled': _pharmacy,
      'vaccinationAlerts': _vaccinationAlerts,
      'screeningAlerts': _screeningAlerts,
      'aiEnabled': _aiEnabled,
      'aiDocAnalysis': _aiDocAnalysis,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await widget.contextRef.userRef.set(
      {'health': payload},
      SetOptions(merge: true),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil sante mis a jour')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil medical'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.save)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Informations sante', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(controller: _bloodTypeCtrl, decoration: const InputDecoration(labelText: 'Groupe sanguin')),
          TextField(controller: _allergiesCtrl, decoration: const InputDecoration(labelText: 'Allergies (virgules)')),
          TextField(controller: _conditionsCtrl, decoration: const InputDecoration(labelText: 'Maladies chroniques (virgules)')),
          TextField(controller: _weightCtrl, decoration: const InputDecoration(labelText: 'Poids (kg)')),
          TextField(controller: _heightCtrl, decoration: const InputDecoration(labelText: 'Taille (cm)')),
          TextField(controller: _tensionCtrl, decoration: const InputDecoration(labelText: 'Tension')),
          TextField(controller: _glycemieCtrl, decoration: const InputDecoration(labelText: 'Glycemie')),
          TextField(controller: _heartRateCtrl, decoration: const InputDecoration(labelText: 'Frequence cardiaque')),
          TextField(controller: _activityCtrl, decoration: const InputDecoration(labelText: 'Activite physique')),
          const SizedBox(height: 12),
          const Text('Urgence', style: TextStyle(fontWeight: FontWeight.w700)),
          TextField(controller: _emergencyNameCtrl, decoration: const InputDecoration(labelText: 'Contact urgence (nom)')),
          TextField(controller: _emergencyPhoneCtrl, decoration: const InputDecoration(labelText: 'Contact urgence (telephone)')),
          const SizedBox(height: 12),
          const Text('Historique', style: TextStyle(fontWeight: FontWeight.w700)),
          TextField(controller: _historyCtrl, decoration: const InputDecoration(labelText: 'Historique medical (virgules)')),
          TextField(controller: _hospitalizationsCtrl, decoration: const InputDecoration(labelText: 'Hospitalisations (virgules)')),
          TextField(controller: _vaccinationsCtrl, decoration: const InputDecoration(labelText: 'Vaccinations (virgules)')),
          const SizedBox(height: 12),
          const Text('Notifications & modules', style: TextStyle(fontWeight: FontWeight.w700)),
          SwitchListTile(value: _medNotif, onChanged: (v) => setState(() => _medNotif = v), title: const Text('Notif medicaments')),
          SwitchListTile(value: _apptNotif, onChanged: (v) => setState(() => _apptNotif = v), title: const Text('Notif rendez-vous')),
          SwitchListTile(value: _cycleNotif, onChanged: (v) => setState(() => _cycleNotif = v), title: const Text('Notif cycle')),
          SwitchListTile(value: _aiNotif, onChanged: (v) => setState(() => _aiNotif = v), title: const Text('Notif IA')),
          SwitchListTile(value: _smartReminders, onChanged: (v) => setState(() => _smartReminders = v), title: const Text('Rappel intelligent')),
          SwitchListTile(value: _thresholdAlerts, onChanged: (v) => setState(() => _thresholdAlerts = v), title: const Text('Alertes seuils')),
          SwitchListTile(value: _sosGps, onChanged: (v) => setState(() => _sosGps = v), title: const Text('SOS GPS')),
          SwitchListTile(value: _sosNotif, onChanged: (v) => setState(() => _sosNotif = v), title: const Text('SOS notifications')),
          SwitchListTile(value: _teleconsult, onChanged: (v) => setState(() => _teleconsult = v), title: const Text('Teleconsultation')),
          SwitchListTile(value: _pharmacy, onChanged: (v) => setState(() => _pharmacy = v), title: const Text('Pharmacie')),
          SwitchListTile(value: _vaccinationAlerts, onChanged: (v) => setState(() => _vaccinationAlerts = v), title: const Text('Alertes vaccination')),
          SwitchListTile(value: _screeningAlerts, onChanged: (v) => setState(() => _screeningAlerts = v), title: const Text('Alertes depistage')),
          SwitchListTile(value: _aiEnabled, onChanged: (v) => setState(() => _aiEnabled = v), title: const Text('Check IA')),
          SwitchListTile(value: _aiDocAnalysis, onChanged: (v) => setState(() => _aiDocAnalysis = v), title: const Text('Analyse documents IA')),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      ),
    );
  }

  double? _toDouble(String raw) {
    final s = raw.trim().replaceAll(',', '.');
    return s.isEmpty ? null : double.tryParse(s);
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
}

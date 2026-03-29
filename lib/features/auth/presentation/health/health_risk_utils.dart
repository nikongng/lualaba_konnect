class HealthRiskComputation {
  final int score;
  final String label;
  final List<String> risks;

  const HealthRiskComputation({
    required this.score,
    required this.label,
    required this.risks,
  });
}

HealthRiskComputation computeHealthRiskSummary({
  required double? bmi,
  required String tension,
  required String glycemie,
  required String heartRate,
  required List<String> allergies,
  required List<String> conditions,
  required List<String> alerts,
  required List<String> aiAlerts,
  required int treatmentsCount,
}) {
  var score = 86;
  final risks = <String>[];

  void addRisk(String label, int penalty) {
    if (!risks.contains(label)) risks.add(label);
    score -= penalty;
  }

  if (bmi != null) {
    if (bmi >= 30 || bmi < 18.5) {
      addRisk('IMC hors zone stable', 16);
    } else if (bmi >= 25) {
      addRisk('Poids a surveiller', 9);
    }
  }

  final tensionValues = _extractMetricNumbers(tension);
  if (tensionValues.length >= 2) {
    final systolic = tensionValues[0];
    final diastolic = tensionValues[1];
    if (systolic >= 140 || diastolic >= 90) {
      addRisk('Tension elevee', 18);
    } else if (systolic >= 130 || diastolic >= 85) {
      addRisk('Tension a surveiller', 10);
    }
  }

  final glycemiaValues = _extractMetricNumbers(glycemie);
  if (glycemiaValues.isNotEmpty) {
    final glucose = glycemiaValues.first;
    if (glucose <= 20) {
      if (glucose >= 7) {
        addRisk('Glycemie elevee', 18);
      } else if (glucose >= 6) {
        addRisk('Glycemie a surveiller', 10);
      }
    } else {
      if (glucose >= 126) {
        addRisk('Glycemie elevee', 18);
      } else if (glucose >= 110) {
        addRisk('Glycemie a surveiller', 10);
      }
    }
  }

  final heartRateValues = _extractMetricNumbers(heartRate);
  if (heartRateValues.isNotEmpty) {
    final pulse = heartRateValues.first;
    if (pulse > 110 || pulse < 50) {
      addRisk('Frequence cardiaque hors zone', 12);
    } else if (pulse > 100 || pulse < 55) {
      addRisk('Frequence cardiaque a surveiller', 7);
    }
  }

  if (conditions.isNotEmpty) addRisk('Maladies chroniques declarees', 14);
  if (allergies.isNotEmpty) addRisk('Allergies a garder visibles', 5);
  if (alerts.isNotEmpty || aiAlerts.isNotEmpty) addRisk('Alertes sante actives', 16);
  if (treatmentsCount >= 3) addRisk('Traitement quotidien a suivre', 6);

  final clampedScore = score.clamp(18, 97).toInt();
  final label = clampedScore >= 80
      ? 'bon'
      : clampedScore >= 60
          ? 'a surveiller'
          : 'sensible';

  return HealthRiskComputation(
    score: clampedScore,
    label: label,
    risks: risks.isEmpty ? const <String>['Aucun risque critique detecte'] : risks.take(3).toList(growable: false),
  );
}

HealthRiskComputation computeHealthRiskSummaryFromUserData(Map<String, dynamic> data) {
  final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};

  final weight = _toDouble(health['weight'] ?? health['weightKg'] ?? health['poids']);
  final height = _toDouble(health['height'] ?? health['heightCm'] ?? health['taille']);
  final bmi = _computeBmi(weight, height);
  final tension = _safeText(health['bloodPressure'] ?? health['tension']);
  final glycemie = _safeText(health['glucose'] ?? health['glycemie']);
  final heartRate = _safeText(health['heartRate'] ?? health['frequenceCardiaque']);
  final allergies = _stringList(health['allergies']);
  final conditions = _stringList(health['chronicConditions'] ?? health['conditions'] ?? health['medicalConditions']);
  final alerts = _stringList(health['alerts'] ?? health['importantAlerts'] ?? health['notifications']);
  final aiAlerts = _stringList(health['aiAlerts'] ?? health['alertsAi']);
  final meds = _medicationBullets(health['medications']);
  final medsToday = _medicationBullets(health['medicationsToday'] ?? health['todayMedications']);

  return computeHealthRiskSummary(
    bmi: bmi,
    tension: tension,
    glycemie: glycemie,
    heartRate: heartRate,
    allergies: allergies,
    conditions: conditions,
    alerts: alerts,
    aiAlerts: aiAlerts,
    treatmentsCount: medsToday.isNotEmpty ? medsToday.length : meds.length,
  );
}

double? _toDouble(dynamic raw) {
  if (raw is num) return raw.toDouble();
  final value = _safeText(raw).replaceAll(',', '.');
  return value.isEmpty ? null : double.tryParse(value);
}

double? _computeBmi(double? weight, double? heightCm) {
  if (weight == null || heightCm == null || heightCm <= 0) return null;
  final heightMeters = heightCm > 3 ? heightCm / 100 : heightCm;
  if (heightMeters <= 0) return null;
  return weight / (heightMeters * heightMeters);
}

String _safeText(dynamic value) => (value ?? '').toString().trim();

List<String> _stringList(dynamic raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return raw.map((item) => _safeText(item)).where((item) => item.isNotEmpty).toList(growable: false);
  }
  final text = _safeText(raw);
  if (text.isEmpty) return const [];
  if (text.contains(',')) {
    return text.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList(growable: false);
  }
  return <String>[text];
}

List<String> _medicationBullets(dynamic raw) {
  if (raw is List) {
    final out = <String>[];
    for (final item in raw) {
      if (item is Map) {
        final map = item.map((key, value) => MapEntry(key.toString(), value));
        final name = _safeText(map['name'] ?? map['medicament'] ?? map['label']);
        final dose = _safeText(map['dose']);
        final schedule = _safeText(map['schedule'] ?? map['horaire']);
        if (name.isNotEmpty) {
          final details = [
            if (dose.isNotEmpty) dose,
            if (schedule.isNotEmpty) schedule,
          ].join(' / ');
          out.add(details.isNotEmpty ? '$name - $details' : name);
        }
      } else {
        final text = _safeText(item);
        if (text.isNotEmpty) out.add(text);
      }
    }
    return out;
  }
  return _stringList(raw);
}

List<double> _extractMetricNumbers(String raw) {
  final matches = RegExp(r'\d+(?:[.,]\d+)?').allMatches(raw);
  return matches
      .map((match) => double.tryParse(match.group(0)!.replaceAll(',', '.')))
      .whereType<double>()
      .toList(growable: false);
}

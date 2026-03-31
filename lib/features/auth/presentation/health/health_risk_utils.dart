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

String healthRiskDisplayLabel(String label) {
  switch (label) {
    case 'bon':
      return 'Bon';
    case 'a surveiller':
      return 'A surveiller';
    case 'sensible':
      return 'Sensible';
    default:
      return 'En attente';
  }
}

String healthRiskSupportText(int? score) {
  final safeScore = (score ?? 0).clamp(0, 100);
  if (safeScore >= 80) {
    return 'Belle dynamique aujourd hui. Votre score monte en ouverture pour mettre en valeur votre forme.';
  }
  if (safeScore >= 60) {
    return 'Votre profil demande un peu d attention. Suivez les points a surveiller et gardez le rythme.';
  }
  if (safeScore > 0) {
    return 'Votre sante merite une vigilance renforcee. Ouvrez Ma sante pour voir les facteurs qui tirent le score vers le bas.';
  }
  return 'Le score s animera ici des que votre profil sante sera disponible.';
}

String healthRiskTopPoint(List<String> risks) {
  return risks.isEmpty ? 'Aucun risque critique detecte' : risks.first;
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
  final stressLab =
      (health['stressLab'] is Map) ? Map<String, dynamic>.from(health['stressLab'] as Map) : <String, dynamic>{};
  final context =
      (stressLab['context'] is Map) ? Map<String, dynamic>.from(stressLab['context'] as Map) : <String, dynamic>{};
  final face =
      (stressLab['face'] is Map) ? Map<String, dynamic>.from(stressLab['face'] as Map) : <String, dynamic>{};
  final cameraFinger = (stressLab['cameraFinger'] is Map)
      ? Map<String, dynamic>.from(stressLab['cameraFinger'] as Map)
      : <String, dynamic>{};
  final bpExperimental = (cameraFinger['bpExperimental'] is Map)
      ? Map<String, dynamic>.from(cameraFinger['bpExperimental'] as Map)
      : <String, dynamic>{};

  final weight = _toDouble(health['weight'] ?? health['weightKg'] ?? health['poids']);
  final height = _toDouble(health['height'] ?? health['heightCm'] ?? health['taille']);
  final bmi = _computeBmi(weight, height);
  final officialTension = _safeText(health['bloodPressure'] ?? health['tension']);
  final estimatedPressure = _pressureFromMap(bpExperimental);
  final estimatedTension = estimatedPressure == null
      ? ''
      : '${estimatedPressure.systolic.toStringAsFixed(0)}/${estimatedPressure.diastolic.toStringAsFixed(0)}';
  final tension = officialTension.isNotEmpty ? officialTension : estimatedTension;
  final glycemie = _safeText(health['glucose'] ?? health['glycemie']);
  final heartRate = _effectiveHeartRate(health, cameraFinger);
  final allergies = _stringList(health['allergies']);
  final conditions = _stringList(health['chronicConditions'] ?? health['conditions'] ?? health['medicalConditions']);
  final alerts = _stringList(health['alerts'] ?? health['importantAlerts'] ?? health['notifications']);
  final aiAlerts = _stringList(health['aiAlerts'] ?? health['alertsAi']);
  final meds = _medicationBullets(health['medications']);
  final medsToday = _medicationBullets(health['medicationsToday'] ?? health['todayMedications']);
  final treatmentsCount = medsToday.isNotEmpty ? medsToday.length : meds.length;
  final age = _ageFromRaw(data['birthDate'] ?? health['birthDate']);
  final contextStress = _toDouble(context['score']);
  final faceStress = _toDouble(face['score']);
  final stressScore = _toDouble(cameraFinger['stressScore'] ?? cameraFinger['score']);
  final signalQuality = _toDouble(cameraFinger['signalQuality']);
  final hrv = _toDouble(cameraFinger['hrvRmssd']);
  final tensionValues = _extractMetricNumbers(tension);
  final heartRateValues = _extractMetricNumbers(heartRate);
  final glycemiaValues = _extractMetricNumbers(glycemie);

  var score = 96.0;
  final riskPenalties = <String, double>{};

  void addRisk(String label, double penalty) {
    if (penalty <= 0) return;
    final previous = riskPenalties[label];
    if (previous != null && previous >= penalty) return;
    if (previous != null) {
      score += previous;
    }
    riskPenalties[label] = penalty;
    score -= penalty;
  }

  if (bmi != null) {
    if (bmi >= 35 || bmi < 17) {
      addRisk('IMC tres eloigne de la zone stable', 18);
    } else if (bmi >= 30 || bmi < 18.5) {
      addRisk('IMC hors zone stable', 14);
    } else if (bmi >= 27) {
      addRisk('Poids a surveiller', 8);
    } else if (bmi >= 25) {
      addRisk('Poids legerement au-dessus de la zone stable', 4);
    }
  }

  if (tensionValues.length >= 2) {
    final systolic = tensionValues[0];
    final diastolic = tensionValues[1];
    final pressureFactor = officialTension.isNotEmpty
        ? 1.0
        : _experimentalConfidenceFactor(
            confidence: _safeText(bpExperimental['confidence']),
            signalQuality: signalQuality,
          );
    if (systolic >= 160 || diastolic >= 100) {
      addRisk('Tension tres elevee', 22 * pressureFactor);
    } else if (systolic >= 140 || diastolic >= 90) {
      addRisk('Tension elevee', 16 * pressureFactor);
    } else if (systolic >= 130 || diastolic >= 85) {
      addRisk('Tension a surveiller', 8 * pressureFactor);
    } else if (systolic < 90 || diastolic < 60) {
      addRisk('Tension basse', 12 * pressureFactor);
    } else if (systolic < 100 || diastolic < 65) {
      addRisk('Tension plutot basse', 6 * pressureFactor);
    }
  }

  if (glycemiaValues.isNotEmpty) {
    final glucose = glycemiaValues.first;
    if (glucose <= 20) {
      if (glucose < 3.9) {
        addRisk('Glycemie basse', 16);
      } else if (glucose >= 7) {
        addRisk('Glycemie elevee', 18);
      } else if (glucose >= 6) {
        addRisk('Glycemie a surveiller', 10);
      }
    } else {
      if (glucose < 70) {
        addRisk('Glycemie basse', 16);
      } else if (glucose >= 126) {
        addRisk('Glycemie elevee', 18);
      } else if (glucose >= 110) {
        addRisk('Glycemie a surveiller', 10);
      }
    }
  }

  if (heartRateValues.isNotEmpty) {
    final pulse = heartRateValues.first;
    if (pulse > 120 || pulse < 45) {
      addRisk('Frequence cardiaque nettement hors zone', 15);
    } else if (pulse > 110 || pulse < 50) {
      addRisk('Frequence cardiaque hors zone', 12);
    } else if (pulse > 100 || pulse < 55) {
      addRisk('Frequence cardiaque a surveiller', 7);
    }
  }

  final signalFactor = _signalFactor(signalQuality);
  if (hrv != null) {
    if (hrv < 18) {
      addRisk('Variabilite cardiaque basse', 10 * signalFactor);
    } else if (hrv < 26) {
      addRisk('Variabilite cardiaque a surveiller', 7 * signalFactor);
    } else if (hrv < 35) {
      addRisk('Recuperation a surveiller', 4 * signalFactor);
    }
  }

  if (contextStress != null) {
    if (contextStress >= 80) {
      addRisk('Stress climat eleve', 8);
    } else if (contextStress >= 65) {
      addRisk('Stress climat a surveiller', 5);
    } else if (contextStress >= 50) {
      addRisk('Climat fatigant', 2.5);
    }
  }

  if (faceStress != null) {
    if (faceStress >= 80) {
      addRisk('Stress visible sur les expressions faciales', 6);
    } else if (faceStress >= 65) {
      addRisk('Tension faciale a surveiller', 4);
    } else if (faceStress >= 50) {
      addRisk('Legere tension faciale', 2);
    }
  }

  if (stressScore != null) {
    if (stressScore >= 80) {
      addRisk('Charge physiologique elevee', 10 * signalFactor);
    } else if (stressScore >= 65) {
      addRisk('Charge physiologique a surveiller', 6 * signalFactor);
    } else if (stressScore >= 50) {
      addRisk('Fatigue physiologique legere', 3 * signalFactor);
    }
  }

  if (conditions.length >= 3) {
    addRisk('Charge chronique elevee', 16);
  } else if (conditions.isNotEmpty) {
    addRisk('Maladies chroniques declarees', 12);
  }

  if (allergies.length >= 3) {
    addRisk('Allergies multiples a garder visibles', 6);
  } else if (allergies.isNotEmpty) {
    addRisk('Allergies a garder visibles', 4);
  }

  if (alerts.isNotEmpty) {
    addRisk('Alertes sante actives', 12);
  }
  if (aiAlerts.isNotEmpty) {
    addRisk('Alerte IA a verifier', 7);
  }

  if (treatmentsCount >= 5) {
    addRisk('Traitement quotidien complexe', 8);
  } else if (treatmentsCount >= 3) {
    addRisk('Traitement quotidien a suivre', 5);
  }

  if (age != null) {
    if (age >= 75) {
      addRisk('Suivi preventif renforce recommande', 6);
    } else if (age >= 65) {
      addRisk('Suivi preventif a renforcer', 3);
    }
  }

  final clampedScore = score.round().clamp(18, 98).toInt();
  final label = clampedScore >= 82
      ? 'bon'
      : clampedScore >= 62
          ? 'a surveiller'
          : 'sensible';
  final topRisks = riskPenalties.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return HealthRiskComputation(
    score: clampedScore,
    label: label,
    risks: topRisks.isEmpty
        ? const <String>['Aucun risque critique detecte']
        : topRisks.take(3).map((entry) => entry.key).toList(growable: false),
  );
}

double _signalFactor(double? signalQuality) {
  if (signalQuality == null) return 0.7;
  return (signalQuality / 100).clamp(0.45, 1.0);
}

double _experimentalConfidenceFactor({
  required String confidence,
  required double? signalQuality,
}) {
  final signalFactor = _signalFactor(signalQuality);
  final confidenceWeight = switch (confidence.toLowerCase()) {
    'moyenne' => 0.85,
    'faible' => 0.65,
    'tres faible' => 0.45,
    _ => 0.60,
  };
  return (signalFactor * confidenceWeight).clamp(0.35, 0.90);
}

String _effectiveHeartRate(Map<String, dynamic> health, Map<String, dynamic> cameraFinger) {
  final measured = _toDouble(cameraFinger['heartRateBpm']);
  final signalQuality = _toDouble(cameraFinger['signalQuality']);
  if (measured != null && (signalQuality == null || signalQuality >= 45)) {
    return measured.toStringAsFixed(0);
  }

  final fallbackRaw = health['heartRate'] ?? health['frequenceCardiaque'];
  final fallback = _safeText(fallbackRaw);
  if (fallback.isNotEmpty) return fallback;

  return measured?.toStringAsFixed(0) ?? '';
}

int? _ageFromRaw(dynamic raw) {
  final value = _safeText(raw);
  if (value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  final now = DateTime.now();
  var age = now.year - parsed.year;
  if (now.month < parsed.month || (now.month == parsed.month && now.day < parsed.day)) {
    age -= 1;
  }
  return age < 0 ? null : age;
}

_PressureSample? _pressureFromMap(Map<String, dynamic> raw) {
  final systolic = _toDouble(raw['systolic']);
  final diastolic = _toDouble(raw['diastolic']);
  if (systolic == null || diastolic == null) return null;
  return _PressureSample(systolic: systolic, diastolic: diastolic);
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

class _PressureSample {
  final double systolic;
  final double diastolic;

  const _PressureSample({
    required this.systolic,
    required this.diastolic,
  });
}

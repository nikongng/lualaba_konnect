import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'health_user_context.dart';

class HealthPpgVitalsPage extends StatefulWidget {
  const HealthPpgVitalsPage({
    super.key,
    required this.contextRef,
  });

  final HealthUserContext contextRef;

  @override
  State<HealthPpgVitalsPage> createState() => _HealthPpgVitalsPageState();
}

class _HealthPpgVitalsPageState extends State<HealthPpgVitalsPage> {
  CameraController? _controller;
  bool _initializing = true;
  bool _measuring = false;
  bool _processingFrame = false;
  String? _error;
  Timer? _ticker;
  DateTime? _measurementStartedAt;
  Duration _elapsed = Duration.zero;

  final List<_PpgSample> _samples = <_PpgSample>[];
  _PpgMeasurementResult? _result;
  double? _liveIntensity;
  Map<String, dynamic> _userData = <String, dynamic>{};

  static const Duration _measurementDuration = Duration(seconds: 30);

  CollectionReference<Map<String, dynamic>> get _metricsRef =>
      widget.contextRef.subCollection('health_measurements');

  CollectionReference<Map<String, dynamic>> get _sessionsRef =>
      widget.contextRef.subCollection('health_stress_sessions');

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _disposeCamera();
    super.dispose();
  }

  Future<void> _disposeCamera() async {
    try {
      if (_controller?.value.isStreamingImages == true) {
        await _controller?.stopImageStream();
      }
    } catch (_) {}
    try {
      await _controller?.dispose();
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'La mesure PPG camera/doigt est disponible surtout sur mobile.';
        });
      }
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('Aucune camera disponible');
      }

      CameraDescription selected = cameras.first;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selected = camera;
          break;
        }
      }

      final controller = CameraController(
        selected,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initializing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Initialisation camera impossible: $e';
      });
    }
  }

  Future<void> _startMeasurement() async {
    final controller = _controller;
    if (controller == null || _measuring) return;

    try {
      final userSnap = await widget.contextRef.userRef.get();
      _userData = userSnap.data() ?? <String, dynamic>{};

      _samples.clear();
      _result = null;
      _liveIntensity = null;
      _elapsed = Duration.zero;
      _measurementStartedAt = DateTime.now();

      await controller.setFlashMode(FlashMode.torch);
      await controller.startImageStream(_onFrame);

      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted || _measurementStartedAt == null) return;
        final elapsed = DateTime.now().difference(_measurementStartedAt!);
        if (elapsed >= _measurementDuration) {
          _stopMeasurement();
          return;
        }
        setState(() => _elapsed = elapsed);
      });

      if (!mounted) return;
      setState(() => _measuring = true);
    } catch (e) {
      _snack('Demarrage mesure impossible: $e', error: true);
    }
  }

  Future<void> _stopMeasurement() async {
    final controller = _controller;
    if (controller == null || !_measuring) return;

    _ticker?.cancel();

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}

    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}

    if (!mounted) return;
    setState(() => _measuring = false);

    final result = _analyzeSamples(_samples, _userData);
    setState(() => _result = result);
    await _persistResult(result);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (!_measuring || _processingFrame) return;
    _processingFrame = true;
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (_samples.isNotEmpty && nowMs - _samples.last.timeMs < 45) return;

      final intensity = _computeFrameIntensity(image);
      if (intensity == null) return;

      _samples.add(_PpgSample(timeMs: nowMs, intensity: intensity));
      if (_samples.length > 900) {
        _samples.removeAt(0);
      }

      if (mounted) {
        setState(() => _liveIntensity = intensity);
      }
    } finally {
      _processingFrame = false;
    }
  }

  double? _computeFrameIntensity(CameraImage image) {
    if (image.planes.isEmpty) return null;

    if (image.format.group == ImageFormatGroup.bgra8888) {
      final bytes = image.planes.first.bytes;
      if (bytes.isEmpty) return null;
      var total = 0.0;
      var count = 0;
      for (var i = 0; i + 3 < bytes.length; i += 64) {
        total += bytes[i + 2];
        count++;
      }
      return count == 0 ? null : total / count;
    }

    final bytes = image.planes.first.bytes;
    if (bytes.isEmpty) return null;
    var total = 0.0;
    var count = 0;
    for (var i = 0; i < bytes.length; i += 24) {
      total += bytes[i];
      count++;
    }
    return count == 0 ? null : total / count;
  }

  _PpgMeasurementResult _analyzeSamples(
    List<_PpgSample> samples,
    Map<String, dynamic> userData,
  ) {
    if (samples.length < 90) {
      return const _PpgMeasurementResult(
        status: 'insuffisant',
        summary: 'Pas assez de signal. Reessayez en couvrant completement la camera avec le doigt.',
        caution:
            'Gardez le doigt immobile sur l objectif arriere et le flash pendant 30 secondes.',
      );
    }

    final startMs = samples.first.timeMs;
    final timesMs = samples.map((s) => (s.timeMs - startMs).toDouble()).toList(growable: false);
    final raw = samples.map((s) => s.intensity).toList(growable: false);
    final smooth = _movingAverage(raw, 4);
    final trend = _movingAverage(smooth, 18);
    final band = List<double>.generate(
      smooth.length,
      (index) => smooth[index] - trend[index],
      growable: false,
    );

    final mean = _mean(band);
    final std = _stdDev(band, mean);
    final threshold = mean + (std * 0.55);
    final peakTimes = <double>[];
    var lastPeakMs = -1000.0;

    for (var i = 1; i < band.length - 1; i++) {
      final value = band[i];
      if (value > band[i - 1] &&
          value >= band[i + 1] &&
          value > threshold &&
          (timesMs[i] - lastPeakMs) >= 380) {
        peakTimes.add(timesMs[i]);
        lastPeakMs = timesMs[i];
      }
    }

    final rrIntervals = <double>[];
    for (var i = 1; i < peakTimes.length; i++) {
      final interval = peakTimes[i] - peakTimes[i - 1];
      if (interval >= 400 && interval <= 1500) {
        rrIntervals.add(interval);
      }
    }

    final waveform = _normalizeWaveform(band, maxPoints: 180);
    final coverage = _fingerCoverageScore(raw);
    final stability = _signalStabilityScore(rrIntervals, std);
    final quality = ((coverage * 0.45) + (stability * 0.55)).round().clamp(0, 100);

    if (rrIntervals.length < 2) {
      return _PpgMeasurementResult(
        status: 'qualite faible',
        summary: 'Le signal existe mais les pulsations ne sont pas assez stables pour une lecture fiable.',
        caution:
            'Reessayez en pressant legerement le doigt, sans bouger, avec le flash allume et une respiration calme.',
        signalQuality: quality,
        waveform: waveform,
      );
    }

    final bpm = 60000 / _mean(rrIntervals);
    final hrv = _rmssd(rrIntervals);
    final stressScore = _estimateStressScore(bpm: bpm, hrv: hrv, quality: quality);
    final pressure = _estimateBloodPressure(
      userData: userData,
      bpm: bpm,
      hrv: hrv,
      quality: quality,
      stressScore: stressScore,
    );

    return _PpgMeasurementResult(
      status: 'mesure terminee',
      summary:
          'Mesure terminee. La frequence cardiaque et la variabilite cardiaque ont ete lues a partir du signal camera + doigt.',
      caution:
          'La tension affichee ici reste une estimation. Confirmez toujours avec un brassard si vous voulez une valeur medicale.',
      heartRateBpm: bpm,
      hrvRmssd: hrv,
      signalQuality: quality,
      waveform: waveform,
      stressScore: stressScore,
      bpEstimate: pressure,
    );
  }

  int _fingerCoverageScore(List<double> raw) {
    final mean = _mean(raw);
    final amplitude = raw.isEmpty ? 0 : raw.reduce(math.max) - raw.reduce(math.min);
    var score = 0.0;
    if (mean >= 90 && mean <= 250) score += 60;
    if (amplitude >= 2.5) score += 25;
    if (amplitude >= 5.0) score += 15;
    return score.round().clamp(0, 100);
  }

  int _signalStabilityScore(List<double> rrIntervals, double std) {
    if (rrIntervals.isEmpty) return 0;
    final rrMean = _mean(rrIntervals);
    final rrStd = _stdDev(rrIntervals, rrMean);
    var score = 100.0;
    score -= (rrStd / 12).clamp(0, 45);
    score -= ((0.6 - std.abs()).abs() * 30).clamp(0, 35);
    return score.round().clamp(0, 100);
  }

  int _estimateStressScore({
    required double bpm,
    required double hrv,
    required int quality,
  }) {
    final hrLoad = ((bpm - 68).clamp(0, 55) * 1.35);
    final hrvLoad = ((42 - hrv).clamp(0, 32) * 1.4);
    final qualityPenalty = ((100 - quality).clamp(0, 100) * 0.18);
    return (18 + hrLoad + hrvLoad + qualityPenalty).round().clamp(0, 100);
  }

  _ExperimentalPressure _estimateBloodPressure({
    required Map<String, dynamic> userData,
    required double bpm,
    required double hrv,
    required int quality,
    required int stressScore,
  }) {
    final health = (userData['health'] is Map)
        ? Map<String, dynamic>.from(userData['health'] as Map)
        : <String, dynamic>{};
    final baseline = _parsePressure(
      (health['bloodPressure'] ?? health['tension'] ?? '').toString(),
    );
    final age = _inferAge(userData, health);
    final weight = _toDouble(health['weight'] ?? health['weightKg'] ?? health['poids']);
    final height = _toDouble(health['height'] ?? health['heightCm'] ?? health['taille']);
    final bmi = _computeBmi(weight, height);

    final baseSys = baseline?.systolic ??
        (110 +
                ((age ?? 30) * 0.18) +
                ((bmi != null ? (bmi - 21).clamp(0, 14) : 1.5) * 0.9))
            .round();
    final baseDia = baseline?.diastolic ??
        (70 +
                ((age ?? 30) * 0.08) +
                ((bmi != null ? (bmi - 21).clamp(0, 14) : 1.5) * 0.45))
            .round();

    final sys = (baseSys +
            ((bpm - 72) * 0.45) -
            ((hrv - 34) * 0.12) +
            ((stressScore - 45) * 0.10) +
            ((100 - quality) * 0.04))
        .round()
        .clamp(90, 180);
    final dia = (baseDia +
            ((bpm - 72) * 0.24) -
            ((hrv - 34) * 0.08) +
            ((stressScore - 45) * 0.06) +
            ((100 - quality) * 0.03))
        .round()
        .clamp(55, 120);

    final confidence = baseline != null
        ? (quality >= 75 ? 'moyenne' : 'faible')
        : (quality >= 80 ? 'faible' : 'tres faible');

    String level;
    if (sys >= 140 || dia >= 90) {
      level = 'tendance elevee';
    } else if (sys < 100 || dia < 60) {
      level = 'tendance basse';
    } else {
      level = 'tendance moyenne';
    }

    return _ExperimentalPressure(
      systolic: sys,
      diastolic: dia,
      confidence: confidence,
      level: level,
      basedOnBaseline: baseline != null,
    );
  }

  _PressureReading? _parsePressure(String raw) {
    final match = RegExp(r'(\d{2,3})\s*[/\-]\s*(\d{2,3})').firstMatch(raw);
    if (match == null) return null;
    final sys = int.tryParse(match.group(1) ?? '');
    final dia = int.tryParse(match.group(2) ?? '');
    if (sys == null || dia == null) return null;
    return _PressureReading(systolic: sys, diastolic: dia);
  }

  int? _inferAge(Map<String, dynamic> userData, Map<String, dynamic> health) {
    final birthRaw = (userData['birthDate'] ?? health['birthDate'] ?? '').toString().trim();
    if (birthRaw.isEmpty) return null;
    final birth = DateTime.tryParse(birthRaw);
    if (birth == null) return null;
    final now = DateTime.now();
    var age = now.year - birth.year;
    if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) {
      age -= 1;
    }
    return age < 0 ? null : age;
  }

  double? _computeBmi(double? weightKg, double? heightCm) {
    if (weightKg == null || heightCm == null || heightCm <= 0) return null;
    final heightM = heightCm / 100;
    if (heightM <= 0) return null;
    return weightKg / (heightM * heightM);
  }

  List<double> _movingAverage(List<double> values, int radius) {
    if (values.isEmpty) return const <double>[];
    return List<double>.generate(values.length, (index) {
      final start = math.max(0, index - radius);
      final end = math.min(values.length - 1, index + radius);
      var total = 0.0;
      var count = 0;
      for (var i = start; i <= end; i++) {
        total += values[i];
        count++;
      }
      return count == 0 ? values[index] : total / count;
    }, growable: false);
  }

  List<double> _normalizeWaveform(List<double> values, {required int maxPoints}) {
    if (values.isEmpty) return const <double>[];
    final step = values.length <= maxPoints ? 1 : (values.length / maxPoints).ceil();
    final sampled = <double>[];
    for (var i = 0; i < values.length; i += step) {
      sampled.add(values[i]);
    }
    final minValue = sampled.reduce(math.min);
    final maxValue = sampled.reduce(math.max);
    final span = maxValue - minValue;
    if (span.abs() < 0.0001) {
      return List<double>.filled(sampled.length, 0.5, growable: false);
    }
    return sampled
        .map((value) => ((value - minValue) / span).clamp(0.0, 1.0))
        .toList(growable: false);
  }

  List<double> _waveformForDisplay() {
    if (_samples.length < 6) return const <double>[];
    final raw = _samples.map((sample) => sample.intensity).toList(growable: false);
    final smooth = _movingAverage(raw, 3);
    final trend = _movingAverage(smooth, 16);
    final band = List<double>.generate(
      smooth.length,
      (index) => smooth[index] - trend[index],
      growable: false,
    );
    return _normalizeWaveform(band, maxPoints: 180);
  }

  double _mean(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _stdDev(List<double> values, double mean) {
    if (values.isEmpty) return 0;
    final variance =
        values.map((value) => math.pow(value - mean, 2)).reduce((a, b) => a + b) / values.length;
    return math.sqrt(variance);
  }

  double _rmssd(List<double> rrIntervals) {
    if (rrIntervals.length < 2) return 0;
    final squares = <double>[];
    for (var i = 1; i < rrIntervals.length; i++) {
      final diff = rrIntervals[i] - rrIntervals[i - 1];
      squares.add(diff * diff);
    }
    return math.sqrt(_mean(squares));
  }

  double? _toDouble(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString().trim().replaceAll(',', '.'));
  }

  Future<void> _persistResult(_PpgMeasurementResult result) async {
    await widget.contextRef.userRef.set(
      {
        'health': {
          'stressLab': {
            'cameraFinger': {
              'status': result.status,
              'score': result.stressScore,
              'level': result.stressScore == null
                  ? null
                  : (result.stressScore! < 35
                      ? 'faible'
                      : result.stressScore! < 65
                          ? 'modere'
                          : 'eleve'),
              'summary': result.summary,
              'caution': result.caution,
              'heartRateBpm': result.heartRateBpm,
              'hrvRmssd': result.hrvRmssd,
              'signalQuality': result.signalQuality,
              'stressScore': result.stressScore,
              'bpExperimental': result.bpEstimate == null
                  ? null
                  : {
                      'systolic': result.bpEstimate!.systolic,
                      'diastolic': result.bpEstimate!.diastolic,
                      'confidence': result.bpEstimate!.confidence,
                      'level': result.bpEstimate!.level,
                      'basedOnBaseline': result.bpEstimate!.basedOnBaseline,
                    },
              'waveform': result.waveform,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          },
        },
      },
      SetOptions(merge: true),
    );

    await _sessionsRef.add({
      'type': 'cameraFingerPpg',
      'title': 'Frequence cardiaque et tension',
      'summary': result.summary,
      'status': result.status,
      'signalQuality': result.signalQuality,
      'heartRateBpm': result.heartRateBpm,
      'hrvRmssd': result.hrvRmssd,
      'stressScore': result.stressScore,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (result.heartRateBpm != null) {
      await _metricsRef.add({
        'type': 'heartRate',
        'value': result.heartRateBpm,
        'unit': 'bpm',
        'recordedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (result.hrvRmssd != null) {
      await _metricsRef.add({
        'type': 'hrv',
        'value': result.hrvRmssd,
        'unit': 'ms',
        'recordedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (result.stressScore != null) {
      await _metricsRef.add({
        'type': 'stressExperimental',
        'value': result.stressScore!.toDouble(),
        'unit': '/100',
        'recordedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? Colors.white : const Color(0xFF102127);
    final sub = isDark ? Colors.white70 : const Color(0xFF5E7077);
    const accent = Color(0xFF2D6BFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Frequence cardiaque et tension'),
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: text, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: accent.withOpacity(0.12)),
                      ),
                      child: Text(
                        'Placez le doigt sur l objectif arriere et le flash. Restez immobile 30 secondes pour mesurer la frequence cardiaque, la variabilite cardiaque et afficher une estimation prudente de la tension.',
                        style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio == 0
                            ? 3 / 4
                            : 1 / _controller!.value.aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(_controller!),
                            Container(color: Colors.black.withOpacity(0.14)),
                            Center(
                              child: Container(
                                width: 180,
                                height: 180,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withOpacity(0.9), width: 3),
                                  color: Colors.redAccent.withOpacity(_measuring ? 0.10 : 0.02),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _measuring ? 'Doigt en place' : 'Placez le doigt ici',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 16,
                              child: Row(
                                children: [
                                  _CameraStatChip(
                                    label: _measuring
                                        ? '${_elapsed.inSeconds}s / ${_measurementDuration.inSeconds}s'
                                        : 'Pret',
                                  ),
                                  const SizedBox(width: 10),
                                  _CameraStatChip(
                                    label: _liveIntensity == null
                                        ? 'Signal n/d'
                                        : 'Signal ${_liveIntensity!.toStringAsFixed(0)}',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF111B21) : Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: accent.withOpacity(0.12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Signal de la mesure',
                            style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 17),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 150,
                            child: CustomPaint(
                              painter: _WavePainter(
                                values: _result?.waveform ?? _waveformForDisplay(),
                                accent: accent,
                                grid: sub.withOpacity(0.20),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: accent.withOpacity(0.10)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _measuring ? _stopMeasurement : _startMeasurement,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _measuring ? Colors.redAccent : accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: Icon(_measuring ? Icons.stop_rounded : Icons.play_arrow_rounded),
                              label: Text(_measuring ? 'Arreter et analyser' : 'Demarrer la mesure'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_result != null) ...[
                      const SizedBox(height: 12),
                      _PpgResultCard(
                        result: _result!,
                        text: text,
                        sub: sub,
                        accent: accent,
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _PpgSample {
  const _PpgSample({
    required this.timeMs,
    required this.intensity,
  });

  final int timeMs;
  final double intensity;
}

class _PpgMeasurementResult {
  const _PpgMeasurementResult({
    required this.status,
    required this.summary,
    required this.caution,
    this.heartRateBpm,
    this.hrvRmssd,
    this.signalQuality,
    this.waveform = const <double>[],
    this.stressScore,
    this.bpEstimate,
  });

  final String status;
  final String summary;
  final String caution;
  final double? heartRateBpm;
  final double? hrvRmssd;
  final int? signalQuality;
  final List<double> waveform;
  final int? stressScore;
  final _ExperimentalPressure? bpEstimate;
}

class _PressureReading {
  const _PressureReading({
    required this.systolic,
    required this.diastolic,
  });

  final int systolic;
  final int diastolic;
}

class _ExperimentalPressure {
  const _ExperimentalPressure({
    required this.systolic,
    required this.diastolic,
    required this.confidence,
    required this.level,
    required this.basedOnBaseline,
  });

  final int systolic;
  final int diastolic;
  final String confidence;
  final String level;
  final bool basedOnBaseline;
}

class _CameraStatChip extends StatelessWidget {
  const _CameraStatChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PpgResultCard extends StatelessWidget {
  const _PpgResultCard({
    required this.result,
    required this.text,
    required this.sub,
    required this.accent,
  });

  final _PpgMeasurementResult result;
  final Color text;
  final Color sub;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.status,
            style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            result.summary,
            style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (result.heartRateBpm != null)
                _MetricTile(
                  label: 'Frequence cardiaque',
                  value: '${result.heartRateBpm!.toStringAsFixed(0)} bpm',
                ),
              if (result.hrvRmssd != null)
                _MetricTile(
                  label: 'Variabilite cardiaque',
                  value: '${result.hrvRmssd!.toStringAsFixed(0)} ms',
                ),
              if (result.signalQuality != null)
                _MetricTile(
                  label: 'Qualite du signal',
                  value: '${result.signalQuality}/100',
                ),
              if (result.stressScore != null)
                _MetricTile(
                  label: 'Niveau de stress',
                  value: '${result.stressScore}/100',
                ),
            ],
          ),
          if (result.bpEstimate != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.70),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimation de la tension',
                    style: TextStyle(color: text, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${result.bpEstimate!.systolic}/${result.bpEstimate!.diastolic} mmHg'
                    ' | ${result.bpEstimate!.level}'
                    ' | confiance ${result.bpEstimate!.confidence}',
                    style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.bpEstimate!.basedOnBaseline
                        ? 'L estimation est reajustee avec votre tension historique quand elle est disponible.'
                        : 'Aucune ligne de base tensionnelle trouvee, donc l approximation reste tres prudente.',
                    style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            result.caution,
            style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.76),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.values,
    required this.accent,
    required this.grid,
  });

  final List<double> values;
  final Color accent;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.length < 2) return;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y = size.height - (values[i] * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.accent != accent ||
        oldDelegate.grid != grid;
  }
}

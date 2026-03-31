import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lualaba_konnect/screnns/camera_screen.dart';

import 'health_height_measure_page.dart';
import 'health_ppg_vitals_page.dart';
import 'health_user_context.dart';

class HealthStressLabPage extends StatefulWidget {
  const HealthStressLabPage({
    super.key,
    required this.contextRef,
  });

  final HealthUserContext contextRef;

  @override
  State<HealthStressLabPage> createState() => _HealthStressLabPageState();
}

class _HealthStressLabPageState extends State<HealthStressLabPage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _hrvCtrl = TextEditingController();
  final TextEditingController _restingHrCtrl = TextEditingController();
  final TextEditingController _experimentalNotesCtrl = TextEditingController();

  bool _loading = true;
  bool _analyzingContext = false;
  bool _analyzingFace = false;
  bool _estimatingExperimental = false;

  double _trafficLoad = 5;
  double _heatLoad = 5;
  double _pollutionLoad = 5;
  double _activityMinutes = 30;
  double _signalQuality = 6;

  double? _lat;
  double? _lng;
  double? _speedKmh;
  String _locationLabel = '';

  Uint8List? _faceBytes;
  String _faceImageName = '';

  String _cameraCaptureLabel = '';
  bool _cameraCaptureIsVideo = false;
  double? _lastHeightCm;
  String _heightReferenceLabel = '';

  bool _palpitations = false;
  bool _headache = false;
  bool _heatExposure = false;

  _StressLabResult? _contextResult;
  _StressLabResult? _faceResult;
  _StressLabResult? _experimentalResult;

  CollectionReference<Map<String, dynamic>> get _sessionsRef =>
      widget.contextRef.subCollection('health_stress_sessions');

  CollectionReference<Map<String, dynamic>> get _metricsRef =>
      widget.contextRef.subCollection('health_measurements');

  @override
  void initState() {
    super.initState();
    _loadLatestState();
  }

  @override
  void dispose() {
    _hrvCtrl.dispose();
    _restingHrCtrl.dispose();
    _experimentalNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLatestState() async {
    try {
      final snap = await widget.contextRef.userRef.get();
      final data = snap.data() ?? <String, dynamic>{};
      final health = (data['health'] is Map)
          ? Map<String, dynamic>.from(data['health'] as Map)
          : <String, dynamic>{};
      final stressLab = (health['stressLab'] is Map)
          ? Map<String, dynamic>.from(health['stressLab'] as Map)
          : <String, dynamic>{};

      final contextMap = _asMap(stressLab['context']);
      if (contextMap.isNotEmpty) {
        _contextResult = _resultFromMap(contextMap);
        _trafficLoad = _toDouble(contextMap['trafficLoad']) ?? _trafficLoad;
        _heatLoad = _toDouble(contextMap['heatLoad']) ?? _heatLoad;
        _pollutionLoad = _toDouble(contextMap['pollutionLoad']) ?? _pollutionLoad;
        _activityMinutes = _toDouble(contextMap['activityMinutes']) ?? _activityMinutes;
        _lat = _toDouble(contextMap['lat']);
        _lng = _toDouble(contextMap['lng']);
        _speedKmh = _toDouble(contextMap['speedKmh']);
        _locationLabel = _safeStr(contextMap['locationLabel']);
      }

      final faceMap = _asMap(stressLab['face']);
      if (faceMap.isNotEmpty) {
        _faceResult = _resultFromMap(faceMap);
        _faceImageName = _safeStr(faceMap['imageName']);
      }

      final experimentalMap = _asMap(stressLab['cameraFinger']);
      if (experimentalMap.isNotEmpty) {
        _experimentalResult = _resultFromCameraFingerMap(experimentalMap);
        final hrv = _toDouble(experimentalMap['hrvRmssd']);
        final hr = _toDouble(experimentalMap['restingHeartRate']);
        if (hrv != null) {
          _hrvCtrl.text = hrv.toStringAsFixed(hrv.truncateToDouble() == hrv ? 0 : 1);
        }
        if (hr != null) {
          _restingHrCtrl.text = hr.toStringAsFixed(hr.truncateToDouble() == hr ? 0 : 1);
        }
        _signalQuality = _toDouble(experimentalMap['signalQuality']) ?? _signalQuality;
        _cameraCaptureLabel = _safeStr(experimentalMap['captureLabel']);
        _cameraCaptureIsVideo = _boolValue(experimentalMap['captureIsVideo']) ?? false;
        _palpitations = _boolValue(experimentalMap['palpitations']) ?? false;
        _headache = _boolValue(experimentalMap['headache']) ?? false;
        _heatExposure = _boolValue(experimentalMap['heatExposure']) ?? false;
        _experimentalNotesCtrl.text = _safeStr(experimentalMap['notes']);
      }

      final heightMap = _asMap(health['heightMeasurement']);
      _lastHeightCm = _toDouble(heightMap['valueCm'] ?? health['heightCm'] ?? health['height']);
      _heightReferenceLabel = _safeStr(heightMap['referenceLabel']);
    } catch (_) {
      // Ignore hydration issues and keep the page interactive.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final places = await placemarkFromCoordinates(lat, lng);
      if (places.isEmpty) return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
      final place = places.first;
      final parts = <String>[
        _safeStr(place.locality),
        _safeStr(place.subAdministrativeArea),
        _safeStr(place.country),
      ].where((part) => part.isNotEmpty).toList(growable: false);
      return parts.isEmpty
          ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
          : parts.join(', ');
    } catch (_) {
      return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    }
  }

  String _guessImageMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _analyzeContextStress() async {
    if (_analyzingContext) return;

    setState(() => _analyzingContext = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Le GPS est desactive');
      }

      final granted = await Geolocator.checkPermission();
      if (granted == LocationPermission.denied || granted == LocationPermission.deniedForever) {
        throw Exception('Permission GPS refusee');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final placeLabel = await _reverseGeocode(position.latitude, position.longitude);
      final result = _computeContextStress(
        trafficLoad: _trafficLoad,
        heatLoad: _heatLoad,
        pollutionLoad: _pollutionLoad,
        activityMinutes: _activityMinutes,
        speedKmh: position.speed >= 0 ? position.speed * 3.6 : null,
        measuredAt: DateTime.now(),
        locationLabel: placeLabel,
      );

      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _speedKmh = position.speed >= 0 ? position.speed * 3.6 : null;
        _locationLabel = placeLabel;
        _contextResult = result;
      });

      await widget.contextRef.userRef.set(
        {
          'health': {
            'stressLab': {
              'context': {
                'score': result.score,
                'level': result.level,
                'summary': result.summary,
                'signals': result.signals,
                'caution': result.caution,
                'trafficLoad': _trafficLoad,
                'heatLoad': _heatLoad,
                'pollutionLoad': _pollutionLoad,
                'activityMinutes': _activityMinutes,
                'lat': position.latitude,
                'lng': position.longitude,
                'speedKmh': _speedKmh,
                'locationLabel': placeLabel,
                'updatedAt': FieldValue.serverTimestamp(),
              },
            },
          },
        },
        SetOptions(merge: true),
      );

      await _sessionsRef.add({
        'type': 'context',
        'title': 'Stress lie au climat',
        'score': result.score,
        'level': result.level,
        'summary': result.summary,
        'signals': result.signals,
        'locationLabel': placeLabel,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _metricsRef.add({
        'type': 'stressContext',
        'value': result.score!.toDouble(),
        'unit': '/100',
        'recordedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _snack('Analyse contextuelle impossible: $e', error: true);
    } finally {
      if (mounted) setState(() => _analyzingContext = false);
    }
  }

  Future<void> _pickFaceImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        preferredCameraDevice: source == ImageSource.camera ? CameraDevice.front : CameraDevice.rear,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _faceBytes = bytes;
        _faceImageName = picked.name;
      });
    } catch (e) {
      _snack('Impossible de charger la photo: $e', error: true);
    }
  }

  Future<void> _analyzeFaceStress() async {
    if (_analyzingFace) return;
    if (_faceBytes == null) {
      _snack('Ajoutez un selfie ou une photo du visage.', error: true);
      return;
    }

    setState(() => _analyzingFace = true);
    try {
      final apiKey = dotenv.maybeGet('GEMINI_API_KEY') ?? '';
      _StressLabResult result;

      if (apiKey.isEmpty) {
        result = const _StressLabResult(
          score: null,
          level: 'config manquante',
          summary:
              'Le module visage est pret, mais GEMINI_API_KEY est necessaire pour lire les microtensions faciales.',
          signals: <String>['Ajoutez GEMINI_API_KEY', 'Relancez l analyse'],
          caution:
              'Cette lecture reste uniquement indicative et ne remplace ni un examen clinique ni un avis medical.',
        );
      } else {
        final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
        final response = await model.generateContent([
          Content.multi([
            TextPart(
              'Tu analyses uniquement des signes visuels de tension faciale potentielle. '
              'Aucun diagnostic medical. Reponds exactement sur 5 lignes: '
              'score: <0-100 ou NA>; '
              'niveau: <faible|modere|eleve>; '
              'signaux: <3 signaux separes par ;>; '
              'resume: <1 phrase courte>; '
              'prudence: <1 phrase courte rappelant que c est indicatif>.',
            ),
            DataPart(_guessImageMime(_faceImageName), _faceBytes!),
          ]),
        ]);
        result = _parseGeminiStressResult(response.text ?? '');
      }

      if (!mounted) return;
      setState(() => _faceResult = result);

      await widget.contextRef.userRef.set(
        {
          'health': {
            'stressLab': {
              'face': {
                'score': result.score,
                'level': result.level,
                'summary': result.summary,
                'signals': result.signals,
                'caution': result.caution,
                'imageName': _faceImageName,
                'updatedAt': FieldValue.serverTimestamp(),
              },
            },
          },
        },
        SetOptions(merge: true),
      );

      await _sessionsRef.add({
        'type': 'face',
        'title': 'Expressions faciales',
        'score': result.score,
        'level': result.level,
        'summary': result.summary,
        'signals': result.signals,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (result.score != null) {
        await _metricsRef.add({
          'type': 'stressFace',
          'value': result.score!.toDouble(),
          'unit': '/100',
          'recordedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      _snack('Analyse faciale impossible: $e', error: true);
    } finally {
      if (mounted) setState(() => _analyzingFace = false);
    }
  }

  Future<void> _captureCameraFingerSession() async {
    try {
      final dynamic captured = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CameraScreen()),
      );
      if (captured is! XFile) return;

      final lower = captured.path.toLowerCase();
      final isVideo = lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.avi');

      if (!mounted) return;
      setState(() {
        _cameraCaptureIsVideo = isVideo;
        _cameraCaptureLabel = isVideo
            ? 'Capture video recue (${captured.name})'
            : 'Capture image recue (${captured.name})';
      });
    } catch (e) {
      _snack('Capture camera impossible: $e', error: true);
    }
  }

  Future<void> _estimateExperimentalVitals() async {
    if (_estimatingExperimental) return;

    final restingHr = _toDouble(_restingHrCtrl.text);
    final hrv = _toDouble(_hrvCtrl.text);
    if (restingHr == null && hrv == null) {
      _snack('Renseignez au moins la frequence cardiaque ou la HRV.', error: true);
      return;
    }

    setState(() => _estimatingExperimental = true);
    try {
      final result = _computeExperimentalVitals(
        restingHeartRate: restingHr,
        hrvRmssd: hrv,
        signalQuality: _signalQuality,
        palpitations: _palpitations,
        headache: _headache,
        heatExposure: _heatExposure,
      );

      if (!mounted) return;
      setState(() => _experimentalResult = result);

      await widget.contextRef.userRef.set(
        {
          'health': {
            'stressLab': {
              'cameraFinger': {
                'score': result.score,
                'level': result.level,
                'summary': result.summary,
                'signals': result.signals,
                'caution': result.caution,
                'restingHeartRate': restingHr,
                'hrvRmssd': hrv,
                'signalQuality': _signalQuality,
                'captureLabel': _cameraCaptureLabel,
                'captureIsVideo': _cameraCaptureIsVideo,
                'palpitations': _palpitations,
                'headache': _headache,
                'heatExposure': _heatExposure,
                'notes': _experimentalNotesCtrl.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              },
            },
          },
        },
        SetOptions(merge: true),
      );

      await _sessionsRef.add({
        'type': 'cameraFinger',
        'title': 'Frequence cardiaque et tension',
        'score': result.score,
        'level': result.level,
        'summary': result.summary,
        'signals': result.signals,
        'captureLabel': _cameraCaptureLabel,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _metricsRef.add({
        'type': 'stressExperimental',
        'value': result.score!.toDouble(),
        'unit': '/100',
        'recordedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (hrv != null) {
        await _metricsRef.add({
          'type': 'hrv',
          'value': hrv,
          'unit': 'ms',
          'recordedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      _snack('Evaluation experimentale impossible: $e', error: true);
    } finally {
      if (mounted) setState(() => _estimatingExperimental = false);
    }
  }

  _StressLabResult _computeContextStress({
    required double trafficLoad,
    required double heatLoad,
    required double pollutionLoad,
    required double activityMinutes,
    required DateTime measuredAt,
    required String locationLabel,
    double? speedKmh,
  }) {
    final trafficScore = (trafficLoad / 10) * 34;
    final heatScore = (heatLoad / 10) * 24;
    final pollutionScore = (pollutionLoad / 10) * 20;
    final activityScore = activityMinutes <= 20
        ? 8
        : activityMinutes <= 45
            ? 15
            : activityMinutes <= 75
                ? 22
                : 28;
    final speedScore = speedKmh == null
        ? 6
        : speedKmh < 8
            ? 12
            : speedKmh < 20
                ? 10
                : speedKmh < 45
                    ? 6
                    : 3;
    final rushHour = ((measuredAt.hour >= 7 && measuredAt.hour <= 9) ||
            (measuredAt.hour >= 16 && measuredAt.hour <= 19))
        ? 6
        : 0;
    final score = _clampScore(
      trafficScore + heatScore + pollutionScore + activityScore + speedScore + rushHour,
    );

    final signals = <String>[
      if (trafficLoad >= 7) 'Embouteillage dense',
      if (heatLoad >= 7) 'Chaleur elevee',
      if (pollutionLoad >= 7) 'Pollution notable',
      if (activityMinutes >= 60) 'Charge physique soutenue',
      if (speedKmh != null && speedKmh < 15 && trafficLoad >= 6) 'Ralentissement prolonge',
    ];
    if (signals.isEmpty) {
      signals.add('Conditions climatiques plutot stables pour le moment');
    }

    final place = locationLabel.isEmpty ? 'votre zone actuelle' : locationLabel;
    return _StressLabResult(
      score: score,
      level: _levelFromScore(score),
      summary:
          'Le climat et les conditions autour de $place suggerent un niveau de stress ${_levelFromScore(score)}. '
          'Ce score combine chaleur, pollution, circulation et effort physique recent.',
      signals: signals,
      caution:
          'Indicateur de bien-etre uniquement. Il aide a prioriser repos, hydratation, respiration et verification des symptomes.',
    );
  }

  _StressLabResult _computeExperimentalVitals({
    required double? restingHeartRate,
    required double? hrvRmssd,
    required double signalQuality,
    required bool palpitations,
    required bool headache,
    required bool heatExposure,
  }) {
    final hrScore = restingHeartRate == null
        ? 16
        : restingHeartRate <= 75
            ? 10
            : restingHeartRate <= 90
                ? 22
                : restingHeartRate <= 105
                    ? 34
                    : 46;
    final hrvScore = hrvRmssd == null
        ? 16
        : hrvRmssd >= 45
            ? 8
            : hrvRmssd >= 32
                ? 18
                : hrvRmssd >= 22
                    ? 30
                    : 42;
    final signalPenalty = ((10 - signalQuality).clamp(0, 10) / 10) * 8;
    final symptomPenalty =
        (palpitations ? 10 : 0) + (headache ? 8 : 0) + (heatExposure ? 6 : 0);
    final score = _clampScore(hrScore + hrvScore + signalPenalty + symptomPenalty);

    final signals = <String>[
      if (restingHeartRate != null)
        'Frequence cardiaque au repos ${restingHeartRate.toStringAsFixed(0)} bpm',
      if (hrvRmssd != null) 'Variabilite cardiaque ${hrvRmssd.toStringAsFixed(0)} ms',
      'Qualite du signal ${signalQuality.toStringAsFixed(0)}/10',
      if (_cameraCaptureLabel.isNotEmpty)
        _cameraCaptureIsVideo ? 'Capture video recue' : 'Capture image recue',
      if (palpitations) 'Palpitations signalees',
      if (headache) 'Cefalee signalee',
      if (heatExposure) 'Exposition a la chaleur',
    ];

    return _StressLabResult(
      score: score,
      level: _levelFromScore(score),
      summary:
          'Lecture camera/doigt: votre frequence cardiaque et votre charge physiologique paraissent ${_levelFromScore(score)}. '
          'La tension affichee ici reste une estimation a confirmer avec un tensiometre.',
      signals: signals,
      caution:
          'Le smartphone seul ne donne pas une tension clinique fiable. Utilisez un tensiometre si vous voulez une vraie valeur systolique/diastolique.',
    );
  }

  _StressLabResult _parseGeminiStressResult(String raw) {
    final scoreMatch = RegExp(r'score\s*:\s*(\d{1,3}|NA)', caseSensitive: false).firstMatch(raw);
    final levelMatch = RegExp(r'niveau\s*:\s*([^\n]+)', caseSensitive: false).firstMatch(raw);
    final signalsMatch = RegExp(r'signaux\s*:\s*([^\n]+)', caseSensitive: false).firstMatch(raw);
    final summaryMatch = RegExp(r'resume\s*:\s*([^\n]+)', caseSensitive: false).firstMatch(raw);
    final cautionMatch = RegExp(r'prudence\s*:\s*([^\n]+)', caseSensitive: false).firstMatch(raw);

    final rawScore = scoreMatch?.group(1)?.trim() ?? '';
    final parsedScore = rawScore.toUpperCase() == 'NA' ? null : int.tryParse(rawScore);
    final signals = (signalsMatch?.group(1) ?? '')
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    return _StressLabResult(
      score: parsedScore == null ? null : _clampScore(parsedScore),
      level: _safeStr(levelMatch?.group(1)).isEmpty ? 'indicatif' : _safeStr(levelMatch?.group(1)),
      summary: _safeStr(summaryMatch?.group(1)).isEmpty
          ? 'Analyse des expressions faciales disponible, avec prudence.'
          : _safeStr(summaryMatch?.group(1)),
      signals: signals.isEmpty ? const <String>['Lecture des expressions faciales indicative'] : signals,
      caution: _safeStr(cautionMatch?.group(1)).isEmpty
          ? 'Analyse indicative uniquement, a confronter avec le contexte reel et les symptomes.'
          : _safeStr(cautionMatch?.group(1)),
    );
  }

  _StressLabResult _resultFromMap(Map<String, dynamic> map) {
    return _StressLabResult(
      score: _toInt(map['score']),
      level: _safeStr(map['level']),
      summary: _safeStr(map['summary']),
      signals: _stringList(map['signals']),
      caution: _safeStr(map['caution']),
    );
  }

  _StressLabResult _resultFromCameraFingerMap(Map<String, dynamic> map) {
    final score = _toInt(map['score'] ?? map['stressScore']);
    final level = _safeStr(map['level']).isNotEmpty
        ? _safeStr(map['level'])
        : score == null
            ? 'indicatif'
            : _levelFromScore(score);
    final bpMap = _asMap(map['bpExperimental']);
    final bpLabel = (bpMap['systolic'] != null && bpMap['diastolic'] != null)
        ? 'Tension estimee ${bpMap['systolic']}/${bpMap['diastolic']} mmHg'
        : '';

    return _StressLabResult(
      score: score,
      level: level,
      summary: _safeStr(map['summary']).isEmpty
          ? 'Mesure de frequence cardiaque et estimation de tension disponibles.'
          : _safeStr(map['summary']),
      signals: <String>[
        if (_toDouble(map['heartRateBpm']) != null)
          'Frequence cardiaque ${_toDouble(map['heartRateBpm'])!.toStringAsFixed(0)} bpm',
        if (_toDouble(map['hrvRmssd']) != null)
          'Variabilite cardiaque ${_toDouble(map['hrvRmssd'])!.toStringAsFixed(0)} ms',
        if (_toInt(map['signalQuality']) != null)
          'Qualite du signal ${_toInt(map['signalQuality'])}/100',
        if (bpLabel.isNotEmpty) bpLabel,
      ],
      caution: _safeStr(map['caution']),
    );
  }

  Future<void> _openPpgLab() async {
    final contextRef = widget.contextRef;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HealthPpgVitalsPage(contextRef: contextRef),
      ),
    );
    await _loadLatestState();
  }

  Future<void> _openHeightMeasure() async {
    final contextRef = widget.contextRef;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HealthHeightMeasurePage(contextRef: contextRef),
      ),
    );
    await _loadLatestState();
  }

  int _clampScore(num raw) => raw.round().clamp(0, 100);

  String _levelFromScore(int score) {
    if (score < 35) return 'faible';
    if (score < 65) return 'modere';
    return 'eleve';
  }

  Color _toneForScore(BuildContext context, int? score) {
    if (score == null) return Theme.of(context).colorScheme.primary;
    if (score < 35) return Colors.green;
    if (score < 65) return const Color(0xFFFF8A1F);
    return Colors.redAccent;
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => _safeStr(e))
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  String _safeStr(dynamic raw) => (raw ?? '').toString().trim();

  double? _toDouble(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString().trim().replaceAll(',', '.'));
  }

  int? _toInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString().trim());
  }

  bool? _boolValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    final lower = raw.toString().trim().toLowerCase();
    if (lower == 'true' || lower == '1' || lower == 'yes' || lower == 'oui') return true;
    if (lower == 'false' || lower == '0' || lower == 'no' || lower == 'non') return false;
    return null;
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

  String _formatDateTime(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year} - $hh:$min';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF0D1B2A);
    final sub = isDark ? Colors.white70 : const Color(0xFF5E6C76);
    const accent = Color(0xFF00BFA5);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stress & Vital Lab'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _LabNoticeCard(
            cardBg: cardBg,
            text: text,
            sub: sub,
            accent: accent,
            onOpenPpgLab: _openPpgLab,
            onOpenHeightMeasure: _openHeightMeasure,
          ),
          const SizedBox(height: 12),
          _SectionCard(
            cardBg: cardBg,
            text: text,
            sub: sub,
            accent: accent,
            icon: Icons.radar_outlined,
            title: 'Analyse du stress lie au climat',
            subtitle:
                'Chaleur, pollution, circulation et activite physique pour estimer l impact du climat et de l environnement sur votre stress.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FactLine(
                  text: text,
                  sub: sub,
                  label: 'Zone detectee',
                  value: _locationLabel.isEmpty ? 'Non captee' : _locationLabel,
                ),
                _FactLine(
                  text: text,
                  sub: sub,
                  label: 'Deplacement',
                  value: _speedKmh == null ? 'n/d' : '${_speedKmh!.toStringAsFixed(1)} km/h',
                ),
                const SizedBox(height: 10),
                _StressSlider(
                  label: 'Embouteillage',
                  hint: '0 = fluide, 10 = saturation',
                  value: _trafficLoad,
                  accent: const Color(0xFFFF8A1F),
                  text: text,
                  sub: sub,
                  onChanged: (value) => setState(() => _trafficLoad = value),
                ),
                _StressSlider(
                  label: 'Chaleur',
                  hint: '0 = confortable, 10 = tres chaud',
                  value: _heatLoad,
                  accent: const Color(0xFFFF7043),
                  text: text,
                  sub: sub,
                  onChanged: (value) => setState(() => _heatLoad = value),
                ),
                _StressSlider(
                  label: 'Pollution',
                  hint: '0 = faible, 10 = forte exposition',
                  value: _pollutionLoad,
                  accent: const Color(0xFF607D8B),
                  text: text,
                  sub: sub,
                  onChanged: (value) => setState(() => _pollutionLoad = value),
                ),
                _StressSlider(
                  label: 'Activite physique',
                  hint: 'Minutes actives recentes',
                  value: _activityMinutes,
                  accent: accent,
                  min: 0,
                  max: 120,
                  text: text,
                  sub: sub,
                  formatter: (value) => '${value.toStringAsFixed(0)} min',
                  onChanged: (value) => setState(() => _activityMinutes = value),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _analyzingContext ? null : _analyzeContextStress,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _analyzingContext
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.my_location_outlined),
                    label: Text(
                      _analyzingContext
                          ? 'Analyse en cours...'
                          : 'Analyser le stress lie au climat',
                    ),
                  ),
                ),
                if (_contextResult != null) ...[
                  const SizedBox(height: 12),
                  _ResultCard(
                    result: _contextResult!,
                    accent: _toneForScore(context, _contextResult!.score),
                    text: text,
                    sub: sub,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            cardBg: cardBg,
            text: text,
            sub: sub,
            accent: accent,
            icon: Icons.face_retouching_natural_outlined,
            title: 'Analyse du stress par expression faciale',
            subtitle:
                'Lecture assistive des expressions faciales visibles. Le resultat reste prudent et non diagnostique.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 180,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withOpacity(0.10)),
                  ),
                  child: _faceBytes == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.face_outlined, color: accent, size: 34),
                            const SizedBox(height: 8),
                            Text(
                              'Ajoutez un selfie pour lancer l analyse des expressions faciales.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.memory(_faceBytes!, fit: BoxFit.cover),
                        ),
                ),
                if (_faceImageName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _faceImageName,
                    style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickFaceImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Selfie'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pickFaceImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galerie'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _analyzingFace ? null : _analyzeFaceStress,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00695C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _analyzingFace
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.psychology_alt_outlined),
                    label: Text(
                      _analyzingFace
                          ? 'Analyse en cours...'
                          : 'Analyser les expressions faciales',
                    ),
                  ),
                ),
                if (_faceResult != null) ...[
                  const SizedBox(height: 12),
                  _ResultCard(
                    result: _faceResult!,
                    accent: _toneForScore(context, _faceResult!.score),
                    text: text,
                    sub: sub,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            cardBg: cardBg,
            text: text,
            sub: sub,
            accent: accent,
            icon: Icons.monitor_heart_outlined,
            title: 'Frequence cardiaque et tension',
            subtitle:
                'Mesure de la frequence cardiaque, de la variabilite cardiaque et estimation prudente de la tension par camera + doigt.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withOpacity(0.10)),
                  ),
                  child: Text(
                    'Placez le doigt sur l objectif arriere et le flash, puis restez immobile 30 a 45 secondes. '
                    'La frequence cardiaque est mesuree directement, mais la tension reste une estimation a confirmer avec un brassard.',
                    style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _openPpgLab,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D6BFF),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.favorite_outline),
                      label: const Text('Mesurer la frequence cardiaque et la tension'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _captureCameraFingerSession,
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Capture libre'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (_cameraCaptureLabel.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _cameraCaptureLabel,
                          style: TextStyle(color: text, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _restingHrCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Frequence cardiaque au repos (bpm)',
                    hintText: 'Ex: 72',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _hrvCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Variabilite cardiaque (HRV / RMSSD)',
                    hintText: 'Ex: 38 ms',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _experimentalNotesCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes de session',
                    hintText: 'Chaleur, fatigue, cafe, peu de sommeil, etc.',
                  ),
                ),
                const SizedBox(height: 10),
                _StressSlider(
                  label: 'Qualite de la mesure',
                  hint: '0 = tres faible, 10 = tres propre',
                  value: _signalQuality,
                  accent: const Color(0xFF2D6BFF),
                  text: text,
                  sub: sub,
                  onChanged: (value) => setState(() => _signalQuality = value),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('Palpitations'),
                      selected: _palpitations,
                      onSelected: (selected) => setState(() => _palpitations = selected),
                    ),
                    FilterChip(
                      label: const Text('Cefalee'),
                      selected: _headache,
                      onSelected: (selected) => setState(() => _headache = selected),
                    ),
                    FilterChip(
                      label: const Text('Forte chaleur'),
                      selected: _heatExposure,
                      onSelected: (selected) => setState(() => _heatExposure = selected),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _estimatingExperimental ? null : _estimateExperimentalVitals,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D6BFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _estimatingExperimental
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.monitor_heart_outlined),
                    label: Text(
                      _estimatingExperimental
                          ? 'Evaluation en cours...'
                          : 'Estimer la frequence cardiaque, le stress et la tension',
                    ),
                  ),
                ),
                if (_experimentalResult != null) ...[
                  const SizedBox(height: 12),
                  _ResultCard(
                    result: _experimentalResult!,
                    accent: _toneForScore(context, _experimentalResult!.score),
                    text: text,
                    sub: sub,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            cardBg: cardBg,
            text: text,
            sub: sub,
            accent: accent,
            icon: Icons.height_outlined,
            title: 'Mesure de votre taille',
            subtitle:
                'Estimation de votre taille a partir d une photo plein pied et d un objet de reference. Compatible camera simple, sans LiDAR.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withOpacity(0.10)),
                  ),
                  child: Text(
                    _lastHeightCm == null
                        ? 'Aucune taille mesuree pour le moment.'
                        : 'Derniere taille mesuree: ${_lastHeightCm!.toStringAsFixed(1)} cm'
                            '${_heightReferenceLabel.isEmpty ? '' : ' - $_heightReferenceLabel'}',
                    style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openHeightMeasure,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7A4DFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.straighten_outlined),
                    label: const Text('Mesurer ma taille'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            cardBg: cardBg,
            text: text,
            sub: sub,
            accent: accent,
            icon: Icons.history_outlined,
            title: 'Historique recent',
            subtitle:
                'Dernieres analyses climat, expressions faciales, frequence cardiaque, tension et taille.',
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _sessionsRef.orderBy('createdAt', descending: true).limit(8).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Text(
                    'Aucune session enregistree pour le moment.',
                    style: TextStyle(color: sub, fontWeight: FontWeight.w600),
                  );
                }
                return Column(
                  children: docs.map((doc) {
                    final data = doc.data();
                    final score = _toInt(data['score']);
                    final tone = _toneForScore(context, score);
                    final ts = data['createdAt'];
                    final createdAt = ts is Timestamp ? ts.toDate() : null;
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tone.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: tone.withOpacity(0.12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _safeStr(data['title']).isEmpty
                                      ? 'Session'
                                      : _safeStr(data['title']),
                                  style: TextStyle(
                                    color: text,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (score != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: tone.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '$score/100',
                                    style: TextStyle(color: tone, fontWeight: FontWeight.w800),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _safeStr(data['summary']),
                            style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                          ),
                          if (createdAt != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _formatDateTime(createdAt),
                              style: TextStyle(color: sub, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(growable: false),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StressLabResult {
  const _StressLabResult({
    required this.score,
    required this.level,
    required this.summary,
    required this.signals,
    required this.caution,
  });

  final int? score;
  final String level;
  final String summary;
  final List<String> signals;
  final String caution;
}

class _LabNoticeCard extends StatelessWidget {
  const _LabNoticeCard({
    required this.cardBg,
    required this.text,
    required this.sub,
    required this.accent,
    required this.onOpenPpgLab,
    required this.onOpenHeightMeasure,
  });

  final Color cardBg;
  final Color text;
  final Color sub;
  final Color accent;
  final VoidCallback onOpenPpgLab;
  final VoidCallback onOpenHeightMeasure;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withOpacity(0.20),
            Color.lerp(cardBg, const Color(0xFF0D1B2A), 0.10)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.10),
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
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.shield_outlined, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Mode prudent',
                  style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Ergonomique',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Un seul espace pour lire rapidement le stress lie au climat, aux expressions faciales, a la frequence cardiaque, a la tension et a la taille.',
            style: TextStyle(
              color: text,
              height: 1.32,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Ce module suit le stress et la charge physiologique de facon indicative. '
            'La lecture faciale et le protocole camera/doigt servent a l aide a la decision, pas a poser un diagnostic medical.',
            style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'Stress climat',
              'Expression faciale',
              'Frequence cardiaque',
              'Mesure de taille',
            ]
                .map(
                  (label) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(color: text, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: onOpenPpgLab,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                icon: const Icon(Icons.favorite_outline),
                label: const Text(
                  'Frequence cardiaque et tension',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onOpenHeightMeasure,
                style: OutlinedButton.styleFrom(
                  foregroundColor: text,
                  side: BorderSide(color: accent.withOpacity(0.22)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                icon: const Icon(Icons.straighten_outlined),
                label: const Text(
                  'Mesurer ma taille',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.cardBg,
    required this.text,
    required this.sub,
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final Color cardBg;
  final Color text;
  final Color sub;
  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.06),
            blurRadius: 18,
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
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _FactLine extends StatelessWidget {
  const _FactLine({
    required this.text,
    required this.sub,
    required this.label,
    required this.value,
  });

  final Color text;
  final Color sub;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(color: sub, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: text, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _StressSlider extends StatelessWidget {
  const _StressSlider({
    required this.label,
    required this.hint,
    required this.value,
    required this.accent,
    required this.text,
    required this.sub,
    required this.onChanged,
    this.min = 0,
    this.max = 10,
    this.formatter,
  });

  final String label;
  final String hint;
  final double value;
  final Color accent;
  final Color text;
  final Color sub;
  final double min;
  final double max;
  final String Function(double value)? formatter;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final display = formatter?.call(value) ?? value.toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: text, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                display,
                style: TextStyle(color: accent, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: TextStyle(color: sub, fontWeight: FontWeight.w600),
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: accent,
            inactiveColor: accent.withOpacity(0.18),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.accent,
    required this.text,
    required this.sub,
  });

  final _StressLabResult result;
  final Color accent;
  final Color text;
  final Color sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result.score == null
                      ? 'Lecture disponible'
                      : 'Score ${result.score}/100 - ${result.level}',
                  style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  result.level,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.summary,
            style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
          ),
          if (result.signals.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: result.signals
                  .map(
                    (item) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        item,
                        style: TextStyle(color: text, fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (result.caution.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              result.caution,
              style: TextStyle(color: sub, height: 1.45, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:lualaba_konnect/features/auth/presentation/health/health_risk_utils.dart';

class WeatherWidget extends StatefulWidget {
  final bool isDark;
  final Color bg;
  final Color text;
  final Color sub;

  const WeatherWidget({
    super.key,
    required this.isDark,
    required this.bg,
    required this.text,
    required this.sub,
  });

  @override
  State<WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget>
    with SingleTickerProviderStateMixin {
  static const double _windDustRiskThresholdKmh = 40.0;
  static const double _windAlertThresholdKmh = 65.0;
  static const Duration _alertCooldown = Duration(minutes: 30);
  static const int _pageCount = 5;

  String temperature = "--";
  String condition = "Chargement...";
  String cityName = "LOCALISATION...";
  double windSpeed = 0;
  int humidity = 0;
  int sunExposure = 0;
  int aqi = 1;
  bool isDay = true;
  bool isLoading = true;
  List<dynamic> hourlyForecast = [];
  String sunrise = "--:--";
  String sunset = "--:--";
  String pressure = "--";
  String visibility = "--";

  String lastUpdate = "--:--";
  bool isOffline = false;
  int _currentPage = 0;
  late AnimationController _pulseController;
  Timer? _refreshTimer;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _healthSubscription;
  final PageController _pageController = PageController();
  final FlutterLocalNotificationsPlugin _notifs =
      FlutterLocalNotificationsPlugin();
  DateTime? _lastWindAlertAt;
  DateTime? _lastAirAlertAt;
  int? _healthScore;
  String _healthLabel = 'non disponible';
  List<String> _healthRisks = const <String>[];

  double lat = -10.7148;
  double lon = 25.4746;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);

    _initNotifications();
    _initSensors();
    unawaited(_startHealthStateListener());
    fetchAllData();
    _refreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      fetchAllData();
    });
  }

  void _initSensors() {
    _accelSub = accelerometerEvents.listen((event) {
      final acceleration = event.x.abs() + event.y.abs() + event.z.abs();
      if (acceleration > 20) {
        _nextPage();
      }
    });
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifs.initialize(
      const InitializationSettings(android: android),
    );
  }

  Future<void> _getUserLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint(
        "GPS desactive, utilisation des coordonnees par defaut (Kolwezi)",
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint("Permission GPS refusee");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint("Permission GPS refusee definitivement");
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      if (!mounted) return;
      setState(() {
        lat = position.latitude;
        lon = position.longitude;
      });
    } catch (e) {
      debugPrint("Erreur recuperation GPS: $e");
    }
  }

  Future<void> fetchAllData() async {
    await _getUserLocation();

    final apiKey =
        dotenv.env['OPENWEATHER_API_KEY'] ?? dotenv.env['OPENWEATHER_KEY'] ?? '';

    if (apiKey.isEmpty) {
      _simulateData();
      return;
    }

    try {
      final weatherUri = Uri.parse(
        "https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=fr",
      );
      final airUri = Uri.parse(
        "https://api.openweathermap.org/data/2.5/air_pollution?lat=$lat&lon=$lon&appid=$apiKey",
      );
      final forecastUri = Uri.parse(
        "https://api.openweathermap.org/data/2.5/forecast?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=fr",
      );

      final responses = await Future.wait([
        http.get(weatherUri).timeout(const Duration(seconds: 10)),
        http.get(airUri).timeout(const Duration(seconds: 10)),
        http.get(forecastUri).timeout(const Duration(seconds: 10)),
      ]);

      final weatherRes = responses[0];
      final airRes = responses[1];
      final forecastRes = responses[2];

      if (weatherRes.statusCode != 200 ||
          airRes.statusCode != 200 ||
          forecastRes.statusCode != 200) {
        _setOfflineState();
        return;
      }

      final wData = json.decode(weatherRes.body) as Map<String, dynamic>;
      final aData = json.decode(airRes.body) as Map<String, dynamic>;
      final fData = json.decode(forecastRes.body) as Map<String, dynamic>;

      final weatherList = (wData['weather'] as List?) ?? const [];
      final weatherMain = weatherList.isNotEmpty
          ? (weatherList.first['main'] ?? '').toString()
          : '';
      final weatherIcon = weatherList.isNotEmpty
          ? (weatherList.first['icon'] ?? '').toString()
          : '';
      final windSpeedMs = ((wData['wind']?['speed'] as num?) ?? 0).toDouble();
      final cloudCover =
          (((wData['clouds']?['all'] as num?) ?? 0).toDouble()).clamp(0.0, 100.0);
      final forecastList = (fData['list'] as List?) ?? const [];
      final airList = (aData['list'] as List?) ?? const [];
      final airQuality = airList.isNotEmpty
          ? ((airList.first['main']?['aqi'] as num?) ?? 1).toInt()
          : 1;
      final now = DateTime.now();
      final sunriseTimestamp = ((wData['sys']?['sunrise'] as num?) ?? 0).toInt();
      final sunsetTimestamp = ((wData['sys']?['sunset'] as num?) ?? 0).toInt();
      final visibilityMeters =
          ((wData['visibility'] as num?) ?? 0).toDouble();
      final exposure = (100 - cloudCover).round();

      if (!mounted) return;
      setState(() {
        cityName = (wData['name'] ?? cityName).toString().trim().toUpperCase();
        temperature = ((wData['main']?['temp'] as num?) ?? 0).round().toString();
        condition = _translateCondition(weatherMain);
        windSpeed = windSpeedMs * 3.6;
        humidity = ((wData['main']?['humidity'] as num?) ?? 0).toInt();
        isDay = weatherIcon.contains('d');
        sunExposure = isDay ? exposure.clamp(0, 100).toInt() : 0;
        aqi = airQuality;
        hourlyForecast = forecastList.take(5).toList();
        lastUpdate =
            "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
        isOffline = false;
        isLoading = false;
        sunrise = _formatTime(sunriseTimestamp);
        sunset = _formatTime(sunsetTimestamp);
        pressure = ((wData['main']?['pressure'] as num?) ?? 0).toInt().toString();
        visibility = "${(visibilityMeters / 1000).toStringAsFixed(1)} km";
      });
      _checkSafetyAlerts();
    } catch (e) {
      debugPrint("Erreur fetch meteo: $e");
      _setOfflineState();
    }
  }

  Future<void> _startHealthStateListener() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _clearHealthState();
        return;
      }

      final collection = await _resolveUserCollection(user.uid);
      await _healthSubscription?.cancel();

      if (collection == null) {
        _clearHealthState();
        return;
      }

      _healthSubscription = FirebaseFirestore.instance
          .collection(collection)
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
            if (!snapshot.exists) {
              _clearHealthState();
              return;
            }
            _applyHealthState(snapshot.data());
          }, onError: (error) {
            debugPrint('Erreur stream etat sante: $error');
            _clearHealthState();
          });
    } catch (e) {
      debugPrint('Erreur chargement etat sante: $e');
      _clearHealthState();
    }
  }

  Future<String?> _resolveUserCollection(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final preferred = prefs.getString('user_collection')?.trim();
    final candidates = <String>[];
    if (preferred != null && preferred.isNotEmpty) {
      candidates.add(preferred);
    }
    for (final collection in const ['classic_users', 'pro_users', 'enterprise_users', 'users']) {
      if (!candidates.contains(collection)) {
        candidates.add(collection);
      }
    }

    for (final collection in candidates) {
      try {
        final snap = await FirebaseFirestore.instance.collection(collection).doc(uid).get();
        if (snap.exists) {
          return collection;
        }
      } catch (_) {
        // Try the next collection.
      }
    }
    return null;
  }

  void _applyHealthState(Map<String, dynamic>? userData) {
    if (!mounted) return;
    if (userData == null) {
      _clearHealthState();
      return;
    }
    final healthSummary = computeHealthRiskSummaryFromUserData(userData);
    setState(() {
      _healthScore = healthSummary.score;
      _healthLabel = healthSummary.label;
      _healthRisks = healthSummary.risks;
    });
  }

  void _clearHealthState() {
    if (!mounted) return;
    setState(() {
      _healthScore = null;
      _healthLabel = 'non disponible';
      _healthRisks = const <String>[];
    });
  }

  String _formatTime(int timestamp) {
    if (timestamp <= 0) return "--:--";
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
  }

  void _setOfflineState() {
    if (!mounted) return;
    setState(() {
      if (cityName == "LOCALISATION...") {
        cityName = "KOLWEZI";
      }
      isOffline = true;
      isLoading = false;
    });
  }

  void _simulateData() {
    if (!mounted) return;
    setState(() {
      cityName = "DEMO MODE";
      temperature = "28";
      condition = "Nuageux";
      windSpeed = 22.0;
      humidity = 62;
      sunExposure = 58;
      pressure = "1012";
      visibility = "8.0 km";
      lastUpdate = "DEMO";
      isOffline = true;
      isLoading = false;
    });
  }

  void _checkSafetyAlerts() {
    final now = DateTime.now();

    if (windSpeed >= _windAlertThresholdKmh &&
        _shouldSendAlert(_lastWindAlertAt, now)) {
      _lastWindAlertAt = now;
      _showAlerte(
        1001,
        "Alerte vent fort ($cityName)",
        "Vent releve a ${windSpeed.toStringAsFixed(1)} km/h. Vigilance recommandee.",
      );
    }

    if (aqi >= 4 && _shouldSendAlert(_lastAirAlertAt, now)) {
      _lastAirAlertAt = now;
      _showAlerte(
        1002,
        "Alerte qualite de l'air ($cityName)",
        "Air degrade detecte. Protection respiratoire recommandee.",
      );
    }
  }

  bool _shouldSendAlert(DateTime? lastAlertAt, DateTime now) {
    return lastAlertAt == null || now.difference(lastAlertAt) >= _alertCooldown;
  }

  Future<void> _showAlerte(int id, String title, String message) async {
    const details = AndroidNotificationDetails(
      'weather_safety',
      'Vigilance meteo',
      importance: Importance.max,
      priority: Priority.high,
      color: Colors.red,
    );

    await _notifs.show(
      id,
      title,
      message,
      const NotificationDetails(android: details),
    );
  }

  void _nextPage() {
    if (!mounted) return;
    _currentPage = (_currentPage + 1) % _pageCount;
    _pageController.animateToPage(
      _currentPage,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(35),
      child: AnimatedContainer(
        duration: const Duration(seconds: 1),
        height: 230,
        decoration: BoxDecoration(gradient: _getDynamicGradient()),
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Stack(
                children: [
                  PageView(
                    controller: _pageController,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    children: [
                      _buildHealthPage(),
                      _buildPageOne(),
                      _buildPageTwo(),
                      _buildPageThree(),
                      _buildPageFour(),
                    ],
                  ),
                  _buildIndicators(),
                ],
              ),
      ),
    );
  }

  Widget _buildPageOne() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        "$cityName - LIVE",
                        style: _tagStyle.copyWith(
                          color: isOffline
                              ? Colors.orangeAccent
                              : Colors.redAccent.shade100,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isOffline)
                      const Icon(
                        Icons.cloud_off,
                        color: Colors.orangeAccent,
                        size: 14,
                      )
                    else
                      Text(
                        lastUpdate,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                Text(
                  "$temperature C",
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                _buildHourlyTrend(),
                const Spacer(),
                _infoCapsule(isOffline ? "Mode hors ligne" : _getClothingAdvice()),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 1.0, end: 1.1).animate(
                  _pulseController,
                ),
                child: Icon(
                  isOffline ? Icons.wifi_off_rounded : _getIcon(),
                  size: 65,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isOffline ? "HORS LIGNE" : condition.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHealthPage() {
    final score = (_healthScore ?? 0).clamp(0, 100);
    final accent = _healthAccentColor;
    final support = _healthSupportText;
    final topRisk = healthRiskTopPoint(_healthRisks);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactWidth = constraints.maxWidth < 360;
          final compactHeight = constraints.maxHeight < 188;
          final compact = compactWidth || compactHeight;
          final gaugeSize = compactHeight
              ? 94.0
              : compactWidth
                  ? 104.0
                  : 118.0;

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                colors: [
                  accent.withOpacity(0.32),
                  Colors.white.withOpacity(0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.24),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -18,
                  right: -6,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) => Transform.scale(
                      scale: 0.92 + (_pulseController.value * 0.14),
                      child: child,
                    ),
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -22,
                  left: -8,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(0.18),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withOpacity(0.16)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.favorite_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 8),
                            Text(
                              'SANTÉ PERSONNELLE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compactHeight ? 6 : 10),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildAnimatedHealthGauge(score, accent, size: gaugeSize),
                            SizedBox(width: compact ? 10 : 14),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _healthScore == null ? 'Votre score santé' : 'Votre santé aujourd’hui',
                                    maxLines: compactHeight ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: compactHeight
                                          ? 16
                                          : compactWidth
                                              ? 18
                                              : 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  SizedBox(height: compactHeight ? 4 : 6),
                                  Text(
                                    _healthScore == null
                                        ? 'Connectez votre profil santé pour voir une lecture animée ici.'
                                        : support,
                                    maxLines: compactHeight
                                        ? 2
                                        : compactWidth
                                            ? 3
                                            : 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.88),
                                      height: 1.28,
                                      fontSize: compactHeight
                                          ? 10.5
                                          : compactWidth
                                              ? 11.5
                                              : 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: compactHeight ? 6 : 10),
                                  Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.all(compactHeight ? 8 : 10),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Point clé',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.72),
                                            fontSize: compactHeight ? 9 : 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                        SizedBox(height: compactHeight ? 2 : 4),
                                        Text(
                                          topRisk,
                                          maxLines: compactHeight ? 1 : 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: compactHeight
                                                ? 10
                                                : compactWidth
                                                    ? 11
                                                    : 12,
                                            fontWeight: FontWeight.w700,
                                            height: 1.22,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnimatedHealthGauge(int score, Color accent, {double size = 118}) {
    return KeyedSubtree(
      key: ValueKey<int>(score),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: score.toDouble()),
        duration: const Duration(milliseconds: 1800),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          final progress = (value / 100).clamp(0.0, 1.0);
          final display = score <= 0 ? 0 : value.clamp(1, score.toDouble()).round();
          final innerSize = size - 30;
          final ringWidth = size < 112 ? 8.0 : 10.0;

          return SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
                SizedBox(
                  width: size,
                  height: size,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: ringWidth,
                    backgroundColor: Colors.white.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) => Transform.scale(
                    scale: 0.96 + (_pulseController.value * 0.06),
                    child: child,
                  ),
                  child: Container(
                    width: innerSize,
                    height: innerSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withOpacity(0.22),
                          Colors.white.withOpacity(0.08),
                        ],
                      ),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      score <= 0 ? '--' : '$display',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size < 112 ? 26 : 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.1,
                      ),
                    ),
                    Text(
                      '% Santé',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: size < 112 ? 10 : 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _healthLabelDisplay,
                        style: TextStyle(
                          color: accent,
                          fontSize: size < 112 ? 10 : 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHourlyTrend() {
    if (hourlyForecast.isEmpty) return const SizedBox(height: 50);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(hourlyForecast.length, (index) {
          final item = hourlyForecast[index] as Map<String, dynamic>;
          final mainData = (item['main'] as Map<String, dynamic>?) ?? const {};
          final weatherItems = (item['weather'] as List?) ?? const [];
          final weatherMain = weatherItems.isNotEmpty
              ? (weatherItems.first['main'] ?? '').toString()
              : '';
          final temp = ((mainData['temp'] as num?) ?? 0).round();
          final dt = ((item['dt'] as num?) ?? 0).toInt();
          final time =
              "${DateTime.fromMillisecondsSinceEpoch(dt * 1000).hour}h";

          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 500 + (index * 150)),
            curve: Curves.easeOutBack,
            builder: (context, value, child) =>
                Transform.scale(scale: value, child: child),
            child: Column(
              children: [
                Text(
                  "$temp C",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  _getMiniIcon(weatherMain),
                  size: 14,
                  color: Colors.white70,
                ),
                Text(
                  time,
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPageTwo() => _buildBasePage(
        title: "SÉCURITÉ VENT",
        icon: Icons.wind_power,
        content: Column(
          children: [
            Text(
              "${windSpeed.toStringAsFixed(1)} km/h",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: (windSpeed / _windAlertThresholdKmh).clamp(0.0, 1.0),
                backgroundColor: Colors.grey.shade50,
                color: windSpeed >= _windAlertThresholdKmh
                    ? Colors.redAccent
                    : (windSpeed >= _windDustRiskThresholdKmh
                        ? Colors.orange
                        : Colors.blue),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              windSpeed >= _windAlertThresholdKmh
                  ? "ALERTE : vent fort"
                  : (windSpeed >= _windDustRiskThresholdKmh
                      ? "Vigilance poussière et déplacements"
                      : "Vent stable"),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );

  Widget _buildPageThree() => _buildBasePage(
        title: "AIR & SANTÉ",
        icon: Icons.health_and_safety,
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _miniStat("Soleil", "$sunExposure%", Icons.wb_sunny),
            _miniStat("Pollution", _getAirQualityText(), Icons.masks),
            _miniStat("Humidité", "$humidity%", Icons.water_drop),
          ],
        ),
      );

  Widget _buildPageFour() => _buildBasePage(
        title: "ATMOSPHÈRE & VISIBILITÉ",
        icon: Icons.visibility,
        content: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _miniStat("Visibilité", visibility, Icons.remove_red_eye),
                _miniStat("Pression", "$pressure hPa", Icons.speed),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      const Icon(
                        Icons.wb_twilight,
                        color: Colors.orangeAccent,
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sunrise,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        "Lever",
                        style: TextStyle(color: Colors.white54, fontSize: 9),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Container(height: 2, color: Colors.white24),
                    ),
                  ),
                  Column(
                    children: [
                      const Icon(
                        Icons.nights_stay,
                        color: Colors.purpleAccent,
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sunset,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        "Coucher",
                        style: TextStyle(color: Colors.white54, fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildBasePage({
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              Text(title, style: _tagStyle),
            ],
          ),
          const Spacer(),
          content,
          const Spacer(),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 9),
        ),
      ],
    );
  }

  Widget _infoCapsule(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    );
  }

  Widget _buildIndicators() {
    return Positioned(
      bottom: 12,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          _pageCount,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 4,
            width: _currentPage == index ? 16 : 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(_currentPage == index ? 1 : 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  LinearGradient _getDynamicGradient() {
    if (isOffline) {
      return const LinearGradient(
        colors: [Color(0xFF434343), Color(0xFF000000)],
        begin: Alignment.topLeft,
      );
    }
    if (!isDay) {
      return const LinearGradient(
        colors: [Color(0xFF0F2027), Color(0xFF2C5364)],
        begin: Alignment.topLeft,
      );
    }
    if (aqi >= 4 || windSpeed >= _windAlertThresholdKmh) {
      return const LinearGradient(
        colors: [Color(0xFFCB2D3E), Color(0xFFEF473A)],
        begin: Alignment.topLeft,
      );
    }
    if (condition == "Pluie" || condition == "Orage") {
      return const LinearGradient(
        colors: [Color(0xFF373B44), Color(0xFF4286F4)],
        begin: Alignment.topLeft,
      );
    }
    return const LinearGradient(
      colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  IconData _getIcon() {
    if (condition == "Orage") return Icons.thunderstorm;
    if (condition == "Pluie") return Icons.umbrella;
    if (condition == "Nuageux") return Icons.cloud;
    if (condition == "Brume") return Icons.foggy;
    return isDay ? Icons.wb_sunny : Icons.nightlight_round;
  }

  IconData _getMiniIcon(String apiCondition) {
    switch (apiCondition) {
      case "Rain":
      case "Drizzle":
        return Icons.umbrella;
      case "Thunderstorm":
        return Icons.thunderstorm;
      case "Clouds":
        return Icons.cloud;
      case "Mist":
        return Icons.foggy;
      default:
        return Icons.wb_sunny;
    }
  }

  String _translateCondition(String apiCondition) {
    switch (apiCondition) {
      case 'Thunderstorm':
        return "Orage";
      case 'Rain':
        return "Pluie";
      case 'Drizzle':
        return "Bruine";
      case 'Clouds':
        return "Nuageux";
      case 'Clear':
        return "Dégagé";
      case 'Mist':
        return "Brume";
      default:
        return "Variable";
    }
  }

  String _getAirQualityText() {
    if (aqi <= 2) return "Bon";
    if (aqi == 3) return "Moyen";
    return "Mauvais";
  }

  String _getClothingAdvice() {
    final tempValue = int.tryParse(temperature);
    if (condition == "Pluie") return "Pluie : prenez un imperméable";
    if (tempValue != null && tempValue > 28) {
      return "Chaleur : pensez à boire de l'eau";
    }
    return "Conditions stables";
  }

  Color get _healthAccentColor {
    final score = _healthScore ?? 0;
    if (score >= 80) return const Color(0xFF7CFFB2);
    if (score >= 60) return const Color(0xFFFFC14D);
    return const Color(0xFFFF7C7C);
  }

  String get _healthLabelDisplay {
    return healthRiskDisplayLabel(_healthLabel);
  }

  String get _healthSupportText {
    return healthRiskSupportText(_healthScore);
  }

  TextStyle get _tagStyle => const TextStyle(
        color: Colors.white70,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
      );

  @override
  void dispose() {
    _accelSub?.cancel();
    _healthSubscription?.cancel();
    _pageController.dispose();
    _pulseController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }
}

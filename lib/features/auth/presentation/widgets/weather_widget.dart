import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

class _WeatherWidgetState extends State<WeatherWidget> with SingleTickerProviderStateMixin {
  // Données API
  String temperature = "--";
  String condition = "Chargement...";
  double windSpeed = 0;
  int humidity = 0;
  double uvIndex = 0.0;
  int aqi = 1; 
  bool isDay = true;
  bool isLoading = true;
  List<dynamic> hourlyForecast = [];
  
  // État & Capteurs
  String lastUpdate = "--:--";
  bool isOffline = false;
  int _currentPage = 0;
  late AnimationController _pulseController;
  Timer? _refreshTimer;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  final PageController _pageController = PageController();
  final FlutterLocalNotificationsPlugin _notifs = FlutterLocalNotificationsPlugin();

  // Coordonnées de Kolwezi
  final double lat = -10.7148;
  final double lon = 25.4746;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this, duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _initNotifications();
    _initSensors();
    fetchAllData();

    // Rafraîchissement auto toutes les 10 minutes
    _refreshTimer = Timer.periodic(const Duration(minutes: 10), (t) => fetchAllData());
  }

  // --- INITIALISATIONS ---

  void _initSensors() {
    // Détecte si l'utilisateur secoue le téléphone pour changer de page (pratique avec des gants)
    _accelSub = accelerometerEvents.listen((event) {
      double acceleration = event.x.abs() + event.y.abs() + event.z.abs();
      if (acceleration > 20) { // Seuil de secousse ajusté
        _nextPage();
      }
    });
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher'); // Assure-toi d'avoir une icône
    await _notifs.initialize(const InitializationSettings(android: android));
  }

  // --- LOGIQUE DE DONNÉES ---

  Future<void> fetchAllData() async {
    // Clé API OpenWeather (Idéalement à mettre dans un fichier de config sécurisé)
    const String apiKey = String.fromEnvironment('OPENWEATHER_KEY', defaultValue: ''); 
    
    // Si pas de clé, on simule des données pour éviter le crash en démo
    if (apiKey.isEmpty) {
       _simulateData();
       return;
    }

    try {
      final weatherUri = Uri.parse("https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=fr");
      final airUri = Uri.parse("https://api.openweathermap.org/data/2.5/air_pollution?lat=$lat&lon=$lon&appid=$apiKey");
      final forecastUri = Uri.parse("https://api.openweathermap.org/data/2.5/forecast?lat=$lat&lon=$lon&appid=$apiKey&units=metric&lang=fr");

      // Appels parallèles avec Timeout pour gérer la mauvaise connexion à Kolwezi
      final responses = await Future.wait([
        http.get(weatherUri).timeout(const Duration(seconds: 8)),
        http.get(airUri).timeout(const Duration(seconds: 8)),
        http.get(forecastUri).timeout(const Duration(seconds: 8)),
      ]);

      if (responses[0].statusCode == 200) {
        final wData = json.decode(responses[0].body);
        final aData = json.decode(responses[1].body);
        final fData = json.decode(responses[2].body);

        if (mounted) {
          setState(() {
            temperature = (wData['main']['temp'] as num).round().toString();
            condition = _translateCondition(wData['weather'][0]['main']);
            windSpeed = (wData['wind']['speed'] as num).toDouble();
            humidity = wData['main']['humidity'];
            isDay = wData['weather'][0]['icon'].contains('d');
            
            // Calcul approximatif UV si API gratuite (basé sur nuages en journée)
            double cloudCover = (wData['clouds']['all'] as num).toDouble();
            uvIndex = isDay ? (10 * (1 - (cloudCover / 100))) : 0.0;

            aqi = aData['list'][0]['main']['aqi'];
            hourlyForecast = fData['list'].take(5).toList();
            
            final now = DateTime.now();
            lastUpdate = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
            isOffline = false;
            isLoading = false;
          });
          _checkSafetyAlerts();
        }
      } else {
        if (mounted) setState(() => isOffline = true);
      }
    } catch (e) {
      if (mounted) setState(() => isOffline = true);
    }
  }

  void _simulateData() {
    // Fallback si pas de clé API configurée
    setState(() {
      temperature = "28";
      condition = "Nuageux";
      windSpeed = 12.5;
      isOffline = true;
      isLoading = false;
    });
  }

  void _checkSafetyAlerts() {
    // Seuils de sécurité minière
    if (windSpeed > 18.0) _showAlerte("⚠️ VENT VIOLENT", "Arrêt levage recommandé. Vitesse : ${windSpeed}km/h");
    if (aqi >= 4) _showAlerte("😷 QUALITÉ AIR CRITIQUE", "Poussière dense. Masque obligatoire sur site.");
  }

  Future<void> _showAlerte(String tit, String msg) async {
    const details = AndroidNotificationDetails('mine_safety', 'Sécurité Mine', importance: Importance.max, priority: Priority.high, color: Colors.red);
    await _notifs.show(0, tit, msg, const NotificationDetails(android: details));
  }

  void _nextPage() {
    if (mounted) {
      _currentPage = (_currentPage + 1) % 4;
      _pageController.animateToPage(_currentPage, duration: const Duration(milliseconds: 600), curve: Curves.easeOutBack);
    }
  }

  // --- UI BUILD ---

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(35),
      child: AnimatedContainer(
        duration: const Duration(seconds: 1),
        height: 230, // Hauteur ajustée pour le contenu riche
        decoration: BoxDecoration(gradient: _getDynamicGradient()),
        child: isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              children: [
                PageView(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [_buildPageOne(), _buildPageTwo(), _buildPageThree(), _buildPageFour()],
                ),
                _buildIndicators(),
              ],
            ),
      ),
    );
  }

  // PAGE 1 : Général + Graphique Tendance
  Widget _buildPageOne() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text("KOLWEZI • LIVE", style: _tagStyle.copyWith(color: isOffline ? Colors.orangeAccent : Colors.redAccent.shade100)),
                const SizedBox(width: 8),
                if (isOffline) const Icon(Icons.cloud_off, color: Colors.orangeAccent, size: 14) 
                else Text(lastUpdate, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold)),
              ]),
              Text("$temperature°", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white, height: 1.1)),
              _buildHourlyTrend(), // Le graphique animé
              const Spacer(),
              _infoCapsule(isOffline ? "Données cache" : _getClothingAdvice()),
            ]),
          ),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.1).animate(_pulseController),
              child: Icon(isOffline ? Icons.wifi_off_rounded : _getIcon(), size: 65, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(isOffline ? "HORS LIGNE" : condition.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
          ]),
        ],
      ),
    );
  }

  // Le Widget du graphique animé
  Widget _buildHourlyTrend() {
    if (hourlyForecast.isEmpty) return const SizedBox(height: 50);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(hourlyForecast.length, (index) {
          final item = hourlyForecast[index];
          String time = "${DateTime.fromMillisecondsSinceEpoch(item['dt'] * 1000).hour}h";
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 500 + (index * 150)), // Effet cascade
            curve: Curves.easeOutBack,
            builder: (context, val, child) => Transform.scale(scale: val, child: child),
            child: Column(children: [
              Text("${(item['main']['temp'] as num).round()}°", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Icon(_getMiniIcon(item['weather'][0]['main']), size: 14, color: Colors.white70),
              Text(time, style: const TextStyle(color: Colors.white54, fontSize: 9)),
            ]),
          );
        }),
      ),
    );
  }

  // PAGE 2 : Sécurité Vent (Critique pour les mines)
  Widget _buildPageTwo() => _buildBasePage(title: "SÉCURITÉ VENT", icon: Icons.wind_power, content: Column(children: [
    Text("${windSpeed.toStringAsFixed(1)} km/h", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: LinearProgressIndicator(minHeight: 8, value: (windSpeed/20).clamp(0, 1), backgroundColor: Colors.white10, color: windSpeed > 15 ? Colors.orange : Colors.greenAccent),
    ),
    const SizedBox(height: 15),
    Text(windSpeed > 15 ? "⚠️ RISQUE POUSSIÈRE ÉLEVÉ" : "✅ VENT CALME : OPÉRATIONS OK", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
  ]));

  // PAGE 3 : Qualité Air & UV
  Widget _buildPageThree() => _buildBasePage(title: "AIR & SANTÉ", icon: Icons.health_and_safety, content: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
    _miniStat("UV Index", uvIndex.toStringAsFixed(1), Icons.wb_sunny),
    _miniStat("Pollution", _getAirQualityText(), Icons.masks),
    _miniStat("Humidité", "$humidity%", Icons.water_drop),
  ]));

  // PAGE 4 : Infos Sol / Géologie (Pour le fun/contexte)
  Widget _buildPageFour() => _buildBasePage(title: "GÉOLOGIE & SOL", icon: Icons.terrain, content: Column(children: [
    const Text("STABILITÉ : OPTIMALE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
    const SizedBox(height: 10),
    _infoCapsule("Aucun tir de mine signalé"),
    const SizedBox(height: 10),
    const Text("Zone : Kolwezi Est", style: TextStyle(color: Colors.white54, fontSize: 10)),
  ]));

  // --- HELPERS UI ---

  Widget _buildBasePage({required String title, required IconData icon, required Widget content}) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: Colors.white70, size: 16), const SizedBox(width: 8), Text(title, style: _tagStyle)]),
      const Spacer(), content, const Spacer(),
    ]),
  );

  Widget _miniStat(String l, String v, IconData i) => Column(children: [
    Icon(i, color: Colors.white, size: 22), 
    const SizedBox(height: 5),
    Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)), 
    Text(l, style: const TextStyle(color: Colors.white54, fontSize: 9))
  ]);
  
  Widget _infoCapsule(String t) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 10)));

  Widget _buildIndicators() => Positioned(bottom: 12, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) => AnimatedContainer(duration: const Duration(milliseconds: 300), margin: const EdgeInsets.symmetric(horizontal: 3), height: 4, width: _currentPage == i ? 16 : 4, decoration: BoxDecoration(color: Colors.white.withOpacity(_currentPage == i ? 1 : 0.3), borderRadius: BorderRadius.circular(2))))));

  // --- LOGIQUE METIER / COULEURS ---

  LinearGradient _getDynamicGradient() {
    if (isOffline) return const LinearGradient(colors: [Color(0xFF434343), Color(0xFF000000)], begin: Alignment.topLeft);
    if (!isDay) return const LinearGradient(colors: [Color(0xFF0F2027), Color(0xFF2C5364)], begin: Alignment.topLeft);
    if (aqi >= 4 || windSpeed > 18) return const LinearGradient(colors: [Color(0xFFcb2d3e), Color(0xFFef473a)], begin: Alignment.topLeft); // Rouge urgence
    if (condition == "Pluie" || condition == "Orage") return const LinearGradient(colors: [Color(0xFF373B44), Color(0xFF4286f4)], begin: Alignment.topLeft);
    return const LinearGradient(colors: [Color(0xFF00B4DB), Color(0xFF0083B0)], begin: Alignment.topLeft, end: Alignment.bottomRight); // Bleu Lualaba
  }

  IconData _getIcon() {
    if (condition == "Orage") return Icons.thunderstorm;
    if (condition == "Pluie") return Icons.umbrella;
    if (condition == "Nuageux") return Icons.cloud;
    return isDay ? Icons.wb_sunny : Icons.nightlight_round;
  }

  IconData _getMiniIcon(String c) => c == "Rain" ? Icons.umbrella : (c == "Clouds" ? Icons.cloud : Icons.wb_sunny);
  
  String _translateCondition(String api) {
    switch(api) {
      case 'Thunderstorm': return "Orage";
      case 'Rain': return "Pluie";
      case 'Drizzle': return "Bruine";
      case 'Clouds': return "Nuageux";
      case 'Clear': return "Dégagé";
      case 'Mist': return "Brume";
      default: return "Variable";
    }
  }

  String _getAirQualityText() {
    if (aqi <= 2) return "Bon";
    if (aqi == 3) return "Moyen";
    return "Mauvais";
  }

  String _getClothingAdvice() {
    if (condition == "Pluie") return "Prenez un imperméable ☔";
    if (int.tryParse(temperature)! > 28) return "Chaleur : Eau requise 💧";
    return "Tenue EPI Standard 👷‍♂️";
  }

  TextStyle get _tagStyle => const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2);

  @override
  void dispose() {
    _accelSub?.cancel();
    _pageController.dispose();
    _pulseController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }
}
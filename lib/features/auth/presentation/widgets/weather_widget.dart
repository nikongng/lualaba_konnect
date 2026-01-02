import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

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
  String temperature = "--";
  String condition = "Chargement...";
  double windSpeed = 0;
  bool isDay = true;
  bool isLoading = true;
  int _currentPage = 0;
  late AnimationController _pulseController;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    // Première récupération
    fetchWeatherData();

    // Rafraîchissement automatique toutes les 10 minutes
    _refreshTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      fetchWeatherData();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchWeatherData() async {
    // REMPLACE PAR TA CLÉ RÉELLE ICI
    const String apiKey = "e58c0e86611320659c9e44676621201e"; 
    const String city = "Kolwezi";
    const String url = "https://api.openweathermap.org/data/2.5/weather?q=$city&appid=$apiKey&units=metric&lang=fr";

    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            // 1. Température arrondie
            temperature = (data['main']['temp'] as num).round().toString();
            
            // 2. Vitesse du vent
            windSpeed = (data['wind']['speed'] as num).toDouble();
            
            // 3. Détection intelligente de la condition (Priorité à la pluie/orage)
            List weatherList = data['weather'];
            String mainCond = weatherList.any((w) => w['main'] == 'Thunderstorm') 
                ? 'Thunderstorm' 
                : weatherList.any((w) => w['main'] == 'Rain') 
                    ? 'Rain' 
                    : weatherList[0]['main'];
            
            condition = _translateCondition(mainCond);
            
            // 4. Détection jour/nuit via l'icône
            String iconCode = data['weather'][0]['icon'];
            isDay = iconCode.contains('d');
            
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => condition = "Erreur Flux");
    }
  }

  String _translateCondition(String apiCondition) {
    switch (apiCondition) {
      case 'Thunderstorm': return "Orage";
      case 'Rain': 
      case 'Drizzle': return "Pluie";
      case 'Clouds': return "Nuageux";
      case 'Clear': return "Dégagé";
      case 'Mist':
      case 'Fog': return "Brouillard";
      default: return "Variable";
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(35),
      child: AnimatedContainer(
        duration: const Duration(seconds: 1),
        height: 180,
        decoration: BoxDecoration(
          gradient: _getDynamicGradient(),
        ),
        child: isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              children: [
                _buildBackgroundParticles(),
                PageView(
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _buildMainView(),
                    _buildMiningView(),
                  ],
                ),
                Positioned(
                  bottom: 15, left: 0, right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [0, 1].map((i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 6, width: _currentPage == i ? 20 : 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(_currentPage == i ? 1 : 0.4), 
                        borderRadius: BorderRadius.circular(3)
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildBackgroundParticles() {
    bool isRaining = condition == "Pluie" || condition == "Orage";
    return StreamBuilder(
      stream: Stream.periodic(const Duration(milliseconds: 100)),
      builder: (context, snapshot) {
        return Stack(
          children: List.generate(6, (index) {
            return AnimatedPositioned(
              duration: Duration(seconds: isRaining ? 1 : 4),
              left: (index * 60.0 + (DateTime.now().millisecondsSinceEpoch % 2000) / 20),
              top: isRaining ? (index * 40.0 + (DateTime.now().millisecondsSinceEpoch % 1000) / 10) : (index * 30.0),
              child: Opacity(
                opacity: 0.15,
                child: Icon(
                  isRaining ? Icons.water_drop : Icons.air, 
                  color: Colors.white, 
                  size: isRaining ? 20 : 35
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildMainView() {
    return Padding(
      padding: const EdgeInsets.all(25),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("KOLWEZI • LIVE", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 5),
              Text("$temperature°", style: const TextStyle(color: Colors.white, fontSize: 55, fontWeight: FontWeight.bold)),
              Text(condition.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w400, letterSpacing: 1)),
            ],
          ),
          ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 1.1).animate(_pulseController),
            child: Icon(_getIcon(), color: Colors.white, size: 75),
          ),
        ],
      ),
    );
  }

  Widget _buildMiningView() {
    double riskLevel = (windSpeed / 15).clamp(0.0, 1.0); // Seuil ajusté
    return Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        children: [
          const Text("INDICATEURS MINIERS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 15),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 60, width: 60,
                child: CircularProgressIndicator(
                  value: riskLevel, 
                  strokeWidth: 8, 
                  backgroundColor: Colors.white12, 
                  color: riskLevel > 0.4 ? Colors.orangeAccent : Colors.lightGreenAccent
                ),
              ),
              Icon(riskLevel > 0.4 ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: Colors.white, size: 22),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            riskLevel > 0.4 ? "Vent modéré : Vigilance poussière" : "Conditions idéales", 
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 11)
          ),
        ],
      ),
    );
  }

  LinearGradient _getDynamicGradient() {
    if (!isDay) return const LinearGradient(colors: [Color(0xFF141E30), Color(0xFF243B55)], begin: Alignment.topLeft);
    if (condition == "Pluie" || condition == "Orage") {
      return const LinearGradient(colors: [Color(0xFF606c88), Color(0xFF3f4c6b)], begin: Alignment.topLeft);
    }
    return const LinearGradient(
      colors: [Color(0xFF00CBA9), Color(0xFF005F52)], 
      begin: Alignment.topLeft, 
      end: Alignment.bottomRight
    );
  }

  IconData _getIcon() {
    if (condition == "Orage") return Icons.thunderstorm_rounded;
    if (condition == "Pluie") return Icons.umbrella_rounded;
    if (condition == "Nuageux") return Icons.cloud_rounded;
    return isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
  }
}
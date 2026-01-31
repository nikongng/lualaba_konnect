import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../../screnns/metal_detail_page.dart'; // Vérifie bien le chemin (screens?)

class CopperCard extends StatefulWidget {
  const CopperCard({super.key});

  @override
  State<CopperCard> createState() => _CopperCardState();
}

class _CopperCardState extends State<CopperCard> {
  String copperPrice = "---";
  String cobaltPrice = "---";
  String copperChange = "0.00%";
  String cobaltChange = "0.00%";
  String lastUpdate = "Jamais";
  bool isCopperUp = true;
  bool isCobaltUp = true;
  bool isLoading = false;

  final String copperUrl = "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f0/NatCopper.jpg/200px-NatCopper.jpg";
  final String cobaltUrl = "https://upload.wikimedia.org/wikipedia/commons/thumb/6/62/Cobalt_ore_2.jpg/200px-Cobalt_ore_2.jpg";

  @override
  void initState() {
    super.initState();
    fetchPrices(); // Premier chargement au lancement
  }

  // --- LOGIQUE API ---
  Future<void> fetchPrices() async {
    if (isLoading) return;
    
    setState(() => isLoading = true);

    final String apiKey = dotenv.env['METALS_API_KEY'] ?? '';
    // Unité 't' pour la Tonne (LME standard)
    final url = Uri.parse('https://api.metals.dev/v1/latest?api_key=$apiKey&currency=USD&unit=t');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final metals = data['metals'];
        final now = DateTime.now();

        if (mounted) {
          setState(() {
            if (metals.containsKey('copper')) {
              copperPrice = _formatNumber(metals['copper']);
            }
            if (metals.containsKey('cobalt')) {
              cobaltPrice = _formatNumber(metals['cobalt']);
            }
            lastUpdate = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Erreur API Metals: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _formatNumber(dynamic value) {
    if (value == null) return "---";
    // Formate avec séparateur de milliers pour la lisibilité
    return (value as num).toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        children: [
          // Barre d'outils avec le bouton Refresh
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 15, 10, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "MARCHÉ LME (MàJ: $lastUpdate)",
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                IconButton(
                  onPressed: isLoading ? null : fetchPrices,
                  icon: isLoading 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 20, color: Colors.blue),
                ),
              ],
            ),
          ),
          
          _buildMetalRow(
            context,
            label: "CUIVRE (LME)",
            price: copperPrice,
            change: copperChange,
            isUp: isCopperUp,
            color: Colors.orange.shade800,
            chartPoints: [10, 12, 9, 15, 14, 18, 20],
            imageUrl: copperUrl,
          ),
          Divider(height: 1, color: Colors.grey.withOpacity(0.1), indent: 20, endIndent: 20),
          _buildMetalRow(
            context,
            label: "COBALT (LME)",
            price: cobaltPrice,
            change: cobaltChange,
            isUp: isCobaltUp,
            color: Colors.blue.shade900,
            chartPoints: [18, 17, 19, 16, 15, 14, 13],
            imageUrl: cobaltUrl,
          ),
        ],
      ),
    );
  }

  Widget _buildMetalRow(BuildContext context, {
    required String label, required String price, required String change,
    required bool isUp, required Color color, required List<double> chartPoints,
    required String imageUrl,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => MetalDetailPage(
            metalName: label, price: price, change: change, history: chartPoints, color: color,
          ),
        ));
      },
      borderRadius: BorderRadius.circular(30),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              height: 52, width: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.1),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: ClipOval(
                child: Image.network(
                  imageUrl, fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(Icons.layers_rounded, color: color),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text("\$$price", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            // Mini Graphique
            SizedBox(
              width: 60, height: 30,
              child: CustomPaint(painter: SparklinePainter(chartPoints, isUp ? Colors.green : Colors.red)),
            ),
            const SizedBox(width: 15),
            // Badge Variation
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (isUp ? Colors.green : Colors.red).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(change, style: TextStyle(color: isUp ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

// --- CETTE CLASSE DOIT ÊTRE EN DEHORS DES AUTRES CLASSES ---

class SparklinePainter extends CustomPainter {
  final List<double> points;
  final Color color;
  SparklinePainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final double stepX = size.width / (points.length - 1);
    
    // Calcul des min/max pour que le graph tienne dans la petite boîte
    final double maxY = points.reduce((a, b) => a > b ? a : b);
    final double minY = points.reduce((a, b) => a < b ? a : b);
    final double range = (maxY - minY) == 0 ? 1.0 : (maxY - minY);

    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final y = size.height - ((points[i] - minY) / range * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
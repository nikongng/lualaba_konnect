import 'package:flutter/material.dart';
import '../../../../screnns/metal_detail_page.dart'; 
import '../../../../core/services/copper_services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CopperCard extends StatefulWidget {
  const CopperCard({super.key});

  @override
  State<CopperCard> createState() => _CopperCardState();
}

class _CopperCardState extends State<CopperCard> {
  // Données dynamiques initialisées avec des valeurs par défaut
  String copperPrice = "Chargement...";
  String cobaltPrice = "Chargement...";
  String copperChange = "0.00%";
  String cobaltChange = "0.00%";
  bool isCopperUp = true;
  bool isCobaltUp = true;
  bool isLoading = true;

  // Utilisation d'URLs d'images plus directes et robustes (Source: Wikimedia/Pexels)
  final String copperUrl = "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f0/NatCopper.jpg/200px-NatCopper.jpg";
  final String cobaltUrl = "https://upload.wikimedia.org/wikipedia/commons/thumb/6/62/Cobalt_ore_2.jpg/200px-Cobalt_ore_2.jpg";

  @override
  void initState() {
    super.initState();
    fetchPrices();
  }

  // Fonction pour récupérer les données depuis une API ou un service
  Future<void> fetchPrices() async {
    setState(() => isLoading = true);
    try {
      // Simulation d'un appel au service (À remplacer par votre service réel)
      await Future.delayed(const Duration(seconds: 2)); 

      if (mounted) {
        setState(() {
          copperPrice = "9,450.50";
          cobaltPrice = "24,290.00";
          copperChange = "+1.25%";
          cobaltChange = "-0.45%";
          isCopperUp = true;
          isCobaltUp = false;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          copperPrice = "Erreur";
          cobaltPrice = "Erreur";
          isLoading = false;
        });
      }
    }
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
          Divider(
            height: 1, 
            color: Colors.grey.withOpacity(0.1), 
            indent: 20, 
            endIndent: 20
          ),
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

  Widget _buildMetalRow(
    BuildContext context, {
    required String label,
    required String price,
    required String change,
    required bool isUp,
    required Color color,
    required List<double> chartPoints,
    required String imageUrl,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MetalDetailPage(
              metalName: label,
              price: price,
              change: change,
              history: chartPoints,
              color: color,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(30),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Affichage de l'image réseau avec indicateur de progression
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.1),
                border: Border.all(
                  color: color.withOpacity(0.2), 
                  width: 1
                ),
              ),
              child: ClipOval(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    // Si l'URL échoue, on affiche une icône stylisée
                    return Icon(Icons.layers_rounded, color: color, size: 28);
                  },
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label, 
                    style: const TextStyle(
                      fontSize: 10, 
                      fontWeight: FontWeight.w900, 
                      letterSpacing: 1.2, 
                      color: Colors.grey
                    )
                  ),
                  const SizedBox(height: 2),
                  isLoading 
                    ? const Text("...", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                    : Text(
                        "\$$price", 
                        style: const TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.bold
                        )
                      ),
                ],
              ),
            ),
            SizedBox(
              width: 60,
              height: 30,
              child: CustomPaint(
                painter: SparklinePainter(
                  chartPoints, 
                  isUp ? Colors.green : Colors.red
                ),
              ),
            ),
            const SizedBox(width: 15),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isUp 
                    ? Colors.green.withOpacity(0.1) 
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                change,
                style: TextStyle(
                  color: isUp ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final double stepX = size.width / (points.length - 1);
    final double maxY = points.reduce((a, b) => a > b ? a : b);
    final double minY = points.reduce((a, b) => a < b ? a : b);
    final double range = (maxY - minY) == 0 ? 1 : (maxY - minY);
    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final y = size.height - ((points[i] - minY) / range * size.height);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
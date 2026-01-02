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
  // Simuler ou récupérer les données réelles
  String copperPrice = "9,450.50";
  bool isLoading = false;

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
            change: "+1.25%",
            isUp: true,
            color: Colors.orange.shade800,
            chartPoints: [10, 12, 9, 15, 14, 18, 20],
          ),
          Divider(height: 1, color: Colors.grey.withOpacity(0.1), indent: 20, endIndent: 20),
          _buildMetalRow(
            context,
            label: "COBALT (LME)",
            price: "24,290.00",
            change: "-0.45%",
            isUp: false,
            color: Colors.blue.shade900,
            chartPoints: [18, 17, 19, 16, 15, 14, 13],
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
  }) {
    return InkWell(
      // ACTION DE CLIC ACTIVÉE
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
            // Icône
            Container(
              height: 45,
              width: 45,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.analytics_rounded, color: color),
            ),
            const SizedBox(width: 15),
            
            // Textes
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text("\$$price", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            // Mini Graphique
            SizedBox(
              width: 60,
              height: 30,
              child: CustomPaint(
                painter: SparklinePainter(chartPoints, isUp ? Colors.green : Colors.red),
              ),
            ),
            
            const SizedBox(width: 15),

            // Badge %
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isUp ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
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

// Le Peintre pour la petite courbe
class SparklinePainter extends CustomPainter {
  final List<double> points;
  final Color color;
  SparklinePainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

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
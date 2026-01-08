import 'package:flutter/material.dart';

class MetalDetailPage extends StatelessWidget {
  final String metalName;
  final String price;
  final String change;
  final Color color;
  final List<double> history;

  const MetalDetailPage({
    super.key,
    required this.metalName,
    required this.price,
    required this.change,
    required this.color,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Détails $metalName"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(metalName.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, letterSpacing: 2)),
            Text("\$$price", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            Text(change, style: TextStyle(color: change.contains('+') ? Colors.green : Colors.red, fontSize: 18, fontWeight: FontWeight.w600)),
            
            const SizedBox(height: 40),
            const Text("Évolution 7 derniers jours", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            // Graphique agrandi
            Container(
              height: 200,
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              child: CustomPaint(
                painter: DetailChartPainter(history, color),
              ),
            ),
            
            const SizedBox(height: 30),
            _buildInfoRow("Bourse", "London Metal Exchange (LME)"),
            _buildInfoRow("Unité", "Tonne métrique"),
            _buildInfoRow("Dernière mise à jour", "Il y a 5 min"),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// Peintre pour le graphique détaillé
class DetailChartPainter extends CustomPainter {
  final List<double> points;
  final Color color;
  DetailChartPainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final double stepX = size.width / (points.length - 1);
    final double maxY = points.reduce((a, b) => a > b ? a : b);
    final double minY = points.reduce((a, b) => a < b ? a : b);
    
    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final y = size.height - ((points[i] - minY) / (maxY - minY) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
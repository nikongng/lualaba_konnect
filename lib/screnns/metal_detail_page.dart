import 'package:flutter/material.dart';

class MetalDetailPage extends StatelessWidget {
  final String metalName;
  final String price;
  final String change;
  final Color color;
  final List<double> history;
  final String imageUrl;
  final String summary;
  final List<String> locations;
  final List<String> identificationTips;
  final String marketName;

  const MetalDetailPage({
    super.key,
    required this.metalName,
    required this.price,
    required this.change,
    required this.color,
    required this.history,
    this.imageUrl = '',
    this.summary = '',
    this.locations = const <String>[],
    this.identificationTips = const <String>[],
    this.marketName = 'London Metal Exchange (LME)',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? Colors.white : const Color(0xFF111827);
    final sub = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final positive = change.trim().startsWith('-') ? Colors.red : Colors.green;

    return Scaffold(
      appBar: AppBar(
        title: Text('Details $metalName'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.16),
                  color.withOpacity(0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallbackAvatar(),
                        )
                      : _fallbackAvatar(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metalName.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        price,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        change,
                        style: TextStyle(
                          color: positive,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          summary,
                          style: TextStyle(
                            color: sub,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Evolution 7 derniers jours',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: text),
          ),
          const SizedBox(height: 14),
          Container(
            height: 200,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: CustomPaint(
              painter: DetailChartPainter(history, color),
            ),
          ),
          const SizedBox(height: 28),
          _buildSectionTitle('Infos marche', text),
          _buildInfoRow('Marche', marketName, sub),
          _buildInfoRow('Valeur affichee', price, sub),
          _buildInfoRow('Variation', change, sub),
          const SizedBox(height: 20),
          if (locations.isNotEmpty) ...[
            _buildSectionTitle('Zones minieres observees', text),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: locations
                  .map(
                    (location) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        location,
                        style: TextStyle(color: color, fontWeight: FontWeight.w800),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 20),
          ],
          if (identificationTips.isNotEmpty) ...[
            _buildSectionTitle('Indices d identification', text),
            const SizedBox(height: 10),
            ...identificationTips.map(
              (tip) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_rounded, size: 13, color: color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tip,
                        style: TextStyle(color: sub, height: 1.4, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      width: 92,
      height: 92,
      color: color.withOpacity(0.08),
      alignment: Alignment.center,
      child: Icon(Icons.layers_rounded, color: color, size: 36),
    );
  }

  Widget _buildSectionTitle(String label, Color text) {
    return Text(
      label,
      style: TextStyle(
        color: text,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: sub)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class DetailChartPainter extends CustomPainter {
  final List<double> points;
  final Color color;

  DetailChartPainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final stepX = size.width / (points.length - 1);
    final maxY = points.reduce((a, b) => a > b ? a : b);
    final minY = points.reduce((a, b) => a < b ? a : b);
    final range = (maxY - minY) == 0 ? 1.0 : (maxY - minY);

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

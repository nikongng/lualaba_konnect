import 'dart:math' as Math;
import 'package:flutter/material.dart';

class AccountBadges extends StatelessWidget {
  final bool isCertified;
  final String? accountType;
  final double fontSize;

  const AccountBadges({
    super.key,
    required this.isCertified,
    required this.accountType,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    if (isCertified) {
      final color = accountType == 'pro_users'
          ? const Color(0xFFFF8A00)
          : accountType == 'enterprise_users'
              ? const Color(0xFF2ECC71)
              : const Color(0xFF1877F2);
      badges.add(_VerifiedBadge(size: fontSize + 6, color: color));
    }
    // Only show verified badge for now.

    if (badges.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _withSpacing(badges, 6),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  final double size;
  final Color color;

  const _VerifiedBadge({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    final badgeSize = size.clamp(12, 20).toDouble();
    return Container(
      width: badgeSize,
      height: badgeSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(badgeSize, badgeSize),
            painter: _VerifiedStarPainter(color),
          ),
          Icon(
            Icons.check_rounded,
            size: badgeSize * 0.7,
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _VerifiedStarPainter extends CustomPainter {
  final Color color;

  _VerifiedStarPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius * 0.8;
    const points = 16;
    final step = 3.141592653589793 * 2 / points;
    for (int i = 0; i < points; i++) {
      final angle = -3.141592653589793 / 2 + (i * step);
      final radius = i.isEven ? outerRadius : innerRadius;
      final x = center.dx + radius * Math.cos(angle);
      final y = center.dy + radius * Math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PillBadge extends StatelessWidget {
  final String label;
  final double fontSize;
  final Color bgColor;

  const _PillBadge({
    required this.label,
    required this.fontSize,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
    );
  }
}

List<Widget> _withSpacing(List<Widget> items, double space) {
  if (items.isEmpty) return items;
  final out = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    if (i > 0) out.add(SizedBox(width: space));
    out.add(items[i]);
  }
  return out;
}

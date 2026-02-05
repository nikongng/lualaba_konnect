import 'package:flutter/material.dart';

class AnimatedChatBackground extends StatefulWidget {
  const AnimatedChatBackground({super.key});

  @override
  State<AnimatedChatBackground> createState() => _AnimatedChatBackgroundState();
}

class _AnimatedChatBackgroundState extends State<AnimatedChatBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  final List<List<Color>> _palettes = [
    [Color(0xFF8EC5FC), Color(0xFFE0C3FC), Color(0xFFFF9A9E)],
    [Color(0xFF84fab0), Color(0xFF8fd3f4), Color(0xFFa1c4fd)],
    [Color(0xFFf6d365), Color(0xFFfda085), Color(0xFFfbc2eb)],
    [Color(0xFFa18cd1), Color(0xFFfbc2eb), Color(0xFFfad0c4)],
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value * _palettes.length;
        final idx = t.floor() % _palettes.length;
        final next = (idx + 1) % _palettes.length;
        final frac = t - t.floor();

        Color lerpColor(Color a, Color b) => Color.lerp(a, b, frac) ?? a;

        final colors = List.generate(3, (i) => lerpColor(_palettes[idx][i], _palettes[next][i]));

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.8 + 1.6 * (_ctrl.value), -1),
              end: Alignment(0.8 - 1.6 * (_ctrl.value), 1),
              colors: colors,
            ),
          ),
          child: Stack(
            children: [
              // subtle animated circles for depth
              Positioned.fill(
                child: CustomPaint(painter: _BubblesPainter(progress: _ctrl.value)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BubblesPainter extends CustomPainter {
  final double progress;
  _BubblesPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.03);
    final r = size.shortestSide / 6;
    final positions = [
      Offset(size.width * (0.1 + 0.2 * (progress % 1)), size.height * 0.2),
      Offset(size.width * (0.6 - 0.25 * (progress % 1)), size.height * 0.35),
      Offset(size.width * (0.3 + 0.3 * (progress % 1)), size.height * 0.75),
    ];
    for (var i = 0; i < positions.length; i++) {
      canvas.drawCircle(positions[i], r * (0.6 + 0.6 * (i / positions.length)), paint);
    }

    // petits motifs en losange — spacing adaptatif
    final motifPaint = Paint()..color = Colors.white.withOpacity(0.02);
    final spacing = (size.shortestSide / 12).clamp(18.0, 48.0);
    final offsetX = (progress * spacing) % spacing;
    final offsetY = (progress * spacing * 0.6) % spacing;

    for (double y = -spacing; y < size.height + spacing; y += spacing) {
      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        final cx = x + offsetX + (y ~/ spacing % 2 == 0 ? 0 : spacing / 2);
        final cy = y + offsetY;
        final s = spacing * 0.18;
        final path = Path()
          ..moveTo(cx, cy - s)
          ..lineTo(cx + s, cy)
          ..lineTo(cx, cy + s)
          ..lineTo(cx - s, cy)
          ..close();
        canvas.drawPath(path, motifPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BubblesPainter oldDelegate) => oldDelegate.progress != progress;
}

// Overlay widget to draw motifs above content (pointer events ignored)
class MotifsOverlay extends StatelessWidget {
  final double opacity;
  final double scale;
  const MotifsOverlay({super.key, this.opacity = 0.035, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _MotifsPainter(opacity: opacity, scale: scale, progress: 0.0),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _MotifsPainter extends CustomPainter {
  final double opacity;
  final double scale;
  final double progress;
  _MotifsPainter({required this.opacity, required this.scale, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final motifPaint = Paint()..color = Colors.white.withOpacity(opacity);
    final spacing = (size.shortestSide / (12 / scale)).clamp(14.0, 64.0);
    final offsetX = (DateTime.now().millisecond / 1000.0 * spacing) % spacing;
    final offsetY = (DateTime.now().millisecond / 1000.0 * spacing * 0.6) % spacing;

    for (double y = -spacing; y < size.height + spacing; y += spacing) {
      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        final cx = x + offsetX + (y ~/ spacing % 2 == 0 ? 0 : spacing / 2);
        final cy = y + offsetY;
        final s = spacing * 0.14;
        final path = Path()
          ..moveTo(cx, cy - s)
          ..lineTo(cx + s, cy)
          ..lineTo(cx, cy + s)
          ..lineTo(cx - s, cy)
          ..close();
        canvas.drawPath(path, motifPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MotifsPainter oldDelegate) => true; // animate subtly via repaint requests
}


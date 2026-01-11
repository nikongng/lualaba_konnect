import 'package:flutter/material.dart';
import 'dart:math' as math;

class AnimatedFabColumn extends StatefulWidget {
  final VoidCallback onCameraTap;
  final VoidCallback onEditTap;

  const AnimatedFabColumn({super.key, required this.onCameraTap, required this.onEditTap});

  @override
  State<AnimatedFabColumn> createState() => _AnimatedFabColumnState();
}

class _AnimatedFabColumnState extends State<AnimatedFabColumn> {
  double _cameraScale = 1.0;
  double _cameraRotation = 0.0;
  double _editScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 96.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildFab(
            icon: Icons.edit_note_rounded,
            size: 44,
            scale: _editScale,
            gradient: const [Color(0xFF34495E), Color(0xFF1D2733)],
            onTap: widget.onEditTap,
            isCamera: false,
          ),
          const SizedBox(height: 16),
          _buildFab(
            icon: Icons.camera_enhance_rounded,
            size: 56,
            scale: _cameraScale,
            rotation: _cameraRotation,
            gradient: const [Color(0xFFFFB74D), Color(0xFFE57C00)],
            onTap: widget.onCameraTap,
            isCamera: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFab({required IconData icon, required double size, required double scale, double rotation = 0, required List<Color> gradient, required VoidCallback onTap, required bool isCamera}) {
    return GestureDetector(
      onTapDown: (_) => setState(() {
        if (isCamera) { _cameraScale = 0.85; _cameraRotation = math.pi / 8; } 
        else { _editScale = 0.85; }
      }),
      onTapUp: (_) {
        setState(() { _cameraScale = 1.0; _cameraRotation = 0.0; _editScale = 1.0; });
        onTap();
      },
          child: AnimatedRotation(
        turns: rotation,
        duration: const Duration(milliseconds: 150),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: size, height: size,
            decoration: isCamera
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.03),
                    border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.8),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 6))],
                  )
                : BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: gradient),
                    border: Border.all(color: Colors.white.withOpacity(0.12), width: 2),
                    boxShadow: [BoxShadow(color: gradient.last.withOpacity(0.28), blurRadius: 12, offset: const Offset(0, 6))],
                  ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isCamera)
                  Container(
                    width: size * 0.78,
                    height: size * 0.78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.12),
                    ),
                  ),
                Icon(icon, color: Colors.white, size: size * 0.42),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
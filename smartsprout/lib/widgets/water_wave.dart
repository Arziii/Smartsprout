import 'dart:math' as math;
import 'package:flutter/material.dart';

class WaterWave extends StatefulWidget {
  final double value; // 0 to 100
  final Color color;

  const WaterWave({super.key, required this.value, required this.color});

  @override
  State<WaterWave> createState() => _WaterWaveState();
}

class _WaterWaveState extends State<WaterWave>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _WavePainter(
            waveValue: _controller.value,
            fillLevel: widget.value / 100,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double waveValue;
  final double fillLevel;
  final Color color;

  _WavePainter({
    required this.waveValue,
    required this.fillLevel,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final path = Path();

    // Adjusted levels to make sure 0% really looks empty and 100% full
    final yBase = size.height * (1 - fillLevel);
    
    // Wave parameters
    final double waveHeight = fillLevel > 0 && fillLevel < 1 ? 4.0 : 0.0;
    const double waveFrequency = 1.5;

    path.moveTo(0, yBase);

    if (fillLevel > 0) {
      for (double x = 0; x <= size.width; x += 1) {
        final y = yBase +
            math.sin((x / size.width * waveFrequency * math.pi) +
                    (waveValue * 2 * math.pi)) *
                waveHeight;
        path.lineTo(x, y);
      }
    }

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
    
    // Optional: Draw a second, darker wave for depth
    final paintDark = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    
    final pathDark = Path();
    pathDark.moveTo(0, yBase);
    
    if (fillLevel > 0) {
      for (double x = 0; x <= size.width; x += 1) {
        final y = yBase +
            math.cos((x / size.width * waveFrequency * math.pi) +
                    (waveValue * 2 * math.pi)) *
                waveHeight;
        pathDark.lineTo(x, y);
      }
    }
    
    pathDark.lineTo(size.width, size.height);
    pathDark.lineTo(0, size.height);
    pathDark.close();
    
    canvas.drawPath(pathDark, paintDark);
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.waveValue != waveValue ||
      oldDelegate.fillLevel != fillLevel ||
      oldDelegate.color != color;
}

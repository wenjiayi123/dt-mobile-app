import 'dart:math' as math;

import 'package:flutter/material.dart';

class PortTwinBackdrop extends StatefulWidget {
  const PortTwinBackdrop({super.key});

  @override
  State<PortTwinBackdrop> createState() => _PortTwinBackdropState();
}

class _PortTwinBackdropState extends State<PortTwinBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7600),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0.34;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => CustomPaint(
            painter: _PortTwinBackdropPainter(progress: _controller.value),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _PortTwinBackdropPainter extends CustomPainter {
  const _PortTwinBackdropPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF07152C), Color(0xFF050E1E), Color(0xFF020711)],
          stops: [0, 0.46, 1],
        ).createShader(rect),
    );

    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.12),
      size.width * 0.72,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFF1769E0).withValues(alpha: 0.16),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(size.width * 0.12, size.height * 0.12),
                radius: size.width * 0.72,
              ),
            ),
    );
    canvas.drawCircle(
      Offset(size.width * 0.94, size.height * 0.56),
      size.width * 0.58,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFF13B89A).withValues(alpha: 0.10),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(size.width * 0.94, size.height * 0.56),
                radius: size.width * 0.58,
              ),
            ),
    );

    final horizon = size.height * 0.58;
    final vanish = Offset(size.width * 0.5, horizon);
    final gridPaint = Paint()
      ..color = const Color(0xFF4DE4FF).withValues(alpha: 0.055)
      ..strokeWidth = 0.65;
    for (var index = 0; index <= 12; index++) {
      canvas.drawLine(
        vanish,
        Offset(size.width * index / 12, size.height),
        gridPaint,
      );
    }
    for (var index = 0; index < 12; index++) {
      final t = index / 11;
      final y = horizon + math.pow(t, 1.8) * (size.height - horizon);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final scanY = (progress * (size.height + 140)) - 70;
    canvas.drawRect(
      Rect.fromLTWH(0, scanY - 36, size.width, 72),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF4DE4FF).withValues(alpha: 0.025),
            const Color(0xFF4DE4FF).withValues(alpha: 0.09),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, scanY - 36, size.width, 72)),
    );

    final nodePaint = Paint()..color = const Color(0xFF76F7C5);
    for (var index = 0; index < 7; index++) {
      final phase = (progress + index * 0.137) % 1;
      final x = size.width * (0.08 + (index * 0.151) % 0.84);
      final y = size.height * (0.16 + phase * 0.72);
      final opacity = math.sin(phase * math.pi).clamp(0.0, 1.0);
      nodePaint.color = const Color(
        0xFF76F7C5,
      ).withValues(alpha: opacity * 0.34);
      canvas.drawCircle(Offset(x, y), 1.6, nodePaint);
      canvas.drawCircle(
        Offset(x, y),
        6 + 4 * opacity,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = const Color(0xFF4DE4FF).withValues(alpha: opacity * 0.12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PortTwinBackdropPainter oldDelegate) {
    return progress != oldDelegate.progress;
  }
}

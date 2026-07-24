import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum IntelligentActionTone { reinforcement, twin, xiaoyi }

class IntelligentActionButton extends StatefulWidget {
  const IntelligentActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.eyebrow,
    this.tone = IntelligentActionTone.reinforcement,
    this.busyLabel = '智能处理中',
    this.compact = false,
  });

  final String label;
  final String? eyebrow;
  final IconData icon;
  final FutureOr<void> Function()? onPressed;
  final IntelligentActionTone tone;
  final String busyLabel;
  final bool compact;

  @override
  State<IntelligentActionButton> createState() =>
      _IntelligentActionButtonState();
}

class _IntelligentActionButtonState extends State<IntelligentActionButton>
    with TickerProviderStateMixin {
  late final AnimationController _ambientController;
  late final AnimationController _impactController;
  bool _pressed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _impactController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _ambientController.stop();
      _ambientController.value = 0.35;
    } else if (!_ambientController.isAnimating) {
      _ambientController.repeat();
    }
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _impactController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    HapticFeedback.mediumImpact();
    _impactController.forward(from: 0);
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(widget.tone);
    final enabled = widget.onPressed != null && !_busy;
    final visuallyActive = widget.onPressed != null || _busy;
    final height = widget.compact ? 52.0 : 62.0;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedBuilder(
        animation: Listenable.merge([_ambientController, _impactController]),
        builder: (context, child) {
          final ambient = _ambientController.value;
          final pulse = math.sin(ambient * math.pi * 2) * 0.5 + 0.5;
          return AnimatedScale(
            scale: _pressed ? 0.975 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: GestureDetector(
              onTapDown: enabled
                  ? (_) => setState(() => _pressed = true)
                  : null,
              onTapCancel: enabled
                  ? () => setState(() => _pressed = false)
                  : null,
              onTapUp: enabled
                  ? (_) {
                      setState(() => _pressed = false);
                      _run();
                    }
                  : null,
              child: SizedBox(
                height: height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: visuallyActive
                                ? [colors.$1, colors.$2, colors.$3]
                                : const [
                                    Color(0xFF4A5568),
                                    Color(0xFF334155),
                                    Color(0xFF1E293B),
                                  ],
                          ),
                          border: Border.all(
                            color: colors.$4.withValues(
                              alpha: visuallyActive
                                  ? 0.58 + pulse * 0.24
                                  : 0.18,
                            ),
                          ),
                          boxShadow: visuallyActive
                              ? [
                                  BoxShadow(
                                    color: colors.$4.withValues(
                                      alpha: 0.20 + pulse * 0.15,
                                    ),
                                    blurRadius: 18 + pulse * 12,
                                    spreadRadius: -3,
                                    offset: const Offset(0, 8),
                                  ),
                                  BoxShadow(
                                    color: colors.$5.withValues(alpha: 0.12),
                                    blurRadius: 28,
                                    spreadRadius: -8,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: CustomPaint(
                          painter: _IntelligentButtonPainter(
                            progress: ambient,
                            impact: _impactController.value,
                            accent: colors.$4,
                            secondary: colors.$5,
                            enabled: visuallyActive,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.compact ? 14 : 16,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: widget.compact ? 34 : 40,
                            height: widget.compact ? 34 : 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.13),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: _busy
                                ? const Padding(
                                    padding: EdgeInsets.all(9),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    widget.icon,
                                    color: Colors.white,
                                    size: 21,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.eyebrow != null && !widget.compact)
                                  Text(
                                    widget.eyebrow!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFB8EFFF),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.05,
                                    ),
                                  ),
                                Text(
                                  _busy ? widget.busyLabel : widget.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: widget.compact ? 14 : 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            _busy
                                ? Icons.auto_awesome_rounded
                                : Icons.arrow_forward_rounded,
                            color: Colors.white.withValues(alpha: 0.9),
                            size: 19,
                          ),
                        ],
                      ),
                    ),
                    if (_busy)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 2,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                            valueColor: AlwaysStoppedAnimation(colors.$4),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

(Color, Color, Color, Color, Color) _toneColors(IntelligentActionTone tone) {
  switch (tone) {
    case IntelligentActionTone.reinforcement:
      return (
        const Color(0xFF2854C7),
        const Color(0xFF1769E0),
        const Color(0xFF063C80),
        const Color(0xFF60A5FA),
        const Color(0xFF22D3EE),
      );
    case IntelligentActionTone.twin:
      return (
        const Color(0xFF087A88),
        const Color(0xFF0A64A4),
        const Color(0xFF073A66),
        const Color(0xFF4DE4FF),
        const Color(0xFF76F7C5),
      );
    case IntelligentActionTone.xiaoyi:
      return (
        const Color(0xFF176F69),
        const Color(0xFF3157B8),
        const Color(0xFF55308F),
        const Color(0xFF76F7C5),
        const Color(0xFF7DD3FC),
      );
  }
}

class _IntelligentButtonPainter extends CustomPainter {
  const _IntelligentButtonPainter({
    required this.progress,
    required this.impact,
    required this.accent,
    required this.secondary,
    required this.enabled,
  });

  final double progress;
  final double impact;
  final Color accent;
  final Color secondary;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled) return;

    final sweepX = (progress * (size.width + 90)) - 45;
    final sweepPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.24),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(sweepX - 36, 0, 72, size.height));
    final sweepPath = Path()
      ..moveTo(sweepX - 28, size.height)
      ..lineTo(sweepX + 5, 0)
      ..lineTo(sweepX + 45, 0)
      ..lineTo(sweepX + 12, size.height)
      ..close();
    canvas.drawPath(sweepPath, sweepPaint);

    final linePaint = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(18, size.height - 1.5),
      Offset(size.width * (0.45 + 0.45 * progress), size.height - 1.5),
      linePaint,
    );

    if (impact > 0 && impact < 1) {
      final eased = Curves.easeOutCubic.transform(impact);
      final center = Offset(size.width * 0.22, size.height / 2);
      for (var index = 0; index < 3; index++) {
        final shifted = (eased - index * 0.11).clamp(0.0, 1.0);
        if (shifted <= 0) continue;
        canvas.drawCircle(
          center,
          18 + shifted * (58 + index * 13),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = (index.isEven ? accent : secondary).withValues(
              alpha: (1 - shifted) * 0.58,
            ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IntelligentButtonPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        impact != oldDelegate.impact ||
        enabled != oldDelegate.enabled ||
        accent != oldDelegate.accent ||
        secondary != oldDelegate.secondary;
  }
}

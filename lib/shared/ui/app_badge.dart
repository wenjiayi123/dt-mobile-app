import 'package:flutter/material.dart';

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.neutral,
    this.leading,
    this.compact = false,
  });

  final String label;
  final AppBadgeTone tone;
  final IconData? leading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final _BadgePalette palette = _paletteFor(tone);
    final double horizontal = compact ? 8 : 10;
    final double vertical = compact ? 4 : 6;
    final TextStyle style =
        Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: palette.foreground,
          height: 1.0,
        ) ??
        TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: palette.foreground,
          height: 1.0,
        );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(compact ? 999 : 12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            Icon(leading, size: compact ? 12 : 14, color: palette.foreground),
            const SizedBox(width: 6),
          ],
          Text(label, style: style),
        ],
      ),
    );
  }
}

class AppDotBadge extends StatelessWidget {
  const AppDotBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.neutral,
    this.compact = false,
  });

  final String label;
  final AppBadgeTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final _BadgePalette palette = _paletteFor(tone);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(compact ? 999 : 12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 6 : 8,
            height: compact ? 6 : 8,
            decoration: BoxDecoration(
              color: palette.foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style:
                Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.foreground,
                ) ??
                TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                  color: palette.foreground,
                ),
          ),
        ],
      ),
    );
  }
}

class AppCountBadge extends StatelessWidget {
  const AppCountBadge({
    super.key,
    required this.count,
    this.tone = AppBadgeTone.critical,
    this.minWidth = 20,
  });

  final int count;
  final AppBadgeTone tone;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final _BadgePalette palette = _paletteFor(tone);
    final String text = count > 99 ? '99+' : '$count';

    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.foreground,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style:
            Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ) ??
            const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
      ),
    );
  }
}

class AppBadgeWrap extends StatelessWidget {
  const AppBadgeWrap({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 8,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: spacing, runSpacing: runSpacing, children: children);
  }
}

enum AppBadgeTone { neutral, info, success, watch, critical }

class _BadgePalette {
  const _BadgePalette({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

_BadgePalette _paletteFor(AppBadgeTone tone) {
  switch (tone) {
    case AppBadgeTone.info:
      return const _BadgePalette(
        background: Color(0x332563EB),
        foreground: Color(0xFF7DD3FC),
        border: Color(0x664DE4FF),
      );
    case AppBadgeTone.success:
      return const _BadgePalette(
        background: Color(0x2676F7C5),
        foreground: Color(0xFF76F7C5),
        border: Color(0x5576F7C5),
      );
    case AppBadgeTone.watch:
      return const _BadgePalette(
        background: Color(0x33FFB45C),
        foreground: Color(0xFFFFC978),
        border: Color(0x66FFB45C),
      );
    case AppBadgeTone.critical:
      return const _BadgePalette(
        background: Color(0x33FF5D67),
        foreground: Color(0xFFFF8F9B),
        border: Color(0x66FF7889),
      );
    case AppBadgeTone.neutral:
      return const _BadgePalette(
        background: Color(0xCC172B49),
        foreground: Color(0xFFC0D1E8),
        border: Color(0xFF365477),
      );
  }
}

import 'package:flutter/material.dart';

import 'app_badge.dart';

/// 标签语义，和 badge 保持一致，便于全局统一状态表达。
enum AppTagTone { neutral, info, success, watch, critical }

class AppTag extends StatelessWidget {
  const AppTag({
    super.key,
    required this.label,
    this.tone = AppTagTone.neutral,
    this.compact = false,
    this.onTap,
    this.leadingIcon,
  });

  final String label;
  final AppTagTone tone;
  final bool compact;
  final VoidCallback? onTap;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final child = AppBadge(
      label: label,
      tone: _mapTone(tone),
      compact: compact,
      leading: leadingIcon,
    );

    if (onTap == null) {
      return child;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 999 : 12),
        child: child,
      ),
    );
  }

  AppBadgeTone _mapTone(AppTagTone tone) {
    switch (tone) {
      case AppTagTone.info:
        return AppBadgeTone.info;
      case AppTagTone.success:
        return AppBadgeTone.success;
      case AppTagTone.watch:
        return AppBadgeTone.watch;
      case AppTagTone.critical:
        return AppBadgeTone.critical;
      case AppTagTone.neutral:
        return AppBadgeTone.neutral;
    }
  }
}

class AppTagGroup extends StatelessWidget {
  const AppTagGroup({
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

class AppFilterTag extends StatelessWidget {
  const AppFilterTag({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final Color foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final Color border = selected
        ? scheme.primary.withValues(alpha: 0.22)
        : scheme.outlineVariant;

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (onTap == null) {
      return child;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: child,
      ),
    );
  }
}

class AppHintTag extends StatelessWidget {
  const AppHintTag({super.key, required this.label, this.leadingIcon});

  final String label;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

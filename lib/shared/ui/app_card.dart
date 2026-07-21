import 'package:flutter/material.dart';

/// Day 27：UX 打磨 v1 的 shared/ui 基础组件。
///
/// 这一步先不碰页面逻辑，先把通用表达沉到 shared/ui：
/// 1) AppCard：统一卡片壳
/// 2) AppSectionCard：统一标题区块
/// 3) AppSeverityTag：统一 severity 表达（icon + label，克制配色）
/// 4) AppRangeRow：统一区间表达（low ~ high + 轻量进度条）
/// 5) AppKpiTile：统一 KPI 小卡片
/// 6) AppLoadingCard / AppErrorCard / AppErrorView：保留已有错误兜底
///
/// 目标：后续 Situation / Strategy / Alerts / Home 都能复用，
/// 先保可跑，再逐页替换旧的零散样式。

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xEE0D203D), Color(0xEE08162C), Color(0xEE071225)],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: -8,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 20,
            right: 20,
            top: 0,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    scheme.primary.withValues(alpha: 0.72),
                    scheme.secondary.withValues(alpha: 0.52),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );

    if (margin == null) return card;
    return Padding(padding: margin!, child: card);
  }
}

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    this.margin,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      margin: margin,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: subtitle == null
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

enum AppSeverityLevel { neutral, info, watch, critical, success }

class AppSeverityTag extends StatelessWidget {
  const AppSeverityTag({
    super.key,
    required this.label,
    this.level = AppSeverityLevel.neutral,
    this.icon,
    this.compact = false,
  });

  final String label;
  final AppSeverityLevel level;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedColor = _colorFor(scheme, level);
    final resolvedIcon = icon ?? _iconFor(level);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: resolvedColor.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(resolvedIcon, size: compact ? 14 : 15, color: resolvedColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: resolvedColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(AppSeverityLevel level) {
    switch (level) {
      case AppSeverityLevel.neutral:
        return Icons.label_outline;
      case AppSeverityLevel.info:
        return Icons.info_outline;
      case AppSeverityLevel.watch:
        return Icons.warning_amber_rounded;
      case AppSeverityLevel.critical:
        return Icons.error_outline;
      case AppSeverityLevel.success:
        return Icons.task_alt;
    }
  }

  static Color _colorFor(ColorScheme scheme, AppSeverityLevel level) {
    switch (level) {
      case AppSeverityLevel.neutral:
        return scheme.onSurfaceVariant;
      case AppSeverityLevel.info:
        return scheme.primary;
      case AppSeverityLevel.watch:
        return const Color(0xFFFFB45C);
      case AppSeverityLevel.critical:
        return const Color(0xFFFF7889);
      case AppSeverityLevel.success:
        return const Color(0xFF76F7C5);
    }
  }
}

class AppRangeRow extends StatelessWidget {
  const AppRangeRow({
    super.key,
    required this.label,
    required this.low,
    required this.high,
    this.unit = '%',
    this.trailing,
    this.note,
    this.emphasize = false,
  });

  final String label;
  final num low;
  final num high;
  final String unit;
  final Widget? trailing;
  final String? note;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final widthFactor = (high.toDouble() / 100).clamp(0.0, 1.0);
    final isPointValue = low.toDouble() == high.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Text(
                    isPointValue
                        ? '${_formatValue(low)}$unit'
                        : '${_formatValue(low)}$unit ~ ${_formatValue(high)}$unit',
                    style:
                        (emphasize
                                ? theme.textTheme.headlineSmall
                                : theme.textTheme.titleLarge)
                            ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: widthFactor,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        if (note != null && note!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            note!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  static String _formatValue(num value) {
    if (value % 1 == 0) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }
}

class AppKpiTile extends StatelessWidget {
  const AppKpiTile({
    super.key,
    required this.title,
    required this.value,
    required this.supporting,
    required this.icon,
    this.leadingTag,
  });

  final String title;
  final String value;
  final String supporting;
  final IconData icon;
  final Widget? leadingTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              if (leadingTag != null) ...[
                const SizedBox(width: 8),
                leadingTag!,
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(title, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            supporting,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class AppLoadingCard extends StatelessWidget {
  const AppLoadingCard({
    super.key,
    this.title = '加载中',
    this.subtitle = '正在拉取最新状态…',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: title,
      subtitle: subtitle,
      leading: const Icon(Icons.cloud_sync_outlined),
      child: const LinearProgressIndicator(),
    );
  }
}

class AppErrorCard extends StatelessWidget {
  const AppErrorCard({
    super.key,
    required this.error,
    this.onRetry,
    this.title = '加载失败',
    this.message,
    this.retryLabel = '重试',
    this.compact = false,
    this.showDetails = true,
    this.leadingIcon = Icons.error_outline,
  });

  final Object error;
  final VoidCallback? onRetry;
  final String title;
  final String? message;
  final String retryLabel;
  final bool compact;
  final bool showDetails;
  final IconData leadingIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detailText = _normalizeErrorText(error);

    return AppCard(
      child: compact
          ? _CompactErrorBody(
              title: title,
              message: message,
              detailText: detailText,
              showDetails: showDetails,
              onRetry: onRetry,
              retryLabel: retryLabel,
              leadingIcon: leadingIcon,
              scheme: scheme,
            )
          : _RegularErrorBody(
              title: title,
              message: message,
              detailText: detailText,
              showDetails: showDetails,
              onRetry: onRetry,
              retryLabel: retryLabel,
              leadingIcon: leadingIcon,
              scheme: scheme,
            ),
    );
  }
}

class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.title = '当前页面暂不可用',
    this.message = '数据获取失败，但你可以直接重试，不需要退出页面。',
    this.retryLabel = '重新加载',
    this.showDetails = true,
    this.maxWidth = 560,
  });

  final Object error;
  final VoidCallback? onRetry;
  final String title;
  final String message;
  final String retryLabel;
  final bool showDetails;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detailText = _normalizeErrorText(error);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.errorContainer,
                  child: Icon(Icons.cloud_off, color: scheme.onErrorContainer),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (showDetails) ...[
                  const SizedBox(height: 12),
                  _ErrorDetailBox(text: detailText, centered: true),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(retryLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RegularErrorBody extends StatelessWidget {
  const _RegularErrorBody({
    required this.title,
    required this.message,
    required this.detailText,
    required this.showDetails,
    required this.onRetry,
    required this.retryLabel,
    required this.leadingIcon,
    required this.scheme,
  });

  final String title;
  final String? message;
  final String detailText;
  final bool showDetails;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData leadingIcon;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: scheme.errorContainer,
          child: Icon(leadingIcon, size: 20, color: scheme.onErrorContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (showDetails) ...[
                const SizedBox(height: 10),
                _ErrorDetailBox(text: detailText),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactErrorBody extends StatelessWidget {
  const _CompactErrorBody({
    required this.title,
    required this.message,
    required this.detailText,
    required this.showDetails,
    required this.onRetry,
    required this.retryLabel,
    required this.leadingIcon,
    required this.scheme,
  });

  final String title;
  final String? message;
  final String detailText;
  final bool showDetails;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData leadingIcon;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(leadingIcon, color: scheme.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(retryLabel),
            ),
          ],
        ),
        if (message != null && message!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            message!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (showDetails) ...[
          const SizedBox(height: 8),
          _ErrorDetailBox(text: detailText),
        ],
      ],
    );
  }
}

class _ErrorDetailBox extends StatelessWidget {
  const _ErrorDetailBox({required this.text, this.centered = false});

  final String text;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

String _normalizeErrorText(Object error) {
  final raw = error.toString().trim();
  if (raw.isEmpty) return '未知错误';

  var text = raw;
  const prefixes = <String>[
    'Exception: ',
    'Bad state: ',
    'DioException: ',
    'DioException [',
  ];

  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length).trim();
      break;
    }
  }

  if (text.length > 220) {
    return '${text.substring(0, 220)}...';
  }

  return text;
}

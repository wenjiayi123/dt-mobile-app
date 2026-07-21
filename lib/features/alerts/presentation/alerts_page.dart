import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/application/home_tab_notifier.dart';
import '../../demo/application/demo_flow_controller.dart';
import '../../strategy/application/strategy_controller.dart';
import '../application/alerts_controller.dart';

class AlertsPage extends ConsumerWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(alertsSnapshotProvider);
    final replanState = ref.watch(quickReplanProvider);
    final strategyState = ref.watch(strategyControllerProvider);
    final demoFlow = ref.watch(demoFlowProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('告警管理')),
      body: snapshotAsync.when(
        loading: () => const _StateScaffold(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => _StateScaffold(
          child: _ErrorCard(
            message: '当前连接不可用，请稍后重试。',
            onRetry: () =>
                ref.read(alertsSnapshotProvider.notifier).refreshNow(),
          ),
        ),
        data: (snapshot) {
          final items = snapshot.items;
          final topPriority = items.isEmpty ? null : items.first;
          final recommendedTitle = strategyState.recommendedCandidate.title;

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(alertsSnapshotProvider.notifier).refreshNow(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _OverviewCard(snapshot: snapshot),
                const SizedBox(height: 12),
                if (demoFlow.enabled) ...[
                  _AlertsDemoBanner(
                    flow: demoFlow,
                    onPrimary: () {
                      switch (demoFlow.stage) {
                        case DemoFlowStage.ready:
                          ref.read(demoFlowProvider.notifier).start();
                          ref.read(homeTabProvider.notifier).selectIndex(0);
                          break;
                        case DemoFlowStage.stable:
                        case DemoFlowStage.boundary:
                          ref.read(homeTabProvider.notifier).selectIndex(0);
                          break;
                        case DemoFlowStage.alert:
                          ref.read(demoFlowProvider.notifier).advance();
                          ref.read(homeTabProvider.notifier).selectIndex(1);
                          break;
                        case DemoFlowStage.strategy:
                        case DemoFlowStage.executing:
                          ref.read(homeTabProvider.notifier).selectIndex(1);
                          break;
                        case DemoFlowStage.audit:
                          ref.read(homeTabProvider.notifier).selectIndex(3);
                          break;
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (topPriority != null) ...[
                  _PrimaryActionCard(
                    item: topPriority,
                    recommendedTitle: recommendedTitle,
                    linkedStrategies: _resolveLinkedStrategies(
                      strategyState.candidates,
                      topPriority,
                    ),
                    replanState: replanState,
                    onAcknowledge: () => ref
                        .read(alertsSnapshotProvider.notifier)
                        .acknowledgeAlert(topPriority.id),
                    onQuickReplan: () => ref
                        .read(quickReplanProvider.notifier)
                        .triggerQuickReplan(sourceAlertId: topPriority.id),
                    onOpenStrategy: () =>
                        ref.read(homeTabProvider.notifier).selectIndex(1),
                    onContinueToStrategy: () {
                      if (demoFlow.stage == DemoFlowStage.alert) {
                        ref.read(demoFlowProvider.notifier).advance();
                      } else {
                        ref
                            .read(demoFlowProvider.notifier)
                            .setStage(DemoFlowStage.strategy);
                      }
                      ref.read(homeTabProvider.notifier).selectIndex(1);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                const _SectionTitle(title: '告警列表'),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const _EmptyListCard()
                else
                  ...items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _AlertListTile(
                        item: item,
                        linkedStrategies: _resolveLinkedStrategies(
                          strategyState.candidates,
                          item,
                        ),
                        highlight:
                            identical(item, topPriority) ||
                            item.id == topPriority?.id,
                        onAcknowledge: item.isAcknowledged
                            ? null
                            : () => ref
                                  .read(alertsSnapshotProvider.notifier)
                                  .acknowledgeAlert(item.id),
                        onQuickReplan: () => ref
                            .read(quickReplanProvider.notifier)
                            .triggerQuickReplan(sourceAlertId: item.id),
                        onOpenStrategy: () =>
                            ref.read(homeTabProvider.notifier).selectIndex(1),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AlertsDemoBanner extends StatelessWidget {
  const _AlertsDemoBanner({required this.flow, required this.onPrimary});

  final DemoFlowState flow;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final buttonLabel = switch (flow.stage) {
      DemoFlowStage.ready => '开始界面讲解',
      DemoFlowStage.stable => '返回态势 · 核对数据标签',
      DemoFlowStage.boundary => '继续讲解告警来源',
      DemoFlowStage.alert => '进入策略 · 查看真实训练',
      DemoFlowStage.strategy => '进入策略 · 查看测试产物',
      DemoFlowStage.executing => '进入策略 · 查看生产门禁',
      DemoFlowStage.audit => '进入审计 · 核对证据',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B1D34), Color(0xFF372A55), Color(0xFF123B57)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF7889).withValues(alpha: 0.50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_outlined, color: Color(0xFFFFB45C)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '界面讲解 · ${flow.stage.timeLabel} · 不生成告警',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(flow.stage.narrative),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPrimary,
              icon: const Icon(Icons.psychology_alt_rounded),
              label: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateScaffold extends StatelessWidget {
  const _StateScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [child]);
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('告警连接不可用', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.snapshot});

  final AlertsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('告警概览', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              _headline(snapshot),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TagChip(label: _connectionLabel(snapshot.connectionStatus)),
                _TagChip(label: _feedModeLabel(snapshot.feedMode)),
                _TagChip(label: '待处理 ${snapshot.unreadCount}'),
                if (snapshot.items.isNotEmpty)
                  _TagChip(label: '最新 ${snapshot.items.first.source}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _headline(AlertsSnapshot snapshot) {
    if (snapshot.items.isEmpty) return '当前没有活动告警。';
    final criticalCount = snapshot.items
        .where((e) => e.severity == AlertSeverity.critical)
        .length;
    final warnCount = snapshot.items
        .where((e) => e.severity == AlertSeverity.warn)
        .length;

    if (criticalCount > 0) {
      return '存在 $criticalCount 条高优先级告警，建议优先处置。';
    }
    if (warnCount > 0) {
      return '存在 $warnCount 条关注告警，建议保持监测。';
    }
    return '当前以信息事件为主，系统保持运行。';
  }
}

class _PrimaryActionCard extends StatelessWidget {
  const _PrimaryActionCard({
    required this.item,
    required this.recommendedTitle,
    required this.linkedStrategies,
    required this.replanState,
    required this.onAcknowledge,
    required this.onQuickReplan,
    required this.onOpenStrategy,
    required this.onContinueToStrategy,
  });

  final AlertItem item;
  final String recommendedTitle;
  final List<StrategyCandidate> linkedStrategies;
  final ReplanTriggerState replanState;
  final VoidCallback onAcknowledge;
  final VoidCallback onQuickReplan;
  final VoidCallback onOpenStrategy;
  final VoidCallback onContinueToStrategy;

  @override
  Widget build(BuildContext context) {
    final isSubmitting = replanState.status == ReplanTriggerStatus.submitting;
    final toneColor = _severityColor(context, item.severity);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: toneColor.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SeverityPill(severity: item.severity),
                const SizedBox(width: 8),
                _TagChip(label: '当前最高优先级'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              item.title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(item.detail),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.alt_route_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '建议策略：$recommendedTitle',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onOpenStrategy,
                  icon: const Icon(Icons.alt_route_outlined),
                  label: Text(linkedStrategies.isEmpty ? '进入策略处理' : '查看相关策略'),
                ),
                FilledButton.tonalIcon(
                  onPressed: isSubmitting ? null : onQuickReplan,
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt_outlined),
                  label: Text(isSubmitting ? '提交中…' : '发起重规划'),
                ),
                OutlinedButton.icon(
                  onPressed: item.isAcknowledged ? null : onAcknowledge,
                  icon: const Icon(Icons.done_all_outlined),
                  label: Text(item.isAcknowledged ? '已确认' : '确认处理'),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(sizeFactor: animation, child: child),
              ),
              child: replanState.status == ReplanTriggerStatus.idle
                  ? const SizedBox.shrink(key: ValueKey('replan-idle'))
                  : Padding(
                      key: ValueKey(replanState.status),
                      padding: const EdgeInsets.only(top: 12),
                      child: _ReplanFeedbackPanel(
                        state: replanState,
                        onContinueToStrategy: onContinueToStrategy,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplanFeedbackPanel extends StatelessWidget {
  const _ReplanFeedbackPanel({
    required this.state,
    required this.onContinueToStrategy,
  });

  final ReplanTriggerState state;
  final VoidCallback onContinueToStrategy;

  @override
  Widget build(BuildContext context) {
    final submitting = state.status == ReplanTriggerStatus.submitting;
    final success = state.status == ReplanTriggerStatus.success;
    final color = success
        ? const Color(0xFF32C995)
        : state.status == ReplanTriggerStatus.failure
        ? const Color(0xFFFF6F91)
        : const Color(0xFF1769E0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 20,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (submitting)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: color,
                  ),
                )
              else
                Icon(
                  success
                      ? Icons.task_alt_rounded
                      : Icons.error_outline_rounded,
                  color: color,
                  size: 20,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  submitting ? '正在向后端登记重规划审阅申请' : state.message ?? '重规划状态已更新',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                submitting
                    ? '读取中'
                    : success
                    ? '已写入审计'
                    : '需要检查',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            submitting
                ? '后端将校验当前数据哈希是否存在已完成的留出测试产物；客户端不会本地生成候选。'
                : success
                ? '审阅申请已绑定真实测试候选并写入审计；请在策略页人工核对。'
                : '本次申请未登记，请检查连接和测试产物后重试。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 8),
          if (submitting)
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 5,
                backgroundColor: color.withValues(alpha: 0.12),
                color: color,
              ),
            )
          else if (success)
            Column(
              children: [
                Row(
                  children: [
                    for (final label in const [
                      '告警已关联',
                      '策略队列已接单',
                      '人工确认保留',
                    ]) ...[
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '✓ $label',
                            style: TextStyle(
                              color: color,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      if (label != '人工确认保留') const SizedBox(width: 5),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onContinueToStrategy,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('进入策略页审阅测试候选'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AlertListTile extends StatelessWidget {
  const _AlertListTile({
    required this.item,
    required this.linkedStrategies,
    required this.highlight,
    required this.onQuickReplan,
    required this.onOpenStrategy,
    this.onAcknowledge,
  });

  final AlertItem item;
  final List<StrategyCandidate> linkedStrategies;
  final bool highlight;
  final VoidCallback onQuickReplan;
  final VoidCallback onOpenStrategy;
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final toneColor = _severityColor(context, item.severity);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlight
              ? toneColor.withValues(alpha: 0.4)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_severityIcon(item.severity), color: toneColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (highlight)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: _TagChip(label: '当前焦点'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SeverityPill(severity: item.severity),
                _TagChip(label: item.source),
                _TagChip(label: _formatTime(item.createdAt)),
                _TagChip(label: item.isAcknowledged ? '已确认' : '待处理'),
                if (linkedStrategies.isNotEmpty)
                  _TagChip(label: '关联策略 ${linkedStrategies.length}'),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onAcknowledge,
                  icon: const Icon(Icons.task_alt_outlined),
                  label: Text(item.isAcknowledged ? '已确认' : '确认处理'),
                ),
                TextButton.icon(
                  onPressed: onOpenStrategy,
                  icon: const Icon(Icons.alt_route_outlined),
                  label: Text(linkedStrategies.isEmpty ? '进入策略处理' : '查看相关策略'),
                ),
                TextButton.icon(
                  onPressed: onQuickReplan,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('发起重规划'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyListCard extends StatelessWidget {
  const _EmptyListCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: Theme.of(context).colorScheme.primary,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text('当前没有活动告警', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _SeverityPill extends StatelessWidget {
  const _SeverityPill({required this.severity});

  final AlertSeverity severity;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(context, severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_severityIcon(severity), size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            _severityLabel(severity),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

List<StrategyCandidate> _resolveLinkedStrategies(
  List<StrategyCandidate> candidates,
  AlertItem item,
) {
  final normalizedAlertTitle = _normalizeLookup(item.title);
  final normalizedAlertSource = _normalizeLookup(item.source);

  final matched = candidates.where((candidate) {
    return candidate.relatedAlerts.any((link) {
      final normalizedLinkTitle = _normalizeLookup(link.title);
      final normalizedLinkSummary = _normalizeLookup(link.summary);
      final normalizedLinkAction = _normalizeLookup(link.recommendedAction);
      final titleMatches =
          normalizedLinkTitle.isNotEmpty &&
          (normalizedAlertTitle.contains(normalizedLinkTitle) ||
              normalizedLinkTitle.contains(normalizedAlertTitle));
      final summaryMatches =
          normalizedLinkSummary.isNotEmpty &&
          (normalizedAlertTitle.contains(normalizedLinkSummary) ||
              normalizedLinkSummary.contains(normalizedAlertTitle));
      final sourceMatches =
          normalizedAlertSource.isNotEmpty &&
          ((normalizedLinkSummary.isNotEmpty &&
                  (normalizedAlertSource.contains(normalizedLinkSummary) ||
                      normalizedLinkSummary.contains(normalizedAlertSource))) ||
              (normalizedLinkAction.isNotEmpty &&
                  (normalizedAlertSource.contains(normalizedLinkAction) ||
                      normalizedLinkAction.contains(normalizedAlertSource))));
      return titleMatches || summaryMatches || sourceMatches;
    });
  }).toList();

  matched.sort((a, b) => a.title.compareTo(b.title));
  return matched;
}

String _normalizeLookup(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final isAsciiLetter = rune >= 97 && rune <= 122;
    final isDigit = rune >= 48 && rune <= 57;
    final isCjk = rune >= 0x4E00 && rune <= 0x9FFF;
    if (isAsciiLetter || isDigit || isCjk) {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

String _severityLabel(AlertSeverity severity) {
  switch (severity) {
    case AlertSeverity.info:
      return '信息';
    case AlertSeverity.warn:
      return '关注';
    case AlertSeverity.critical:
      return '高优先级';
  }
}

IconData _severityIcon(AlertSeverity severity) {
  switch (severity) {
    case AlertSeverity.info:
      return Icons.info_outline;
    case AlertSeverity.warn:
      return Icons.warning_amber_outlined;
    case AlertSeverity.critical:
      return Icons.error_outline;
  }
}

Color _severityColor(BuildContext context, AlertSeverity severity) {
  switch (severity) {
    case AlertSeverity.info:
      return Theme.of(context).colorScheme.primary;
    case AlertSeverity.warn:
      return const Color(0xFFFFB45C);
    case AlertSeverity.critical:
      return Theme.of(context).colorScheme.error;
  }
}

String _connectionLabel(AlertsConnectionStatus status) {
  switch (status) {
    case AlertsConnectionStatus.connecting:
      return '连接中';
    case AlertsConnectionStatus.connected:
      return '在线';
    case AlertsConnectionStatus.disconnected:
      return '已断开';
  }
}

String _feedModeLabel(AlertsFeedMode mode) {
  switch (mode) {
    case AlertsFeedMode.websocket:
      return '实时链路';
    case AlertsFeedMode.offline:
      return '离线（不生成本地告警）';
  }
}

String _formatTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

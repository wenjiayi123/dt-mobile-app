// lib/features/notifications/presentation/notification_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/features/home/application/home_tab_notifier.dart';
import 'package:dt_mobile_app/features/notifications/application/notification_controller.dart';
import 'package:dt_mobile_app/shared/ui/app_card.dart';

class NotificationPage extends ConsumerStatefulWidget {
  const NotificationPage({super.key});

  @override
  ConsumerState<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends ConsumerState<NotificationPage> {
  String? _focusedNotificationId;

  void _markFocused(InAppNotificationItem item) {
    if (_focusedNotificationId == item.id) return;
    setState(() {
      _focusedNotificationId = item.id;
    });
  }

  InAppNotificationItem? _findFocusedItem(List<InAppNotificationItem> items) {
    final focusedId = _focusedNotificationId;
    if (focusedId == null) return null;
    for (final item in items) {
      if (item.id == focusedId) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationCenterProvider);
    final items = state.items;
    final focusedItem = _findFocusedItem(items);

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知中心'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: state.unreadCount == 0
                  ? null
                  : () {
                      ref
                          .read(notificationCenterProvider.notifier)
                          .markAllRead();
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('全部通知已标记为已读'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
              child: const Text('全部已读'),
            ),
          if (items.isNotEmpty)
            IconButton(
              tooltip: '清空通知',
              onPressed: () async {
                final bool shouldClear = await _confirmClear(context);
                if (!context.mounted || !shouldClear) return;

                ref.read(notificationCenterProvider.notifier).clear();
                setState(() {
                  _focusedNotificationId = null;
                });
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('通知中心已清空'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.delete_outline),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryCard(state: state, focusedItem: focusedItem),
          if (focusedItem != null) ...[
            const SizedBox(height: 12),
            _FocusCard(
              focusedItem: focusedItem,
              onClearFocus: () {
                setState(() {
                  _focusedNotificationId = null;
                });
              },
            ),
          ],
          const SizedBox(height: 12),
          if (items.isEmpty)
            const _EmptyStateCard()
          else
            Card(
              child: Column(
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    _NotificationTile(
                      item: items[i],
                      isFocused: items[i].id == _focusedNotificationId,
                      onFocus: () => _markFocused(items[i]),
                    ),
                    if (i != items.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<bool> _confirmClear(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清空通知中心'),
          content: const Text('这会清空当前端内通知列表。此操作只影响本地通知中心，不影响告警流或后端状态。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认清空'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state, required this.focusedItem});

  final NotificationCenterState state;
  final InAppNotificationItem? focusedItem;

  @override
  Widget build(BuildContext context) {
    final String headline = state.unreadCount == 0
        ? '当前没有待处理通知'
        : '当前有 ${state.unreadCount} 条通知待处理';

    final String detail = focusedItem != null
        ? '当前焦点：${focusedItem!.title}'
        : state.lastUpdatedAt == null
        ? '汇总告警、执行回执与关键变化。'
        : '最近更新：${_formatDateTime(state.lastUpdatedAt!)}';

    return AppSectionCard(
      title: headline,
      subtitle: detail,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _InfoChip(
            icon: Icons.inbox_outlined,
            label: '总数 ${state.items.length}',
          ),
          _InfoChip(
            icon: Icons.mark_email_unread_outlined,
            label: '未读 ${state.unreadCount}',
          ),
        ],
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.focusedItem, required this.onClearFocus});

  final InAppNotificationItem? focusedItem;
  final VoidCallback? onClearFocus;

  @override
  Widget build(BuildContext context) {
    if (focusedItem == null) {
      return const SizedBox.shrink();
    }

    final routeAction = _NotificationTile.resolveRouteAction(focusedItem!);

    return AppSectionCard(
      title: '当前焦点通知 / 当前焦点链路',
      subtitle: '这条通知正在驱动你当前的处理链路，可直接继续进入下一步，与首页 / 告警页焦点语言保持一致。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  focusedItem!.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(focusedItem!.body),
                finalHint(context),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onClearFocus,
                icon: const Icon(Icons.center_focus_weak_outlined),
                label: const Text('清除焦点'),
              ),
              OutlinedButton.icon(
                onPressed: null,
                icon: Icon(routeAction.primaryIcon),
                label: Text('下一步：${routeAction.primaryLabel}'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget finalHint(BuildContext context) {
    final hint = _buildAnchorHint(focusedItem!);
    if (hint.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('暂无通知', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '等告警流、策略执行回执或关键态势变化进入通知中心后，这里会自动出现列表。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({
    required this.item,
    required this.isFocused,
    required this.onFocus,
  });

  final InAppNotificationItem item;
  final bool isFocused;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color severityColor = _severityColor(context, item.severity);
    final String severityLabel = _severityLabel(item.severity);
    final String sourceLabel = _sourceLabel(item.source);
    final _NotificationRouteAction routeAction = resolveRouteAction(item);

    return Container(
      color: isFocused
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
          : null,
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: severityColor.withValues(alpha: 0.12),
          child: Icon(
            _severityIcon(item.severity),
            color: severityColor,
            size: 18,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                style: item.isRead
                    ? (isFocused
                          ? const TextStyle(fontWeight: FontWeight.w700)
                          : null)
                    : const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (isFocused)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.center_focus_strong_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            if (!item.isRead)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: severityColor,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(item.body),
            const SizedBox(height: 8),
            if (_buildAnchorHint(item).isNotEmpty) ...[
              Text(
                _buildAnchorHint(item),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _SeverityChip(label: severityLabel, color: severityColor),
                Text(sourceLabel, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  _formatDateTime(item.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (isFocused)
                  Text(
                    '当前焦点',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () {
                    onFocus();
                    if (!item.isRead) {
                      ref
                          .read(notificationCenterProvider.notifier)
                          .markRead(item.id);
                    }
                    _openTabAndClose(context, ref, routeAction.primaryTab);
                  },
                  icon: Icon(routeAction.primaryIcon),
                  label: Text(routeAction.primaryLabel),
                ),
                if (routeAction.secondaryTab != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      onFocus();
                      if (!item.isRead) {
                        ref
                            .read(notificationCenterProvider.notifier)
                            .markRead(item.id);
                      }
                      _openTabAndClose(context, ref, routeAction.secondaryTab!);
                    },
                    icon: Icon(routeAction.secondaryIcon),
                    label: Text(routeAction.secondaryLabel!),
                  ),
                OutlinedButton.icon(
                  onPressed: onFocus,
                  icon: Icon(
                    isFocused
                        ? Icons.center_focus_strong_outlined
                        : Icons.center_focus_weak_outlined,
                  ),
                  label: Text(isFocused ? '当前焦点' : '查看焦点通知'),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: item.isRead
            ? const Icon(Icons.chevron_right)
            : IconButton(
                tooltip: '标记已读',
                onPressed: () {
                  ref
                      .read(notificationCenterProvider.notifier)
                      .markRead(item.id);
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已读：${item.title}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.done_outline),
              ),
        onTap: () {
          onFocus();
          if (!item.isRead) {
            ref.read(notificationCenterProvider.notifier).markRead(item.id);
          }
          _openTabAndClose(context, ref, routeAction.primaryTab);
        },
      ),
    );
  }

  static _NotificationRouteAction resolveRouteAction(
    InAppNotificationItem item,
  ) {
    if (_looksLikeReceiptNotification(item)) {
      return const _NotificationRouteAction(
        primaryLabel: '查看焦点事件',
        primaryIcon: Icons.fact_check_outlined,
        primaryTab: HomeTab.audit,
        secondaryLabel: '查看焦点策略',
        secondaryIcon: Icons.alt_route_outlined,
        secondaryTab: HomeTab.strategy,
      );
    }

    switch (item.source) {
      case InAppNotificationSource.alerts:
        return const _NotificationRouteAction(
          primaryLabel: '进入告警处置',
          primaryIcon: Icons.warning_amber_rounded,
          primaryTab: HomeTab.alerts,
          secondaryLabel: '查看焦点策略',
          secondaryIcon: Icons.alt_route_outlined,
          secondaryTab: HomeTab.strategy,
        );
      case InAppNotificationSource.strategyExecution:
        return const _NotificationRouteAction(
          primaryLabel: '查看焦点策略',
          primaryIcon: Icons.alt_route_outlined,
          primaryTab: HomeTab.strategy,
          secondaryLabel: '查看焦点事件',
          secondaryIcon: Icons.fact_check_outlined,
          secondaryTab: HomeTab.audit,
        );
      case InAppNotificationSource.situation:
        return const _NotificationRouteAction(
          primaryLabel: '返回态势巡检',
          primaryIcon: Icons.monitor_heart_outlined,
          primaryTab: HomeTab.situation,
          secondaryLabel: '查看焦点策略',
          secondaryIcon: Icons.alt_route_outlined,
          secondaryTab: HomeTab.strategy,
        );
      case InAppNotificationSource.system:
        return const _NotificationRouteAction(
          primaryLabel: '查看焦点事件',
          primaryIcon: Icons.fact_check_outlined,
          primaryTab: HomeTab.audit,
          secondaryLabel: '返回首页态势',
          secondaryIcon: Icons.home_outlined,
          secondaryTab: HomeTab.situation,
        );
    }
  }

  static String _sourceLabel(InAppNotificationSource source) {
    switch (source) {
      case InAppNotificationSource.alerts:
        return '告警通知';
      case InAppNotificationSource.strategyExecution:
        return '策略回执';
      case InAppNotificationSource.situation:
        return '态势变化';
      case InAppNotificationSource.system:
        return '系统通知';
    }
  }

  static String _severityLabel(InAppNotificationSeverity severity) {
    switch (severity) {
      case InAppNotificationSeverity.info:
        return 'INFO';
      case InAppNotificationSeverity.warn:
        return 'WARN';
      case InAppNotificationSeverity.critical:
        return 'CRITICAL';
    }
  }

  static IconData _severityIcon(InAppNotificationSeverity severity) {
    switch (severity) {
      case InAppNotificationSeverity.info:
        return Icons.notifications_outlined;
      case InAppNotificationSeverity.warn:
        return Icons.notifications_active_outlined;
      case InAppNotificationSeverity.critical:
        return Icons.error_outline;
    }
  }

  static Color _severityColor(
    BuildContext context,
    InAppNotificationSeverity severity,
  ) {
    final scheme = Theme.of(context).colorScheme;
    switch (severity) {
      case InAppNotificationSeverity.info:
        return scheme.primary;
      case InAppNotificationSeverity.warn:
        return const Color(0xFFFFB45C);
      case InAppNotificationSeverity.critical:
        return scheme.error;
    }
  }
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationRouteAction {
  const _NotificationRouteAction({
    required this.primaryLabel,
    required this.primaryIcon,
    required this.primaryTab,
    this.secondaryLabel,
    this.secondaryIcon,
    this.secondaryTab,
  });

  final String primaryLabel;
  final IconData primaryIcon;
  final HomeTab primaryTab;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final HomeTab? secondaryTab;
}

bool _looksLikeReceiptNotification(InAppNotificationItem item) {
  if (item.source != InAppNotificationSource.strategyExecution) {
    return false;
  }

  final title = item.title.toLowerCase();
  final body = item.body.toLowerCase();
  return title.contains('回执') ||
      title.contains('acked') ||
      title.contains('ack') ||
      body.contains('回执') ||
      body.contains('已返回') ||
      body.contains('acked') ||
      body.contains('ack');
}

String _buildAnchorHint(InAppNotificationItem item) {
  final String? entityId = item.relatedEntityId;
  final Object? phase = item.meta['phase'];
  final Object? status = item.meta['executionStatus'];
  final Object? policyId = item.meta['policyId'];

  final parts = <String>[];
  if (entityId != null && entityId.isNotEmpty) {
    parts.add('关联ID: $entityId');
  }
  if (policyId is String && policyId.isNotEmpty) {
    parts.add('策略: $policyId');
  }
  if (phase is String && phase.isNotEmpty) {
    parts.add('阶段: $phase');
  }
  if (status is String && status.isNotEmpty) {
    parts.add('状态: $status');
  }

  if (parts.isEmpty && _looksLikeReceiptNotification(item)) {
    return '当前已支持页级直达：可直接进入审计或查看焦点策略；本页还能锁定当前焦点通知。';
  }
  if (parts.isEmpty) {
    return '';
  }
  return '${parts.join(' · ')} · 当前支持页级直达，并可将该通知查看焦点通知。';
}

void _openTabAndClose(BuildContext context, WidgetRef ref, HomeTab tab) {
  ref.read(homeTabProvider.notifier).selectIndex(HomeTab.values.indexOf(tab));
  Navigator.of(context).pop();
}

String _formatDateTime(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  final ss = value.second.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm:$ss';
}

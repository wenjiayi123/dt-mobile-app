import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/features/replay/presentation/replay_page.dart';
import 'package:dt_mobile_app/features/demo/application/demo_flow_controller.dart';

import '../application/audit_controller.dart';

class AuditPage extends ConsumerStatefulWidget {
  const AuditPage({super.key});

  @override
  ConsumerState<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<AuditPage> {
  String? _focusedEventId;

  void _markFocused(AuditEvent event) {
    if (_focusedEventId == event.eventId) return;
    setState(() {
      _focusedEventId = event.eventId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(auditTimelineProvider);
    final items = timeline.items;
    final latestStrategyEvent = _findLatestStrategyEvent(items);
    final focusedEvent = _findFocusedEvent(items);
    final demoFlow = ref.watch(demoFlowProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('审计复核')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (demoFlow.isRunning) ...[
            _AuditDemoClosureCard(
              flow: demoFlow,
              totalCount: timeline.count,
              hasReplay: latestStrategyEvent != null,
            ),
            const SizedBox(height: 12),
          ],
          _ReviewEntryCard(
            latestStrategyEvent: latestStrategyEvent,
            isFocused:
                latestStrategyEvent != null &&
                latestStrategyEvent.eventId == _focusedEventId,
            onOpenLatest: latestStrategyEvent == null
                ? null
                : () => _showAuditDetailSheet(
                    context: context,
                    event: latestStrategyEvent,
                  ),
          ),
          const SizedBox(height: 12),
          _ConclusionCard(
            totalCount: timeline.count,
            latestStrategyEvent: latestStrategyEvent,
            focusedEvent: focusedEvent,
          ),
          const SizedBox(height: 12),
          if (latestStrategyEvent != null)
            _LatestStrategyReceiptCard(
              event: latestStrategyEvent,
              onTap: () =>
                  _openReplayPage(context: context, event: latestStrategyEvent),
              onDetailTap: () => _showAuditDetailSheet(
                context: context,
                event: latestStrategyEvent,
              ),
            )
          else
            const _EmptyStrategyReceiptCard(),
          const SizedBox(height: 16),
          _TimelineSection(
            items: items,
            latestStrategyEvent: latestStrategyEvent,
            focusedEventId: _focusedEventId,
            onEventTap: (event) =>
                _openReplayPage(context: context, event: event),
            onEventDetailTap: (event) =>
                _showAuditDetailSheet(context: context, event: event),
          ),
        ],
      ),
    );
  }

  AuditEvent? _findLatestStrategyEvent(List<AuditEvent> items) {
    for (final item in items) {
      if (_isStrategyEvent(item)) return item;
    }
    return null;
  }

  AuditEvent? _findFocusedEvent(List<AuditEvent> items) {
    final focusedEventId = _focusedEventId;
    if (focusedEventId == null) return null;
    for (final item in items) {
      if (item.eventId == focusedEventId) return item;
    }
    return null;
  }

  bool _isStrategyEvent(AuditEvent event) {
    return isStrategyAuditEvent(event);
  }

  Future<void> _openReplayPage({
    required BuildContext context,
    required AuditEvent event,
  }) async {
    _markFocused(event);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReplayPage(eventId: event.eventId),
      ),
    );
  }

  Future<void> _showAuditDetailSheet({
    required BuildContext context,
    required AuditEvent event,
  }) async {
    _markFocused(event);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _AuditDetailSheet(event: event);
      },
    );
  }
}

class _AuditDemoClosureCard extends StatelessWidget {
  const _AuditDemoClosureCard({
    required this.flow,
    required this.totalCount,
    required this.hasReplay,
  });

  final DemoFlowState flow;
  final int totalCount;
  final bool hasReplay;

  @override
  Widget build(BuildContext context) {
    final complete = flow.stage == DemoFlowStage.audit && hasReplay;
    final color = complete ? const Color(0xFF76F7C5) : const Color(0xFFFFB45C);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B383A), Color(0xFF13365C), Color(0xFF2A235B)],
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: color.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 24,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                complete ? Icons.verified_rounded : Icons.sync_rounded,
                color: color,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  complete ? '界面讲解已完成' : '界面讲解正在收尾',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                flow.stage.timeLabel,
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            complete
                ? '态势变化 → 高优告警 → 策略候选 → 人工表态 → 执行回执 → 审计回放已经串成同一条证据链。'
                : flow.stage.narrative,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                icon: Icons.inventory_2_outlined,
                label: '留痕 $totalCount 条',
              ),
              _StatusPill(
                icon: Icons.movie_filter_outlined,
                label: hasReplay ? '回放已就绪' : '等待回放锚点',
              ),
              const _StatusPill(
                icon: Icons.person_outline_rounded,
                label: '人工确认可追溯',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewEntryCard extends StatelessWidget {
  const _ReviewEntryCard({
    required this.latestStrategyEvent,
    required this.isFocused,
    required this.onOpenLatest,
  });

  final AuditEvent? latestStrategyEvent;
  final bool isFocused;
  final VoidCallback? onOpenLatest;

  @override
  Widget build(BuildContext context) {
    final hasLatest = latestStrategyEvent != null;
    final summary = hasLatest ? '最新策略处置已留痕，等待复核。' : '暂无待复核记录。';
    final nextStep = hasLatest ? '优先复核最新记录' : '等待首条闭环写入';

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('审计复核入口', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              summary,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isFocused)
                  const _StatusPill(
                    icon: Icons.center_focus_strong_outlined,
                    label: '当前共享焦点',
                  ),
                _StatusPill(
                  icon: hasLatest
                      ? Icons.task_alt_outlined
                      : Icons.hourglass_empty,
                  label: nextStep,
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenLatest,
                icon: Icon(
                  hasLatest
                      ? Icons.fact_check_outlined
                      : Icons.schedule_outlined,
                ),
                label: Text(hasLatest ? '复核最新记录' : '等待复核对象'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConclusionCard extends StatelessWidget {
  const _ConclusionCard({
    required this.totalCount,
    required this.latestStrategyEvent,
    required this.focusedEvent,
  });

  final int totalCount;
  final AuditEvent? latestStrategyEvent;
  final AuditEvent? focusedEvent;

  @override
  Widget build(BuildContext context) {
    final latestAction = latestStrategyEvent == null
        ? '暂无待复核闭环'
        : _readTimelineHeadline(latestStrategyEvent!);
    final latestTime = latestStrategyEvent == null
        ? '等待首条记录'
        : _formatDateTime(latestStrategyEvent!.at);
    final focusedLabel = focusedEvent == null
        ? '尚未设定'
        : _readTargetPolicyTitle(focusedEvent!.meta) ??
              _readTimelineHeadline(focusedEvent!);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('审计复核状态', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              latestStrategyEvent == null
                  ? '当前还没有待复核闭环。'
                  : '最近一次策略处置已写入，现在适合先做审计复核，再沿当前焦点链路核对提交、回执与指标快照。',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(
                  icon: Icons.inventory_2_outlined,
                  label: '留痕 $totalCount 条',
                ),
                _StatusPill(
                  icon: Icons.rule_folder_outlined,
                  label: '最近待复核 $latestAction',
                ),
                _StatusPill(icon: Icons.schedule_outlined, label: latestTime),
                _StatusPill(
                  icon: Icons.center_focus_strong_outlined,
                  label: '当前焦点 $focusedLabel',
                ),
                if (latestStrategyEvent != null)
                  _StatusPill(
                    icon: _timelineToneIcon(latestStrategyEvent!),
                    label: _timelineToneLabel(latestStrategyEvent!),
                    color: _timelineToneColor(context, latestStrategyEvent!),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestStrategyReceiptCard extends StatelessWidget {
  const _LatestStrategyReceiptCard({
    required this.event,
    required this.onTap,
    required this.onDetailTap,
  });

  final AuditEvent event;
  final VoidCallback onTap;
  final VoidCallback onDetailTap;

  @override
  Widget build(BuildContext context) {
    final uploadStatus = _AuditUploadStatusView.fromPayload(event.payload);
    final uploadMessage = _readUploadMessage(event.payload);
    final choice = _readHumanChoice(event.meta);
    final targetTitle = _readTargetPolicyTitle(event.meta);
    final remark = _readHumanRemark(event.meta);
    final policySetSummary = _readString(event.meta['policySetSummary']);
    final stateSummary = _readString(event.meta['stateSummary']);
    final effects = _readCandidateEffects(event.meta);
    final executionStatus = _readExecutionStatus(event.meta);
    final executionMessage = _readExecutionMessage(event.meta);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1.0,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const _StatusPill(icon: Icons.bolt_outlined, label: '最新记录'),
                  _StatusPill(
                    icon: _timelineToneIcon(event),
                    label: _timelineToneLabel(event),
                    color: _timelineToneColor(context, event),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '最近待复核事件',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '建议先核验留痕，再进入回放核对相邻审计记录；记录差异不作因果归因。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                targetTitle ?? '未识别策略',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusPill(
                    icon: Icons.rule_folder_outlined,
                    label: choice ?? event.actionLabel,
                  ),
                  if (executionStatus != null)
                    _StatusPill(
                      icon: _executionStatusIcon(executionStatus),
                      label: '执行 · ${executionStatus.toUpperCase()}',
                      color: _executionStatusColor(context, executionStatus),
                    ),
                  _StatusPill(
                    icon: uploadStatus.icon,
                    label: '上传 · ${uploadStatus.label.toUpperCase()}',
                    color: uploadStatus.color(context),
                  ),
                  _StatusPill(icon: Icons.tag_outlined, label: event.requestId),
                ],
              ),
              const SizedBox(height: 14),
              _ReceiptLine(label: '时间', value: _formatDateTime(event.at)),
              if (stateSummary != null)
                _ReceiptLine(label: '状态摘要', value: stateSummary),
              if (executionMessage != null)
                _ReceiptLine(label: '执行说明', value: executionMessage),
              if (policySetSummary != null)
                _ReceiptLine(label: '策略集摘要', value: policySetSummary),
              if (remark != null && remark.isNotEmpty)
                _ReceiptLine(label: '人工备注', value: remark),
              if (uploadMessage != null)
                _ReceiptLine(label: '上传结果', value: uploadMessage),
              if (effects.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('后果快照', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ...effects
                    .take(3)
                    .map(
                      (effect) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.subdirectory_arrow_right,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text(effect)),
                          ],
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('进入回放'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: onDetailTap,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('查看链路'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyStrategyReceiptCard extends StatelessWidget {
  const _EmptyStrategyReceiptCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最近待复核事件', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('当前暂无待复核干预记录。'),
          ],
        ),
      ),
    );
  }
}

class _TimelineSection extends StatelessWidget {
  const _TimelineSection({
    required this.items,
    required this.latestStrategyEvent,
    required this.focusedEventId,
    required this.onEventTap,
    required this.onEventDetailTap,
  });

  final List<AuditEvent> items;
  final AuditEvent? latestStrategyEvent;
  final String? focusedEventId;
  final ValueChanged<AuditEvent> onEventTap;
  final ValueChanged<AuditEvent> onEventDetailTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('复核时间线', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('当前暂无复核记录。'),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('复核时间线', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        ...items.map(
          (event) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TimelineEventCard(
              event: event,
              isLatestWritten:
                  latestStrategyEvent != null &&
                  event.requestId == latestStrategyEvent!.requestId &&
                  event.at == latestStrategyEvent!.at,
              isFocused: event.eventId == focusedEventId,
              onTap: () => onEventTap(event),
              onDetailTap: () => onEventDetailTap(event),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineEventCard extends StatelessWidget {
  const _TimelineEventCard({
    required this.event,
    required this.isLatestWritten,
    required this.isFocused,
    required this.onTap,
    required this.onDetailTap,
  });

  final AuditEvent event;
  final bool isLatestWritten;
  final bool isFocused;
  final VoidCallback onTap;
  final VoidCallback onDetailTap;

  @override
  Widget build(BuildContext context) {
    final isStrategy = isStrategyAuditEvent(event);
    final uploadStatus = _AuditUploadStatusView.fromPayload(event.payload);
    final choice = _readHumanChoice(event.meta);
    final title =
        _readTargetPolicyTitle(event.meta) ?? _readTimelineHeadline(event);
    final stateSummary =
        _readString(event.meta['stateSummary']) ??
        _readString(event.meta['humanChoiceSummary']);
    final effects = _readCandidateEffects(event.meta);
    final executionStatus = _readExecutionStatus(event.meta);

    final borderColor = isFocused
        ? Theme.of(context).colorScheme.tertiary
        : isLatestWritten
        ? Theme.of(context).colorScheme.primary
        : isStrategy
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outlineVariant;

    final borderWidth = isFocused
        ? 2.0
        : (isLatestWritten ? 1.8 : (isStrategy ? 1.4 : 1.0));

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(12),
        ),
        color: isFocused
            ? Theme.of(
                context,
              ).colorScheme.tertiaryContainer.withValues(alpha: 0.45)
            : isLatestWritten
            ? Theme.of(context).colorScheme.surfaceContainerLow
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (isStrategy)
                    const _StatusPill(
                      icon: Icons.auto_awesome_motion_outlined,
                      label: '处置事件',
                    ),
                  if (isLatestWritten)
                    const _StatusPill(icon: Icons.bolt_outlined, label: '最新记录'),
                  if (isFocused)
                    _StatusPill(
                      icon: Icons.center_focus_strong_outlined,
                      label: '当前共享焦点',
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  _StatusPill(
                    icon: Icons.rule_folder_outlined,
                    label: choice ?? event.actionLabel,
                  ),
                  if (executionStatus != null)
                    _StatusPill(
                      icon: _executionStatusIcon(executionStatus),
                      label: executionStatus,
                      color: _executionStatusColor(context, executionStatus),
                    ),
                  _StatusPill(
                    icon: uploadStatus.icon,
                    label: uploadStatus.label,
                    color: uploadStatus.color(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isFocused)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '当前焦点已锁定该事件。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                stateSummary ?? '暂无摘要',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _ReceiptLine(label: 'requestId', value: event.requestId),
              _ReceiptLine(label: '时间', value: _formatDateTime(event.at)),
              if (effects.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '后果快照',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        ...effects
                            .take(2)
                            .map(
                              (effect) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('• $effect'),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _ReplayFocusHintCard(event: event),
              const SizedBox(height: 12),
              if (isFocused)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '当前焦点已锁定该事件。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onTap,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('进入回放'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onDetailTap,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('查看链路'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditDetailSheet extends StatelessWidget {
  const _AuditDetailSheet({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context) {
    final isStrategy = isStrategyAuditEvent(event);
    final uploadStatus = _AuditUploadStatusView.fromPayload(event.payload);
    final uploadMessage = _readUploadMessage(event.payload);

    final choice = _readHumanChoice(event.meta);
    final title =
        _readTargetPolicyTitle(event.meta) ?? _readTimelineHeadline(event);
    final remark = _readHumanRemark(event.meta);

    final stateSummary = _readString(event.meta['stateSummary']);
    final policySetSummary = _readString(event.meta['policySetSummary']);
    final humanChoiceSummary = _readString(event.meta['humanChoiceSummary']);

    final executionStatus = _readExecutionStatus(event.meta);
    final executionMessage = _readExecutionMessage(event.meta);
    final executionUpdatedAt = _readExecutionUpdatedAt(event.meta);

    final effects = _readCandidateEffects(event.meta);
    final candidateSnapshotSummary = _readCandidateSummary(event.meta);
    final candidatePriorityHint = _readCandidatePriorityHint(event.meta);
    final congestionIndex = _readRiskLine(
      event.meta,
      field: 'congestionIndex',
      fallbackLabel: '测试拥堵',
    );
    final conflictRisk = _readRiskLine(
      event.meta,
      field: 'conflictRisk',
      fallbackLabel: '冲突风险',
    );
    final safetyMargin = _readRiskLine(
      event.meta,
      field: 'safetyMargin',
      fallbackLabel: '安全余量',
    );
    final rewardDelta = _readRiskLine(
      event.meta,
      field: 'rewardDelta',
      fallbackLabel: '相对 LOS-PID 收益',
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('闭环详情', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isStrategy)
                  const _StatusPill(
                    icon: Icons.auto_awesome_motion_outlined,
                    label: '处置事件',
                  ),
                _StatusPill(
                  icon: _timelineToneIcon(event),
                  label: _timelineToneLabel(event),
                  color: _timelineToneColor(context, event),
                ),
                _StatusPill(
                  icon: Icons.rule_folder_outlined,
                  label: choice ?? event.actionLabel,
                ),
                if (executionStatus != null)
                  _StatusPill(
                    icon: _executionStatusIcon(executionStatus),
                    label: '执行 · ${executionStatus.toUpperCase()}',
                    color: _executionStatusColor(context, executionStatus),
                  ),
                _StatusPill(
                  icon: uploadStatus.icon,
                  label: '上传 · ${uploadStatus.label.toUpperCase()}',
                  color: uploadStatus.color(context),
                ),
              ],
            ),
            if (isStrategy) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReplayPage(eventId: event.eventId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('证据已对齐 · 进入回放'),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _DetailBlock(
              title: '基础信息',
              children: [
                _ReceiptLine(label: '标题', value: title),
                _ReceiptLine(label: 'requestId', value: event.requestId),
                _ReceiptLine(label: '时间', value: _formatDateTime(event.at)),
                if (remark != null && remark.isNotEmpty)
                  _ReceiptLine(label: '备注', value: remark),
                if (uploadMessage != null)
                  _ReceiptLine(label: '上传结果', value: uploadMessage),
              ],
            ),
            const SizedBox(height: 12),
            _DetailBlock(
              title: '闭环摘要',
              children: [
                if (stateSummary != null)
                  _SummaryParagraph(label: '状态摘要', value: stateSummary),
                if (policySetSummary != null)
                  _SummaryParagraph(label: '策略集摘要', value: policySetSummary),
                if (humanChoiceSummary != null)
                  _SummaryParagraph(label: '人工表态摘要', value: humanChoiceSummary),
                if (stateSummary == null &&
                    policySetSummary == null &&
                    humanChoiceSummary == null)
                  const Text('暂无摘要信息'),
              ],
            ),
            const SizedBox(height: 12),
            _DetailBlock(
              title: '执行反馈',
              children: [
                if (executionStatus != null)
                  _ReceiptLine(label: '执行状态', value: executionStatus),
                if (executionMessage != null)
                  _SummaryParagraph(label: '执行说明', value: executionMessage),
                if (executionUpdatedAt != null)
                  _ReceiptLine(label: '更新时间', value: executionUpdatedAt),
                if (executionStatus == null &&
                    executionMessage == null &&
                    executionUpdatedAt == null)
                  const Text('当前事件没有执行链路字段'),
              ],
            ),
            const SizedBox(height: 12),
            _DetailBlock(
              title: '候选影响快照',
              children: [
                if (candidateSnapshotSummary != null)
                  _SummaryParagraph(
                    label: '候选摘要',
                    value: candidateSnapshotSummary,
                  ),
                if (candidatePriorityHint != null)
                  _SummaryParagraph(
                    label: '优先级提示',
                    value: candidatePriorityHint,
                  ),
                if (congestionIndex != null) Text(congestionIndex),
                if (conflictRisk != null) Text(conflictRisk),
                if (safetyMargin != null) Text(safetyMargin),
                if (rewardDelta != null) Text(rewardDelta),
                if (candidateSnapshotSummary == null &&
                    candidatePriorityHint == null &&
                    congestionIndex == null &&
                    conflictRisk == null &&
                    safetyMargin == null &&
                    rewardDelta == null)
                  const Text('暂无候选快照信息'),
              ],
            ),
            if (effects.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetailBlock(
                title: '业务影响快照',
                children: effects
                    .map(
                      (effect) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• '),
                            Expanded(child: Text(effect)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            _ReplayFocusBlock(event: event),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReplayPage(eventId: event.eventId),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('进入回放'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check),
                    label: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplayFocusHintCard extends StatelessWidget {
  const _ReplayFocusHintCard({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context) {
    final summary = _buildReplayFocusSummary(event);
    final steps = _buildReplayFocusSteps(event);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前焦点链路', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(summary, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: steps
                .map(
                  (step) => _StatusPill(
                    icon: step.icon,
                    label: step.label,
                    color: step.color,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ReplayFocusBlock extends StatelessWidget {
  const _ReplayFocusBlock({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context) {
    final summary = _buildReplayFocusSummary(event);
    final steps = _buildReplayFocusSteps(event);

    return _DetailBlock(
      title: '当前焦点链路',
      children: [
        Text(summary),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: steps
              .map(
                (step) => _StatusPill(
                  icon: step.icon,
                  label: step.label,
                  color: step.color,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _SummaryParagraph extends StatelessWidget {
  const _SummaryParagraph({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label：',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: resolved.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: resolved),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: resolved,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

enum _AuditUploadStatusView {
  pending,
  success,
  failed,
  notConfigured;

  static _AuditUploadStatusView fromPayload(Map<String, Object?>? payload) {
    final raw = payload?['uploadStatus'];

    if (raw is String) {
      switch (raw.trim()) {
        case 'pending':
          return _AuditUploadStatusView.pending;
        case 'success':
          return _AuditUploadStatusView.success;
        case 'failed':
          return _AuditUploadStatusView.failed;
        case 'notConfigured':
          return _AuditUploadStatusView.notConfigured;
      }
    }

    return _AuditUploadStatusView.notConfigured;
  }

  String get label {
    switch (this) {
      case _AuditUploadStatusView.pending:
        return '待上传';
      case _AuditUploadStatusView.success:
        return '已上传';
      case _AuditUploadStatusView.failed:
        return '上传失败';
      case _AuditUploadStatusView.notConfigured:
        return '未配置';
    }
  }

  IconData get icon {
    switch (this) {
      case _AuditUploadStatusView.pending:
        return Icons.cloud_upload_outlined;
      case _AuditUploadStatusView.success:
        return Icons.cloud_done_outlined;
      case _AuditUploadStatusView.failed:
        return Icons.cloud_off_outlined;
      case _AuditUploadStatusView.notConfigured:
        return Icons.cloud_queue_outlined;
    }
  }

  Color color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (this) {
      case _AuditUploadStatusView.pending:
        return const Color(0xFFFFB45C);
      case _AuditUploadStatusView.success:
        return const Color(0xFF76F7C5);
      case _AuditUploadStatusView.failed:
        return scheme.error;
      case _AuditUploadStatusView.notConfigured:
        return const Color(0xFF9DB2D8);
    }
  }
}

bool isStrategyAuditEvent(AuditEvent event) {
  final source = event.meta['source'];
  if (source == 'strategy_tab') return true;
  if (source is String && source.startsWith('strategy_')) return true;
  if (event.meta['human_choice'] is Map<String, Object?>) return true;
  if (event.meta['execution_feedback'] is Map<String, Object?>) return true;
  if (_readExecutionStatus(event.meta) != null) return true;
  return false;
}

String _readTimelineHeadline(AuditEvent event) {
  final executionStatus = _readExecutionStatus(event.meta);
  if (executionStatus != null) {
    return '执行状态 · ${_timelineToneLabel(event)}';
  }
  final title = _readTargetPolicyTitle(event.meta);
  if (title != null) return title;
  final stateSummary = _readString(event.meta['stateSummary']);
  if (stateSummary != null) return stateSummary;
  return event.actionLabel;
}

String _timelineToneLabel(AuditEvent event) {
  final status = _readExecutionStatus(event.meta);
  if (status == null) return '人工确认';
  switch (status) {
    case 'submitted':
      return '已提交执行';
    case 'executing':
      return '执行中';
    case 'dry_run_recorded':
      return '仅记录干跑';
    case 'acked':
      return '已回执';
    case 'failed':
      return '执行失败';
    default:
      return status.toUpperCase();
  }
}

IconData _timelineToneIcon(AuditEvent event) {
  final status = _readExecutionStatus(event.meta);
  if (status == null) return Icons.person_outline;
  return _executionStatusIcon(status);
}

Color _timelineToneColor(BuildContext context, AuditEvent event) {
  final status = _readExecutionStatus(event.meta);
  if (status == null) return Theme.of(context).colorScheme.primary;
  return _executionStatusColor(context, status);
}

IconData _executionStatusIcon(String status) {
  switch (status) {
    case 'submitted':
      return Icons.outbox_outlined;
    case 'executing':
      return Icons.autorenew;
    case 'dry_run_recorded':
      return Icons.receipt_long_outlined;
    case 'acked':
      return Icons.task_alt;
    case 'failed':
      return Icons.error_outline;
    default:
      return Icons.sync_outlined;
  }
}

Color _executionStatusColor(BuildContext context, String status) {
  switch (status) {
    case 'submitted':
    case 'executing':
      return const Color(0xFFFFB45C);
    case 'dry_run_recorded':
      return const Color(0xFF9DC8F8);
    case 'acked':
      return const Color(0xFF76F7C5);
    case 'failed':
      return Theme.of(context).colorScheme.error;
    default:
      return Theme.of(context).colorScheme.primary;
  }
}

String? _readUploadMessage(Map<String, Object?>? payload) {
  final value = payload?['uploadMessage'];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String? _readString(Object? raw) {
  if (raw is String && raw.trim().isNotEmpty) {
    return raw.trim();
  }
  return null;
}

String? _readHumanChoice(Map<String, Object?> meta) {
  final humanChoice = meta['human_choice'];
  if (humanChoice is Map<String, Object?>) {
    final label = humanChoice['label'];
    if (label is String && label.trim().isNotEmpty) {
      return label.trim();
    }
  }
  return null;
}

String? _readHumanRemark(Map<String, Object?> meta) {
  final humanChoice = meta['human_choice'];
  if (humanChoice is Map<String, Object?>) {
    final remark = humanChoice['remark'];
    if (remark is String && remark.trim().isNotEmpty) {
      return remark.trim();
    }
  }
  return null;
}

String? _readTargetPolicyTitle(Map<String, Object?> meta) {
  final directTitle = meta['targetPolicyTitle'];
  if (directTitle is String && directTitle.trim().isNotEmpty) {
    return directTitle.trim();
  }

  final humanChoice = meta['human_choice'];
  if (humanChoice is Map<String, Object?>) {
    final nestedTitle = humanChoice['target_policy_title'];
    if (nestedTitle is String && nestedTitle.trim().isNotEmpty) {
      return nestedTitle.trim();
    }
  }

  return null;
}

String? _readCandidateSummary(Map<String, Object?> meta) {
  final snapshot = meta['candidate_snapshot'];
  if (snapshot is Map<String, Object?>) {
    final summary = snapshot['summary'];
    if (summary is String && summary.trim().isNotEmpty) {
      return summary.trim();
    }
  }
  return null;
}

String? _readCandidatePriorityHint(Map<String, Object?> meta) {
  final snapshot = meta['candidate_snapshot'];
  if (snapshot is Map<String, Object?>) {
    final hint = snapshot['priorityHint'];
    if (hint is String && hint.trim().isNotEmpty) {
      return hint.trim();
    }
  }
  return null;
}

List<String> _readCandidateEffects(Map<String, Object?> meta) {
  final snapshot = meta['candidate_snapshot'];
  if (snapshot is Map<String, Object?>) {
    final effects = snapshot['effects'];
    if (effects is List) {
      return effects
          .map((item) {
            if (item is Map) {
              final type = item['type']?.toString() ?? 'system';
              final targetName = item['targetName']?.toString() ?? 'unknown';
              final impact = item['impact']?.toString() ?? '暂无影响说明';
              return '$type · $targetName：$impact';
            }
            return item.toString().trim();
          })
          .where((e) => e.isNotEmpty)
          .toList();
    }
  }
  return const [];
}

String? _readRiskLine(
  Map<String, Object?> meta, {
  required String field,
  required String fallbackLabel,
}) {
  final snapshot = meta['candidate_snapshot'];
  if (snapshot is! Map<String, Object?>) return null;

  final raw = snapshot[field];
  if (raw is! Map<String, Object?>) return null;

  final low = raw['low'];
  final high = raw['high'];
  final unit = raw['unit']?.toString() ?? '%';
  final prefix = raw['prefix']?.toString() ?? '';

  if (low is! num || high is! num) return null;

  if (low.toDouble() == high.toDouble()) {
    return '$fallbackLabel：$prefix${_formatNum(low)}$unit';
  }
  return '$fallbackLabel：$prefix${_formatNum(low)}$unit ~ $prefix${_formatNum(high)}$unit';
}

String? _readExecutionStatus(Map<String, Object?> meta) {
  final direct = meta['executionStatus'];
  if (direct is String && direct.trim().isNotEmpty) {
    return direct.trim();
  }

  final feedback = meta['execution_feedback'];
  if (feedback is Map<String, Object?>) {
    final nested = feedback['executionStatus'];
    if (nested is String && nested.trim().isNotEmpty) {
      return nested.trim();
    }
  }

  return null;
}

String? _readExecutionMessage(Map<String, Object?> meta) {
  final direct = meta['executionMessage'];
  if (direct is String && direct.trim().isNotEmpty) {
    return direct.trim();
  }

  final feedback = meta['execution_feedback'];
  if (feedback is Map<String, Object?>) {
    final nested = feedback['executionMessage'];
    if (nested is String && nested.trim().isNotEmpty) {
      return nested.trim();
    }
  }

  return null;
}

String? _readExecutionUpdatedAt(Map<String, Object?> meta) {
  final direct = meta['executionUpdatedAt'];
  if (direct is String && direct.trim().isNotEmpty) {
    return _formatIsoString(direct.trim());
  }

  final feedback = meta['execution_feedback'];
  if (feedback is Map<String, Object?>) {
    final nested = feedback['executionAt'];
    if (nested is String && nested.trim().isNotEmpty) {
      return _formatIsoString(nested.trim());
    }
  }

  return null;
}

class _ReplayFocusStep {
  const _ReplayFocusStep({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;
}

String _buildReplayFocusSummary(AuditEvent event) {
  final choice = _readHumanChoice(event.meta) ?? event.actionLabel;
  final executionStatus = _readExecutionStatus(event.meta);
  final effectCount = _readCandidateEffects(event.meta).length;

  final tail = executionStatus == null
      ? '重点核对人工表态及其指标快照。'
      : '重点核对人工表态与执行回执的时间顺序。';

  if (effectCount > 0) {
    return '进入回放后会围绕本次“$choice”高亮相邻审计记录，并优先核对 $effectCount 条已记录影响线索；不作干预因果归因。$tail';
  }
  return '进入回放后会围绕本次“$choice”核对事件链路；不作干预因果归因。$tail';
}

List<_ReplayFocusStep> _buildReplayFocusSteps(AuditEvent event) {
  final choice = _readHumanChoice(event.meta) ?? event.actionLabel;
  final executionStatus = _readExecutionStatus(event.meta);

  return [
    const _ReplayFocusStep(icon: Icons.visibility_outlined, label: '干预前基线'),
    _ReplayFocusStep(icon: Icons.how_to_vote_outlined, label: '人工表态 · $choice'),
    _ReplayFocusStep(
      icon: executionStatus == null
          ? Icons.insights_outlined
          : _executionStatusIcon(executionStatus),
      label: executionStatus == null
          ? '干预后变化'
          : '执行回执 · ${executionStatus.toUpperCase()}',
      color: executionStatus == null ? null : null,
    ),
  ];
}

String _formatIsoString(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return _formatDateTime(parsed);
}

String _formatNum(num value) {
  if (value is int) return value.toString();

  final doubleValue = value.toDouble();
  if (doubleValue == doubleValue.roundToDouble()) {
    return doubleValue.toInt().toString();
  }
  return doubleValue.toStringAsFixed(1);
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final ss = local.second.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm:$ss';
}

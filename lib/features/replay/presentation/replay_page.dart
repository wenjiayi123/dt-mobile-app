import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/application/home_tab_notifier.dart';
import '../application/replay_controller.dart';

class ReplayPage extends ConsumerStatefulWidget {
  const ReplayPage({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends ConsumerState<ReplayPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(replayTimelineProvider.notifier).load(widget.eventId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final replayTimelineAsync = ref.watch(replayTimelineProvider);
    final replayReady = replayTimelineAsync.maybeWhen(
      data: (timeline) => timeline != null && timeline.frames.isNotEmpty,
      orElse: () => false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('进入回放'),
        actions: [
          IconButton(
            tooltip: '刷新链路',
            onPressed: () {
              ref.read(replayTimelineProvider.notifier).refreshCurrent();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: replayTimelineAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (error, stackTrace) => _ReplayErrorView(
          errorText: error.toString(),
          onRetry: () {
            ref.read(replayTimelineProvider.notifier).load(widget.eventId);
          },
        ),
        data: (timeline) {
          if (timeline == null || timeline.frames.isEmpty) {
            return _ReplayEmptyView(
              eventId: widget.eventId,
              onRetry: () {
                ref.read(replayTimelineProvider.notifier).load(widget.eventId);
              },
            );
          }

          final selectedFrame = timeline.selectedFrame;
          if (selectedFrame == null) {
            return _ReplayEmptyView(
              eventId: widget.eventId,
              onRetry: () {
                ref.read(replayTimelineProvider.notifier).load(widget.eventId);
              },
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _ReplayEntryBanner(timeline: timeline),
              const SizedBox(height: 12),
              _ReplayConclusionCard(
                frame: selectedFrame,
                currentIndex: timeline.selectedFrameIndex,
                totalFrames: timeline.frameCount,
              ),
              const SizedBox(height: 12),
              _SharedFocusReplayCard(timeline: timeline),
              const SizedBox(height: 12),
              _InterventionFocusCard(timeline: timeline),
              const SizedBox(height: 12),
              _FrameChangeSummaryCard(timeline: timeline),
              const SizedBox(height: 12),
              _ReplayTimelineSliderCard(
                timeline: timeline,
                onChanged: (index) {
                  ref.read(replayTimelineProvider.notifier).selectFrame(index);
                },
              ),
              const SizedBox(height: 12),
              _ReplayTimelineListCard(
                timeline: timeline,
                onSelect: (index) {
                  ref.read(replayTimelineProvider.notifier).selectFrame(index);
                },
              ),
              const SizedBox(height: 12),
              _SnapshotCard(frame: selectedFrame),
              const SizedBox(height: 12),
              _PoliciesCard(frame: selectedFrame),
              const SizedBox(height: 12),
              _HumanActionCard(frame: selectedFrame),
              const SizedBox(height: 12),
              _AlertsCard(frame: selectedFrame),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
      bottomNavigationBar: replayReady
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('返回焦点事件'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () {
                          ref
                              .read(homeTabProvider.notifier)
                              .select(HomeTab.situation);
                          ref
                              .read(homeDashboardProvider.notifier)
                              .showDashboard();
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.task_alt_rounded),
                        label: const Text('闭环完成 · 返回运营总览'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _ReplayEntryBanner extends StatelessWidget {
  const _ReplayEntryBanner({required this.timeline});

  final ReplayTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final selected = timeline.selectedFrame;
    final selectedRisk = selected?.snapshot.riskInterval.displayText ?? '--';
    final selectedAction = selected?.humanAction?.actionTypeLabel;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('回放说明', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '当前已进入焦点事件链路，默认高亮相邻审计记录，用于核对提交、回执与指标快照。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(
                  icon: Icons.flag_outlined,
                  label: '焦点事件 ${timeline.anchorEventId}',
                ),
                _InfoPill(
                  icon: Icons.account_tree_outlined,
                  label: '共 ${timeline.frameCount} 帧',
                ),
                _InfoPill(
                  icon: Icons.compare_arrows_outlined,
                  label: '当前风险 $selectedRisk',
                ),
                if (selectedAction != null && selectedAction.trim().isNotEmpty)
                  _InfoPill(
                    icon: Icons.person_search_outlined,
                    label: '人工表态 $selectedAction',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplayConclusionCard extends StatelessWidget {
  const _ReplayConclusionCard({
    required this.frame,
    required this.currentIndex,
    required this.totalFrames,
  });

  final ReplayFrame frame;
  final int currentIndex;
  final int totalFrames;

  @override
  Widget build(BuildContext context) {
    final risk = frame.snapshot.riskInterval;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前帧结论', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '当前位于第 ${currentIndex + 1} / $totalFrames 个关键帧。',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              frame.snapshot.summaryText,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(
                  icon: Icons.schedule_outlined,
                  label: _formatDateTime(frame.time),
                ),
                _InfoPill(
                  icon: Icons.radar_outlined,
                  label: frame.snapshot.stabilityLevel.name,
                ),
                _InfoPill(
                  icon: Icons.warning_amber_outlined,
                  label: risk.displayText,
                ),
                _InfoPill(
                  icon: Icons.hub_outlined,
                  label: '${frame.policies.length} 条策略候选',
                ),
                _InfoPill(
                  icon: Icons.notifications_active_outlined,
                  label: '${frame.alerts.length} 条关联告警',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedFocusReplayCard extends StatelessWidget {
  const _SharedFocusReplayCard({required this.timeline});

  final ReplayTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final selected = timeline.selectedFrame;
    if (selected == null) return const SizedBox.shrink();

    final isAnchor = selected.eventId == timeline.anchorEventId;
    final suggestion = selected.humanAction == null
        ? '可继续回看本次事件链路。'
        : '可对照人工表态与风险变化。';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('焦点事件', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              isAnchor ? '当前已对齐焦点事件。' : '当前正在查看焦点事件前后关键帧。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(
                  icon: Icons.flag_outlined,
                  label: '焦点事件 ${timeline.anchorEventId}',
                ),
                _InfoPill(
                  icon: Icons.account_tree_outlined,
                  label: '回放链路 ${timeline.frameCount} 帧',
                ),
                _InfoPill(
                  icon: Icons.tips_and_updates_outlined,
                  label: suggestion,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InterventionFocusCard extends StatelessWidget {
  const _InterventionFocusCard({required this.timeline});

  final ReplayTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = timeline.selectedFrameIndex;
    final beforeIndex = selectedIndex > 0 ? selectedIndex - 1 : null;
    final afterIndex = selectedIndex;
    final beforeFrame = beforeIndex == null
        ? null
        : timeline.frames[beforeIndex];
    final afterFrame = timeline.frames[afterIndex];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('相邻审计记录', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              beforeFrame == null ? '当前事件已是最早记录。' : '当前默认高亮相邻两条记录，不作因果归因。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (beforeFrame != null)
                  _InfoPill(
                    icon: Icons.history_outlined,
                    label: '干预前 · 第 ${beforeIndex! + 1} 帧',
                  ),
                _InfoPill(
                  icon: Icons.flag_outlined,
                  label: '干预后 · 第 ${afterIndex + 1} 帧',
                ),
                _InfoPill(
                  icon: Icons.compare_arrows_outlined,
                  label: beforeFrame == null
                      ? afterFrame.snapshot.riskInterval.displayText
                      : '${beforeFrame.snapshot.riskInterval.displayText} → ${afterFrame.snapshot.riskInterval.displayText}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameChangeSummaryCard extends StatelessWidget {
  const _FrameChangeSummaryCard({required this.timeline});

  final ReplayTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = timeline.selectedFrameIndex;
    final current = timeline.selectedFrame;
    if (current == null) return const SizedBox.shrink();

    final previous = selectedIndex > 0
        ? timeline.frames[selectedIndex - 1]
        : null;
    final changeSummary = previous == null
        ? '当前是最早关键帧。'
        : _buildChangeSummary(previous, current);

    final points = <String>[
      current.snapshot.summaryText,
      if (previous != null)
        '测试冲突风险记录 ${previous.snapshot.riskInterval.displayText} → ${current.snapshot.riskInterval.displayText}',
      if (current.humanAction != null)
        '人工表态：${current.humanAction!.actionTypeLabel}',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本帧变化点', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              changeSummary,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...points
                .take(3)
                .map(
                  (point) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Icon(Icons.circle, size: 8),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            point,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _buildChangeSummary(ReplayFrame previous, ReplayFrame current) {
    final prevRisk = previous.snapshot.riskInterval;
    final currRisk = current.snapshot.riskInterval;
    final prevScore = previous.snapshot.systemScore;
    final currScore = current.snapshot.systemScore;

    final riskPart = prevRisk.displayText == currRisk.displayText
        ? '两条记录的测试冲突风险相同'
        : '测试冲突风险记录从 ${prevRisk.displayText} 变为 ${currRisk.displayText}';
    final scorePart = currScore >= prevScore
        ? '测试安全余量记录为 $currScore%'
        : '测试安全余量记录降至 $currScore%';

    return '$riskPart，$scorePart。';
  }
}

class _ReplayTimelineSliderCard extends StatelessWidget {
  const _ReplayTimelineSliderCard({
    required this.timeline,
    required this.onChanged,
  });

  final ReplayTimeline timeline;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final frameCount = timeline.frameCount;
    final selectedIndex = timeline.selectedFrameIndex;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('关键帧时间轴', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '拖动时间轴可核对审计记录顺序；记录差异不代表干预因果效果。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Slider(
              value: selectedIndex.toDouble(),
              min: 0,
              max: (frameCount - 1).toDouble(),
              divisions: frameCount > 1 ? frameCount - 1 : 1,
              label: '关键帧 ${selectedIndex + 1}',
              onChanged: (value) {
                onChanged(value.round());
              },
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    frameCount > 0
                        ? _formatDateTime(timeline.frames.first.time)
                        : '--',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  frameCount > 0
                      ? _formatDateTime(timeline.frames.last.time)
                      : '--',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplayTimelineListCard extends StatelessWidget {
  const _ReplayTimelineListCard({
    required this.timeline,
    required this.onSelect,
  });

  final ReplayTimeline timeline;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('关键帧列表', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '默认高亮当前帧及其前一帧，便于快速看出前后差异。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            ...List.generate(timeline.frames.length, (index) {
              final frame = timeline.frames[index];
              final isSelected = index == timeline.selectedFrameIndex;
              final isFocusedBefore =
                  timeline.selectedFrameIndex > 0 &&
                  index == timeline.selectedFrameIndex - 1;
              final isFocusedAfter = index == timeline.selectedFrameIndex;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelect(index),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected || isFocusedBefore
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: isSelected ? 1.6 : (isFocusedBefore ? 1.2 : 1),
                      ),
                      color: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer
                                .withValues(alpha: 0.45)
                          : isFocusedBefore
                          ? Theme.of(context).colorScheme.secondaryContainer
                                .withValues(alpha: 0.35)
                          : null,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 14, child: Text('${index + 1}')),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _formatDateTime(frame.time),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  if (isFocusedBefore)
                                    _TimelineTag(
                                      label: '干预前',
                                      isPrimary: false,
                                    ),
                                  if (isFocusedAfter) ...[
                                    if (isFocusedBefore)
                                      const SizedBox(width: 6),
                                    _TimelineTag(label: '干预后', isPrimary: true),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                frame.snapshot.summaryText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        else if (isFocusedBefore)
                          Icon(
                            Icons.history,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _TimelineTag extends StatelessWidget {
  const _TimelineTag({required this.label, required this.isPrimary});

  final String label;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPrimary ? scheme.primaryContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: isPrimary
              ? scheme.onPrimaryContainer
              : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.frame});

  final ReplayFrame frame;

  @override
  Widget build(BuildContext context) {
    final snapshot = frame.snapshot;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本帧证据', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '以下指标用于支撑当前帧结论。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            _MetricLine(label: '稳定等级', value: snapshot.stabilityLevel.name),
            _MetricLine(label: '测试安全余量', value: '${snapshot.systemScore}%'),
            _MetricLine(
              label: '测试平均拥堵',
              value: '${snapshot.strategyPressure}%',
            ),
            _MetricLine(
              label: '安全余量记录',
              value: '${snapshot.constraintHeadroom}%',
            ),
            _MetricLine(
              label: '测试冲突风险',
              value: snapshot.riskInterval.displayText,
            ),
            const SizedBox(height: 10),
            _SummaryBox(text: snapshot.summaryText),
          ],
        ),
      ),
    );
  }
}

class _PoliciesCard extends StatelessWidget {
  const _PoliciesCard({required this.frame});

  final ReplayFrame frame;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('候选策略', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '查看当前帧被纳入比较的策略候选。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (frame.policies.isEmpty)
              const Text('暂无策略集合')
            else
              ...frame.policies.map(
                (policy) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      border: Border.all(
                        color: policy.isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          policy.title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(policy.summary),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoPill(
                              icon: Icons.stars_outlined,
                              label: '评分提示 ${policy.scoreHint}',
                            ),
                            if (policy.isSelected)
                              const _InfoPill(
                                icon: Icons.check_circle_outline,
                                label: '当前采用',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HumanActionCard extends StatelessWidget {
  const _HumanActionCard({required this.frame});

  final ReplayFrame frame;

  @override
  Widget build(BuildContext context) {
    final action = frame.humanAction;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('人工确认', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '查看该关键帧的人工表态与备注。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (action == null)
              const Text('该关键帧暂无人工表态')
            else ...[
              _InfoPill(
                icon: Icons.person_search_outlined,
                label: action.actionTypeLabel,
              ),
              const SizedBox(height: 10),
              _SummaryBox(text: action.summary),
              if (action.remark != null &&
                  action.remark!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                _MetricLine(label: '备注', value: action.remark!),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.frame});

  final ReplayFrame frame;

  @override
  Widget build(BuildContext context) {
    final alerts = frame.alerts;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('关联告警', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '查看该关键帧对应的风险提示。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (alerts.isEmpty)
              const Text('该关键帧暂无告警')
            else
              ...alerts.map(
                (alert) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(
                        context,
                      ).colorScheme.errorContainer.withValues(alpha: 0.35),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(alert.detail),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoPill(
                              icon: Icons.priority_high,
                              label: alert.severityLabel,
                            ),
                            _InfoPill(
                              icon: Icons.schedule_outlined,
                              label: _formatDateTime(alert.time),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

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
            width: 130,
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

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainer,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
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

class _ReplayEmptyView extends StatelessWidget {
  const _ReplayEmptyView({required this.eventId, required this.onRetry});

  final String eventId;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '未找到回放数据',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('当前事件暂未生成可用回放链路。'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplayErrorView extends StatelessWidget {
  const _ReplayErrorView({required this.errorText, required this.onRetry});

  final String errorText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('回放加载失败', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(errorText),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新加载'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime time) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final year = time.year.toString().padLeft(4, '0');
  final month = twoDigits(time.month);
  final day = twoDigits(time.day);
  final hour = twoDigits(time.hour);
  final minute = twoDigits(time.minute);
  final second = twoDigits(time.second);
  return '$year-$month-$day $hour:$minute:$second';
}

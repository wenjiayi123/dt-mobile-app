import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audit/application/audit_controller.dart';
import '../../demo/application/demo_flow_controller.dart';
import '../../home/application/home_tab_notifier.dart';
import '../application/rl_training_controller.dart';
import '../application/strategy_controller.dart';
import 'rl_decision_console.dart';
import 'rl_training_linkage_card.dart';

class StrategyPage extends ConsumerWidget {
  const StrategyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strategyState = ref.watch(strategyControllerProvider);
    final auditTimeline = ref.watch(auditTimelineProvider);
    final demoFlow = ref.watch(demoFlowProvider);

    final latestSubmissionAudit = _findAuditByRequestId(
      auditTimeline.items,
      strategyState.lastSubmission?.requestId,
    );

    final controller = ref.read(strategyControllerProvider.notifier);
    final hasCandidates = strategyState.candidates.isNotEmpty;
    final showPageLoading =
        strategyState.isRefreshingCandidates && !hasCandidates;
    final showPageError =
        !hasCandidates && strategyState.fetchErrorMessage != null;

    Widget body;
    if (showPageLoading) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: const [_StrategyLoadingBlock()],
      );
    } else if (showPageError) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StrategyErrorBlock(
            message: strategyState.fetchErrorMessage!,
            onRetry: () => controller.refreshCandidates(),
            onBackToSituation: () =>
                ref.read(homeTabProvider.notifier).selectIndex(0),
          ),
        ],
      );
    } else if (!hasCandidates) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const RlTrainingLinkageCard(),
          const SizedBox(height: 12),
          _StrategyErrorBlock(
            message: '尚无完成留出测试的策略产物。请先在上方训练任一基线。',
            onRetry: () => controller.refreshCandidates(),
            onBackToSituation: () =>
                ref.read(homeTabProvider.notifier).selectIndex(0),
          ),
        ],
      );
    } else {
      final focusCandidate = _resolveFocusCandidate(strategyState);
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (demoFlow.isRunning) ...[
            _StrategyDemoBanner(
              flow: demoFlow,
              state: strategyState,
              onOpenAudit: () =>
                  ref.read(homeTabProvider.notifier).selectIndex(3),
            ),
            const SizedBox(height: 12),
          ],
          const RlTrainingLinkageCard(),
          const SizedBox(height: 12),
          RlDecisionConsole(
            state: strategyState,
            focusCandidate: focusCandidate,
            onRun: (testedCandidate) async {
              if (demoFlow.isRunning) {
                ref
                    .read(demoFlowProvider.notifier)
                    .setStage(DemoFlowStage.strategy);
              }
              await controller.refreshCandidates(silent: true);
              final training = ref.read(rlTrainingProvider);
              final metrics = training.evaluationMetrics;
              ref
                  .read(auditTimelineProvider.notifier)
                  .recordAction(
                    'ai_suggestion',
                    meta: <String, Object?>{
                      'source': 'rl_policy_test',
                      'stateSummary':
                          '已播放独立测试集轨迹 ${training.replayFrames.length} 帧 · job=${training.jobId ?? 'unknown'}',
                      'policySetSummary':
                          '${testedCandidate.title} · reward=${metrics['reward'] ?? metrics['mean_reward'] ?? 'n/a'} · dataset=${training.datasetSha256}',
                      'humanChoiceSummary': '测试产物已查看；生产执行仍为关闭状态',
                      'targetPolicyId': testedCandidate.id,
                      'targetPolicyTitle': testedCandidate.title,
                    },
                  );
            },
          ),
          const SizedBox(height: 12),
          _SharedFocusStrategyCard(
            candidate: focusCandidate,
            latestSubmission: strategyState.lastSubmission,
            onOpenAudit: () =>
                ref.read(homeTabProvider.notifier).selectIndex(3),
            onOpenImpact: () => _showWhySheet(
              context: context,
              state: strategyState,
              candidate: focusCandidate,
            ),
            onAdvance: () => _showAdoptDialog(
              pageContext: context,
              ref: ref,
              candidate: focusCandidate,
            ),
          ),
          const SizedBox(height: 12),
          _StrategyCompareSection(
            candidates: strategyState.candidates,
            recommendedPolicyId: strategyState.recommendedPolicyId,
            latestSelectedPolicyId: strategyState.latestSelectedPolicyId,
            justSubmittedPolicyId: strategyState.lastSubmission?.policyId,
            onOpenWhy: (candidate) => _showWhySheet(
              context: context,
              state: strategyState,
              candidate: candidate,
            ),
            onAdoptTap: (candidate) => _showAdoptDialog(
              pageContext: context,
              ref: ref,
              candidate: candidate,
            ),
          ),
          const SizedBox(height: 12),
          _StrategyTrustLayerCard(
            state: strategyState,
            candidate: focusCandidate,
          ),
          if (strategyState.lastSubmission != null) ...[
            const SizedBox(height: 12),
            _SubmissionPulseCard(
              summary: strategyState.lastSubmission!,
              auditEvent: latestSubmissionAudit,
              onOpenAudit: () =>
                  ref.read(homeTabProvider.notifier).selectIndex(3),
              onBackToSituation: () =>
                  ref.read(homeTabProvider.notifier).selectIndex(0),
            ),
            const SizedBox(height: 12),
            _DecisionReceiptCard(
              summary: strategyState.lastSubmission!,
              auditEvent: latestSubmissionAudit,
            ),
          ],
          if (strategyState.fetchErrorMessage != null) ...[
            const SizedBox(height: 12),
            _FetchErrorCard(
              message: strategyState.fetchErrorMessage!,
              onRetry: () => controller.refreshCandidates(),
            ),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('策略确认'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: strategyState.isRefreshingCandidates
                ? null
                : () => controller.refreshCandidates(),
            icon: strategyState.isRefreshingCandidates
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }

  Future<void> _showAdoptDialog({
    required BuildContext pageContext,
    required WidgetRef ref,
    required StrategyCandidate candidate,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();

    final result = await showDialog<_AdoptDialogResult>(
      context: pageContext,
      builder: (dialogContext) => _AdoptDialog(candidate: candidate),
    );

    if (result == null) return;

    final controller = ref.read(strategyControllerProvider.notifier);
    controller.startDraft(policyId: candidate.id, policyTitle: candidate.title);
    controller.setDraftChoice(result.choiceType);
    controller.setDraftRemark(result.remark);

    try {
      await controller.submitDraft();

      if (!pageContext.mounted) return;
      final submission = ref.read(strategyControllerProvider).lastSubmission;
      final resultMessage = submission == null
          ? '策略请求已提交，请在审计页核对后端回执'
          : '${submission.executionStatus.label}：${submission.executionMessage}';
      ScaffoldMessenger.of(pageContext)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(resultMessage),
            duration: const Duration(seconds: 3),
          ),
        );
    } catch (error) {
      if (!pageContext.mounted) return;
      controller.clearDraft();
      ScaffoldMessenger.of(pageContext)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('提交失败：$error'),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  Future<void> _showWhySheet({
    required BuildContext context,
    required StrategyControllerState state,
    required StrategyCandidate candidate,
  }) async {
    final vesselEffects = candidate.effects
        .where((e) => e.type == EffectTargetType.vessel)
        .toList();
    final berthEffects = candidate.effects
        .where((e) => e.type == EffectTargetType.berth)
        .toList();
    final timeWindowEffects = candidate.effects
        .where((e) => e.type == EffectTargetType.timeWindow)
        .toList();
    final otherEffects = candidate.effects
        .where((e) => e.type == EffectTargetType.system)
        .toList();

    final baselineTitle = _resolveBaselineTitle(
      state.candidates,
      candidate.baselinePolicyId,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('方案影响', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  candidate.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(candidate.summary),
                const SizedBox(height: 16),
                _WhyHeadline(candidate: candidate),
                const SizedBox(height: 12),
                _DecisionHealthPanel(candidate: candidate),
                const SizedBox(height: 16),
                _DecisionSignalStrip(candidate: candidate),
                const SizedBox(height: 12),
                _StrategyTrustExplainer(
                  state: state,
                  candidate: candidate,
                  compact: false,
                ),
                if (vesselEffects.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _EffectGroupSection(title: '受影响船舶', effects: vesselEffects),
                ],
                if (berthEffects.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _EffectGroupSection(title: '泊位影响', effects: berthEffects),
                ],
                if (timeWindowEffects.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _EffectGroupSection(
                    title: '时间窗口影响',
                    effects: timeWindowEffects,
                  ),
                ],
                if (otherEffects.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _EffectGroupSection(title: '其他系统影响', effects: otherEffects),
                ],
                if (candidate.relatedAlerts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _RelatedAlertsPanel(alerts: candidate.relatedAlerts),
                ],
                if (candidate.counterfactuals.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _CounterfactualSection(
                    candidate: candidate,
                    baselineTitle: baselineTitle,
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.check),
                    label: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static IconData _choiceIcon(HumanChoiceType choice) {
    switch (choice) {
      case HumanChoiceType.override:
        return Icons.front_hand_outlined;
      case HumanChoiceType.guidance:
        return Icons.alt_route_outlined;
      case HumanChoiceType.veto:
        return Icons.block_outlined;
    }
  }

  static String _choiceSubtitle(HumanChoiceType choice) {
    switch (choice) {
      case HumanChoiceType.override:
        return '以人工判断覆盖当前建议';
      case HumanChoiceType.guidance:
        return '保留系统建议，并加入人工约束';
      case HumanChoiceType.veto:
        return '拒绝当前方案，阻止其进入执行';
    }
  }

  AuditEvent? _findAuditByRequestId(List<AuditEvent> items, String? requestId) {
    if (requestId == null || requestId.isEmpty) return null;

    for (final item in items) {
      if (item.requestId == requestId) return item;
    }
    return null;
  }
}

class _StrategyDemoBanner extends StatelessWidget {
  const _StrategyDemoBanner({
    required this.flow,
    required this.state,
    required this.onOpenAudit,
  });

  final DemoFlowState flow;
  final StrategyControllerState state;
  final VoidCallback onOpenAudit;

  @override
  Widget build(BuildContext context) {
    final submission = state.lastSubmission;
    final isExecuting = flow.stage == DemoFlowStage.executing;
    final isAuditReady = flow.stage == DemoFlowStage.audit;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF102E4C), Color(0xFF20346A), Color(0xFF31205E)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFB8A7FF).withValues(alpha: 0.48),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_rounded, color: Color(0xFF76F7C5)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '小懿联动 · ${flow.stage.timeLabel} · ${flow.stage.shortLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (submission != null)
                Text(
                  submission.executionLabel,
                  style: const TextStyle(
                    color: Color(0xFF76F7C5),
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(flow.stage.narrative),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              Chip(label: Text('${state.candidates.length} 套候选')),
              Chip(
                label: Text(
                  state.candidates.isEmpty
                      ? '推荐 · 暂无测试产物'
                      : '推荐 · ${state.recommendedCandidate.title}',
                ),
              ),
              const Chip(label: Text('人工确认门禁')),
            ],
          ),
          if (isExecuting) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 5),
            const SizedBox(height: 7),
            Text(submission?.executionMessage ?? '执行链路正在接单，请等待回执。'),
          ],
          if (isAuditReady) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenAudit,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('执行已回执 · 进入审计回放'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _resolveBaselineTitle(
  List<StrategyCandidate> candidates,
  String? baselinePolicyId,
) {
  if (baselinePolicyId == null || baselinePolicyId.isEmpty) {
    return 'baseline';
  }

  for (final item in candidates) {
    if (item.id == baselinePolicyId) {
      return item.title;
    }
  }
  return baselinePolicyId;
}

class _AdoptDialogResult {
  const _AdoptDialogResult({required this.choiceType, required this.remark});

  final HumanChoiceType choiceType;
  final String remark;
}

class _AdoptDialog extends StatefulWidget {
  const _AdoptDialog({required this.candidate});

  final StrategyCandidate candidate;

  @override
  State<_AdoptDialog> createState() => _AdoptDialogState();
}

class _AdoptDialogState extends State<_AdoptDialog> {
  late final TextEditingController _remarkController;
  HumanChoiceType _selectedChoice = HumanChoiceType.guidance;

  @override
  void initState() {
    super.initState();
    _remarkController = TextEditingController();
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  void _closeWithResult() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(
      _AdoptDialogResult(
        choiceType: _selectedChoice,
        remark: _remarkController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('提交人工表态'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.candidate.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(widget.candidate.summary),
            const SizedBox(height: 16),
            Text('确认类型', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _HumanChoiceSelector(
              selectedChoice: _selectedChoice,
              onChanged: (choice) {
                setState(() {
                  _selectedChoice = choice;
                });
              },
            ),
            const SizedBox(height: 10),
            Text(
              StrategyPage._choiceSubtitle(_selectedChoice),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _remarkController,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                labelText: '备注',
                hintText: '填写表态备注',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _closeWithResult, child: const Text('提交表态')),
      ],
    );
  }
}

class _SharedFocusStrategyCard extends StatelessWidget {
  const _SharedFocusStrategyCard({
    required this.candidate,
    required this.latestSubmission,
    required this.onOpenAudit,
    required this.onOpenImpact,
    required this.onAdvance,
  });

  final StrategyCandidate? candidate;
  final StrategySubmissionSummary? latestSubmission;
  final VoidCallback onOpenAudit;
  final VoidCallback? onOpenImpact;
  final VoidCallback? onAdvance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCandidate = candidate != null;
    final title = hasCandidate ? candidate!.title : '当前共享焦点策略待确定';
    final summary = hasCandidate
        ? candidate!.summary
        : '当前还没有可收敛的焦点策略，建议先查看焦点告警或刷新候选策略。';
    final statusLabel = latestSubmission == null
        ? '当前焦点策略'
        : '当前焦点策略 · ${latestSubmission!.executionStatus.label}';
    final auditReady = latestSubmission?.executionStatus.isTerminal ?? false;
    final isExecuting = latestSubmission != null && !auditReady;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.adjust_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(summary),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.notifications_active_outlined,
                  label: hasCandidate
                      ? '关联告警 ${candidate!.relatedAlerts.length}'
                      : '等待焦点策略',
                ),
                _InfoChip(
                  icon: Icons.rule_folder_outlined,
                  label: hasCandidate
                      ? '人工确认 ${candidate!.priorityHint.contains('人工确认') ? '需要' : '可选'}'
                      : '待确认',
                ),
                if (latestSubmission != null)
                  _InfoChip(
                    icon: Icons.schedule,
                    label: '执行状态 ${latestSubmission!.executionStatus.label}',
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (auditReady)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onOpenAudit,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('执行已回执 · 进入审计'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpenImpact,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('查看影响'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isExecuting ? null : onAdvance,
                      icon: Icon(
                        isExecuting
                            ? Icons.sync_rounded
                            : Icons.play_circle_outline,
                      ),
                      label: Text(isExecuting ? '执行中 · 等待回执' : '确认方案'),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _StrategyCompareSection extends StatelessWidget {
  const _StrategyCompareSection({
    required this.candidates,
    required this.recommendedPolicyId,
    required this.latestSelectedPolicyId,
    required this.justSubmittedPolicyId,
    required this.onOpenWhy,
    required this.onAdoptTap,
  });

  final List<StrategyCandidate> candidates;
  final String? recommendedPolicyId;
  final String? latestSelectedPolicyId;
  final String? justSubmittedPolicyId;
  final ValueChanged<StrategyCandidate> onOpenWhy;
  final ValueChanged<StrategyCandidate> onAdoptTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('策略对比', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...candidates.take(3).map((candidate) {
              final isRecommended = candidate.id == recommendedPolicyId;
              final isLatestSelected = candidate.id == latestSelectedPolicyId;
              final isJustSubmitted = candidate.id == justSubmittedPolicyId;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CompareCandidateTile(
                  candidate: candidate,
                  isRecommended: isRecommended,
                  isLatestSelected: isLatestSelected,
                  isJustSubmitted: isJustSubmitted,
                  onOpenWhy: () => onOpenWhy(candidate),
                  onAdoptTap: () => onAdoptTap(candidate),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _AdaptiveMetricsRow extends StatelessWidget {
  const _AdaptiveMetricsRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = _AccessibilityLayout.isCompact(context);
        final itemWidth = stacked
            ? constraints.maxWidth
            : (constraints.maxWidth - 16) / 3;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

class _AdaptiveActionButtons extends StatelessWidget {
  const _AdaptiveActionButtons({
    required this.primary,
    required this.secondary,
  });

  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) {
    if (_AccessibilityLayout.isCompact(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [secondary, const SizedBox(height: 10), primary],
      );
    }

    return Row(
      children: [
        Expanded(child: secondary),
        const SizedBox(width: 10),
        Expanded(child: primary),
      ],
    );
  }
}

class _AccessibleButtonStyles {
  static ButtonStyle primary(BuildContext context) {
    return FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  static ButtonStyle secondary(BuildContext context) {
    return OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

class _AccessibilityLayout {
  static bool isCompact(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width;
    final textScale = mediaQuery.textScaler.scale(1);
    return width < 392 || textScale >= 1.15;
  }
}

class _HumanChoiceSelector extends StatelessWidget {
  const _HumanChoiceSelector({
    required this.selectedChoice,
    required this.onChanged,
  });

  final HumanChoiceType selectedChoice;
  final ValueChanged<HumanChoiceType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: HumanChoiceType.values
          .map(
            (choice) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _HumanChoiceOptionTile(
                choice: choice,
                selected: choice == selectedChoice,
                onTap: () => onChanged(choice),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _HumanChoiceOptionTile extends StatelessWidget {
  const _HumanChoiceOptionTile({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final HumanChoiceType choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highlight = selected ? scheme.primary : scheme.outlineVariant;
    final background = selected
        ? scheme.primaryContainer.withValues(alpha: 0.45)
        : scheme.surface;

    return Semantics(
      button: true,
      selected: selected,
      label: '人工确认 ${choice.label}，${StrategyPage._choiceSubtitle(choice)}',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: highlight),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 22,
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(StrategyPage._choiceIcon(choice), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              choice.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        StrategyPage._choiceSubtitle(choice),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompareCandidateTile extends StatelessWidget {
  const _CompareCandidateTile({
    required this.candidate,
    required this.isRecommended,
    required this.isLatestSelected,
    required this.isJustSubmitted,
    required this.onOpenWhy,
    required this.onAdoptTap,
  });

  final StrategyCandidate candidate;
  final bool isRecommended;
  final bool isLatestSelected;
  final bool isJustSubmitted;
  final VoidCallback onOpenWhy;
  final VoidCallback onAdoptTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isRecommended)
                const _StatusPill(icon: Icons.auto_awesome, label: '推荐方案'),
              if (isLatestSelected)
                const _StatusPill(icon: Icons.history, label: '最近提交'),
              if (isJustSubmitted)
                const _StatusPill(icon: Icons.task_alt, label: '已提交'),
              _PriorityPill(priorityHint: candidate.priorityHint),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            candidate.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(candidate.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          _AdaptiveMetricsRow(
            children: [
              _CompareMetricCell(
                label: '测试拥堵',
                value: candidate.congestionIndex.displayText,
              ),
              _CompareMetricCell(
                label: '冲突',
                value: candidate.conflictRisk.displayText,
              ),
              _CompareMetricCell(
                label: '相对收益',
                value: candidate.rewardDelta.displayText,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '证据：${_tradeoffSummary(candidate)}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _AdaptiveActionButtons(
            secondary: Tooltip(
              message: '查看方案影响',
              child: Semantics(
                button: true,
                label: '查看 ${candidate.title} 的后果与反事实',
                child: OutlinedButton.icon(
                  style: _AccessibleButtonStyles.secondary(context),
                  onPressed: onOpenWhy,
                  icon: const Icon(Icons.psychology_alt_outlined),
                  label: const Text('查看影响'),
                ),
              ),
            ),
            primary: Tooltip(
              message: '提交人工表态；公开回放只记录 dry-run',
              child: Semantics(
                button: true,
                label: '确认 ${candidate.title} 并提交人工表态',
                child: FilledButton.icon(
                  style: _AccessibleButtonStyles.primary(context),
                  onPressed: onAdoptTap,
                  icon: const Icon(Icons.rule_folder_outlined),
                  label: const Text('提交人工表态'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _tradeoffSummary(StrategyCandidate candidate) {
    return '测试拥堵 ${candidate.congestionIndex.displayText} · '
        '冲突 ${candidate.conflictRisk.displayText} · '
        '安全余量 ${candidate.safetyMargin.displayText}；仅限当前沙箱合同。';
  }
}

class _CompareMetricCell extends StatelessWidget {
  const _CompareMetricCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label：$value',
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelatedAlertsPanel extends StatelessWidget {
  const _RelatedAlertsPanel({required this.alerts});

  final List<AlertLink> alerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHigh,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '关联当前告警',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '这条策略会直接影响下面这些当前告警，便于你判断是“先稳边界”还是“先抢吞吐”。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          ...alerts.map(
            (alert) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RelatedAlertTile(alert: alert),
            ),
          ),
        ],
      ),
    );
  }
}

class _RelatedAlertTile extends StatelessWidget {
  const _RelatedAlertTile({required this.alert});

  final AlertLink alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _severityTone(theme, alert.severity);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: tone.background,
        border: Border.all(color: tone.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusPill(
                icon: tone.icon,
                label: _severityLabel(alert.severity),
                color: tone.foreground,
              ),
              Text(
                alert.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(alert.summary),
          const SizedBox(height: 6),
          Text(
            '建议动作：${alert.recommendedAction}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static _SeverityTone _severityTone(ThemeData theme, String severity) {
    switch (severity) {
      case 'high':
        return _SeverityTone(
          foreground: theme.colorScheme.error,
          background: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
          border: theme.colorScheme.error.withValues(alpha: 0.35),
          icon: Icons.priority_high_rounded,
        );
      case 'low':
        return _SeverityTone(
          foreground: theme.colorScheme.tertiary,
          background: theme.colorScheme.tertiaryContainer.withValues(
            alpha: 0.45,
          ),
          border: theme.colorScheme.tertiary.withValues(alpha: 0.35),
          icon: Icons.info_outline_rounded,
        );
      default:
        return _SeverityTone(
          foreground: theme.colorScheme.primary,
          background: theme.colorScheme.primaryContainer.withValues(
            alpha: 0.45,
          ),
          border: theme.colorScheme.primary.withValues(alpha: 0.35),
          icon: Icons.report_gmailerrorred_rounded,
        );
    }
  }

  static String _severityLabel(String severity) {
    switch (severity) {
      case 'high':
        return '高优告警';
      case 'low':
        return '低优告警';
      default:
        return '中优告警';
    }
  }
}

class _SeverityTone {
  const _SeverityTone({
    required this.foreground,
    required this.background,
    required this.border,
    required this.icon,
  });

  final Color foreground;
  final Color background;
  final Color border;
  final IconData icon;
}

class _StrategyTrustLayerCard extends StatelessWidget {
  const _StrategyTrustLayerCard({required this.state, required this.candidate});

  final StrategyControllerState state;
  final StrategyCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final freshness = _freshnessLabel(state.lastCandidatesUpdatedAt);
    final boundaryLabel = _decisionBoundaryLabel(candidate);
    final boundaryColor = _decisionBoundaryColor(context, candidate);
    final boundaryIcon = _decisionBoundaryIcon(candidate);
    final trustSummary = _trustSummary(candidate);
    final boundary = _boundarySummary(candidate);
    final manualReason = _manualConfirmReason(candidate);

    return Card(
      child: ExpansionTile(
        leading: Icon(boundaryIcon, color: boundaryColor),
        title: const Text('判断依据'),
        subtitle: Text('$freshness · $boundaryLabel'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                icon:
                    state.candidatesDataSource ==
                        StrategyCandidatesDataSource.backendArtifact
                    ? Icons.fact_check_outlined
                    : Icons.inventory_2_outlined,
                label: '${state.candidatesDataSource.label} · $freshness',
                color:
                    state.candidatesDataSource ==
                        StrategyCandidatesDataSource.backendArtifact
                    ? theme.colorScheme.primary
                    : theme.colorScheme.tertiary,
              ),
              _StatusPill(
                icon: Icons.rule_folder_outlined,
                label: candidate.priorityHint.contains('人工确认')
                    ? '需要人工确认'
                    : '建议人工确认',
                color: candidate.priorityHint.contains('人工确认')
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _TrustLine(
            icon: Icons.verified_outlined,
            title: '推荐理由',
            content: trustSummary,
          ),
          const SizedBox(height: 10),
          _TrustLine(
            icon: Icons.speed_outlined,
            title: '决策边界',
            content: boundary,
          ),
          const SizedBox(height: 10),
          _TrustLine(
            icon: Icons.person_search_outlined,
            title: '人工确认',
            content: manualReason,
          ),
        ],
      ),
    );
  }
}

class _StrategyTrustExplainer extends StatelessWidget {
  const _StrategyTrustExplainer({
    required this.state,
    required this.candidate,
    this.compact = true,
  });

  final StrategyControllerState state;
  final StrategyCandidate candidate;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('证据与边界说明', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (!compact)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(
                  icon:
                      state.candidatesDataSource ==
                          StrategyCandidatesDataSource.backendArtifact
                      ? Icons.fact_check_outlined
                      : Icons.inventory_2_outlined,
                  label:
                      '${state.candidatesDataSource.label} · '
                      '${_freshnessLabel(state.lastCandidatesUpdatedAt)}',
                  color:
                      state.candidatesDataSource ==
                          StrategyCandidatesDataSource.backendArtifact
                      ? theme.colorScheme.primary
                      : theme.colorScheme.tertiary,
                ),
                _StatusPill(
                  icon: _decisionBoundaryIcon(candidate),
                  label: _decisionBoundaryLabel(candidate),
                  color: _decisionBoundaryColor(context, candidate),
                ),
              ],
            ),
          if (!compact) const SizedBox(height: 10),
          Text('• 数据新鲜度：${_freshnessDetail(state)}'),
          const SizedBox(height: 4),
          Text('• 推荐依据：${_trustSummary(candidate)}'),
          const SizedBox(height: 4),
          Text('• 决策边界：${_boundarySummary(candidate)}'),
          const SizedBox(height: 4),
          Text('• 人工确认原因：${_manualConfirmReason(candidate)}'),
        ],
      ),
    );
  }
}

class _TrustLine extends StatelessWidget {
  const _TrustLine({
    required this.icon,
    required this.title,
    required this.content,
  });

  final IconData icon;
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(content),
            ],
          ),
        ),
      ],
    );
  }
}

class _DecisionSignalStrip extends StatelessWidget {
  const _DecisionSignalStrip({required this.candidate});

  final StrategyCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final riskTone = _riskToneText(candidate);
    final tradeoffTone = _tradeoffText(candidate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('方案判断', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text('• 风险判断：$riskTone'),
          const SizedBox(height: 4),
          Text('• 取舍判断：$tradeoffTone'),
        ],
      ),
    );
  }

  String _riskToneText(StrategyCandidate candidate) {
    if (candidate.conflictRisk.unit == 'n/a' ||
        candidate.congestionIndex.unit == 'n/a') {
      return '当前公开基准未提供港口实测冲突/拥堵风险标签，不能据此判断生产安全。';
    }
    final conflictHigh = candidate.conflictRisk.high.toDouble();
    final congestion = candidate.congestionIndex.high.toDouble();

    if (conflictHigh >= 25) {
      return '冲突上沿偏高，需明确人工确认。';
    }
    if (congestion >= 25) {
      return '测试平均拥堵偏高，需人工核对环境响应参数。';
    }
    return '测试拥堵和冲突指标均较低；这只适用于当前留出测试合同。';
  }

  String _tradeoffText(StrategyCandidate candidate) {
    final delta = candidate.rewardDelta.high.toDouble();
    if (candidate.baselinePolicyId == null) {
      return '当前缺少同合同声明基线，不能给出收益比较。';
    }
    if (delta > 0) {
      return '当前留出测试改善高于声明基线；不代表生产港口增益。';
    }
    if (delta < 0) {
      return '当前留出测试改善低于声明基线，应优先保留基线方案。';
    }
    return '当前留出测试与声明基线持平。';
  }
}

class _DecisionHealthPanel extends StatelessWidget {
  const _DecisionHealthPanel({required this.candidate});

  final StrategyCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final congestion = (candidate.congestionIndex.high.toDouble() / 100)
        .clamp(0, 1)
        .toDouble();
    final conflict = (candidate.conflictRisk.high.toDouble() / 100)
        .clamp(0, 1)
        .toDouble();
    final safety = (candidate.safetyMargin.high.toDouble() / 100)
        .clamp(0, 1)
        .toDouble();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.72),
            scheme.tertiaryContainer.withValues(alpha: 0.48),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.monitor_heart_outlined,
                color: scheme.primary,
                size: 19,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '策略体检·收益与安全边界',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  candidate.baselinePolicyId == null ? '无基线' : '已对比基线',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DecisionPointMetric(
            label: '相对声明基线改善',
            valueLabel: candidate.rewardDelta.displayText,
            color: const Color(0xFF1B74E8),
          ),
          const SizedBox(height: 9),
          _DecisionHealthBar(
            label: '测试平均拥堵',
            valueLabel: candidate.congestionIndex.displayText,
            value: congestion,
            color: const Color(0xFFFFB45C),
          ),
          const SizedBox(height: 9),
          _DecisionHealthBar(
            label: '测试平均冲突风险',
            valueLabel: candidate.conflictRisk.displayText,
            value: conflict,
            color: const Color(0xFF8B5CF6),
          ),
          const SizedBox(height: 9),
          _DecisionHealthBar(
            label: '测试平均安全余量',
            valueLabel: candidate.safetyMargin.displayText,
            value: safety,
            color: const Color(0xFF0B9E86),
          ),
          const SizedBox(height: 10),
          Text(
            '全部数值直接来自独立测试段聚合结果；不包装置信区间，也不等同于生产效果。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionHealthBar extends StatelessWidget {
  const _DecisionHealthBar({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.color,
  });

  final String label;
  final String valueLabel;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              valueLabel,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: value.clamp(0, 1),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.64),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _DecisionPointMetric extends StatelessWidget {
  const _DecisionPointMetric({
    required this.label,
    required this.valueLabel,
    required this.color,
  });

  final String label;
  final String valueLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          valueLabel,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _DecisionReceiptCard extends StatelessWidget {
  const _DecisionReceiptCard({required this.summary, required this.auditEvent});

  final StrategySubmissionSummary summary;
  final AuditEvent? auditEvent;

  @override
  Widget build(BuildContext context) {
    final uploadStatus = _AuditUploadStatusView.fromPayload(
      auditEvent?.payload,
    );
    final uploadMessage = _readUploadMessage(auditEvent?.payload);
    final stateSummary = _readMetaString(auditEvent, 'stateSummary');
    final policySetSummary = _readMetaString(auditEvent, 'policySetSummary');
    final humanChoiceSummary = _readMetaString(
      auditEvent,
      'humanChoiceSummary',
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('提交回执', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(
                  icon: Icons.rule_folder_outlined,
                  label: summary.choiceLabel,
                ),
                _ExecutionStatusPill(status: summary.executionStatus),
                _StatusPill(
                  icon: uploadStatus.icon,
                  label: '同步 · ${uploadStatus.upperLabel}',
                  color: uploadStatus.color(context),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ReceiptLine(label: '策略', value: summary.policyTitle),
            _ReceiptLine(label: '方案 ID', value: summary.policyId),
            _ReceiptLine(label: '请求 ID', value: summary.requestId),
            _ReceiptLine(
              label: '提交时间',
              value: _formatDateTime(summary.submittedAt),
            ),
            _ReceiptLine(label: '执行状态', value: summary.executionLabel),
            _ReceiptLine(label: '状态说明', value: summary.executionMessage),
            _ReceiptLine(
              label: '最后更新',
              value: _formatDateTime(summary.lastUpdatedAt),
            ),
            _ReceiptLine(
              label: '备注',
              value: summary.remark.isEmpty ? '无' : summary.remark,
            ),
            if (stateSummary != null) ...[
              const SizedBox(height: 10),
              _ReceiptBlock(title: '状态摘要', content: stateSummary),
            ],
            if (policySetSummary != null) ...[
              const SizedBox(height: 10),
              _ReceiptBlock(title: '策略集摘要', content: policySetSummary),
            ],
            if (humanChoiceSummary != null) ...[
              const SizedBox(height: 10),
              _ReceiptBlock(title: '人工确认', content: humanChoiceSummary),
            ],
            if (uploadMessage != null) ...[
              const SizedBox(height: 10),
              _ReceiptBlock(title: '同步结果', content: uploadMessage),
            ],
          ],
        ),
      ),
    );
  }

  static String? _readMetaString(AuditEvent? event, String key) {
    if (event == null) return null;
    final value = event.meta[key];
    return value?.toString();
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
            width: 72,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ReceiptBlock extends StatelessWidget {
  const _ReceiptBlock({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(content),
        ],
      ),
    );
  }
}

class _SubmissionPulseCard extends StatelessWidget {
  const _SubmissionPulseCard({
    required this.summary,
    required this.auditEvent,
    required this.onOpenAudit,
    required this.onBackToSituation,
  });

  final StrategySubmissionSummary summary;
  final AuditEvent? auditEvent;
  final VoidCallback onOpenAudit;
  final VoidCallback onBackToSituation;

  @override
  Widget build(BuildContext context) {
    final uploadStatus = _AuditUploadStatusView.fromPayload(
      auditEvent?.payload,
    );
    final uploadMessage = _readUploadMessage(auditEvent?.payload);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('提交状态', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(
                  icon: Icons.rule_folder_outlined,
                  label: summary.choiceLabel,
                ),
                _ExecutionStatusPill(status: summary.executionStatus),
                _StatusPill(
                  icon: uploadStatus.icon,
                  label: '同步 · ${uploadStatus.upperLabel}',
                  color: uploadStatus.color(context),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(_buildExecutionMessage(uploadMessage)),
            const SizedBox(height: 12),
            _AdaptiveActionButtons(
              secondary: OutlinedButton.icon(
                style: _AccessibleButtonStyles.secondary(context),
                onPressed: onBackToSituation,
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回态势'),
              ),
              primary: Tooltip(
                message: '查看执行结果与审计记录',
                child: Semantics(
                  button: true,
                  label: '打开审计页查看执行结果',
                  child: FilledButton.icon(
                    style: _AccessibleButtonStyles.primary(context),
                    onPressed: onOpenAudit,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('打开审计'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildExecutionMessage(String? uploadMessage) {
    final execution = summary.executionStatus;
    switch (execution) {
      case StrategyExecutionStatus.submitted:
        return '执行请求已受理，等待下游开始处理。';
      case StrategyExecutionStatus.executing:
        return '执行流程正在进行中，请留意后续结果。';
      case StrategyExecutionStatus.dryRunRecorded:
        return uploadMessage == null
            ? '公开回放决策仅写入审计，未下发生产系统。'
            : '公开回放决策仅写入审计；$uploadMessage';
      case StrategyExecutionStatus.acked:
        return uploadMessage == null
            ? '执行结果已返回，审计记录已同步更新。'
            : '执行结果已返回；$uploadMessage';
      case StrategyExecutionStatus.failed:
        return summary.executionMessage;
    }
  }
}

class _FetchErrorCard extends StatelessWidget {
  const _FetchErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minVerticalPadding: 10,
        leading: const Icon(Icons.cloud_off),
        title: const Text('方案刷新失败'),
        subtitle: Text(message),
        trailing: TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(72, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          onPressed: onRetry,
          child: const Text('重试'),
        ),
      ),
    );
  }
}

class _StrategyLoadingBlock extends StatelessWidget {
  const _StrategyLoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(height: 6),
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在加载策略候选…'),
          ],
        ),
      ),
    );
  }
}

class _StrategyErrorBlock extends StatelessWidget {
  const _StrategyErrorBlock({
    required this.message,
    required this.onRetry,
    required this.onBackToSituation,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBackToSituation;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 32),
            const SizedBox(height: 12),
            Text('策略候选当前不可用', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 16),
            _AdaptiveActionButtons(
              secondary: OutlinedButton(
                style: _AccessibleButtonStyles.secondary(context),
                onPressed: onBackToSituation,
                child: const Text('返回态势'),
              ),
              primary: FilledButton(
                style: _AccessibleButtonStyles.primary(context),
                onPressed: onRetry,
                child: const Text('重试'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhyHeadline extends StatelessWidget {
  const _WhyHeadline({required this.candidate});

  final StrategyCandidate candidate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        '这套候选的核心取舍是：${_headline(candidate)}',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }

  String _headline(StrategyCandidate candidate) {
    final delta = candidate.rewardDelta.high.toDouble();
    if (candidate.baselinePolicyId == null) {
      return '缺少同合同声明基线，暂不能做比较';
    }
    if (delta > 0) {
      return '留出测试改善高于声明基线，仍需人工核对安全边界';
    }
    if (delta < 0) {
      return '留出测试改善低于声明基线，不应优先替代基线方案';
    }
    return '留出测试与声明基线持平';
  }
}

class _EffectGroupSection extends StatelessWidget {
  const _EffectGroupSection({required this.title, required this.effects});

  final String title;
  final List<EffectItem> effects;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...effects.map(
          (effect) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EffectTile(effect: effect),
          ),
        ),
      ],
    );
  }
}

class _EffectTile extends StatelessWidget {
  const _EffectTile({required this.effect});

  final EffectItem effect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(effect.readableLine),
    );
  }
}

class _CounterfactualSection extends StatelessWidget {
  const _CounterfactualSection({
    required this.candidate,
    required this.baselineTitle,
  });

  final StrategyCandidate candidate;
  final String baselineTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('反事实对比', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('对比基线：$baselineTitle'),
        const SizedBox(height: 10),
        ...candidate.counterfactuals.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CounterfactualTile(item: item),
          ),
        ),
      ],
    );
  }
}

class _CounterfactualTile extends StatelessWidget {
  const _CounterfactualTile({required this.item});

  final CounterfactualItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(item.readableLine),
    );
  }
}

class _PriorityPill extends StatelessWidget {
  const _PriorityPill({required this.priorityHint});

  final String priorityHint;

  @override
  Widget build(BuildContext context) {
    return _StatusPill(
      icon: _icon(priorityHint),
      label: _displayLabel(priorityHint),
      color: _color(context, priorityHint),
    );
  }

  static String _displayLabel(String hint) {
    if (hint.contains('人工确认')) return '需人工确认';
    if (hint.contains('测试收益最高')) return '测试收益排序第一';
    return '留出测试候选';
  }

  static IconData _icon(String hint) {
    if (hint.contains('人工确认')) return Icons.person_search_outlined;
    if (hint.contains('测试收益最高')) return Icons.leaderboard_outlined;
    return Icons.fact_check_outlined;
  }

  static Color _color(BuildContext context, String hint) {
    final scheme = Theme.of(context).colorScheme;
    if (hint.contains('人工确认')) return scheme.tertiary;
    if (hint.contains('测试收益最高')) return scheme.primary;
    return scheme.onSurfaceVariant;
  }
}

StrategyCandidate _resolveFocusCandidate(StrategyControllerState state) {
  if (state.lastSubmission != null) {
    for (final candidate in state.candidates) {
      if (candidate.id == state.lastSubmission!.policyId) return candidate;
    }
  }
  if (state.latestSelectedPolicyId != null) {
    for (final candidate in state.candidates) {
      if (candidate.id == state.latestSelectedPolicyId) return candidate;
    }
  }
  return state.recommendedCandidate;
}

String _freshnessLabel(DateTime? updatedAt) {
  if (updatedAt == null) return '等待首帧';
  final diff = DateTime.now().difference(updatedAt);
  if (diff.inSeconds < 30) return '${diff.inSeconds}s 前刷新';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s 前刷新';
  if (diff.inMinutes < 60) return '${diff.inMinutes}min 前刷新';
  return '${diff.inHours}h 前刷新';
}

String _freshnessDetail(StrategyControllerState state) {
  final freshness = _freshnessLabel(state.lastCandidatesUpdatedAt);
  if (state.candidatesDataSource ==
      StrategyCandidatesDataSource.backendArtifact) {
    return '当前为后端测试产物，$freshness；它不是现场实时数据，提交结果以审计回执为准。';
  }
  return '当前为本机缓存，$freshness；应先刷新并核对产物哈希，再决定是否提交。';
}

String _decisionBoundaryLabel(StrategyCandidate candidate) {
  if (_riskMetricsUnavailable(candidate)) {
    return '风险指标未评估';
  }
  final conflictHigh = candidate.conflictRisk.high.toDouble();
  final congestion = candidate.congestionIndex.high.toDouble();
  final rewardDelta = candidate.rewardDelta.low.toDouble();
  final hasHighAlert = candidate.relatedAlerts.any(
    (alert) => alert.severity == 'high',
  );
  if (!hasHighAlert &&
      conflictHigh < 18 &&
      congestion < 18 &&
      rewardDelta >= 0) {
    return '指标边界较低';
  }
  if (conflictHigh < 25 && congestion < 25) {
    return '指标边界中等';
  }
  return '指标边界较高';
}

IconData _decisionBoundaryIcon(StrategyCandidate candidate) {
  switch (_decisionBoundaryLabel(candidate)) {
    case '指标边界较低':
      return Icons.verified_outlined;
    case '指标边界中等':
      return Icons.rule_outlined;
    case '风险指标未评估':
      return Icons.help_outline_rounded;
    default:
      return Icons.warning_amber_outlined;
  }
}

Color _decisionBoundaryColor(
  BuildContext context,
  StrategyCandidate candidate,
) {
  final scheme = Theme.of(context).colorScheme;
  switch (_decisionBoundaryLabel(candidate)) {
    case '指标边界较低':
      return const Color(0xFF76F7C5);
    case '指标边界中等':
      return scheme.primary;
    case '风险指标未评估':
      return const Color(0xFFFFD08A);
    default:
      return scheme.error;
  }
}

String _trustSummary(StrategyCandidate candidate) {
  if (_riskMetricsUnavailable(candidate)) {
    return candidate.rewardDelta.low.toDouble() > 0
        ? '留出测试改善高于声明基线，但缺少港口实测风险标签，只能作为人工复核候选。'
        : '缺少港口实测风险标签，不应据此自动执行。';
  }
  final signals = <String>[];
  if (candidate.rewardDelta.low.toDouble() > 0) {
    signals.add('留出测试改善高于声明基线');
  }
  if (candidate.conflictRisk.high.toDouble() < 18) {
    signals.add('冲突上沿仍处于可控范围');
  }
  if (candidate.congestionIndex.high.toDouble() < 18) {
    signals.add('测试平均拥堵低于 18%');
  }
  if (signals.isEmpty) {
    return '当前测试指标没有形成低边界组合，不应据此自动执行。';
  }
  return '${signals.join('；')}，因此这条方案可以作为当前优先候选。';
}

String _boundarySummary(StrategyCandidate candidate) {
  if (_riskMetricsUnavailable(candidate)) {
    return '当前公开基准未提供可验证的拥堵与冲突风险标签；应先接入现场数据和安全联锁。';
  }
  final congestion = candidate.congestionIndex.high.toDouble();
  final conflictHigh = candidate.conflictRisk.high.toDouble();
  if (conflictHigh >= congestion && conflictHigh >= 25) {
    return '测试平均冲突风险较高；应核对数据映射、环境响应和现场安全联锁。';
  }
  if (congestion > conflictHigh && congestion >= 25) {
    return '测试平均拥堵较高；应核对数据映射和环境响应参数。';
  }
  return '当前留出测试的拥堵与冲突指标较低，但仍不构成生产执行授权。';
}

bool _riskMetricsUnavailable(StrategyCandidate candidate) {
  return candidate.congestionIndex.unit == 'n/a' ||
      candidate.conflictRisk.unit == 'n/a' ||
      candidate.safetyMargin.unit == 'n/a';
}

String _manualConfirmReason(StrategyCandidate candidate) {
  final hasHighAlert = candidate.relatedAlerts.any(
    (alert) => alert.severity == 'high',
  );
  if (candidate.priorityHint.contains('人工确认')) {
    return '${hasHighAlert ? '当前仍挂着高优告警，' : ''}${_boundarySummary(candidate)}人工需要确认是否接受这次取舍。';
  }
  if (candidate.relatedAlerts.isNotEmpty) {
    return '该方案会影响 ${candidate.relatedAlerts.length} 条当前告警，系统建议人工确认后再推进，避免把局部优化误当成全局最优。';
  }
  return '虽然当前方案可作为推荐，但仍建议人工确认关键约束和执行窗口，防止输入缺口导致推荐偏保守。';
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: resolved.withValues(alpha: 0.12),
          border: Border.all(color: resolved.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: resolved),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(color: resolved, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExecutionStatusPill extends StatelessWidget {
  const _ExecutionStatusPill({required this.status});

  final StrategyExecutionStatus status;

  @override
  Widget build(BuildContext context) {
    return _StatusPill(
      icon: _icon(status),
      label: status.label,
      color: _color(context, status),
    );
  }

  static IconData _icon(StrategyExecutionStatus status) {
    switch (status) {
      case StrategyExecutionStatus.submitted:
        return Icons.outbox_outlined;
      case StrategyExecutionStatus.executing:
        return Icons.sync;
      case StrategyExecutionStatus.dryRunRecorded:
        return Icons.receipt_long_outlined;
      case StrategyExecutionStatus.acked:
        return Icons.task_alt;
      case StrategyExecutionStatus.failed:
        return Icons.error_outline;
    }
  }

  static Color _color(BuildContext context, StrategyExecutionStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case StrategyExecutionStatus.submitted:
        return scheme.primary;
      case StrategyExecutionStatus.executing:
        return const Color(0xFFFFB45C);
      case StrategyExecutionStatus.dryRunRecorded:
        return const Color(0xFF9DC8F8);
      case StrategyExecutionStatus.acked:
        return const Color(0xFF76F7C5);
      case StrategyExecutionStatus.failed:
        return scheme.error;
    }
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

  String get upperLabel {
    switch (this) {
      case _AuditUploadStatusView.pending:
        return 'PENDING';
      case _AuditUploadStatusView.success:
        return 'SUCCESS';
      case _AuditUploadStatusView.failed:
        return 'FAILED';
      case _AuditUploadStatusView.notConfigured:
        return 'LOCAL';
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
        return Icons.inventory_2_outlined;
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
        return scheme.primary;
    }
  }
}

String? _readUploadMessage(Map<String, Object?>? payload) {
  final raw = payload?['uploadMessage'];
  return raw?.toString();
}

String _formatDateTime(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  final ss = dt.second.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm:$ss';
}

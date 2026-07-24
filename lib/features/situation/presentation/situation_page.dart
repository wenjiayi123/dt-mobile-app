import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dt_mobile_app/shared/ui/app_card.dart';
import 'package:dt_mobile_app/shared/ui/intelligent_action_button.dart';

import '../../demo/application/demo_flow_controller.dart';
import '../../home/application/home_tab_notifier.dart';
import '../application/situation_controller.dart';
import 'twin_3d_screen.dart';

class SituationPage extends ConsumerWidget {
  const SituationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final situationAsync = ref.watch(situationProvider);
    final demoFlow = ref.watch(demoFlowProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(situationProvider.notifier).refreshNow(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '态势总览',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: '刷新态势',
                onPressed: () =>
                    ref.read(situationProvider.notifier).refreshNow(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (demoFlow.enabled) ...[
            _SituationDemoBanner(
              flow: demoFlow,
              onRestart: () => ref.read(demoFlowProvider.notifier).restart(),
              onPrimary: () {
                switch (demoFlow.stage) {
                  case DemoFlowStage.ready:
                    ref.read(demoFlowProvider.notifier).start();
                    break;
                  case DemoFlowStage.stable:
                    ref.read(demoFlowProvider.notifier).advance();
                    break;
                  case DemoFlowStage.boundary:
                    ref.read(demoFlowProvider.notifier).advance();
                    ref.read(homeTabProvider.notifier).selectIndex(2);
                    break;
                  case DemoFlowStage.alert:
                    ref.read(homeTabProvider.notifier).selectIndex(2);
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
          situationAsync.when(
            loading: () => const _SituationLoadingBlock(),
            error: (error, stackTrace) => _SituationErrorBlock(
              error: error,
              onRetry: () => ref.read(situationProvider.notifier).refreshNow(),
              onGoStrategy: () =>
                  ref.read(homeTabProvider.notifier).selectIndex(1),
            ),
            data: (snapshot) => _SituationDataBlock(
              snapshot: snapshot,
              onGoStrategy: () =>
                  ref.read(homeTabProvider.notifier).selectIndex(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _SituationDemoBanner extends StatelessWidget {
  const _SituationDemoBanner({
    required this.flow,
    required this.onPrimary,
    required this.onRestart,
  });

  final DemoFlowState flow;
  final VoidCallback onPrimary;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final stage = flow.stage;
    final color =
        stage == DemoFlowStage.boundary || stage == DemoFlowStage.alert
        ? const Color(0xFFFFB45C)
        : const Color(0xFF4DE4FF);
    final buttonLabel = switch (stage) {
      DemoFlowStage.ready => '开始界面讲解',
      DemoFlowStage.stable => '讲解风险证据组件',
      DemoFlowStage.boundary => '进入告警 · 核对数据来源',
      DemoFlowStage.alert => '进入策略 · 查看真实训练',
      DemoFlowStage.strategy => '进入策略 · 查看测试产物',
      DemoFlowStage.executing => '进入策略 · 查看生产门禁',
      DemoFlowStage.audit => '进入审计 · 核对证据',
    };
    final buttonIcon = switch (stage) {
      DemoFlowStage.ready => Icons.play_arrow_rounded,
      DemoFlowStage.stable => Icons.trending_up_rounded,
      DemoFlowStage.boundary ||
      DemoFlowStage.alert => Icons.crisis_alert_rounded,
      DemoFlowStage.strategy ||
      DemoFlowStage.executing => Icons.psychology_alt_rounded,
      DemoFlowStage.audit => Icons.fact_check_outlined,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF102E4C), Color(0xFF222253)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.movie_filter_outlined, color: color, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '界面讲解 · ${stage.timeLabel} · ${stage.shortLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(stage.narrative),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPrimary,
              icon: Icon(buttonIcon),
              label: Text(buttonLabel),
            ),
          ),
          if (flow.isRunning) ...[
            const SizedBox(height: 5),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onRestart,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('重新开始界面讲解'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SituationDataBlock extends StatelessWidget {
  const _SituationDataBlock({
    required this.snapshot,
    required this.onGoStrategy,
  });

  final SituationSnapshot snapshot;
  final VoidCallback onGoStrategy;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _KeyConclusionCard(snapshot: snapshot, onGoStrategy: onGoStrategy),
        const SizedBox(height: 12),
        _Twin3dEntryCard(snapshot: snapshot),
        const SizedBox(height: 12),
        snapshot.dataSource == SituationDataSource.live
            ? _MetricGrid(snapshot: snapshot)
            : _BusinessEvidenceGrid(snapshot: snapshot),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: ExpansionTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('查看判断依据'),
            subtitle: const Text('数据可信度与决策边界'),
            childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            children: [
              _TrustSemanticsCard(snapshot: snapshot),
              _DecisionBoundaryCard(
                snapshot: snapshot,
                onGoStrategy: onGoStrategy,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _TrendProjectionCard(
          points: snapshot.trendPoints,
          businessEvidence:
              snapshot.dataSource == SituationDataSource.publicReplay,
        ),
      ],
    );
  }
}

class _Twin3dEntryCard extends StatelessWidget {
  const _Twin3dEntryCard({required this.snapshot});

  final SituationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B2440), Color(0xFF07162C), Color(0xFF07111F)],
        ),
        border: Border.all(
          color: const Color(0xFF4DE4FF).withValues(alpha: 0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22D3EE).withValues(alpha: 0.13),
            blurRadius: 26,
            spreadRadius: -7,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4DE4FF), Color(0xFF1769E0)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4DE4FF).withValues(alpha: 0.32),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.view_in_ar_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '3D 港区接口布局',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      snapshot.dataSource == SituationDataSource.live
                          ? '现场快照 · 业务对象 · 执行回放'
                          : '共享后端证据 · 业务对象槽位 · 留出集回放',
                      style: const TextStyle(
                        color: Color(0xFF9DC8F8),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: const Color(0xFF76F7C5).withValues(alpha: 0.1),
                  border: Border.all(
                    color: const Color(0xFF76F7C5).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  switch (snapshot.dataSource) {
                    SituationDataSource.live => '实时数据',
                    SituationDataSource.publicReplay => '公开历史回放',
                    SituationDataSource.cache => '缓存数据',
                  },
                  style: TextStyle(
                    color: snapshot.dataSource == SituationDataSource.live
                        ? const Color(0xFF76F7C5)
                        : const Color(0xFFFFD08A),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _TwinEntrySignal(label: '稳态', value: '${snapshot.systemScore}'),
              const SizedBox(width: 7),
              _TwinEntrySignal(
                label: '策略压力',
                value: '${snapshot.strategyPressure}',
              ),
              const SizedBox(width: 7),
              _TwinEntrySignal(
                label: '风险',
                value: '${snapshot.riskIntervalHigh}%',
              ),
            ],
          ),
          const SizedBox(height: 12),
          IntelligentActionButton(
            label: '进入 3D 孪生屏',
            eyebrow: 'PORT-DT TWIN · 双端同源',
            icon: Icons.view_in_ar_rounded,
            tone: IntelligentActionTone.twin,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Twin3DScreen(snapshot: snapshot),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TwinEntrySignal extends StatelessWidget {
  const _TwinEntrySignal({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF4DE4FF).withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFF28466D)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFFB8EFFF),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF7894BD),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustSemanticsCard extends StatelessWidget {
  const _TrustSemanticsCard({required this.snapshot});

  final SituationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final freshness = _freshnessSummary(
      snapshot.refreshAt,
      snapshot.dataSource,
    );
    final evidence = _evidenceSummary(snapshot);
    final theme = Theme.of(context);

    return AppSectionCard(
      title: '数据证据',
      subtitle: '数据新鲜度、来源与证据边界。',
      leading: const Icon(Icons.verified_user_outlined),
      trailing: AppSeverityTag(
        label: evidence.label,
        level: evidence.level,
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppSeverityTag(
                label: freshness.modeLabel,
                level: freshness.modeLevel,
                icon: freshness.modeIcon,
                compact: true,
              ),
              AppSeverityTag(
                label: freshness.ageLabel,
                level: freshness.ageLevel,
                icon: Icons.schedule,
                compact: true,
              ),
              AppSeverityTag(
                label: evidence.label,
                level: evidence.level,
                icon: Icons.analytics_outlined,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            evidence.headline,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            evidence.detail,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyConclusionCard extends StatelessWidget {
  const _KeyConclusionCard({
    required this.snapshot,
    required this.onGoStrategy,
  });

  final SituationSnapshot snapshot;
  final VoidCallback onGoStrategy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final severityLevel = _severityFrom(snapshot.stabilityLevel);

    return AppSectionCard(
      title: '当前状态',
      leading: Icon(_headlineIcon(snapshot.stabilityLevel)),
      trailing: AppSeverityTag(
        label: _headlineLabel(snapshot.stabilityLevel),
        level: severityLevel,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snapshot.summaryText,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppSeverityTag(
                label: '数据 ${snapshot.dataSource.label}',
                level: AppSeverityLevel.info,
                icon: Icons.cloud_sync_outlined,
                compact: true,
              ),
              AppSeverityTag(
                label: '刷新 ${_formatTime(snapshot.refreshAt)}',
                level: AppSeverityLevel.neutral,
                icon: Icons.schedule,
                compact: true,
              ),
              AppSeverityTag(
                label: '状态 ${snapshot.stabilityLevel.label}',
                level: severityLevel,
                icon: Icons.rule_folder_outlined,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _actionBridge(snapshot),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _caution(snapshot),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          if (snapshot.dataSource == SituationDataSource.live)
            AppRangeRow(
              label: '现场网关风险区间',
              low: snapshot.riskIntervalLow,
              high: snapshot.riskIntervalHigh,
              emphasize: true,
              trailing: AppSeverityTag(
                label: _riskHeadline(snapshot.riskIntervalHigh),
                level: _riskSeverity(snapshot.riskIntervalHigh),
                compact: true,
              ),
              note: _riskNote(snapshot),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('当前未接入可验证的实时风险标签；本页只展示固定数字孪生测试证据，不生成替代风险值。'),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onGoStrategy,
              icon: const Icon(Icons.alt_route),
              label: const Text('查看焦点策略'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.snapshot});

  final SituationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: '关键指标',
      subtitle: null,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: AppKpiTile(
                  title: '运行状态',
                  value: snapshot.stabilityLevel.label,
                  supporting: '',
                  icon: Icons.shield_outlined,
                  leadingTag: AppSeverityTag(
                    label: _headlineShort(snapshot.stabilityLevel),
                    level: _severityFrom(snapshot.stabilityLevel),
                    compact: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppKpiTile(
                  title: '调度压力',
                  value: '${snapshot.strategyPressure}/100',
                  supporting: _pressureLabel(snapshot.strategyPressure),
                  icon: Icons.speed_outlined,
                  leadingTag: AppSeverityTag(
                    label: _pressureLabel(snapshot.strategyPressure),
                    level: snapshot.strategyPressure >= 75
                        ? AppSeverityLevel.critical
                        : snapshot.strategyPressure >= 50
                        ? AppSeverityLevel.watch
                        : AppSeverityLevel.success,
                    compact: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppKpiTile(
                  title: '边界余量',
                  value: '${snapshot.constraintHeadroom}%',
                  supporting: _constraintLabel(snapshot.constraintHeadroom),
                  icon: Icons.margin_outlined,
                  leadingTag: AppSeverityTag(
                    label: _constraintLabel(snapshot.constraintHeadroom),
                    level: snapshot.constraintHeadroom <= 8
                        ? AppSeverityLevel.critical
                        : snapshot.constraintHeadroom <= 15
                        ? AppSeverityLevel.watch
                        : AppSeverityLevel.success,
                    compact: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppKpiTile(
                  title: snapshot.dataSource == SituationDataSource.live
                      ? '风险上沿'
                      : '派生风险',
                  value: '${snapshot.riskIntervalHigh}%',
                  supporting: _riskHeadline(snapshot.riskIntervalHigh),
                  icon: Icons.warning_amber_outlined,
                  leadingTag: AppSeverityTag(
                    label: _riskHeadline(snapshot.riskIntervalHigh),
                    level: _riskSeverity(snapshot.riskIntervalHigh),
                    compact: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusinessEvidenceGrid extends StatelessWidget {
  const _BusinessEvidenceGrid({required this.snapshot});

  final SituationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    String percent(double? value, {required String sign}) =>
        value == null ? 'n/a' : '$sign${value.toStringAsFixed(0)}%';
    return AppSectionCard(
      title: '固定业务证据',
      subtitle:
          '${snapshot.businessDatasetId ?? 'unknown dataset'} · '
          '${snapshot.businessTestRows ?? 0} 个最终测试时间步',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: AppKpiTile(
                  title: '泊位利用率',
                  value: percent(snapshot.berthImprovementPercent, sign: '+'),
                  supporting: '相对声明基线',
                  icon: Icons.anchor_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppKpiTile(
                  title: '平均待泊时间',
                  value: percent(snapshot.waitReductionPercent, sign: '-'),
                  supporting: '固定留出集',
                  icon: Icons.schedule_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppKpiTile(
                  title: '情景用电成本',
                  value: percent(snapshot.costReductionPercent, sign: '-'),
                  supporting: '含日终能量结算',
                  icon: Icons.bolt_outlined,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: AppKpiTile(
                  title: '证据性质',
                  value: '离线仿真',
                  supporting: '非港口实测KPI',
                  icon: Icons.science_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DecisionBoundaryCard extends StatelessWidget {
  const _DecisionBoundaryCard({
    required this.snapshot,
    required this.onGoStrategy,
  });

  final SituationSnapshot snapshot;
  final VoidCallback onGoStrategy;

  @override
  Widget build(BuildContext context) {
    if (snapshot.dataSource == SituationDataSource.publicReplay) {
      return const AppSectionCard(
        title: '决策边界',
        subtitle: '公开输入驱动的数字孪生证据。',
        leading: Icon(Icons.rule_outlined),
        child: Text(
          '当前没有可验证的实时港口风险标签和现场执行权限。候选只能进入人工复核与干跑审计；生产动作必须经过独立白名单、约束检查和异人确认。',
        ),
      );
    }
    final theme = Theme.of(context);
    final boundary = _boundarySummary(snapshot);
    final inputs = _inputSummary(snapshot);

    return AppSectionCard(
      title: '决策边界',
      subtitle: '当前余量与人工确认条件。',
      leading: const Icon(Icons.rule_outlined),
      trailing: AppSeverityTag(
        label: boundary.label,
        level: boundary.level,
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            boundary.headline,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            boundary.detail,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSeverityTag(
                  label: inputs.label,
                  level: inputs.level,
                  compact: true,
                ),
                const SizedBox(height: 7),
                Text(
                  inputs.note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppSeverityTag(
                label: inputs.delayLabel,
                level: inputs.delayLevel,
                icon: Icons.schedule_outlined,
                compact: true,
              ),
              AppSeverityTag(
                label: inputs.inputLabel,
                level: inputs.inputLevel,
                icon: Icons.input_outlined,
                compact: true,
              ),
              AppSeverityTag(
                label: boundary.edgeLabel,
                level: boundary.level,
                icon: Icons.warning_amber_outlined,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onGoStrategy,
              icon: const Icon(Icons.alt_route),
              label: const Text('查看策略'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendProjectionCard extends StatelessWidget {
  const _TrendProjectionCard({
    required this.points,
    required this.businessEvidence,
  });

  final List<double> points;
  final bool businessEvidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = _normalize(points);

    return AppSectionCard(
      title: businessEvidence ? '逐日测试序列' : '历史密度序列',
      subtitle: businessEvidence
          ? '完整UTC日的待泊时间改善率 · 非实时趋势'
          : '后端返回的最近观测点 · 非未来预测',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            businessEvidence ? '待泊时间改善率' : '交通密度历史点',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (normalized.isEmpty)
            const Text('接口未返回历史密度点，本页不生成替代曲线。')
          else
            SizedBox(
              height: 88,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < normalized.length; i++) ...[
                    Expanded(
                      child: _TrendBar(
                        heightFactor: normalized[i],
                        label: i == normalized.length - 1
                            ? (businessEvidence ? '末日' : '当前')
                            : (businessEvidence
                                  ? '-${normalized.length - 1 - i}d'
                                  : '-${(normalized.length - 1 - i) * 5}m'),
                      ),
                    ),
                    if (i != normalized.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  static List<double> _normalize(List<double> input) {
    if (input.isEmpty) return const [];
    final minValue = input.reduce((a, b) => a < b ? a : b);
    final maxValue = input.reduce((a, b) => a > b ? a : b);
    final span = maxValue - minValue;
    if (span <= 0.0001) {
      return List<double>.filled(input.length, 0.5);
    }
    return input.map((e) => ((e - minValue) / span).clamp(0.1, 1.0)).toList();
  }
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({required this.heightFactor, required this.label});

  final double heightFactor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = 18 + 44 * heightFactor;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _SituationLoadingBlock extends StatelessWidget {
  const _SituationLoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AppLoadingCard(title: '态势加载中', subtitle: '正在获取最新状态与风险证据…'),
        SizedBox(height: 12),
        _PlaceholderCard(height: 128),
        SizedBox(height: 12),
        _PlaceholderCard(height: 216),
        SizedBox(height: 12),
        _PlaceholderCard(height: 146),
      ],
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return AppCard(child: SizedBox(height: height));
  }
}

class _SituationErrorBlock extends StatelessWidget {
  const _SituationErrorBlock({
    required this.error,
    required this.onRetry,
    required this.onGoStrategy,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onGoStrategy;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppErrorCard(
          error: error,
          title: '态势暂时不可用',
          message: '当前可先查看策略焦点，或稍后重试刷新态势。',
          retryLabel: '重试',
          onRetry: onRetry,
          leadingIcon: Icons.cloud_off,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onGoStrategy,
            icon: const Icon(Icons.alt_route),
            label: const Text('查看焦点策略'),
          ),
        ),
      ],
    );
  }
}

class _FreshnessSummary {
  const _FreshnessSummary({
    required this.modeLabel,
    required this.modeLevel,
    required this.modeIcon,
    required this.ageLabel,
    required this.ageLevel,
  });

  final String modeLabel;
  final AppSeverityLevel modeLevel;
  final IconData modeIcon;
  final String ageLabel;
  final AppSeverityLevel ageLevel;
}

class _EvidenceSummary {
  const _EvidenceSummary({
    required this.label,
    required this.level,
    required this.headline,
    required this.detail,
  });

  final String label;
  final AppSeverityLevel level;
  final String headline;
  final String detail;
}

class _BoundarySummary {
  const _BoundarySummary({
    required this.label,
    required this.level,
    required this.headline,
    required this.detail,
    required this.edgeLabel,
  });

  final String label;
  final AppSeverityLevel level;
  final String headline;
  final String detail;
  final String edgeLabel;
}

class _InputSummary {
  const _InputSummary({
    required this.label,
    required this.level,
    required this.note,
    required this.delayLabel,
    required this.delayLevel,
    required this.inputLabel,
    required this.inputLevel,
  });

  final String label;
  final AppSeverityLevel level;
  final String note;
  final String delayLabel;
  final AppSeverityLevel delayLevel;
  final String inputLabel;
  final AppSeverityLevel inputLevel;
}

_FreshnessSummary _freshnessSummary(
  DateTime refreshAt,
  SituationDataSource dataSource,
) {
  final ageSeconds = DateTime.now().difference(refreshAt).inSeconds;
  final isLive = dataSource == SituationDataSource.live;
  final isDemo = dataSource == SituationDataSource.publicReplay;

  final modeLabel = isLive
      ? '实时视图'
      : isDemo
      ? '历史回放'
      : '缓存视图';
  final modeLevel = isLive
      ? AppSeverityLevel.info
      : isDemo
      ? AppSeverityLevel.neutral
      : AppSeverityLevel.watch;
  final modeIcon = isLive
      ? Icons.wifi_tethering
      : isDemo
      ? Icons.science_outlined
      : Icons.history;

  if (ageSeconds <= 30) {
    return _FreshnessSummary(
      modeLabel: modeLabel,
      modeLevel: modeLevel,
      modeIcon: modeIcon,
      ageLabel: '刚刚刷新',
      ageLevel: AppSeverityLevel.success,
    );
  }
  if (ageSeconds <= 180) {
    return _FreshnessSummary(
      modeLabel: modeLabel,
      modeLevel: modeLevel,
      modeIcon: modeIcon,
      ageLabel: '${ageSeconds}s 前刷新',
      ageLevel: AppSeverityLevel.neutral,
    );
  }
  final ageMinutes = (ageSeconds / 60).floor();
  return _FreshnessSummary(
    modeLabel: modeLabel,
    modeLevel: modeLevel,
    modeIcon: modeIcon,
    ageLabel: '$ageMinutes min 前刷新',
    ageLevel: ageMinutes >= 10
        ? AppSeverityLevel.watch
        : AppSeverityLevel.neutral,
  );
}

_EvidenceSummary _evidenceSummary(SituationSnapshot snapshot) {
  if (snapshot.dataSource == SituationDataSource.cache) {
    return const _EvidenceSummary(
      label: '缓存副本',
      level: AppSeverityLevel.watch,
      headline: '当前显示最后一次可读快照。',
      detail: '缓存可用于界面连续性，不应替代最新后端响应或生产决策依据。',
    );
  }
  if (snapshot.dataSource == SituationDataSource.publicReplay) {
    return const _EvidenceSummary(
      label: '公开历史回放',
      level: AppSeverityLevel.neutral,
      headline: '来源、时间范围和数据哈希可追溯。',
      detail: '这说明数据证据可复现，不代表现场实时性、推荐置信度或生产效果。',
    );
  }
  return const _EvidenceSummary(
    label: '已验证现场网关',
    level: AppSeverityLevel.success,
    headline: '快照来自部署方声明并验证的现场数据网关。',
    detail: '仍需结合字段质量、延迟、权限和现场安全联锁；本标签不是模型置信度。',
  );
}

_BoundarySummary _boundarySummary(SituationSnapshot snapshot) {
  if (snapshot.constraintHeadroom <= 8) {
    return const _BoundarySummary(
      label: '边界贴近上限',
      level: AppSeverityLevel.critical,
      headline: '当前必须人工确认，原因是边界余量已经很薄。',
      detail: '继续自动推进时，最先可能撞到的是作业边界余量；这类状态不适合只按单点推荐自动执行。',
      edgeLabel: '先撞边界余量',
    );
  }
  if (snapshot.riskIntervalHigh >= 80) {
    return _BoundarySummary(
      label: snapshot.dataSource == SituationDataSource.live
          ? '风险上沿偏高'
          : '派生风险偏高',
      level: AppSeverityLevel.critical,
      headline: '当前建议可看，但先要把高位风险说清楚。',
      detail: snapshot.dataSource == SituationDataSource.live
          ? '继续自动推进时，最先容易越界的是风险上沿；建议先人工确认再决定是否触发重规划。'
          : '该值来自历史 AIS 聚合行的确定性公式，不是未来预测；只用于沙箱人工审阅。',
      edgeLabel: snapshot.dataSource == SituationDataSource.live
          ? '先撞风险上沿'
          : '历史派生点值',
    );
  }
  if (snapshot.strategyPressure >= 60) {
    return const _BoundarySummary(
      label: '压力持续抬升',
      level: AppSeverityLevel.watch,
      headline: '当前更适合人在环盯盘推进。',
      detail: '不是不能推进，而是调度压力在升高，建议把确认动作和后续留痕放在一起看。',
      edgeLabel: '先撞调度压力',
    );
  }
  return const _BoundarySummary(
    label: '边界仍有余量',
    level: AppSeverityLevel.success,
    headline: '当前仍以观察为主，人工确认压力较低。',
    detail: '主要约束尚未逼近上限；该规则摘要只用于触发人工审阅，不代表策略有效性。',
    edgeLabel: '暂无明显越界点',
  );
}

_InputSummary _inputSummary(SituationSnapshot snapshot) {
  if (snapshot.dataSource == SituationDataSource.cache) {
    return const _InputSummary(
      label: '缓存输入',
      level: AppSeverityLevel.watch,
      note: '当前为缓存视图，只用于界面连续性，不作为最新状态或策略效果依据。',
      delayLabel: '链路延迟偏高',
      delayLevel: AppSeverityLevel.watch,
      inputLabel: '实时输入暂缺',
      inputLevel: AppSeverityLevel.watch,
    );
  }
  if (snapshot.dataSource == SituationDataSource.publicReplay) {
    return const _InputSummary(
      label: '公开历史回放',
      level: AppSeverityLevel.neutral,
      note: '当前读取公开历史 AIS 聚合结果，不代表生产港口实时状态。',
      delayLabel: '历史时间戳',
      delayLevel: AppSeverityLevel.neutral,
      inputLabel: '匿名 AIS 聚合',
      inputLevel: AppSeverityLevel.info,
    );
  }
  if (snapshot.constraintHeadroom <= 8 || snapshot.riskIntervalHigh >= 80) {
    return const _InputSummary(
      label: '已验证输入 · 高风险边界',
      level: AppSeverityLevel.critical,
      note: '现场网关快照中的边界值偏高；规则只要求人工确认，不给出模型置信度。',
      delayLabel: '现场快照已读取',
      delayLevel: AppSeverityLevel.success,
      inputLabel: '合同字段已解析',
      inputLevel: AppSeverityLevel.success,
    );
  }
  if (snapshot.strategyPressure >= 60 || snapshot.riskIntervalHigh >= 60) {
    return const _InputSummary(
      label: '已验证输入 · 风险抬升',
      level: AppSeverityLevel.watch,
      note: '现场网关快照中的风险值抬升；规则只要求人工盯盘，不给出模型置信度。',
      delayLabel: '现场快照已读取',
      delayLevel: AppSeverityLevel.success,
      inputLabel: '合同字段已解析',
      inputLevel: AppSeverityLevel.success,
    );
  }
  return const _InputSummary(
    label: '已验证输入 · 风险较低',
    level: AppSeverityLevel.success,
    note: '现场网关快照中的风险值较低；仍需人工与现场安全联锁，不给出模型置信度。',
    delayLabel: '现场快照已读取',
    delayLevel: AppSeverityLevel.success,
    inputLabel: '合同字段已解析',
    inputLevel: AppSeverityLevel.success,
  );
}

String _formatTime(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  final ss = dt.second.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

String _actionBridge(SituationSnapshot snapshot) {
  switch (snapshot.stabilityLevel) {
    case SituationStabilityLevel.stable:
      return '当前可继续观察，并查看推荐策略。';
    case SituationStabilityLevel.watch:
      return '建议进入策略页进行人工确认。';
    case SituationStabilityLevel.critical:
      return '建议优先查看策略并确认后续动作。';
  }
}

String _caution(SituationSnapshot snapshot) {
  if (snapshot.constraintHeadroom <= 8) {
    return '当前边界余量较薄，不适合无确认自动推进。';
  }
  if (snapshot.riskIntervalHigh >= 80) {
    return snapshot.dataSource == SituationDataSource.live
        ? '现场网关风险上沿已偏高，后续动作建议留痕。'
        : '历史 AIS 派生风险指标偏高，后续动作仅作沙箱审阅。';
  }
  return '';
}

String _riskNote(SituationSnapshot snapshot) {
  if (snapshot.dataSource != SituationDataSource.live) {
    return '该点值由当前历史 AIS 聚合行按公开环境公式派生，不是未来预测或置信区间。';
  }
  if (snapshot.riskIntervalHigh >= 85) {
    return '高位风险区间，建议人工确认后再触发重规划。';
  }
  if (snapshot.riskIntervalHigh >= 60) {
    return '风险正在抬升，建议保持现有策略集并准备干预。';
  }
  return '当前风险区间处于低至中段，可继续观察。';
}

String _headlineLabel(SituationStabilityLevel level) {
  switch (level) {
    case SituationStabilityLevel.stable:
      return '指标稳定';
    case SituationStabilityLevel.watch:
      return '需要保持盯盘';
    case SituationStabilityLevel.critical:
      return '已接近临界';
  }
}

String _headlineShort(SituationStabilityLevel level) {
  switch (level) {
    case SituationStabilityLevel.stable:
      return '稳定';
    case SituationStabilityLevel.watch:
      return '观察';
    case SituationStabilityLevel.critical:
      return '临界';
  }
}

IconData _headlineIcon(SituationStabilityLevel level) {
  switch (level) {
    case SituationStabilityLevel.stable:
      return Icons.verified_outlined;
    case SituationStabilityLevel.watch:
      return Icons.visibility_outlined;
    case SituationStabilityLevel.critical:
      return Icons.warning_amber_outlined;
  }
}

AppSeverityLevel _severityFrom(SituationStabilityLevel level) {
  switch (level) {
    case SituationStabilityLevel.stable:
      return AppSeverityLevel.success;
    case SituationStabilityLevel.watch:
      return AppSeverityLevel.watch;
    case SituationStabilityLevel.critical:
      return AppSeverityLevel.critical;
  }
}

String _pressureLabel(int value) {
  if (value >= 75) return '高';
  if (value >= 50) return '偏高';
  return '';
}

String _constraintLabel(int value) {
  if (value <= 8) return '薄';
  if (value <= 15) return '偏紧';
  return '';
}

String _riskHeadline(int high) {
  if (high >= 80) return '高';
  if (high >= 60) return '抬升';
  return '';
}

AppSeverityLevel _riskSeverity(int high) {
  if (high >= 80) return AppSeverityLevel.critical;
  if (high >= 60) return AppSeverityLevel.watch;
  return AppSeverityLevel.success;
}

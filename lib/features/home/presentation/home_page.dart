import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/app.dart';
import 'package:dt_mobile_app/features/alerts/application/alerts_controller.dart';
import 'package:dt_mobile_app/features/alerts/presentation/alerts_page.dart';
import 'package:dt_mobile_app/features/audit/application/audit_controller.dart';
import 'package:dt_mobile_app/features/audit/presentation/audit_page.dart';
import 'package:dt_mobile_app/features/demo/application/demo_flow_controller.dart';
import 'package:dt_mobile_app/features/home/application/shared_system_evidence_controller.dart';
import 'package:dt_mobile_app/features/notifications/application/notification_controller.dart';
import 'package:dt_mobile_app/features/notifications/presentation/notification_page.dart';
import 'package:dt_mobile_app/features/situation/presentation/situation_page.dart';
import 'package:dt_mobile_app/features/strategy/application/strategy_controller.dart';
import 'package:dt_mobile_app/features/strategy/presentation/strategy_page.dart';
import 'package:dt_mobile_app/features/xiaoyi/presentation/xiaoyi_leadership_panel.dart';

import '../application/home_tab_notifier.dart';

class HomeShellPage extends ConsumerStatefulWidget {
  const HomeShellPage({super.key});

  @override
  ConsumerState<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends ConsumerState<HomeShellPage> {
  static const double _xiaoyiLauncherSize = 64;
  static const double _xiaoyiLauncherMargin = 12;

  Offset? _xiaoyiLauncherOffset;
  late final ValueNotifier<_SharedFocusState> _sharedFocusNotifier;

  @override
  void initState() {
    super.initState();
    _sharedFocusNotifier = ValueNotifier<_SharedFocusState>(
      const _SharedFocusState.empty(),
    );
  }

  @override
  void dispose() {
    _sharedFocusNotifier.dispose();
    super.dispose();
  }

  void _updateSharedFocus(_SharedFocusState next) {
    if (_sharedFocusNotifier.value == next) return;
    _sharedFocusNotifier.value = next;
  }

  void _openTab(HomeTab tab) {
    ref.read(homeDashboardProvider.notifier).showBusinessTab();
    ref.read(homeTabProvider.notifier).selectIndex(HomeTab.values.indexOf(tab));
  }

  void _openXiaoyiHome() {
    ref.read(homeDashboardProvider.notifier).showDashboard();
  }

  Offset _defaultXiaoyiOffset(BoxConstraints constraints) {
    final maxX = math.max(
      _xiaoyiLauncherMargin,
      constraints.maxWidth - _xiaoyiLauncherSize - _xiaoyiLauncherMargin,
    );
    final maxY = math.max(
      _xiaoyiLauncherMargin,
      constraints.maxHeight - _xiaoyiLauncherSize - _xiaoyiLauncherMargin,
    );
    return Offset(maxX, maxY);
  }

  Offset _clampXiaoyiOffset(Offset offset, BoxConstraints constraints) {
    final maxX = math.max(
      _xiaoyiLauncherMargin,
      constraints.maxWidth - _xiaoyiLauncherSize - _xiaoyiLauncherMargin,
    );
    final maxY = math.max(
      _xiaoyiLauncherMargin,
      constraints.maxHeight - _xiaoyiLauncherSize - _xiaoyiLauncherMargin,
    );
    return Offset(
      offset.dx.clamp(_xiaoyiLauncherMargin, maxX).toDouble(),
      offset.dy.clamp(_xiaoyiLauncherMargin, maxY).toDouble(),
    );
  }

  void _moveXiaoyiLauncher(
    DragUpdateDetails details,
    BoxConstraints constraints,
  ) {
    final next =
        (_xiaoyiLauncherOffset ?? _defaultXiaoyiOffset(constraints)) +
        details.delta;
    setState(
      () => _xiaoyiLauncherOffset = _clampXiaoyiOffset(next, constraints),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(homeTabProvider);
    final unreadAlertsAsync = ref.watch(unreadAlertsCountProvider);
    final unreadNotifications = ref.watch(unreadNotificationsCountProvider);
    final demoFlow = ref.watch(demoFlowProvider);
    final showDashboard = ref.watch(homeDashboardProvider);
    final theme = Theme.of(context);

    final String? alertsBadgeText = unreadAlertsAsync.when(
      data: (count) => count > 0 ? (count > 99 ? '99+' : '$count') : null,
      loading: () => '…',
      error: (error, stackTrace) => '!',
    );

    final String? notificationsBadgeText = unreadNotifications > 0
        ? (unreadNotifications > 99 ? '99+' : '$unreadNotifications')
        : null;

    final selectedNavIndex = showDashboard
        ? 0
        : HomeTab.values.indexOf(tab) + 1;

    final bodyContent = showDashboard
        ? SafeArea(
            top: false,
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              children: [
                _OperationsCockpit(
                  activeTab: tab,
                  onOpenTab: _openTab,
                  onUpdateSharedFocus: _updateSharedFocus,
                ),
              ],
            ),
          )
        : IndexedStack(
            index: HomeTab.values.indexOf(tab),
            children: const [
              SituationPage(),
              StrategyPage(),
              AlertsPage(),
              AuditPage(),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '港口运营决策',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _SharedFocusBanner(
              notifier: _sharedFocusNotifier,
              onOpenTab: _openTab,
              demoFlow: demoFlow,
            ),
          ),
        ),
        actions: [
          const _ConnectionBadge(),
          const SizedBox(width: 6),
          _NotificationBellButton(
            badgeText: notificationsBadgeText,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationPage(),
                ),
              );
            },
          ),
          const SizedBox(width: 2),
          _TopMenu(
            onOpenAuth: () => Navigator.of(context).pushNamed(routeAuth),
            onOpenSettings: () =>
                Navigator.of(context).pushNamed(routeSettings),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final launcherOffset = _clampXiaoyiOffset(
            _xiaoyiLauncherOffset ?? _defaultXiaoyiOffset(constraints),
            constraints,
          );

          return Stack(
            children: [
              Positioned.fill(child: bodyContent),
              Positioned(
                left: launcherOffset.dx,
                top: launcherOffset.dy,
                child: _DraggableXiaoyiLauncher(
                  size: _xiaoyiLauncherSize,
                  onTap: _openXiaoyiHome,
                  onLongPress: () => setState(() {
                    _xiaoyiLauncherOffset = _defaultXiaoyiOffset(constraints);
                  }),
                  onPanUpdate: (details) =>
                      _moveXiaoyiLauncher(details, constraints),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedNavIndex,
        onDestinationSelected: (index) {
          if (index == 0) {
            ref.read(homeDashboardProvider.notifier).showDashboard();
            return;
          }
          _openTab(HomeTab.values[index - 1]);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: '首页',
          ),
          for (final t in HomeTab.values)
            NavigationDestination(
              icon: _NavIconWithBadge(
                icon: t.icon,
                badgeText: t == HomeTab.alerts ? alertsBadgeText : null,
              ),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

class _DraggableXiaoyiLauncher extends StatelessWidget {
  const _DraggableXiaoyiLauncher({
    required this.size,
    required this.onTap,
    required this.onLongPress,
    required this.onPanUpdate,
  });

  final double size;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final GestureDragUpdateCallback onPanUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: '可拖动的小懿精灵入口',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        onPanUpdate: onPanUpdate,
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surface.withValues(alpha: 0.96),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.24),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          scheme.primaryContainer.withValues(alpha: 0.42),
                          scheme.surface.withValues(alpha: 0.10),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: Icon(
                    Icons.hub_rounded,
                    color: scheme.primary,
                    size: 44,
                    semanticLabel: '小懿协同助手',
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF34D399),
                      border: Border.all(color: scheme.surface, width: 1.5),
                    ),
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

class _OperationsCockpit extends ConsumerStatefulWidget {
  const _OperationsCockpit({
    required this.activeTab,
    required this.onOpenTab,
    required this.onUpdateSharedFocus,
  });

  final HomeTab activeTab;
  final ValueChanged<HomeTab> onOpenTab;
  final ValueChanged<_SharedFocusState> onUpdateSharedFocus;

  @override
  ConsumerState<_OperationsCockpit> createState() => _OperationsCockpitState();
}

class _OperationsCockpitState extends ConsumerState<_OperationsCockpit> {
  int _sceneIndex = 0;

  static const List<String> _sceneLabels = <String>['单港运行', '东一码头', '多港联动'];

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(alertsSnapshotProvider);
    final strategyState = ref.watch(strategyControllerProvider);
    final auditTimeline = ref.watch(auditTimelineProvider);
    final notificationState = ref.watch(notificationCenterProvider);
    final demoFlow = ref.watch(demoFlowProvider);
    final sharedEvidence = ref.watch(sharedSystemEvidenceProvider);

    final vm = _OverviewViewModel.from(
      alertsAsync: alertsAsync,
      strategyState: strategyState,
      auditTimeline: auditTimeline,
      notificationState: notificationState,
    );

    final sharedFocus = demoFlow.isRunning
        ? _sharedFocusForDemo(demoFlow.stage)
        : vm.sharedFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onUpdateSharedFocus(sharedFocus);
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xE60D203D), Color(0xE608162C), Color(0xE6050E1E)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.10),
                blurRadius: 30,
                spreadRadius: -10,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '运营总控首页',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _StatusPill(
                    icon: vm.statusIcon,
                    label: vm.statusLabel,
                    kind: vm.statusKind,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _sceneLabels.length; i++)
                    _SceneSwitchChip(
                      label: _sceneLabels[i],
                      selected: _sceneIndex == i,
                      onTap: () => setState(() => _sceneIndex = i),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (demoFlow.enabled)
                _DemoDirectorCard(
                  state: demoFlow,
                  onStart: () => ref.read(demoFlowProvider.notifier).start(),
                  onAdvance: () =>
                      ref.read(demoFlowProvider.notifier).advance(),
                  onRestart: () =>
                      ref.read(demoFlowProvider.notifier).restart(),
                  onOpenTarget: () => widget.onOpenTab(
                    HomeTab.values[demoFlow.stage.targetTabIndex],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xB8071225),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.17),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vm.headline,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _PrimaryActionCard(
                        icon: vm.primaryActionIcon,
                        title: vm.primaryActionLabel,
                        onTap: () => widget.onOpenTab(vm.primaryActionTab),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: '高优告警',
                      value: '${vm.criticalAlerts}',
                      icon: Icons.crisis_alert_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricCard(
                      label: '执行在途',
                      value: '${vm.pendingExecutions}',
                      icon: Icons.psychology_alt_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricCard(
                      label: '异常资产',
                      value: '${vm.abnormalAssets}',
                      icon: Icons.precision_manufacturing_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _SharedSystemEvidenceCard(evidence: sharedEvidence),
              const SizedBox(height: 10),
              XiaoyiLeadershipPanel(onOpenTab: widget.onOpenTab),
              const SizedBox(height: 10),
              _KeyEventCard(
                title: vm.keyEventTitle,
                detail: vm.keyEventDetail,
                sceneLabel: _sceneLabels[_sceneIndex],
              ),
              const SizedBox(height: 10),
              _ScenarioPackagingSection(
                scenarios: _buildScenarioCards(vm),
                onOpenTab: widget.onOpenTab,
              ),
              Card(
                margin: EdgeInsets.zero,
                child: ExpansionTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('数据来源'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        vm.dataLine,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharedSystemEvidenceCard extends StatelessWidget {
  const _SharedSystemEvidenceCard({required this.evidence});

  final AsyncValue<SharedSystemEvidence> evidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xB8071A27),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF76F7C5).withValues(alpha: 0.28),
        ),
      ),
      child: evidence.when(
        loading: () => const Row(
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 9),
            Text('正在核验 Web / 移动端共享后端证据…'),
          ],
        ),
        error: (error, stackTrace) => Text(
          '共享后端证据不可用：$error',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        data: (value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: Color(0xFF76F7C5),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '双端共享后端 · ${value.backendId}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  value.auditChainValid ? '证据链有效' : '证据链异常',
                  style: TextStyle(
                    color: value.auditChainValid
                        ? const Color(0xFF76F7C5)
                        : theme.colorScheme.error,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '整套系统固定留出集（${value.datasetId} · ${value.testRows}步）：'
              '泊位利用率 +${value.berthPointGain.toStringAsFixed(2)} 个百分点'
              '（相对 +${value.berthImprovementPercent.toStringAsFixed(0)}%） / '
              '待泊时间 -${value.waitReductionPercent.toStringAsFixed(0)}% / '
              '情景用电成本 -${value.costReductionPercent.toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 5),
            Text(
              '移动闭环 ${value.workflowOperations} 项固定集成操作：'
              '重复提交抑制 ${value.duplicateSuppressionPercent.toStringAsFixed(0)}% / '
              '越权生产下发阻断 ${value.unsafeDispatchBlockPercent.toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '边界：前者是数字孪生离线收益，后者是本地接口可靠性；均非港口实测 SLA。',
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFFFFD08A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

_SharedFocusState _sharedFocusForDemo(DemoFlowStage stage) {
  final tab = HomeTab.values[stage.targetTabIndex];
  final icon = switch (stage) {
    DemoFlowStage.ready ||
    DemoFlowStage.stable ||
    DemoFlowStage.boundary => Icons.monitor_heart_outlined,
    DemoFlowStage.alert => Icons.warning_amber_rounded,
    DemoFlowStage.strategy ||
    DemoFlowStage.executing => Icons.psychology_alt_outlined,
    DemoFlowStage.audit => Icons.history_toggle_off_outlined,
  };
  return _SharedFocusState(
    typeLabel: '界面讲解 ${stage.timeLabel}',
    title: stage.headline,
    subtitle: stage.narrative,
    tab: tab,
    icon: icon,
  );
}

class _DemoDirectorCard extends StatelessWidget {
  const _DemoDirectorCard({
    required this.state,
    required this.onStart,
    required this.onAdvance,
    required this.onRestart,
    required this.onOpenTarget,
  });

  final DemoFlowState state;
  final VoidCallback onStart;
  final VoidCallback onAdvance;
  final VoidCallback onRestart;
  final VoidCallback onOpenTarget;

  String get _targetLabel => switch (state.stage) {
    DemoFlowStage.ready ||
    DemoFlowStage.stable ||
    DemoFlowStage.boundary => '打开态势',
    DemoFlowStage.alert => '打开告警',
    DemoFlowStage.strategy || DemoFlowStage.executing => '打开策略',
    DemoFlowStage.audit => '打开审计',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102E4C), Color(0xFF15366C), Color(0xFF30215F)],
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.46)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4DE4FF).withValues(alpha: 0.14),
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
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                child: const Icon(
                  Icons.movie_filter_outlined,
                  color: Color(0xFF76F7C5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '界面讲解导航',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '态势 × 告警 × RL × 小懿 × 审计',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF9DC8F8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                icon: state.isComplete
                    ? Icons.task_alt_rounded
                    : Icons.play_circle_outline_rounded,
                label: state.stage.timeLabel,
                kind: state.isComplete ? _StatusKind.ok : _StatusKind.info,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            state.stage.headline,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            state.stage.narrative,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFC4D8F3),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _DemoStageRail(stage: state.stage),
          if (state.isComplete) ...[
            const SizedBox(height: 12),
            const _DemoClosureOutcome(),
          ],
          const SizedBox(height: 13),
          if (!state.isRunning)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('开始界面讲解'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenTarget,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(_targetLabel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: state.isComplete
                      ? FilledButton.icon(
                          onPressed: onRestart,
                          icon: const Icon(Icons.replay_rounded),
                          label: const Text('重新开始界面讲解'),
                        )
                      : FilledButton.icon(
                          onPressed: state.canAdvanceManually
                              ? onAdvance
                              : null,
                          icon: Icon(
                            state.stage == DemoFlowStage.executing
                                ? Icons.sync_rounded
                                : Icons.skip_next_rounded,
                          ),
                          label: Text(state.stage.nextActionLabel),
                        ),
                ),
              ],
            ),
          if (state.isRunning && !state.isComplete) ...[
            const SizedBox(height: 6),
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

class _DemoClosureOutcome extends StatelessWidget {
  const _DemoClosureOutcome();

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF76F7C5);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xB8071A27),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: -7,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_rounded, color: accent, size: 19),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  '界面讲解已完成 · 未改变业务状态',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '请以页面中的后端状态、数据哈希、测试产物和审计上传结果为准；讲解轨道本身不是业务证据。',
            style: TextStyle(
              color: Color(0xFFC4D8F3),
              fontSize: 10,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              const Expanded(
                child: _DemoOutcomeMetric(
                  label: '数据状态',
                  before: '不修改',
                  after: '看接口',
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: _DemoOutcomeMetric(
                  label: '训练状态',
                  before: '不模拟',
                  after: '看 worker',
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: _DemoOutcomeMetric(
                  label: '执行状态',
                  before: '不伪造',
                  after: '看回执',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DemoOutcomeMetric extends StatelessWidget {
  const _DemoOutcomeMetric({
    required this.label,
    required this.before,
    required this.after,
  });

  final String label;
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF9DC8F8),
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$before  ',
                    style: const TextStyle(color: Color(0xFF7894BD)),
                  ),
                  const TextSpan(
                    text: '→ ',
                    style: TextStyle(color: Color(0xFF4DE4FF)),
                  ),
                  TextSpan(
                    text: after,
                    style: const TextStyle(
                      color: Color(0xFF76F7C5),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoStageRail extends StatelessWidget {
  const _DemoStageRail({required this.stage});

  final DemoFlowStage stage;

  @override
  Widget build(BuildContext context) {
    const stages = <DemoFlowStage>[
      DemoFlowStage.stable,
      DemoFlowStage.boundary,
      DemoFlowStage.alert,
      DemoFlowStage.strategy,
      DemoFlowStage.executing,
      DemoFlowStage.audit,
    ];
    return Row(
      children: [
        for (var index = 0; index < stages.length; index++) ...[
          _DemoStageDot(
            label: stages[index].shortLabel,
            active:
                stage != DemoFlowStage.ready &&
                stage.index >= stages[index].index,
            current: stage == stages[index],
          ),
          if (index != stages.length - 1)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                height: 2,
                color: stage.index > stages[index].index
                    ? const Color(0xFF76F7C5)
                    : const Color(0xFF3C5378),
              ),
            ),
        ],
      ],
    );
  }
}

class _DemoStageDot extends StatelessWidget {
  const _DemoStageDot({
    required this.label,
    required this.active,
    required this.current,
  });

  final String label;
  final bool active;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF76F7C5) : const Color(0xFF6F89B1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: current ? 13 : 10,
          height: current ? 13 : 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : const Color(0xFF152844),
            border: Border.all(color: color),
            boxShadow: current
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.50),
                      blurRadius: 9,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: current ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SceneSwitchChip extends StatelessWidget {
  const _SceneSwitchChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

List<_ScenarioCardVm> _buildScenarioCards(_OverviewViewModel vm) {
  return [
    _ScenarioCardVm(
      title: '异常拥堵处置',
      summary: vm.criticalAlerts > 0
          ? '当前有 ${vm.criticalAlerts} 条高优告警，先定位拥堵点，再进入候选策略确认。'
          : '当前显示后端回传状态；界面讲解不会修改告警或风险。',
      evidence: vm.criticalAlerts > 0 ? '先去告警，再带入策略。' : '当前可直接讲标准处置闭环。',
      icon: Icons.traffic_outlined,
      tab: HomeTab.alerts,
      cta: '从告警开始',
    ),
    _ScenarioCardVm(
      title: '人工确认执行',
      summary: vm.pendingExecutions > 0
          ? '当前有 ${vm.pendingExecutions} 条执行在途，适合展示人工确认、回执盯盘与边界接管。'
          : '当前没有执行阻塞；策略页会明确区分 dry-run 与适配器回执。',
      evidence: vm.pendingExecutions > 0 ? '先盯回执，再去审计留痕。' : '先去策略页确认一条方案。',
      icon: Icons.rule_folder_outlined,
      tab: HomeTab.strategy,
      cta: '去策略确认',
    ),
    _ScenarioCardVm(
      title: '事后追责复盘',
      summary: vm.auditCount > 0
          ? '当前已有 ${vm.auditCount} 条留痕，可直接展示审计复核、执行回执与回放复盘。'
          : '当前留痕较少，先完成一次确认执行后再进入复盘故事线。',
      evidence: vm.auditHint,
      icon: Icons.fact_check_outlined,
      tab: HomeTab.audit,
      cta: '去审计复盘',
    ),
  ];
}

class _ScenarioPackagingSection extends StatelessWidget {
  const _ScenarioPackagingSection({
    required this.scenarios,
    required this.onOpenTab,
  });

  final List<_ScenarioCardVm> scenarios;
  final ValueChanged<HomeTab> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surface,
      child: ExpansionTile(
        leading: const Icon(Icons.workspaces_outline),
        title: Text(
          '更多业务入口',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          for (var i = 0; i < scenarios.length; i++) ...[
            _ScenarioStoryCard(
              vm: scenarios[i],
              onTap: () => onOpenTab(scenarios[i].tab),
            ),
            if (i != scenarios.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _ScenarioStoryCard extends StatelessWidget {
  const _ScenarioStoryCard({required this.vm, required this.onTap});

  final _ScenarioCardVm vm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  vm.icon,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vm.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vm.summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            vm.evidence,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(vm.cta),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenarioCardVm {
  const _ScenarioCardVm({
    required this.title,
    required this.summary,
    required this.evidence,
    required this.icon,
    required this.tab,
    required this.cta,
  });

  final String title;
  final String summary;
  final String evidence;
  final IconData icon;
  final HomeTab tab;
  final String cta;
}

class _KeyEventCard extends StatelessWidget {
  const _KeyEventCard({
    required this.title,
    required this.detail,
    required this.sceneLabel,
  });

  final String title;
  final String detail;
  final String sceneLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xCC10213D), Color(0xCC071225)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.bolt_rounded,
              size: 18,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '最近关键事件 · $sceneLabel',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewViewModel {
  const _OverviewViewModel({
    required this.headline,
    required this.subline,
    required this.statusLabel,
    required this.statusIcon,
    required this.statusKind,
    required this.criticalAlerts,
    required this.pendingExecutions,
    required this.unreadNotifications,
    required this.auditCount,
    required this.auditHint,
    required this.abnormalAssets,
    required this.keyEventTitle,
    required this.keyEventDetail,
    required this.dataLine,
    required this.compactSummary,
    required this.primaryActionLabel,
    required this.primaryActionHint,
    required this.primaryActionIcon,
    required this.primaryActionTab,
    required this.sharedFocus,
  });

  final String headline;
  final String subline;
  final String statusLabel;
  final IconData statusIcon;
  final _StatusKind statusKind;
  final int criticalAlerts;
  final int pendingExecutions;
  final int unreadNotifications;
  final int auditCount;
  final String auditHint;
  final int abnormalAssets;
  final String keyEventTitle;
  final String keyEventDetail;
  final String dataLine;
  final String compactSummary;
  final String primaryActionLabel;
  final String primaryActionHint;
  final IconData primaryActionIcon;
  final HomeTab primaryActionTab;
  final _SharedFocusState sharedFocus;

  factory _OverviewViewModel.from({
    required AsyncValue<AlertsSnapshot> alertsAsync,
    required StrategyControllerState strategyState,
    required AuditTimeline auditTimeline,
    required NotificationCenterState notificationState,
  }) {
    final AlertsSnapshot snapshot = alertsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => AlertsSnapshot.empty,
    );

    final criticalAlerts = snapshot.items
        .where((item) => item.severity == AlertSeverity.critical)
        .length;

    final submission = strategyState.lastSubmission;
    final pendingExecutions = submission == null
        ? 0
        : ((submission.executionStatus == StrategyExecutionStatus.submitted ||
                  submission.executionStatus ==
                      StrategyExecutionStatus.executing)
              ? 1
              : 0);

    final unreadNotifications = notificationState.unreadCount;
    final auditCount = auditTimeline.items.length;
    final abnormalAssets = snapshot.items
        .where((item) => item.severity != AlertSeverity.info)
        .map((item) => item.source)
        .toSet()
        .length;

    final status = _resolveStatus(
      snapshot: snapshot,
      criticalAlerts: criticalAlerts,
      pendingExecutions: pendingExecutions,
    );

    final primaryAction = _primaryAction(
      criticalAlerts: criticalAlerts,
      pendingExecutions: pendingExecutions,
      unreadNotifications: unreadNotifications,
    );

    return _OverviewViewModel(
      headline: _buildHeadline(
        criticalAlerts: criticalAlerts,
        pendingExecutions: pendingExecutions,
        unreadNotifications: unreadNotifications,
      ),
      subline: _buildSubline(
        snapshot: snapshot,
        submission: submission,
        auditTimeline: auditTimeline,
      ),
      statusLabel: status.label,
      statusIcon: status.icon,
      statusKind: status.kind,
      criticalAlerts: criticalAlerts,
      pendingExecutions: pendingExecutions,
      unreadNotifications: unreadNotifications,
      auditCount: auditCount,
      auditHint: auditTimeline.latest == null
          ? '尚无回执留痕'
          : '最近：${_auditActionLabel(auditTimeline.latest!.actionType)}',
      abnormalAssets: abnormalAssets,
      keyEventTitle: _buildKeyEventTitle(
        snapshot: snapshot,
        submission: submission,
        auditTimeline: auditTimeline,
      ),
      keyEventDetail: _buildKeyEventDetail(
        snapshot: snapshot,
        submission: submission,
        auditTimeline: auditTimeline,
      ),
      dataLine: _buildDataLine(
        snapshot: snapshot,
        strategyState: strategyState,
        auditTimeline: auditTimeline,
      ),
      compactSummary:
          '高优 $criticalAlerts · 执行 $pendingExecutions · 通知 $unreadNotifications',
      primaryActionLabel: primaryAction.label,
      primaryActionHint: primaryAction.hint,
      primaryActionIcon: primaryAction.icon,
      primaryActionTab: primaryAction.tab,
      sharedFocus: _buildSharedFocus(
        criticalAlerts: criticalAlerts,
        pendingExecutions: pendingExecutions,
        unreadNotifications: unreadNotifications,
        snapshot: snapshot,
        submission: submission,
        auditTimeline: auditTimeline,
      ),
    );
  }

  static String _buildHeadline({
    required int criticalAlerts,
    required int pendingExecutions,
    required int unreadNotifications,
  }) {
    if (criticalAlerts > 0) {
      return '当前存在高优风险，先从告警进入策略处理';
    }
    if (pendingExecutions > 0) {
      return '当前有策略执行在途，建议优先盯回执';
    }
    if (unreadNotifications > 0) {
      return '整体稳定，但有新动态待确认';
    }
    return '当前整体平稳，可继续巡检策略与审计闭环';
  }

  static String _buildSubline({
    required AlertsSnapshot snapshot,
    required StrategySubmissionSummary? submission,
    required AuditTimeline auditTimeline,
  }) {
    final fragments = <String>[];

    if (snapshot.statusMessage.trim().isNotEmpty) {
      fragments.add(snapshot.statusMessage.trim());
    }

    if (submission != null) {
      fragments.add(
        '最近执行：${submission.policyTitle} · ${submission.executionLabel}',
      );
    }

    if (auditTimeline.latest != null) {
      fragments.add('最近留痕：${auditTimeline.latest!.humanChoiceSummary}');
    }

    if (fragments.isEmpty) {
      return '建议从态势结论进入，再沿告警 → 策略 → 审计完成一次闭环检查。';
    }

    return fragments.take(2).join('  ·  ');
  }

  static _ResolvedStatus _resolveStatus({
    required AlertsSnapshot snapshot,
    required int criticalAlerts,
    required int pendingExecutions,
  }) {
    if (criticalAlerts > 0) {
      return const _ResolvedStatus(
        label: '需干预',
        icon: Icons.priority_high_rounded,
        kind: _StatusKind.warning,
      );
    }

    if (pendingExecutions > 0) {
      return const _ResolvedStatus(
        label: '盯执行',
        icon: Icons.sync_rounded,
        kind: _StatusKind.info,
      );
    }

    if (snapshot.feedMode == AlertsFeedMode.offline) {
      return const _ResolvedStatus(
        label: '等待接入港口',
        icon: Icons.cloud_off_outlined,
        kind: _StatusKind.neutral,
      );
    }

    if (snapshot.connectionStatus == AlertsConnectionStatus.disconnected) {
      return const _ResolvedStatus(
        label: '已断开',
        icon: Icons.cloud_off,
        kind: _StatusKind.danger,
      );
    }

    if (snapshot.connectionStatus == AlertsConnectionStatus.connecting) {
      return const _ResolvedStatus(
        label: '连接中',
        icon: Icons.cloud_sync_outlined,
        kind: _StatusKind.info,
      );
    }

    return const _ResolvedStatus(
      label: '平稳',
      icon: Icons.check_circle_outline,
      kind: _StatusKind.ok,
    );
  }

  static _SharedFocusState _buildSharedFocus({
    required int criticalAlerts,
    required int pendingExecutions,
    required int unreadNotifications,
    required AlertsSnapshot snapshot,
    required StrategySubmissionSummary? submission,
    required AuditTimeline auditTimeline,
  }) {
    if (criticalAlerts > 0 && snapshot.items.isNotEmpty) {
      final top = snapshot.items.first;
      return _SharedFocusState(
        typeLabel: '焦点告警',
        title: top.title,
        subtitle: '存在 $criticalAlerts 条高优告警，建议先进入告警链路。',
        tab: HomeTab.alerts,
        icon: Icons.warning_amber_rounded,
      );
    }

    if (pendingExecutions > 0 && submission != null) {
      return _SharedFocusState(
        typeLabel: '焦点策略',
        title: submission.policyTitle,
        subtitle: '执行仍在进行中，建议继续盯回执与人工确认。',
        tab: HomeTab.strategy,
        icon: Icons.psychology_alt_outlined,
      );
    }

    if (auditTimeline.latest != null) {
      return _SharedFocusState(
        typeLabel: '焦点事件',
        title: _auditActionLabel(auditTimeline.latest!.actionType),
        subtitle: '最近一次关键处置已留痕，可继续做审计复核与回放。',
        tab: HomeTab.audit,
        icon: Icons.history_toggle_off_outlined,
      );
    }

    if (unreadNotifications > 0) {
      return _SharedFocusState(
        typeLabel: '焦点通知',
        title: '有 $unreadNotifications 条通知待确认',
        subtitle: '通知链路仍有未读项，建议先看最新回执与异常提示。',
        tab: HomeTab.alerts,
        icon: Icons.notifications_active_outlined,
      );
    }

    return const _SharedFocusState(
      typeLabel: '焦点态势',
      title: '当前系统无显著阻塞',
      subtitle: '可先巡检态势页，确认数据新鲜度与边界逼近情况。',
      tab: HomeTab.situation,
      icon: Icons.monitor_heart_outlined,
    );
  }

  static _PrimaryAction _primaryAction({
    required int criticalAlerts,
    required int pendingExecutions,
    required int unreadNotifications,
  }) {
    if (criticalAlerts > 0) {
      return const _PrimaryAction(
        label: '从告警进入策略处理',
        hint: '统一路径：先看告警，再到策略确认，最后到审计复核。',
        icon: Icons.crisis_alert_outlined,
        tab: HomeTab.alerts,
      );
    }
    if (pendingExecutions > 0) {
      return const _PrimaryAction(
        label: '去策略盯执行回执',
        hint: '统一路径的中段：在策略页盯执行状态，完成后去审计复核。',
        icon: Icons.auto_mode_outlined,
        tab: HomeTab.strategy,
      );
    }
    if (unreadNotifications > 0) {
      return const _PrimaryAction(
        label: '去审计复核留痕',
        hint: '统一路径的末段：确认本次策略执行是否已完整留痕。',
        icon: Icons.notifications_active_outlined,
        tab: HomeTab.audit,
      );
    }
    return const _PrimaryAction(
      label: '开始一次巡检',
      hint: '从态势结论进入，快速检查今日运行状态。',
      icon: Icons.monitor_heart_outlined,
      tab: HomeTab.situation,
    );
  }

  static String _buildKeyEventTitle({
    required AlertsSnapshot snapshot,
    required StrategySubmissionSummary? submission,
    required AuditTimeline auditTimeline,
  }) {
    final latestCritical = snapshot.items
        .where((item) => item.severity == AlertSeverity.critical)
        .toList();
    latestCritical.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (latestCritical.isNotEmpty) {
      final item = latestCritical.first;
      return '${item.title} · ${item.source}';
    }

    if (submission != null) {
      return '${submission.policyTitle} · ${submission.executionLabel}';
    }

    if (auditTimeline.latest != null) {
      return '最近复核：${auditTimeline.latest!.humanChoiceSummary}';
    }

    return '当前未发现需要升级处理的关键事件';
  }

  static String _buildKeyEventDetail({
    required AlertsSnapshot snapshot,
    required StrategySubmissionSummary? submission,
    required AuditTimeline auditTimeline,
  }) {
    final latestCritical = snapshot.items
        .where((item) => item.severity == AlertSeverity.critical)
        .toList();
    latestCritical.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (latestCritical.isNotEmpty) {
      final item = latestCritical.first;
      return '来自 ${item.source}，建议沿 告警 → 策略处理 → 审计复核 推进。';
    }

    if (submission != null) {
      return '最近一次策略已进入 ${submission.executionLabel}，建议继续看回执并完成审计复核。';
    }

    if (auditTimeline.latest != null) {
      return '最近一条留痕已生成，可从审计复核进入回放复盘。';
    }

    return '当前可从态势巡检开始，完成一次全链路健康检查。';
  }

  static String _auditActionLabel(AuditActionType type) {
    switch (type) {
      case AuditActionType.override:
        return 'override';
      case AuditActionType.guidance:
        return 'guidance';
      case AuditActionType.veto:
        return 'veto';
    }
  }

  static String _buildDataLine({
    required AlertsSnapshot snapshot,
    required StrategyControllerState strategyState,
    required AuditTimeline auditTimeline,
  }) {
    final alertsSource = snapshot.feedMode == AlertsFeedMode.offline
        ? '告警：等待接入港口（无本地生成）'
        : '告警：WebSocket 事件流';
    final strategySource =
        strategyState.candidatesDataSource == StrategyCandidatesDataSource.cache
        ? '策略：cache'
        : '策略：测试产物';
    final auditSource = auditTimeline.latest == null ? '审计：待生成' : '审计：本地留痕';

    return '$alertsSource  ·  $strategySource  ·  $auditSource';
  }
}

class _ResolvedStatus {
  const _ResolvedStatus({
    required this.label,
    required this.icon,
    required this.kind,
  });

  final String label;
  final IconData icon;
  final _StatusKind kind;
}

enum _StatusKind { ok, info, warning, danger, neutral }

class _PrimaryAction {
  const _PrimaryAction({
    required this.label,
    required this.hint,
    required this.icon,
    required this.tab,
  });

  final String label;
  final String hint;
  final IconData icon;
  final HomeTab tab;
}

class _ConnectionBadge extends ConsumerWidget {
  const _ConnectionBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(alertsSnapshotProvider);
    final snapshot = alertsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => AlertsSnapshot.empty,
    );

    IconData icon;
    String label;
    _StatusKind kind;

    switch (snapshot.connectionStatus) {
      case AlertsConnectionStatus.connected:
        icon = Icons.cloud_done_outlined;
        label = snapshot.feedMode == AlertsFeedMode.offline ? '离线' : 'WS 已连接';
        kind = snapshot.feedMode == AlertsFeedMode.offline
            ? _StatusKind.neutral
            : _StatusKind.ok;
        break;
      case AlertsConnectionStatus.connecting:
        icon = Icons.cloud_sync_outlined;
        label = '连接中';
        kind = _StatusKind.info;
        break;
      case AlertsConnectionStatus.disconnected:
        icon = Icons.cloud_off_outlined;
        label = '断开';
        kind = _StatusKind.danger;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _StatusPill(icon: icon, label: label, kind: kind),
    );
  }
}

class _NotificationBellButton extends StatelessWidget {
  const _NotificationBellButton({required this.badgeText, required this.onTap});

  final String? badgeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded),
          if (badgeText != null)
            Positioned(
              right: -8,
              top: -8,
              child: _BadgeBubble(text: badgeText!),
            ),
        ],
      ),
    );
  }
}

class _TopMenu extends StatelessWidget {
  const _TopMenu({required this.onOpenAuth, required this.onOpenSettings});

  final VoidCallback onOpenAuth;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) {
        switch (value) {
          case 'auth':
            onOpenAuth();
            break;
          case 'settings':
            onOpenSettings();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'auth',
          child: ListTile(
            leading: Icon(Icons.verified_user_outlined),
            title: Text('访问凭证'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.tune_rounded),
            title: Text('设置'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _NavIconWithBadge extends StatelessWidget {
  const _NavIconWithBadge({required this.icon, this.badgeText});

  final IconData icon;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (badgeText != null)
          Positioned(
            right: -10,
            top: -8,
            child: _BadgeBubble(text: badgeText!),
          ),
      ],
    );
  }
}

class _BadgeBubble extends StatelessWidget {
  const _BadgeBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onError,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.kind,
  });

  final IconData icon;
  final String label;
  final _StatusKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (bg, fg) = switch (kind) {
      _StatusKind.ok => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _StatusKind.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _StatusKind.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _StatusKind.danger => (scheme.errorContainer, scheme.onErrorContainer),
      _StatusKind.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionCard extends StatelessWidget {
  const _PrimaryActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2854C7), Color(0xFF1769E0), Color(0xFF087A88)],
            ),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.54)),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.18),
                blurRadius: 20,
                spreadRadius: -6,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharedFocusState {
  const _SharedFocusState({
    required this.typeLabel,
    required this.title,
    required this.subtitle,
    required this.tab,
    required this.icon,
  });

  const _SharedFocusState.empty()
    : typeLabel = '焦点链路',
      title = '尚未建立全局焦点',
      subtitle = '请先从首页总控中选择当前最重要的一段链路。',
      tab = HomeTab.situation,
      icon = Icons.adjust_rounded;

  final String typeLabel;
  final String title;
  final String subtitle;
  final HomeTab tab;
  final IconData icon;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SharedFocusState &&
          runtimeType == other.runtimeType &&
          typeLabel == other.typeLabel &&
          title == other.title &&
          subtitle == other.subtitle &&
          tab == other.tab &&
          icon == other.icon;

  @override
  int get hashCode => Object.hash(typeLabel, title, subtitle, tab, icon);
}

class _SharedFocusBanner extends StatelessWidget {
  const _SharedFocusBanner({
    required this.notifier,
    required this.onOpenTab,
    required this.demoFlow,
  });

  final ValueNotifier<_SharedFocusState> notifier;
  final ValueChanged<HomeTab> onOpenTab;
  final DemoFlowState demoFlow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ValueListenableBuilder<_SharedFocusState>(
      valueListenable: notifier,
      builder: (context, focus, _) {
        final resolvedFocus = demoFlow.isRunning
            ? _sharedFocusForDemo(demoFlow.stage)
            : focus;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onOpenTab(resolvedFocus.tab),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(resolvedFocus.icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${resolvedFocus.typeLabel} · ${resolvedFocus.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '进入',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

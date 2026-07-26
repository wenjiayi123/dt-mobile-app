import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/features/alerts/application/alerts_controller.dart';
import 'package:dt_mobile_app/features/audit/application/audit_controller.dart';
import 'package:dt_mobile_app/features/home/application/home_tab_notifier.dart';
import 'package:dt_mobile_app/features/situation/application/situation_controller.dart';
import 'package:dt_mobile_app/features/situation/presentation/twin_3d_screen.dart';
import 'package:dt_mobile_app/features/strategy/application/strategy_controller.dart';
import 'package:dt_mobile_app/features/xiaoyi/application/xiaoyi_leadership_controller.dart';
import 'package:dt_mobile_app/shared/ui/app_badge.dart';
import 'package:dt_mobile_app/shared/ui/intelligent_action_button.dart';

class XiaoyiLeadershipPanel extends ConsumerStatefulWidget {
  const XiaoyiLeadershipPanel({super.key, required this.onOpenTab});

  final ValueChanged<HomeTab> onOpenTab;

  @override
  ConsumerState<XiaoyiLeadershipPanel> createState() =>
      _XiaoyiLeadershipPanelState();
}

class _XiaoyiLeadershipPanelState extends ConsumerState<XiaoyiLeadershipPanel> {
  late final TextEditingController _commandController;
  String? _executingActionId;
  _XiaoyiExecutionResult? _lastResult;
  bool _isExpanded = false;
  bool _coreLinkageRunning = false;
  bool _coreLinkageCompleted = false;
  int _coreLinkageStage = -1;
  double _coreLinkageProgress = 0;
  String _coreLinkageDetail = '等待读取港区业务链路';

  @override
  void initState() {
    super.initState();
    _commandController = TextEditingController();
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(xiaoyiLeadershipControllerProvider);
    final controller = ref.read(xiaoyiLeadershipControllerProvider.notifier);
    final alertsAsync = ref.watch(alertsSnapshotProvider);
    final strategy = ref.watch(strategyControllerProvider);
    final audit = ref.watch(auditTimelineProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_commandController.text != state.commandText) {
      _commandController.value = TextEditingValue(
        text: state.commandText,
        selection: TextSelection.collapsed(offset: state.commandText.length),
      );
    }

    final alertSnapshot = alertsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => AlertsSnapshot.empty,
    );
    final criticalAlerts = alertSnapshot.items
        .where((item) => item.severity == AlertSeverity.critical)
        .length;
    final pendingExecution = strategy.lastSubmission == null
        ? 0
        : strategy.lastSubmission!.executionStatus.isTerminal
        ? 0
        : 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _XiaoyiSpriteIcon(size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '小懿决策助手',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '研判、审批、汇报，一处完成。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
                icon: Icon(
                  _isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
                label: Text(_isExpanded ? '收起' : '展开'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ExecutiveSignalStrip(
            criticalAlerts: criticalAlerts,
            pendingExecutions: pendingExecution,
            auditCount: audit.items.length,
          ),
          if (!_isExpanded) ...[
            const SizedBox(height: 12),
            _XiaoyiCoreLinkageConsole(
              busy: _executingActionId != null || _coreLinkageRunning,
              completed: _coreLinkageCompleted,
              stageIndex: _coreLinkageStage,
              progress: _coreLinkageProgress,
              stageDetail: _coreLinkageDetail,
              onLinkage: () => _runCoreLinkage(context),
              onSituation: () => widget.onOpenTab(HomeTab.situation),
              onStrategy: () => _executeAction(
                context,
                'run_policy_test',
                command: '小懿，运行强化学习策略测试',
              ),
              onTwin: () => _executeAction(
                context,
                'open_simulation_demo',
                command: '小懿，打开3D孪生屏',
              ),
              onBrief: () => _executeAction(
                context,
                'generate_meeting_brief',
                command: '小懿，生成领导会议简报',
              ),
            ),
          ],
          if (_executingActionId != null && !_coreLinkageRunning) ...[
            const SizedBox(height: 9),
            _XiaoyiActionProgress(actionId: _executingActionId!),
          ],
          if (_isExpanded) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _commandController,
              minLines: 2,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '输入指令',
                hintText: '例如：生成会议简报 / 验证策略能否上线',
              ),
              onChanged: controller.setCommand,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: state.selectedActionId.isEmpty
                  ? null
                  : state.selectedActionId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '选择动作'),
              items: [
                for (final action in xiaoyiLeadershipActions)
                  DropdownMenuItem<String>(
                    value: action.id,
                    child: Text('${action.category.label} · ${action.label}'),
                  ),
              ],
              onChanged: (value) => controller.selectAction(value ?? ''),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => controller.judge(),
                    icon: const Icon(Icons.manage_search_outlined),
                    label: const Text('先判断'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _executeCurrentAction(context),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('执行'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _XiaoyiAnswerCard(state: state),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 460),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(sizeFactor: animation, child: child),
            ),
            child: _lastResult == null
                ? const SizedBox.shrink(key: ValueKey('no-xiaoyi-result'))
                : Padding(
                    key: ValueKey(_lastResult!.title),
                    padding: const EdgeInsets.only(top: 10),
                    child: _XiaoyiExecutionResultCard(result: _lastResult!),
                  ),
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 12),
            _ExecutiveCommandGroups(
              executingActionId: _executingActionId,
              onExecute: _executeAction,
            ),
            if (state.logs.isNotEmpty) ...[
              const SizedBox(height: 12),
              _XiaoyiLogList(logs: state.logs),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _executeCurrentAction(BuildContext context) async {
    final state = ref.read(xiaoyiLeadershipControllerProvider);
    await _executeAction(
      context,
      state.selectedActionId,
      command: state.commandText,
    );
  }

  Future<void> _executeAction(
    BuildContext context,
    String actionId, {
    String? command,
  }) async {
    if (_executingActionId != null) return;

    final controller = ref.read(xiaoyiLeadershipControllerProvider.notifier);
    final pendingAction = controller.judge(
      actionId: actionId,
      command: command,
      updateState: false,
    );

    if (pendingAction == null) {
      controller.execute(actionId: actionId, command: command);
      return;
    }

    if (pendingAction.requiresConfirmation) {
      final confirmed = await _confirmLeadershipAction(context, pendingAction);
      if (!confirmed) {
        controller.execute(
          actionId: actionId,
          command: command,
          confirmed: false,
        );
        setState(() {
          _lastResult = _XiaoyiExecutionResult(
            title: '等待领导确认',
            detail: '${pendingAction.label} 已停在确认口，未进入执行联动。',
            nextStep: '确认后只做验证和留痕，不生产下发。',
            target: pendingAction.category.label,
            tone: AppBadgeTone.watch,
          );
        });
        return;
      }
    }

    final startedAt = DateTime.now();
    setState(() => _executingActionId = pendingAction.id);

    final action = controller.execute(actionId: actionId, command: command);
    if (action == null) return;

    try {
      final result = await _applySideEffect(action);
      final elapsed = DateTime.now().difference(startedAt);
      const minimumVisibleTime = Duration(milliseconds: 720);
      if (elapsed < minimumVisibleTime) {
        await Future<void>.delayed(minimumVisibleTime - elapsed);
      }
      _recordLeadershipAudit(action, result);

      if (mounted) {
        setState(() => _lastResult = result);
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('小懿已执行：${action.label}'),
            duration: const Duration(seconds: 2),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _executingActionId = null);
      }
    }
  }

  Future<bool> _confirmLeadershipAction(
    BuildContext context,
    XiaoyiLeadershipAction action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('确认执行：${action.label}'),
          content: Text(
            '${action.description}\n\n该动作会形成领导审批留痕。当前移动端只做验证、研判和审计记录，不直接生产下发。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('先不执行'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认执行'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<_XiaoyiExecutionResult> _applySideEffect(
    XiaoyiLeadershipAction action,
  ) async {
    switch (action.type) {
      case XiaoyiLeadershipActionType.refreshSituation:
        await ref.read(situationProvider.notifier).refreshNow();
        widget.onOpenTab(HomeTab.situation);
        return _resultFor(
          action,
          detail: '已刷新态势快照，并打开态势页查看数据来源、派生风险点值和证据边界。',
          nextStep: '如派生风险指标偏高，可继续执行“风险升级建议”并人工复核。',
          target: '态势',
        );
      case XiaoyiLeadershipActionType.openStrategy:
      case XiaoyiLeadershipActionType.reviewStrategyPortfolio:
      case XiaoyiLeadershipActionType.runPolicyTest:
      case XiaoyiLeadershipActionType.verifyOnlineDryRun:
        await ref
            .read(strategyControllerProvider.notifier)
            .refreshCandidates(silent: true);
        widget.onOpenTab(HomeTab.strategy);
        return _resultFor(
          action,
          detail: _strategyActionDetail(action),
          nextStep: action.type == XiaoyiLeadershipActionType.verifyOnlineDryRun
              ? '策略页已打开，请查看候选方案与审批边界；本次为验证留痕，不生产下发。'
              : '策略页已打开，可继续审阅推荐、备选和风险对照。',
          target: '策略',
          tone: action.requiresConfirmation
              ? AppBadgeTone.watch
              : AppBadgeTone.info,
        );
      case XiaoyiLeadershipActionType.openAlerts:
        await _refreshAlertsSilently();
        widget.onOpenTab(HomeTab.alerts);
        return _resultFor(
          action,
          detail: '已刷新告警快照，并打开风险告警页。',
          nextStep: '可继续查看高优风险来源，必要时执行“风险升级建议”。',
          target: '告警',
        );
      case XiaoyiLeadershipActionType.requestRiskEscalation:
        await _refreshAlertsSilently();
        await ref
            .read(quickReplanProvider.notifier)
            .triggerQuickReplan(trigger: 'risk_escalation');
        final replan = ref.read(quickReplanProvider);
        widget.onOpenTab(HomeTab.alerts);
        return _resultFor(
          action,
          detail: replan.message ?? '后端未返回重规划审阅状态',
          nextStep: replan.status == ReplanTriggerStatus.success
              ? '告警页已打开；请进入策略页人工审阅已绑定的测试候选。'
              : '告警页已打开；当前未形成重规划申请，请核对后端和测试产物。',
          target: '告警',
          tone: replan.status == ReplanTriggerStatus.success
              ? AppBadgeTone.critical
              : AppBadgeTone.watch,
        );
      case XiaoyiLeadershipActionType.openAudit:
      case XiaoyiLeadershipActionType.openReplayBrief:
        widget.onOpenTab(HomeTab.audit);
        return _resultFor(
          action,
          detail: '已打开审计复盘页，查看人工表态、执行回执与证据链。',
          nextStep: '可按事件时间线追溯“谁确认、为什么做、效果如何”。',
          target: '审计',
        );
      case XiaoyiLeadershipActionType.openSituation:
      case XiaoyiLeadershipActionType.openSimulationDemo:
        if (action.type == XiaoyiLeadershipActionType.openSimulationDemo) {
          await ref.read(situationProvider.notifier).refreshNow();
        }
        final situationState = ref.read(situationProvider);
        if (action.type == XiaoyiLeadershipActionType.openSimulationDemo &&
            mounted &&
            situationState.hasValue) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  Twin3DScreen(snapshot: situationState.requireValue),
            ),
          );
        } else {
          widget.onOpenTab(HomeTab.situation);
        }
        return _resultFor(
          action,
          detail: action.type == XiaoyiLeadershipActionType.openSimulationDemo
              ? '已刷新后端态势并打开3D证据屏；公开回放、布局示意和测试产物均有独立标签。'
              : '已打开态势总览页。',
          nextStep: action.type == XiaoyiLeadershipActionType.openSimulationDemo
              ? '先核对数据来源；只有存在完成的留出测试产物时才可播放策略轨迹。'
              : '先确认系统稳态，再决定是否进入策略审批。',
          target: action.type == XiaoyiLeadershipActionType.openSimulationDemo
              ? '3D孪生'
              : '态势',
        );
      case XiaoyiLeadershipActionType.refreshDashboard:
        await _refreshExecutiveSnapshot();
        return _resultFor(
          action,
          detail: '已同步态势、策略候选和告警快照，首页摘要可按同一口径汇报。',
          nextStep: '继续查看首页指标，或执行“生成会议简报”。',
          target: '运营首页',
        );
      case XiaoyiLeadershipActionType.linkageHealth:
        return _buildLinkageHealthResult(action);
      case XiaoyiLeadershipActionType.dataLinkCheck:
        return _buildDataLinkResult(action);
      case XiaoyiLeadershipActionType.startXiaoyi:
        return _resultFor(
          action,
          detail: '小懿领导联动网关已就绪，当前支持指令识别、页面联动、审批验证和审计留痕。',
          nextStep: '可直接点击下方任一“执行”，或在输入框发出领导口径指令。',
          target: '小懿',
          tone: AppBadgeTone.success,
        );
      case XiaoyiLeadershipActionType.askBrief:
        return _buildExecutiveBriefResult(action);
      case XiaoyiLeadershipActionType.setEfficiencyPriority:
      case XiaoyiLeadershipActionType.setBalancedDispatch:
      case XiaoyiLeadershipActionType.setLowCarbonPriority:
      case XiaoyiLeadershipActionType.setShorePowerPriority:
        await ref
            .read(strategyControllerProvider.notifier)
            .refreshCandidates(silent: true);
        final refreshed = ref.read(strategyControllerProvider);
        widget.onOpenTab(HomeTab.strategy);
        return _resultFor(
          action,
          detail: refreshed.candidates.isEmpty
              ? '客户端解释偏好已切换为“${action.label}”，但当前没有完成留出测试的候选。'
              : '客户端解释偏好已切换为“${action.label}”，已读取 ${refreshed.candidates.length} 个测试候选。',
          nextStep: refreshed.candidates.isEmpty
              ? '请先完成训练与独立测试；本操作不会生成候选。'
              : '请在策略页审阅测试指标和人工确认边界。',
          target: '策略',
          tone: refreshed.candidates.isEmpty
              ? AppBadgeTone.watch
              : AppBadgeTone.success,
        );
      case XiaoyiLeadershipActionType.generateMeetingBrief:
        return _buildMeetingBriefResult(action);
    }
  }

  Future<void> _refreshAlertsSilently() async {
    await ref.read(alertsSnapshotProvider.notifier).refreshNow();
  }

  Future<void> _refreshExecutiveSnapshot() async {
    await Future.wait<void>([
      ref.read(situationProvider.notifier).refreshNow(),
      ref
          .read(strategyControllerProvider.notifier)
          .refreshCandidates(silent: true),
      _refreshAlertsSilently(),
    ]);
  }

  Future<void> _runCoreLinkage(BuildContext context) async {
    if (_coreLinkageRunning || _executingActionId != null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _coreLinkageRunning = true;
      _coreLinkageCompleted = false;
      _coreLinkageStage = 0;
      _coreLinkageProgress = 0.08;
      _coreLinkageDetail = '读取后端态势、告警、测试候选与审计状态';
      _lastResult = null;
    });

    try {
      final situationOk = await _runCoreLinkageStage(
        index: 0,
        progress: 0.24,
        detail: '态势刷新调用完成 · 以页面数据源标签为准',
        task: () => ref.read(situationProvider.notifier).refreshNow(),
      );
      final alertsOk = await _runCoreLinkageStage(
        index: 1,
        progress: 0.48,
        detail: '告警刷新调用完成 · 断线时不生成本地告警',
        task: _refreshAlertsSilently,
      );
      final strategyOk = await _runCoreLinkageStage(
        index: 2,
        progress: 0.72,
        detail: '测试候选读取完成 · 空列表表示尚无完成产物',
        task: () => ref
            .read(strategyControllerProvider.notifier)
            .refreshCandidates(silent: true),
      );
      final auditOk = await _runCoreLinkageStage(
        index: 3,
        progress: 0.92,
        detail: '本地审计缓存已读取 · 上传状态以事件标签为准',
        task: () async {
          ref.read(auditTimelineProvider);
        },
      );
      final allHealthy = situationOk && alertsOk && strategyOk && auditOk;
      if (!mounted || !context.mounted) return;
      await _executeAction(
        context,
        'linkage_health',
        command: '小懿，同步强化学习与3D孪生链路',
      );
      if (!mounted) return;
      setState(() {
        _coreLinkageStage = 4;
        _coreLinkageProgress = 1;
        _coreLinkageDetail = allHealthy
            ? '状态读取完成 · 各模块保留独立证据标签'
            : '状态读取完成但存在失败 · 已保留降级标签';
        _coreLinkageCompleted = true;
      });
      HapticFeedback.heavyImpact();
    } finally {
      if (mounted) setState(() => _coreLinkageRunning = false);
    }
  }

  Future<bool> _runCoreLinkageStage({
    required int index,
    required double progress,
    required String detail,
    required Future<void> Function() task,
  }) async {
    if (!mounted) return false;
    setState(() {
      _coreLinkageStage = index;
      _coreLinkageDetail = switch (index) {
        0 => '正在读取港区态势快照',
        1 => '正在扫描告警与影响链',
        2 => '正在校验强化学习候选策略',
        _ => '正在核对人工确认与审计证据',
      };
    });
    try {
      await task();
    } catch (error) {
      if (mounted) {
        setState(() {
          _coreLinkageProgress = progress;
          _coreLinkageDetail = '读取失败：$error';
        });
      }
      return false;
    }
    if (!mounted) return false;
    setState(() {
      _coreLinkageProgress = progress;
      _coreLinkageDetail = detail;
    });
    HapticFeedback.selectionClick();
    return true;
  }

  _XiaoyiExecutionResult _buildExecutiveBriefResult(
    XiaoyiLeadershipAction action,
  ) {
    final alertSnapshot = ref
        .read(alertsSnapshotProvider)
        .maybeWhen(data: (value) => value, orElse: () => AlertsSnapshot.empty);
    final strategy = ref.read(strategyControllerProvider);
    final audit = ref.read(auditTimelineProvider);
    final criticalCount = alertSnapshot.items
        .where((item) => item.severity == AlertSeverity.critical)
        .length;

    return _resultFor(
      action,
      detail:
          '领导口径已生成：当前高优风险 $criticalCount 项，候选策略 ${strategy.candidates.length} 个，审计留痕 ${audit.items.length} 条。',
      nextStep: criticalCount > 0 ? '建议先打开风险告警，再审阅策略组合。' : '建议直接审阅策略组合或生成会议简报。',
      target: '领导口径',
    );
  }

  _XiaoyiExecutionResult _buildMeetingBriefResult(
    XiaoyiLeadershipAction action,
  ) {
    final strategy = ref.read(strategyControllerProvider);
    final audit = ref.read(auditTimelineProvider);
    final latestPolicy = strategy.candidates.isEmpty
        ? '暂无完成留出测试的候选'
        : strategy.recommendedCandidate.title;

    return _resultFor(
      action,
      detail: '会议摘要已整理：运行状态、关键风险、策略状态“$latestPolicy”、人工确认边界、审计证据链。',
      nextStep: strategy.candidates.isEmpty
          ? '当前无测试候选；请先完成训练和独立测试。'
          : '可进入审计复盘查看证据链，或进入策略页查看测试候选详情。',
      target: '会议简报',
      tone: strategy.candidates.isEmpty
          ? AppBadgeTone.watch
          : AppBadgeTone.success,
      evidenceCount: audit.items.length,
    );
  }

  _XiaoyiExecutionResult _buildLinkageHealthResult(
    XiaoyiLeadershipAction action,
  ) {
    final alerts = ref.read(alertsSnapshotProvider);
    final strategy = ref.read(strategyControllerProvider);
    final audit = ref.read(auditTimelineProvider);
    final alertsStatus = alerts.when(
      data: (snapshot) => _alertConnectionLabel(snapshot.connectionStatus),
      loading: () => '连接中',
      error: (error, stackTrace) => '降级可用',
    );

    return _resultFor(
      action,
      detail:
          '健康检查完成：移动端可用，告警链路 $alertsStatus，策略候选 ${strategy.candidates.length} 个，审计留痕 ${audit.items.length} 条。',
      nextStep: '如需现场汇报，可继续执行“同步运营首页”或“生成会议简报”。',
      target: '联动健康',
      tone: alerts.hasError || strategy.fetchErrorMessage != null
          ? AppBadgeTone.watch
          : AppBadgeTone.success,
    );
  }

  _XiaoyiExecutionResult _buildDataLinkResult(XiaoyiLeadershipAction action) {
    final alerts = ref.read(alertsSnapshotProvider);
    final strategy = ref.read(strategyControllerProvider);
    final situation = ref.read(situationProvider);
    final situationStatus = situation.maybeWhen(
      data: (snapshot) =>
          '${snapshot.dataSource.label} · ${snapshot.systemScore}',
      orElse: () => '等待刷新',
    );
    final alertsStatus = alerts.maybeWhen(
      data: (snapshot) =>
          '${snapshot.feedMode.name} · ${snapshot.items.length} 项',
      orElse: () => '等待连接',
    );

    return _resultFor(
      action,
      detail:
          '数据链路检查完成：态势 $situationStatus，告警 $alertsStatus，策略数据源 ${strategy.candidatesDataSource.label}。',
      nextStep: '如发现数据源降级，可先同步运营首页，再进入对应页面核验。',
      target: '数据链路',
    );
  }

  String _strategyActionDetail(XiaoyiLeadershipAction action) {
    final strategy = ref.read(strategyControllerProvider);
    if (strategy.candidates.isEmpty) {
      return '策略页已刷新；当前没有完成留出测试的候选，本操作未生成替代数据。';
    }
    final recommended = strategy.recommendedCandidate.title;
    return switch (action.type) {
      XiaoyiLeadershipActionType.verifyOnlineDryRun =>
        '已刷新可供 dry-run 审阅的测试候选“$recommended”；本动作未提交执行请求。',
      XiaoyiLeadershipActionType.runPolicyTest =>
        '已读取完成的留出测试候选“$recommended”；本动作未启动新的测试任务。',
      XiaoyiLeadershipActionType.reviewStrategyPortfolio =>
        '已刷新策略组合，当前推荐策略为“$recommended”。',
      _ => '已刷新策略候选，当前推荐策略为“$recommended”。',
    };
  }

  String _alertConnectionLabel(AlertsConnectionStatus status) {
    return switch (status) {
      AlertsConnectionStatus.connecting => '连接中',
      AlertsConnectionStatus.connected => '已连接',
      AlertsConnectionStatus.disconnected => '已断开',
    };
  }

  _XiaoyiExecutionResult _resultFor(
    XiaoyiLeadershipAction action, {
    required String detail,
    required String nextStep,
    required String target,
    AppBadgeTone tone = AppBadgeTone.info,
    int? evidenceCount,
  }) {
    return _XiaoyiExecutionResult(
      title: action.label,
      detail: detail,
      nextStep: nextStep,
      target: target,
      tone: tone,
      evidenceCount: evidenceCount,
    );
  }

  void _recordLeadershipAudit(
    XiaoyiLeadershipAction action,
    _XiaoyiExecutionResult result,
  ) {
    final source = switch (action.type) {
      XiaoyiLeadershipActionType.requestRiskEscalation =>
        AuditEventSource.triggerReplan,
      XiaoyiLeadershipActionType.setEfficiencyPriority ||
      XiaoyiLeadershipActionType.setBalancedDispatch ||
      XiaoyiLeadershipActionType.setLowCarbonPriority ||
      XiaoyiLeadershipActionType.setShorePowerPriority =>
        AuditEventSource.configChange,
      XiaoyiLeadershipActionType.verifyOnlineDryRun =>
        AuditEventSource.humanOverride,
      _ => AuditEventSource.aiSuggestion,
    };

    ref
        .read(auditTimelineProvider.notifier)
        .recordEvent(
          source: source,
          actionType: AuditActionType.guidance,
          stateSummary: '小懿领导联动执行：${action.label}',
          policySetSummary: result.detail,
          humanChoiceSummary: '领导点击执行：${action.command}',
          payload: <String, Object?>{
            'source': 'xiaoyi_mobile_leadership_panel',
            'actionId': action.id,
            'actionType': action.type.name,
            'category': action.category.label,
            'target': result.target,
            'nextStep': result.nextStep,
            'requiresConfirmation': action.requiresConfirmation,
            'executivePreference': action.executivePreference,
          },
        );
  }
}

class _XiaoyiCoreLinkageConsole extends StatefulWidget {
  const _XiaoyiCoreLinkageConsole({
    required this.busy,
    required this.completed,
    required this.stageIndex,
    required this.progress,
    required this.stageDetail,
    required this.onLinkage,
    required this.onSituation,
    required this.onStrategy,
    required this.onTwin,
    required this.onBrief,
  });

  final bool busy;
  final bool completed;
  final int stageIndex;
  final double progress;
  final String stageDetail;
  final Future<void> Function() onLinkage;
  final VoidCallback onSituation;
  final Future<void> Function() onStrategy;
  final Future<void> Function() onTwin;
  final Future<void> Function() onBrief;

  @override
  State<_XiaoyiCoreLinkageConsole> createState() =>
      _XiaoyiCoreLinkageConsoleState();
}

class _XiaoyiCoreLinkageConsoleState extends State<_XiaoyiCoreLinkageConsole>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0.32;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B2A35), Color(0xFF102653), Color(0xFF241B48)],
        ),
        border: Border.all(
          color: const Color(0xFF76F7C5).withValues(alpha: 0.30),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22D3EE).withValues(alpha: 0.13),
            blurRadius: 28,
            spreadRadius: -8,
          ),
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.10),
            blurRadius: 32,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 126,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _XiaoyiLinkagePainter(
                          progress: _controller.value,
                          busy: widget.busy,
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 8,
                      top: 42,
                      child: _LinkageNode(
                        label: 'RL',
                        caption: '策略引擎',
                        icon: Icons.hub_rounded,
                        color: Color(0xFF60A5FA),
                      ),
                    ),
                    const Positioned(
                      right: 8,
                      top: 42,
                      child: _LinkageNode(
                        label: '3D',
                        caption: '孪生港区',
                        icon: Icons.view_in_ar_rounded,
                        color: Color(0xFF4DE4FF),
                      ),
                    ),
                    Container(
                      width: 62,
                      height: 62,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF0F766E),
                            Color(0xFF2563EB),
                            Color(0xFF7C3AED),
                          ],
                        ),
                        border: Border.all(
                          color: const Color(
                            0xFFB8EFFF,
                          ).withValues(alpha: 0.58),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF76F7C5,
                            ).withValues(alpha: 0.30),
                            blurRadius: 22,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/images/xiaoyi_maritime_officer.png',
                        fit: BoxFit.cover,
                        semanticLabel: '小懿Q版海事训练顾问',
                      ),
                    ),
                    Positioned(
                      top: 4,
                      child: Text(
                        widget.busy
                            ? '智能联动中'
                            : widget.completed
                            ? '三端联动已就绪'
                            : '小懿 · 三端协同',
                        style: const TextStyle(
                          color: Color(0xFFB8EFFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _CoreLinkageProgress(
            busy: widget.busy,
            completed: widget.completed,
            stageIndex: widget.stageIndex,
            progress: widget.progress,
            detail: widget.stageDetail,
          ),
          if (widget.completed) ...[
            const SizedBox(height: 10),
            IntelligentActionButton(
              label: '小懿接力 · 查看港区稳态',
              eyebrow: 'NEXT · SITUATION AWARENESS',
              busyLabel: '正在打开态势总览',
              icon: Icons.arrow_forward_rounded,
              tone: IntelligentActionTone.twin,
              compact: true,
              onPressed: widget.busy ? null : widget.onSituation,
            ),
          ],
          const SizedBox(height: 10),
          IntelligentActionButton(
            label: widget.completed ? '重新同步小懿智能联动' : '启动小懿智能联动',
            eyebrow: 'XIAOYI COPILOT · RL × 3D TWIN',
            busyLabel: '正在同步三端状态',
            icon: Icons.auto_awesome_rounded,
            tone: IntelligentActionTone.xiaoyi,
            onPressed: widget.busy ? null : widget.onLinkage,
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _LinkagePortal(
                  label: '查看策略',
                  caption: '强化学习',
                  icon: Icons.science_outlined,
                  color: const Color(0xFF60A5FA),
                  onTap: widget.busy ? null : widget.onStrategy,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _LinkagePortal(
                  label: '3D孪生',
                  caption: '动态港区',
                  icon: Icons.view_in_ar_outlined,
                  color: const Color(0xFF4DE4FF),
                  onTap: widget.busy ? null : widget.onTwin,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _LinkagePortal(
                  label: '生成简报',
                  caption: '小懿汇报',
                  icon: Icons.summarize_outlined,
                  color: const Color(0xFF76F7C5),
                  onTap: widget.busy ? null : widget.onBrief,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoreLinkageProgress extends StatelessWidget {
  const _CoreLinkageProgress({
    required this.busy,
    required this.completed,
    required this.stageIndex,
    required this.progress,
    required this.detail,
  });

  final bool busy;
  final bool completed;
  final int stageIndex;
  final double progress;
  final String detail;

  @override
  Widget build(BuildContext context) {
    const stages = <(String, IconData)>[
      ('态势', Icons.sensors_rounded),
      ('告警', Icons.warning_amber_rounded),
      ('策略', Icons.hub_rounded),
      ('审计', Icons.fact_check_outlined),
    ];
    final accent = completed
        ? const Color(0xFF76F7C5)
        : const Color(0xFF4DE4FF);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: completed ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                completed
                    ? Icons.task_alt_rounded
                    : busy
                    ? Icons.auto_awesome_rounded
                    : Icons.memory_rounded,
                color: accent,
                size: 16,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: Text(
                    detail,
                    key: ValueKey(detail),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFD2E5FF),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: value,
                backgroundColor: const Color(0xFF172845),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var index = 0; index < stages.length; index++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: (completed || index <= stageIndex)
                          ? accent.withValues(alpha: 0.13)
                          : const Color(0x66071120),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (completed || index <= stageIndex)
                            ? accent.withValues(alpha: 0.38)
                            : const Color(0xFF294264),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          completed || index < stageIndex
                              ? Icons.check_rounded
                              : stages[index].$2,
                          size: 11,
                          color: completed || index <= stageIndex
                              ? accent
                              : const Color(0xFF607CA5),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          stages[index].$1,
                          style: TextStyle(
                            color: completed || index <= stageIndex
                                ? const Color(0xFFD2E5FF)
                                : const Color(0xFF607CA5),
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (index != stages.length - 1) const SizedBox(width: 5),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _XiaoyiActionProgress extends StatelessWidget {
  const _XiaoyiActionProgress({required this.actionId});

  final String actionId;

  @override
  Widget build(BuildContext context) {
    final action = xiaoyiLeadershipActionsById[actionId];
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2441),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x664DE4FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF76F7C5),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '小懿正在执行 · ${action?.label ?? '智能联动动作'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Text(
                '读取业务上下文',
                style: TextStyle(color: Color(0xFF9DC8F8), fontSize: 8),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(99)),
            child: LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: Color(0xFF172845),
              color: Color(0xFF4DE4FF),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkageNode extends StatelessWidget {
  const _LinkageNode({
    required this.label,
    required this.caption,
    required this.icon,
    required this.color,
  });

  final String label;
  final String caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color.withValues(alpha: 0.52)),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: 13),
            ],
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(height: 3),
        Text(
          '$label · $caption',
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _LinkagePortal extends StatefulWidget {
  const _LinkagePortal({
    required this.label,
    required this.caption,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String caption;
  final IconData icon;
  final Color color;
  final Future<void> Function()? onTap;

  @override
  State<_LinkagePortal> createState() => _LinkagePortalState();
}

class _LinkagePortalState extends State<_LinkagePortal> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.95 : 1,
      duration: const Duration(milliseconds: 110),
      child: GestureDetector(
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapCancel: widget.onTap == null
            ? null
            : () => setState(() => _pressed = false),
        onTapUp: widget.onTap == null
            ? null
            : (_) {
                setState(() => _pressed = false);
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: widget.color.withValues(alpha: _pressed ? 0.18 : 0.08),
            border: Border.all(
              color: widget.color.withValues(alpha: _pressed ? 0.62 : 0.25),
            ),
            boxShadow: _pressed
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.26),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(widget.icon, color: widget.color, size: 18),
              const SizedBox(height: 4),
              Text(
                widget.label,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                widget.caption,
                maxLines: 1,
                style: const TextStyle(
                  color: Color(0xFF7894BD),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _XiaoyiLinkagePainter extends CustomPainter {
  const _XiaoyiLinkagePainter({required this.progress, required this.busy});

  final double progress;
  final bool busy;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.54);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (var index = 0; index < 3; index++) {
      final radius = 34.0 + index * 19;
      ringPaint.color =
          (index.isEven ? const Color(0xFF4DE4FF) : const Color(0xFF76F7C5))
              .withValues(alpha: 0.12 + (busy ? 0.09 : 0));
      canvas.drawCircle(center, radius, ringPaint);
    }

    final angle = progress * math.pi * 2;
    final beamEnd = Offset(
      center.dx + math.cos(angle) * size.width * 0.42,
      center.dy + math.sin(angle) * 58,
    );
    canvas.drawLine(
      center,
      beamEnd,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFFFFD166).withValues(alpha: 0.88),
            const Color(0xFF22D3EE).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromPoints(center, beamEnd))
        ..strokeWidth = busy ? 2.2 : 1.4,
    );

    final left = Offset(37, size.height * 0.49);
    final right = Offset(size.width - 37, size.height * 0.49);
    for (final endpoint in [left, right]) {
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(
          (center.dx + endpoint.dx) / 2,
          center.dy - 22,
          endpoint.dx,
          endpoint.dy,
        );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = busy ? 2 : 1.3
          ..color = const Color(0xFF4DE4FF).withValues(alpha: 0.46),
      );
      final metric = path.computeMetrics().first;
      final point = metric
          .getTangentForOffset(metric.length * progress)
          ?.position;
      if (point != null) {
        canvas.drawCircle(
          point,
          busy ? 4 : 3,
          Paint()..color = const Color(0xFF76F7C5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _XiaoyiLinkagePainter oldDelegate) {
    return progress != oldDelegate.progress || busy != oldDelegate.busy;
  }
}

class _ExecutiveSignalStrip extends StatelessWidget {
  const _ExecutiveSignalStrip({
    required this.criticalAlerts,
    required this.pendingExecutions,
    required this.auditCount,
  });

  final int criticalAlerts;
  final int pendingExecutions;
  final int auditCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        AppBadge(
          label: '高优风险 $criticalAlerts',
          tone: criticalAlerts > 0
              ? AppBadgeTone.critical
              : AppBadgeTone.success,
          leading: Icons.warning_amber_rounded,
          compact: true,
        ),
        AppBadge(
          label: '执行在途 $pendingExecutions',
          tone: pendingExecutions > 0
              ? AppBadgeTone.watch
              : AppBadgeTone.neutral,
          leading: Icons.sync_rounded,
          compact: true,
        ),
        AppBadge(
          label: '审计留痕 $auditCount',
          tone: auditCount > 0 ? AppBadgeTone.info : AppBadgeTone.neutral,
          leading: Icons.fact_check_outlined,
          compact: true,
        ),
      ],
    );
  }
}

class _XiaoyiAnswerCard extends StatelessWidget {
  const _XiaoyiAnswerCard({required this.state});

  final XiaoyiLeadershipState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _XiaoyiSpriteIcon(size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.matchedAction?.label ?? '小懿回应',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              AppBadge(
                label: state.busy ? '思考中' : 'ready',
                tone: state.busy ? AppBadgeTone.watch : AppBadgeTone.success,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.answer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              '指令包',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Text(
                  state.packet,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
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

class _XiaoyiExecutionResult {
  const _XiaoyiExecutionResult({
    required this.title,
    required this.detail,
    required this.nextStep,
    required this.target,
    required this.tone,
    this.evidenceCount,
  });

  final String title;
  final String detail;
  final String nextStep;
  final String target;
  final AppBadgeTone tone;
  final int? evidenceCount;
}

class _XiaoyiExecutionResultCard extends StatelessWidget {
  const _XiaoyiExecutionResultCard({required this.result});

  final _XiaoyiExecutionResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.task_alt_rounded, color: scheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '执行结果 · ${result.title}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              AppBadge(label: result.target, tone: result.tone, compact: true),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '下一步：${result.nextStep}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (result.evidenceCount != null) ...[
            const SizedBox(height: 8),
            AppBadge(
              label: '证据链 ${result.evidenceCount}',
              tone: AppBadgeTone.neutral,
              leading: Icons.fact_check_outlined,
              compact: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _ExecutiveCommandGroups extends ConsumerWidget {
  const _ExecutiveCommandGroups({
    required this.executingActionId,
    required this.onExecute,
  });

  final String? executingActionId;
  final Future<void> Function(
    BuildContext context,
    String actionId, {
    String? command,
  })
  onExecute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = <XiaoyiLeadershipCategory, List<XiaoyiLeadershipAction>>{
      for (final category in XiaoyiLeadershipCategory.values)
        category: xiaoyiLeadershipActions
            .where((action) => action.category == category)
            .toList(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '小懿互动功能 / 指令清单',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        for (final entry in grouped.entries) ...[
          _CommandCategoryBlock(
            category: entry.key,
            actions: entry.value,
            executingActionId: executingActionId,
            onExecute: onExecute,
            onJudge: (action) => ref
                .read(xiaoyiLeadershipControllerProvider.notifier)
                .judge(command: action.command, actionId: action.id),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _CommandCategoryBlock extends StatelessWidget {
  const _CommandCategoryBlock({
    required this.category,
    required this.actions,
    required this.executingActionId,
    required this.onExecute,
    required this.onJudge,
  });

  final XiaoyiLeadershipCategory category;
  final List<XiaoyiLeadershipAction> actions;
  final String? executingActionId;
  final Future<void> Function(
    BuildContext context,
    String actionId, {
    String? command,
  })
  onExecute;
  final void Function(XiaoyiLeadershipAction action) onJudge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_categoryIcon(category), size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              AppBadge(
                label: '${actions.length}',
                tone: AppBadgeTone.neutral,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < actions.length; i++) ...[
            _CommandActionRow(
              action: actions[i],
              isExecuting: executingActionId == actions[i].id,
              isAnyActionExecuting: executingActionId != null,
              onExecute: () => onExecute(
                context,
                actions[i].id,
                command: actions[i].command,
              ),
              onJudge: () => onJudge(actions[i]),
            ),
            if (i != actions.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  IconData _categoryIcon(XiaoyiLeadershipCategory category) {
    return switch (category) {
      XiaoyiLeadershipCategory.executivePanel =>
        Icons.dashboard_customize_outlined,
      XiaoyiLeadershipCategory.executiveDecision => Icons.verified_outlined,
      XiaoyiLeadershipCategory.commandLinkage => Icons.account_tree_outlined,
    };
  }
}

class _CommandActionRow extends StatelessWidget {
  const _CommandActionRow({
    required this.action,
    required this.isExecuting,
    required this.isAnyActionExecuting,
    required this.onExecute,
    required this.onJudge,
  });

  final XiaoyiLeadershipAction action;
  final bool isExecuting;
  final bool isAnyActionExecuting;
  final VoidCallback onExecute;
  final VoidCallback onJudge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(action.icon, size: 18, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                action.command,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            TextButton(
              onPressed: isAnyActionExecuting ? null : onJudge,
              child: const Text('判断'),
            ),
            FilledButton.tonal(
              onPressed: isAnyActionExecuting ? null : onExecute,
              child: Text(isExecuting ? '执行中' : '执行'),
            ),
          ],
        ),
      ],
    );
  }
}

class _XiaoyiLogList extends StatelessWidget {
  const _XiaoyiLogList({required this.logs});

  final List<XiaoyiLeadershipLog> logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _XiaoyiSpriteIcon(size: 22, showGlow: false),
              const SizedBox(width: 8),
              Text(
                '联动日志',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final log in logs.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${log.timeLabel} · ${log.kind}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      log.message,
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
    );
  }
}

class _XiaoyiSpriteIcon extends StatelessWidget {
  const _XiaoyiSpriteIcon({required this.size, this.showGlow = true});

  final double size;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primaryContainer.withValues(alpha: 0.38),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.22),
                  blurRadius: size * 0.35,
                  offset: Offset(0, size * 0.08),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/xiaoyi_maritime_officer.png',
        fit: BoxFit.cover,
        semanticLabel: '小懿Q版海事训练顾问',
      ),
    );
  }
}

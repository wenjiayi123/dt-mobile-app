import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audit/application/audit_controller.dart';
import '../../demo/application/demo_flow_controller.dart';
import '../../home/application/home_tab_notifier.dart';
import '../application/rl_training_controller.dart';
import '../domain/shared_rl_contract.dart';

class RlTrainingLinkageCard extends ConsumerStatefulWidget {
  const RlTrainingLinkageCard({super.key});

  @override
  ConsumerState<RlTrainingLinkageCard> createState() =>
      _RlTrainingLinkageCardState();
}

class _RlTrainingLinkageCardState extends ConsumerState<RlTrainingLinkageCard> {
  bool _handoffSheetShown = false;
  bool _handoffSheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rlTrainingProvider.notifier).checkConnection();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rlTrainingProvider);
    final demoStage = ref.watch(demoFlowProvider.select((flow) => flow.stage));
    final activeTab = ref.watch(homeTabProvider);
    final controller = ref.read(rlTrainingProvider.notifier);
    if (demoStage != DemoFlowStage.strategy) {
      _handoffSheetShown = false;
    }
    if (demoStage == DemoFlowStage.strategy &&
        activeTab == HomeTab.strategy &&
        !_handoffSheetShown &&
        !_handoffSheetOpen &&
        !state.hasRequest) {
      _handoffSheetShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openTrainingHandoffSheet();
      });
    }
    final accent = switch (state.phase) {
      RlDesktopTrainingPhase.rejected ||
      RlDesktopTrainingPhase.failed => const Color(0xFFFF6F91),
      RlDesktopTrainingPhase.completed => const Color(0xFF76F7C5),
      RlDesktopTrainingPhase.waitingDesktopApproval => const Color(0xFFFFB45C),
      _ => const Color(0xFF4DE4FF),
    };

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A213D), Color(0xFF132455), Color(0xFF251A55)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.13),
            blurRadius: 24,
            spreadRadius: -10,
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
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.hub_outlined, color: accent),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '电脑端强化学习训练',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '手机发起 · 电脑审批 · 双端同步',
                      style: TextStyle(
                        color: Color(0xFF9DC8F8),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _LinkStatusPill(
                label: state.phaseLabel,
                color: accent,
                icon: state.desktopOnline
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
              ),
            ],
          ),
          const SizedBox(height: 11),
          const Text(
            '手机只负责提交与查看证据。电脑端批准后，Python 训练器仅读取时间顺序训练集并关闭渲染；训练进程结束后，才在留出测试集记录回放轨迹。',
            style: TextStyle(
              color: Color(0xFFD2E5FF),
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          _DatasetEvidenceStrip(state: state),
          const SizedBox(height: 12),
          _HumanGateRail(phase: state.phase),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '参数来源 · ${state.configSourceLabel}',
                  style: const TextStyle(
                    color: Color(0xFFBDFBE1),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed:
                    state.phase ==
                            RlDesktopTrainingPhase.waitingDesktopApproval ||
                        state.phase == RlDesktopTrainingPhase.training ||
                        state.phase == RlDesktopTrainingPhase.evaluating
                    ? null
                    : controller.applyXiaoyiRecommendedConfig,
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('小懿推荐默认参数'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _ConfigSummary(config: state.config),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      state.phase ==
                              RlDesktopTrainingPhase.waitingDesktopApproval ||
                          state.phase == RlDesktopTrainingPhase.training ||
                          state.phase == RlDesktopTrainingPhase.evaluating
                      ? null
                      : () async {
                          final config = await _showConfigSheet(
                            context,
                            state.config,
                            state.algorithms,
                          );
                          if (config != null) controller.updateConfig(config);
                        },
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('配置训练参数'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _primaryAction(state, controller),
                  icon: state.isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_primaryIcon(state.phase)),
                  label: Text(_primaryLabel(state.phase)),
                ),
              ),
            ],
          ),
          if (state.hasRequest ||
              state.phase == RlDesktopTrainingPhase.failed) ...[
            const SizedBox(height: 12),
            _TrainingProgressPanel(state: state, accent: accent),
          ],
          if (state.hasRequest) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('rl-training-reset'),
                onPressed: state.isBusy
                    ? null
                    : () {
                        controller.reset();
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('已清除本次任务视图，可以重新提交训练申请'),
                            ),
                          );
                      },
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('重置'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFFC46B),
                  side: const BorderSide(color: Color(0x99FFC46B)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.desktop_windows_outlined,
                color: Color(0xFF7BA2D4),
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '电脑端确认页：${state.desktopPanelUrl.replaceFirst(RegExp(r'^https?://'), '')}',
                  style: const TextStyle(
                    color: Color(0xFF7BA2D4),
                    fontSize: 10,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: state.desktopLaunchInProgress
                    ? null
                    : controller.launchDesktopPanel,
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: Text(state.desktopPanelActive ? '电脑端已打开' : '打开电脑端系统'),
              ),
            ],
          ),
          Text(
            state.desktopLaunchMessage,
            style: TextStyle(
              color: state.desktopPanelActive
                  ? const Color(0xFF76F7C5)
                  : const Color(0xFF7BA2D4),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTrainingHandoffSheet() async {
    if (_handoffSheetOpen || !mounted) return;
    _handoffSheetOpen = true;
    try {
      final action = await showModalBottomSheet<_HandoffSheetAction>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: const Color(0xFF071226),
        builder: (sheetContext) => _TrainingHandoffSheet(
          onManualConfig: () =>
              Navigator.of(sheetContext).pop(_HandoffSheetAction.manualConfig),
          onSubmit: () =>
              _submitTrainingRequest(ref.read(rlTrainingProvider.notifier)),
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
      );
      if (!mounted || action != _HandoffSheetAction.manualConfig) return;
      final current = ref.read(rlTrainingProvider);
      final config = await _showConfigSheet(
        context,
        current.config,
        current.algorithms,
      );
      if (!mounted) return;
      if (config != null) {
        ref.read(rlTrainingProvider.notifier).updateConfig(config);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openTrainingHandoffSheet();
      });
    } finally {
      _handoffSheetOpen = false;
    }
  }

  Future<bool> _submitTrainingRequest(RlTrainingController controller) async {
    final ok = await controller.submitTrainingRequest();
    if (!mounted || !ok) return ok;
    final requestId = ref.read(rlTrainingProvider).requestId;
    ref
        .read(auditTimelineProvider.notifier)
        .recordAction(
          'ai_suggestion',
          meta: <String, Object?>{
            'source': 'mobile_rl_training_request',
            'stateSummary': '数据指纹与训练参数已提交电脑端',
            'policySetSummary': '真实七算法训练申请 $requestId',
            'humanChoiceSummary': '等待电脑端人工批准，移动端不可绕过',
            'targetPolicyTitle': '港口交通流策略训练',
          },
        );
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('训练申请已到电脑端，请切换到电脑进行人工批准')));
    return true;
  }

  VoidCallback? _primaryAction(
    RlTrainingState state,
    RlTrainingController controller,
  ) {
    if (state.isBusy) return null;
    switch (state.phase) {
      case RlDesktopTrainingPhase.waitingDesktopApproval:
        return controller.refreshStatus;
      case RlDesktopTrainingPhase.approved:
      case RlDesktopTrainingPhase.training:
      case RlDesktopTrainingPhase.evaluating:
      case RlDesktopTrainingPhase.completed:
        return controller.refreshStatus;
      case RlDesktopTrainingPhase.checkingConnection:
      case RlDesktopTrainingPhase.preparingRequest:
        return null;
      case RlDesktopTrainingPhase.idle:
      case RlDesktopTrainingPhase.rejected:
      case RlDesktopTrainingPhase.failed:
        return () async {
          await _submitTrainingRequest(controller);
        };
    }
  }

  static String _primaryLabel(RlDesktopTrainingPhase phase) => switch (phase) {
    RlDesktopTrainingPhase.checkingConnection => '检查电脑端连接',
    RlDesktopTrainingPhase.preparingRequest => '正在提交训练申请',
    RlDesktopTrainingPhase.waitingDesktopApproval => '检查电脑端审批结果',
    RlDesktopTrainingPhase.approved ||
    RlDesktopTrainingPhase.training => '刷新训练进度',
    RlDesktopTrainingPhase.evaluating => '刷新留出测试',
    RlDesktopTrainingPhase.completed => '刷新训练结果',
    RlDesktopTrainingPhase.rejected => '修改后重新提交',
    _ => '向电脑端提交训练申请',
  };

  static IconData _primaryIcon(RlDesktopTrainingPhase phase) => switch (phase) {
    RlDesktopTrainingPhase.waitingDesktopApproval => Icons.approval_outlined,
    RlDesktopTrainingPhase.approved ||
    RlDesktopTrainingPhase.training ||
    RlDesktopTrainingPhase.evaluating => Icons.sync_rounded,
    RlDesktopTrainingPhase.completed => Icons.task_alt_rounded,
    _ => Icons.send_to_mobile_outlined,
  };
}

enum _HandoffSheetAction { manualConfig }

class _TrainingHandoffSheet extends ConsumerWidget {
  const _TrainingHandoffSheet({
    required this.onManualConfig,
    required this.onSubmit,
    required this.onClose,
  });

  final VoidCallback onManualConfig;
  final Future<bool> Function() onSubmit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rlTrainingProvider);
    final controller = ref.read(rlTrainingProvider.notifier);
    final parametersReady = state.configSource != 'default';
    final canSubmit =
        parametersReady &&
        state.desktopPanelActive &&
        !state.hasRequest &&
        !state.isBusy;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.91,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1769E0), Color(0xFF098F91)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.sync_alt_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '手机 × 电脑训练接力',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '先确定参数，再打开电脑端，最后由电脑人工批准',
                          style: TextStyle(
                            color: Color(0xFF9DC8F8),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '暂不启动',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _HandoffStepCard(
                number: '1',
                title: '确定训练参数',
                status: parametersReady ? state.configSourceLabel : '等待选择',
                active: parametersReady,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '推荐值来自当前数据契约和可复现默认种子：PPO、2 万步、训练集无渲染。它只是起始配置，不代表已经收敛。',
                      style: TextStyle(
                        color: Color(0xFFD2E5FF),
                        fontSize: 10,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ConfigSummary(config: state.config),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: controller.applyXiaoyiRecommendedConfig,
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: const Text('使用小懿推荐参数'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onManualConfig,
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('手动配置参数'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 11),
              _HandoffStepCard(
                number: '2',
                title: '启动电脑端强化学习系统',
                status: state.desktopPanelActive ? '桌面审批页已打开' : '等待启动',
                active: state.desktopPanelActive,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.desktopLaunchMessage,
                      style: TextStyle(
                        color: state.desktopPanelActive
                            ? const Color(0xFF76F7C5)
                            : const Color(0xFFB9CDEB),
                        fontSize: 10,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      state.desktopPanelUrl,
                      style: const TextStyle(
                        color: Color(0xFF6FCBFF),
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            !parametersReady || state.desktopLaunchInProgress
                            ? null
                            : controller.launchDesktopPanel,
                        icon: state.desktopLaunchInProgress
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.desktop_windows_rounded),
                        label: Text(
                          state.desktopPanelActive ? '电脑端系统已打开' : '启动并打开电脑端系统',
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: state.desktopLaunchInProgress
                            ? null
                            : controller.refreshDesktopPanelStatus,
                        icon: const Icon(Icons.sync_rounded, size: 15),
                        label: const Text('刷新桌面在线状态'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 11),
              _HandoffStepCard(
                number: '3',
                title: '提交申请，转到电脑人工批准',
                status: state.hasRequest ? '电脑端已收到申请' : '尚未提交',
                active: state.hasRequest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '手机提交后仍不会创建训练 Job。你需要切换到电脑，在“移动端训练申请”中点击“电脑端批准并启动训练”。',
                      style: TextStyle(
                        color: Color(0xFFD2E5FF),
                        fontSize: 10,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: canSubmit ? onSubmit : null,
                        icon: const Icon(Icons.send_to_mobile_outlined),
                        label: Text(
                          state.hasRequest ? '训练申请已提交到电脑端' : '向电脑端提交训练申请',
                        ),
                      ),
                    ),
                    if (!parametersReady || !state.desktopPanelActive) ...[
                      const SizedBox(height: 7),
                      Text(
                        !parametersReady
                            ? '请先选择“小懿推荐参数”或“手动配置参数”。'
                            : '请先启动电脑端系统，确认桌面审批页在线。',
                        style: const TextStyle(
                          color: Color(0xFFFFD08A),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: state.hasRequest ? onClose : null,
                  icon: const Icon(Icons.screen_share_outlined),
                  label: const Text('申请已提交 · 切换到电脑端人工确认'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HandoffStepCard extends StatelessWidget {
  const _HandoffStepCard({
    required this.number,
    required this.title,
    required this.status,
    required this.active,
    required this.child,
  });

  final String number;
  final String title;
  final String status;
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF76F7C5) : const Color(0xFF4DE4FF);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1830),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 27,
                height: 27,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: color),
                ),
                child: Text(
                  number,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          child,
        ],
      ),
    );
  }
}

class _HumanGateRail extends StatelessWidget {
  const _HumanGateRail({required this.phase});

  final RlDesktopTrainingPhase phase;

  @override
  Widget build(BuildContext context) {
    final requestDone =
        phase.index >= RlDesktopTrainingPhase.waitingDesktopApproval.index &&
        phase != RlDesktopTrainingPhase.failed;
    final approved = <RlDesktopTrainingPhase>{
      RlDesktopTrainingPhase.approved,
      RlDesktopTrainingPhase.training,
      RlDesktopTrainingPhase.evaluating,
      RlDesktopTrainingPhase.completed,
    }.contains(phase);
    final training =
        phase == RlDesktopTrainingPhase.training ||
        phase == RlDesktopTrainingPhase.evaluating ||
        phase == RlDesktopTrainingPhase.completed;
    return Row(
      children: [
        Expanded(
          child: _GateNode(
            label: '手机提交',
            active: requestDone,
            icon: Icons.phone_android,
          ),
        ),
        _GateLine(active: approved),
        Expanded(
          child: _GateNode(
            label: '电脑人工批准',
            active: approved,
            icon: Icons.verified_user_outlined,
          ),
        ),
        _GateLine(active: training),
        Expanded(
          child: _GateNode(
            label: '训练→测试回放',
            active: training,
            icon: Icons.model_training_outlined,
          ),
        ),
      ],
    );
  }
}

class _GateNode extends StatelessWidget {
  const _GateNode({
    required this.label,
    required this.active,
    required this.icon,
  });
  final String label;
  final bool active;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 31,
        height: 31,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? const Color(0xFF147E83) : const Color(0xFF18294A),
          border: Border.all(
            color: active ? const Color(0xFF76F7C5) : const Color(0xFF385078),
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: active ? Colors.white : const Color(0xFF7790B4),
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: active ? const Color(0xFFBDFBE1) : const Color(0xFF7894BD),
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _GateLine extends StatelessWidget {
  const _GateLine({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 19),
      color: active ? const Color(0xFF76F7C5) : const Color(0xFF304667),
    ),
  );
}

class _ConfigSummary extends StatelessWidget {
  const _ConfigSummary({required this.config});
  final RlTrainingConfig config;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: const Color(0xA807142A),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF2B4168)),
    ),
    child: Row(
      children: [
        Expanded(
          child: _ConfigItem(label: '算法', value: config.algorithmLabel),
        ),
        Expanded(
          child: _ConfigItem(
            label: config.algorithm == 'mpc' ? '滚动求解' : '训练步数',
            value: config.algorithm == 'mpc'
                ? '无需训练'
                : _compactInt(config.totalSteps),
          ),
        ),
        Expanded(
          child: _ConfigItem(
            label: '批大小',
            value: config.algorithm == 'mpc' ? '不适用' : '${config.batchSize}',
          ),
        ),
        Expanded(
          child: _ConfigItem(label: '护栏', value: config.guardrailLabel),
        ),
      ],
    ),
  );
}

class _DatasetEvidenceStrip extends StatelessWidget {
  const _DatasetEvidenceStrip({required this.state});

  final RlTrainingState state;

  @override
  Widget build(BuildContext context) {
    final color = state.liveDataVerified
        ? const Color(0xFF76F7C5)
        : const Color(0xFFFFD08A);
    final hash = state.datasetSha256.length > 12
        ? state.datasetSha256.substring(0, 12)
        : state.datasetSha256;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 5,
        children: [
          Text(
            state.liveDataVerified
                ? '已验证实时数据'
                : '${state.datasetTitle} · 非生产实况',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '数据集 ${state.datasetId}',
            style: const TextStyle(color: Color(0xFFB9CDEB), fontSize: 9),
          ),
          Text(
            'SHA-256 $hash',
            style: const TextStyle(
              color: Color(0xFF7BA2D4),
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            state.sharedContractVerified
                ? '${state.algorithms.length}/7 算法契约已核验'
                : '${state.algorithms.length}/7 算法契约待核验',
            style: TextStyle(
              color: state.sharedContractVerified
                  ? const Color(0xFF76F7C5)
                  : const Color(0xFFFFD08A),
              fontSize: 9,
            ),
          ),
          Text(
            '${state.environmentVersion} · ${state.observationDimensions}D观测 / ${state.actionDimensions}D动作',
            style: const TextStyle(color: Color(0xFF7BA2D4), fontSize: 9),
          ),
          Text(
            '${state.formalRlRunCount}组RL正式训练 + ${state.formalControlBaselineCount}组MPC证据',
            style: const TextStyle(color: Color(0xFF7BA2D4), fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _ConfigItem extends StatelessWidget {
  const _ConfigItem({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFF7894BD), fontSize: 9),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _TrainingProgressPanel extends StatelessWidget {
  const _TrainingProgressPanel({required this.state, required this.accent});
  final RlTrainingState state;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xCC061126),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: accent.withValues(alpha: 0.32)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                state.stage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${state.progress.toStringAsFixed(1)}%',
              style: TextStyle(color: accent, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: state.progress / 100,
          minHeight: 7,
          borderRadius: BorderRadius.circular(10),
          backgroundColor: const Color(0xFF172C4B),
          color: accent,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ProgressMetric(
                label: state.config.algorithm == 'mpc' ? '求解方式' : '步数',
                value:
                    '${state.step} / ${state.totalStepsReported > 0 ? state.totalStepsReported : state.config.totalSteps}',
              ),
            ),
            Expanded(
              child: _ProgressMetric(
                label: '奖励',
                value: state.reward == 0
                    ? '待采样'
                    : state.reward.toStringAsFixed(2),
              ),
            ),
            Expanded(
              child: _ProgressMetric(label: '产物编号', value: state.policyVersion),
            ),
            Expanded(
              child: _ProgressMetric(label: '预计剩余', value: state.eta),
            ),
          ],
        ),
        if (state.evaluationMetrics.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ProgressMetric(
                  label: '测试平均收益',
                  value: (state.evaluationMetrics['mean_reward'] ?? 0)
                      .toStringAsFixed(3),
                ),
              ),
              Expanded(
                child: _ProgressMetric(
                  label: '测试平均拥堵',
                  value:
                      '${((state.evaluationMetrics['mean_congestion'] ?? 0) * 100).toStringAsFixed(1)}%',
                ),
              ),
              Expanded(
                child: _ProgressMetric(
                  label: '测试冲突风险',
                  value:
                      '${((state.evaluationMetrics['mean_conflict_risk'] ?? 0) * 100).toStringAsFixed(1)}%',
                ),
              ),
              Expanded(
                child: _ProgressMetric(
                  label: '测试回放',
                  value: state.renderReady
                      ? '${state.replayFrames.length} 帧'
                      : '尚未生成',
                ),
              ),
            ],
          ),
        ],
        if (state.requestId != null) ...[
          const SizedBox(height: 8),
          Text(
            '申请 ${state.requestId}${state.jobId == null ? ' · 尚无训练 Job' : ' · Job ${state.jobId}'}',
            style: const TextStyle(color: Color(0xFF7894BD), fontSize: 9),
          ),
        ],
        if (state.errorMessage != null) ...[
          const SizedBox(height: 7),
          Text(
            state.errorMessage!,
            style: const TextStyle(
              color: Color(0xFFFF9AAF),
              fontSize: 10,
              height: 1.35,
            ),
          ),
        ],
        if (state.logs.isNotEmpty) ...[
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFF030B19),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '训练链路日志',
                  style: TextStyle(
                    color: Color(0xFF76F7C5),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                for (final log in state.logs.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '› $log',
                      style: const TextStyle(
                        color: Color(0xFF9CB5D6),
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFF6E8AB2), fontSize: 8),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _LinkStatusPill extends StatelessWidget {
  const _LinkStatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

Future<RlTrainingConfig?> _showConfigSheet(
  BuildContext context,
  RlTrainingConfig initial,
  List<RlAlgorithmDescriptor> algorithms,
) async {
  var config = initial;
  final availableAlgorithms = algorithms.isEmpty
      ? sharedRlAlgorithmIds
            .map(
              (id) =>
                  MapEntry(id, sharedRlAlgorithmLabels[id] ?? id.toUpperCase()),
            )
            .toList(growable: false)
      : algorithms
            .map(
              (item) => MapEntry(
                item.id,
                sharedRlAlgorithmLabels[item.id] ?? item.label,
              ),
            )
            .toList(growable: false);
  return showModalBottomSheet<RlTrainingConfig>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            18,
            4,
            18,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '配置电脑端训练参数',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              const Text(
                '这些参数会随申请提交到电脑端；保存参数不会直接启动训练。',
                style: TextStyle(color: Color(0xFF7894BD), fontSize: 11),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: config.algorithm,
                decoration: const InputDecoration(
                  labelText: '七算法矩阵（6 RL + 1 控制）',
                ),
                items: [
                  for (final item in availableAlgorithms)
                    DropdownMenuItem(value: item.key, child: Text(item.value)),
                ],
                onChanged: (value) => setSheetState(() {
                  if (value == null) return;
                  config = config.copyWith(
                    algorithm: value,
                    totalSteps: value == 'mpc'
                        ? 0
                        : (config.totalSteps < 64 ? 20000 : config.totalSteps),
                  );
                }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: config.objective,
                decoration: const InputDecoration(labelText: '港口优化目标'),
                items: const [
                  DropdownMenuItem(
                    value: 'multi_objective',
                    child: Text('成本 + 碳排 + 峰值 + 安全 + 延误'),
                  ),
                ],
                onChanged: (value) => setSheetState(
                  () => config = config.copyWith(objective: value),
                ),
              ),
              const SizedBox(height: 14),
              _SheetChoiceRow(
                title: config.algorithm == 'mpc' ? '求解方式' : '训练步数',
                values: config.algorithm == 'mpc'
                    ? const [0]
                    : const [5000, 20000, 100000],
                selected: config.totalSteps,
                label: (value) =>
                    config.algorithm == 'mpc' ? '滚动时域优化' : _compactInt(value),
                onSelected: (value) => setSheetState(
                  () => config = config.copyWith(totalSteps: value),
                ),
              ),
              const SizedBox(height: 12),
              if (config.algorithm != 'mpc')
                _SheetChoiceRow(
                  title: '批大小',
                  values: const [128, 256, 512],
                  selected: config.batchSize,
                  label: (value) => '$value',
                  onSelected: (value) => setSheetState(
                    () => config = config.copyWith(batchSize: value),
                  ),
                ),
              const SizedBox(height: 12),
              _SheetChoiceRow(
                title: '安全护栏',
                values: const ['strict', 'balanced', 'explore'],
                selected: config.guardrail,
                label: (value) => switch (value) {
                  'strict' => '严格',
                  'balanced' => '均衡',
                  _ => '探索',
                },
                onSelected: (value) => setSheetState(
                  () => config = config.copyWith(guardrail: value),
                ),
              ),
              const SizedBox(height: 14),
              if (config.algorithm != 'mpc')
                Row(
                  children: [
                    Expanded(
                      child: _ReadOnlyParameter(
                        label: '学习率',
                        value: config.learningRate.toStringAsFixed(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ReadOnlyParameter(
                        label: '折扣因子',
                        value: config.gamma.toStringAsFixed(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ReadOnlyParameter(
                        label: '随机种子',
                        value: '${config.seed}',
                      ),
                    ),
                  ],
                )
              else
                _ReadOnlyParameter(
                  label: '校准方法',
                  value: '训练集网格搜索 · 留出测试集只评估不调参',
                ),
              const SizedBox(height: 10),
              _ReadOnlyParameter(
                label: '固定现场边界',
                value: '公开 AIS 聚合流量 · 5分钟粒度 · 时间顺序留出测试',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(config),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存训练参数'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SheetChoiceRow<T> extends StatelessWidget {
  const _SheetChoiceRow({
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });
  final String title;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      Wrap(
        spacing: 7,
        children: [
          for (final value in values)
            ChoiceChip(
              label: Text(label(value)),
              selected: value == selected,
              onSelected: (_) => onSelected(value),
            ),
        ],
      ),
    ],
  );
}

class _ReadOnlyParameter extends StatelessWidget {
  const _ReadOnlyParameter({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

String _compactInt(int value) {
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(value % 10000 == 0 ? 0 : 1)}万';
  }
  return '$value';
}

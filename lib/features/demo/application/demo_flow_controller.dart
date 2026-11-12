import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/platform/same_window_navigation.dart';

// Legacy phases are retained for the existing safety-gate integration. The
// visible guide below is driven by explicit action IDs instead of these phases.
enum DemoFlowStage {
  ready,
  stable,
  boundary,
  alert,
  strategy,
  executing,
  audit,
}

extension DemoFlowStageX on DemoFlowStage {
  String get timeLabel => const [
    '待启动',
    'T+0s',
    'T+20s',
    'T+40s',
    'T+60s',
    'T+90s',
    'T+120s',
  ][index];
  String get shortLabel =>
      const ['准备', '稳态', '预警', '告警', '策略', '执行', '审计'][index];
  String get headline => const [
    '现场演示尚未启动',
    '态势与数据证据',
    '风险边界',
    '异常与告警',
    'RL 训练与策略',
    '人工确认与安全门',
    '审计凭证与回溯',
  ][index];
  String get narrative => const [
    '用真实页面按钮展示 PortAI 的移动决策闭环。',
    '刷新共享后端态势，核对数据时间和证据标签。',
    '查看风险区间、适用范围和生产权限边界。',
    '告警来自共享后端，离线时明确标记。',
    '训练任务经人工确认后由电脑端 worker 执行。',
    '移动端不绕过生产安全门。',
    '任务、数据集、参数、结果和 Trace ID 可完整回溯。',
  ][index];
  String get nextActionLabel => '继续演示';
  int get targetTabIndex => switch (this) {
    DemoFlowStage.ready || DemoFlowStage.stable || DemoFlowStage.boundary => 0,
    DemoFlowStage.alert => 2,
    DemoFlowStage.strategy || DemoFlowStage.executing => 1,
    DemoFlowStage.audit => 3,
  };
}

enum DemoActionOrigin { guide, page }

enum DemoStepStatus { idle, running, resultReady, failed, skipped }

@immutable
class DemoGuideStep {
  const DemoGuideStep({
    required this.id,
    required this.section,
    required this.title,
    required this.actionId,
    required this.actionLabel,
    required this.narration,
    required this.expectedChange,
    this.prepareActionId,
    this.timeout = const Duration(seconds: 12),
  });
  final String id;
  final String section;
  final String title;
  final String actionId;
  final String actionLabel;
  final String narration;
  final String expectedChange;
  final String? prepareActionId;
  final Duration timeout;
}

const List<DemoGuideStep> portAiDemoSteps = <DemoGuideStep>[
  DemoGuideStep(
    id: 'trained-evidence',
    section: '场景证据',
    title: '已训练场景算法与数据清单',
    actionId: 'trained-evidence',
    actionLabel: '显示全部已训练场景',
    narration:
        '每个已训练场景列出具体算法、数据集名称和数量、State、Reward、Action与输出，并附训练记录、来源文件、模型哈希和准入结论。移动端与港口Web共用同一训练服务，工程派生量按原证据标注。',
    expectedChange: '打开全部已训练场景清单，可选择场景并展开六项明细。',
  ),
  DemoGuideStep(
    id: 'opening',
    section: '核心闭环',
    title: 'PortAI 移动决策入口',
    actionId: 'open-dashboard',
    actionLabel: '返回运营总控',
    narration:
        'PortAI 把港口态势、RL 策略和审计收口到移动端。舷鸥负责理解任务并组织系统能力。本次是公开数据离线回放，无生产控制权。',
    expectedChange: '返回首页，显示运营总控、共享后端证据和舷鸥入口。',
  ),
  DemoGuideStep(
    id: 'situation',
    section: '核心闭环',
    title: '数据与实时态势',
    actionId: 'situation-refresh',
    prepareActionId: 'open-situation',
    actionLabel: '刷新真实态势',
    narration: '这一步调用页面原生刷新按钮。系统会更新稳定度、策略压力和风险区间。图表与数据时间会同步变化。',
    expectedChange: '刷新状态、数据时间、指标卡和趋势图同步更新。',
  ),
  DemoGuideStep(
    id: 'dataset',
    section: 'RL 重点',
    title: '官方训练数据集',
    actionId: 'rl-show-dataset',
    prepareActionId: 'open-strategy',
    actionLabel: '查看数据集证据',
    narration: '先核对数据来源机构与官方地址。再看时间范围、记录数、版本和 SHA-256。最后区分官方原始、校准派生与模拟字段。',
    expectedChange: '弹出宽屏数据证据面板，可核对数据集快照。',
  ),
  DemoGuideStep(
    id: 'contract',
    section: 'RL 重点',
    title: 'RL 训练契约',
    actionId: 'rl-show-contract',
    prepareActionId: 'open-strategy',
    actionLabel: '展开 State / Action / Reward',
    narration:
        '这里展示 State、Action 和 Reward 的业务含义。同时给出算法、步数和时间切分。约束惩罚与人工确认门槛也是合同的一部分。',
    expectedChange: '弹出宽屏训练契约面板，字段按业务含义分组展示。',
  ),
  DemoGuideStep(
    id: 'xiaoyi-task',
    section: '舷鸥主线',
    title: '舷鸥下达 RL 任务',
    actionId: 'xiaoyi-rl-task',
    prepareActionId: 'open-dashboard',
    actionLabel: '输入并解析训练目标',
    narration: '舷鸥先识别优化对象和业务指标。然后生成训练契约与推荐算法。任务只会送入待确认区，不会越过人工安全门。',
    expectedChange: '输入框显示任务，返回意图识别、参数建议、权限边界和追踪号。',
  ),
  DemoGuideStep(
    id: 'xiaoyi-config',
    section: 'RL 重点',
    title: '应用舷鸥推荐参数',
    actionId: 'rl-xiaoyi-config',
    prepareActionId: 'open-strategy',
    actionLabel: '应用推荐参数',
    narration: '舷鸥会写入推荐的训练参数。页面会明确标记参数来源。它们仍是待确认状态，不会绕过人工安全门。',
    expectedChange: '参数来源切换为“舷鸥推荐”，配置摘要随之更新。',
  ),
  DemoGuideStep(
    id: 'handoff',
    section: 'RL 重点',
    title: '手机 × 电脑训练接力',
    actionId: 'rl-open-handoff',
    prepareActionId: 'open-strategy',
    actionLabel: '下发任务并进入电脑端',
    narration:
        '这一次点击会由舷鸥应用参数并下发标准训练申请。系统随后在同一窗口进入电脑端，自动定位这条手机任务。电脑端仍需人工批准，不会越过安全门。',
    expectedChange: '切换到 Web RL 审批页，手机下发的任务自动滚动到视区并高亮。',
    timeout: Duration(seconds: 20),
  ),
  DemoGuideStep(
    id: 'curves',
    section: 'RL 重点',
    title: '历史收敛与业务价值',
    actionId: 'rl-show-curves',
    prepareActionId: 'open-strategy',
    actionLabel: '查看收敛曲线',
    narration: '先看 Reward 是否稳定收敛。再看 Actor/Critic 损失、成功率和违规率。最后对比基线、单目标与综合优化策略。',
    expectedChange: '决策面板切换到训练曲线，显示图例、关键点、检查点和结果卡。',
  ),
  DemoGuideStep(
    id: 'algorithms',
    section: 'RL 重点',
    title: '已训练模型指标',
    actionId: 'rl-show-algorithms',
    prepareActionId: 'open-strategy',
    actionLabel: '对比算法与指标',
    narration: '这里对比各算法的留出集表现。成功率、违规次数和检查点同时可查。所有结果都标明适用边界，不冒充现场收益。',
    expectedChange: '面板切换到算法矩阵和业务指标对比。',
  ),
  DemoGuideStep(
    id: 'replay',
    section: '安全闭环',
    title: '留出集回放与安全门',
    actionId: 'rl-play-replay',
    prepareActionId: 'open-strategy',
    actionLabel: '播放 Dry-run 回放',
    narration: '训练结束后不会直接上线。系统先播放独立留出集，检查约束和违规。恢复需要达到安全门槛，生产权限仍是关闭。',
    expectedChange: '回放帧进度、运行指标和风险状态逐帧变化，并写入审计。',
  ),
  DemoGuideStep(
    id: 'audit',
    section: '安全闭环',
    title: '标准化结果凭证',
    actionId: 'open-audit',
    actionLabel: '打开审计回溯',
    narration:
        '每次操作都会生成标准化结果凭证。凭证包含数据版本、算法参数、指标与验证结论。Trace ID、时间戳和生产权限状态可用于回溯。',
    expectedChange: '切换到审计页，显示最新任务时间线和可追踪字段。',
  ),
  DemoGuideStep(
    id: 'general-qa',
    section: '舷鸥问答',
    title: '一般业务问答',
    actionId: 'xiaoyi-qa-general',
    prepareActionId: 'open-dashboard',
    actionLabel: '询问业务概念',
    narration: '打开蓝色业务问答工作台，逐段解释策略压力、数据依据和适用范围。当前为预设讲解示例，告警上下文读取当前业务快照。',
    expectedChange: '打开蓝色工作台，问题、进度和三段解释依次出现，可直接进入态势页。',
  ),
  DemoGuideStep(
    id: 'daily-qa',
    section: '舷鸥问答',
    title: '日常运行问答',
    actionId: 'xiaoyi-qa-daily',
    prepareActionId: 'open-dashboard',
    actionLabel: '询问日常运行',
    narration: '切换到绿色值班工作台，依次展示数据核对、异常处理和交班留痕。通过态势入口核对业务快照，操作建议保留人工确认。',
    expectedChange: '打开绿色清单，三项值班步骤逐项展开，并显示当前事件上下文。',
  ),
  DemoGuideStep(
    id: 'emergency-qa',
    section: '舷鸥问答',
    title: '紧急问答与升级',
    actionId: 'xiaoyi-qa-emergency',
    prepareActionId: 'open-dashboard',
    actionLabel: '模拟紧急问题',
    narration: '切换到橙红应急工作台。预设情景先讲风险结论，再展示人员保护、隔离通知和恢复门槛；可进入告警中心核对当前事件。',
    expectedChange: '橙红应急主视觉、处置顺序和恢复门槛依次出现，提供告警中心入口。',
  ),
  DemoGuideStep(
    id: 'alerts',
    section: '快速亮点',
    title: '风险识别与告警',
    actionId: 'open-alerts',
    actionLabel: '打开告警中心',
    narration: '这里快速看一下系统的风险识别。告警按优先级展示状态和处置进度。页面同时标明公开回放与生产告警的边界。',
    expectedChange: '进入风险总览，分级计数以大数字呈现，展示四段处置路径及下方事件列表。',
  ),
  DemoGuideStep(
    id: 'twin',
    section: '快速亮点',
    title: '高端 3D 数字孪生屏',
    actionId: 'open-twin-3d',
    prepareActionId: 'open-situation',
    actionLabel: '进入 3D 孪生屏',
    narration: '这是 PortAI 的三维数字孪生屏。可快速查看港区布局、对象槽位和轨迹回放。指标与共享后端同源，并明确标注演示边界。',
    expectedChange: '打开 3D 孪生页，视角、场景和运行指标可见。',
  ),
  DemoGuideStep(
    id: 'notifications',
    section: '快速亮点',
    title: '通知与任务升级',
    actionId: 'open-notifications',
    actionLabel: '打开通知中心',
    narration: '通知中心汇总任务进展与审批提醒。风险升级会显示更高优先级。每条通知保留时间、已读状态和可执行入口。',
    expectedChange: '打开通知列表，展示优先级、时间与已读状态。',
  ),
  DemoGuideStep(
    id: 'api',
    section: '快速亮点',
    title: '接口、环境与权限边界',
    actionId: 'open-settings',
    actionLabel: '查看接口设置',
    narration:
        '这里展示共享 API 和 WebSocket 地址。连接状态与运行环境可以现场核对。生产权限边界同时可见，证明 PortAI 具备联动接口。',
    expectedChange: '打开设置页，显示 API、WS、环境、连接状态和权限说明。',
  ),
];

@immutable
class DemoFlowLog {
  const DemoFlowLog({required this.at, required this.message});
  final DateTime at;
  final String message;
}

@immutable
class DemoFlowState {
  const DemoFlowState({
    required this.enabled,
    required this.stage,
    required this.logs,
    required this.isOpen,
    required this.isCollapsed,
    required this.currentStepIndex,
    required this.stepStatus,
    required this.completedStepIds,
    required this.traceId,
    this.statusMessage,
    this.startedAt,
    this.updatedAt,
  });

  factory DemoFlowState.initial() => const DemoFlowState(
    enabled: false,
    stage: DemoFlowStage.ready,
    logs: <DemoFlowLog>[],
    isOpen: false,
    isCollapsed: false,
    currentStepIndex: 0,
    stepStatus: DemoStepStatus.idle,
    completedStepIds: <String>{},
    traceId: '',
  );

  final bool enabled;
  final DemoFlowStage stage;
  final List<DemoFlowLog> logs;
  final bool isOpen;
  final bool isCollapsed;
  final int currentStepIndex;
  final DemoStepStatus stepStatus;
  final Set<String> completedStepIds;
  final String traceId;
  final String? statusMessage;
  final DateTime? startedAt;
  final DateTime? updatedAt;

  DemoGuideStep get currentStep =>
      portAiDemoSteps[currentStepIndex.clamp(0, portAiDemoSteps.length - 1)];
  bool get isRunning => enabled && stage != DemoFlowStage.ready;
  bool get isComplete =>
      stage == DemoFlowStage.audit ||
      (currentStepIndex == portAiDemoSteps.length - 1 &&
          (stepStatus == DemoStepStatus.resultReady ||
              stepStatus == DemoStepStatus.skipped));
  bool get isBusy => stepStatus == DemoStepStatus.running;
  bool get legacyStageCardsEnabled => false;
  double get progress =>
      (currentStepIndex + (stepStatus == DemoStepStatus.resultReady ? 1 : 0)) /
      portAiDemoSteps.length;
  bool get canAdvanceManually =>
      enabled && stage.index <= DemoFlowStage.alert.index;

  DemoFlowState copyWith({
    bool? enabled,
    DemoFlowStage? stage,
    List<DemoFlowLog>? logs,
    bool? isOpen,
    bool? isCollapsed,
    int? currentStepIndex,
    DemoStepStatus? stepStatus,
    Set<String>? completedStepIds,
    String? traceId,
    Object? statusMessage = _unset,
    Object? startedAt = _unset,
    Object? updatedAt = _unset,
  }) => DemoFlowState(
    enabled: enabled ?? this.enabled,
    stage: stage ?? this.stage,
    logs: logs ?? this.logs,
    isOpen: isOpen ?? this.isOpen,
    isCollapsed: isCollapsed ?? this.isCollapsed,
    currentStepIndex: currentStepIndex ?? this.currentStepIndex,
    stepStatus: stepStatus ?? this.stepStatus,
    completedStepIds: completedStepIds ?? this.completedStepIds,
    traceId: traceId ?? this.traceId,
    statusMessage: identical(statusMessage, _unset)
        ? this.statusMessage
        : statusMessage as String?,
    startedAt: identical(startedAt, _unset)
        ? this.startedAt
        : startedAt as DateTime?,
    updatedAt: identical(updatedAt, _unset)
        ? this.updatedAt
        : updatedAt as DateTime?,
  );
}

const Object _unset = Object();
typedef DemoAction = FutureOr<void> Function();

final demoFlowProvider = NotifierProvider<DemoFlowController, DemoFlowState>(
  DemoFlowController.new,
);

class DemoFlowController extends Notifier<DemoFlowState> {
  static const _prefsPrefix = 'portai_demo_v2_';
  static const _routeOpenActionIds = <String>{
    'open-twin-3d',
    'open-notifications',
    'open-settings',
  };
  final Map<String, DemoAction> _actions = <String, DemoAction>{};
  final Map<String, Completer<void>> _waiters = <String, Completer<void>>{};
  Future<void>? _inFlight;
  late Future<void> _restoration;
  Future<void> _writeQueue = Future<void>.value();
  int _revision = 0;

  @override
  DemoFlowState build() {
    _restoration = _restore();
    return DemoFlowState.initial();
  }

  Future<void> get restorationComplete => _restoration;

  Future<Map<String, String>> checkpointForExternalNavigation() async {
    await _restoration;
    final snapshot = _progressSnapshot(state);
    await _persist();
    return <String, String>{'portai_demo_resume': jsonEncode(snapshot)};
  }

  Future<void> saveProgress() => _persist();

  bool isActionRegistered(String id) => _actions.containsKey(id);
  void registerAction(String id, DemoAction action) {
    _actions[id] = action;
    final waiter = _waiters.remove(id);
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void unregisterAction(String id, DemoAction action) {
    if (identical(_actions[id], action)) _actions.remove(id);
  }

  Future<void> triggerAction(
    String id, {
    DemoActionOrigin origin = DemoActionOrigin.guide,
  }) {
    if (_inFlight != null) return _inFlight!;
    final run = _restoration.then((_) => _runAction(id, origin));
    _inFlight = run;
    return run.whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
  }

  Future<void> _runAction(String id, DemoActionOrigin origin) async {
    final exactIndex = portAiDemoSteps.indexWhere(
      (step) => step.actionId == id,
    );
    final prepareIndex = portAiDemoSteps.indexWhere(
      (step) => step.prepareActionId == id,
    );
    final index = exactIndex >= 0 ? exactIndex : prepareIndex;
    final navigationOnly =
        origin == DemoActionOrigin.page && exactIndex < 0 && prepareIndex >= 0;
    if (origin == DemoActionOrigin.page && index >= 0) {
      _revision++;
      state = state.copyWith(
        enabled: true,
        isOpen: true,
        currentStepIndex: index,
        stepStatus: DemoStepStatus.running,
        statusMessage: '已识别页面原生操作，正在同步结果…',
        traceId: state.traceId.isEmpty ? _newTraceId() : state.traceId,
      );
    } else {
      state = state.copyWith(
        enabled: true,
        isOpen: true,
        stepStatus: DemoStepStatus.running,
        statusMessage: '操作已发起，正在等待页面结果…',
        traceId: state.traceId.isEmpty ? _newTraceId() : state.traceId,
      );
    }
    final token = ++_revision;
    final step = state.currentStep;
    try {
      if (origin == DemoActionOrigin.guide && step.prepareActionId != null) {
        await _invoke(step.prepareActionId!, const Duration(seconds: 4));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      await _invoke(id, step.timeout);
      if (token != _revision) return;
      if (navigationOnly) {
        state = state.copyWith(
          stepStatus: DemoStepStatus.idle,
          statusMessage: '已同步到“${step.title}”，请执行该步骤的真实业务按钮。',
          updatedAt: DateTime.now(),
        );
        unawaited(_persist());
        return;
      }
      state = state.copyWith(
        stepStatus: DemoStepStatus.resultReady,
        completedStepIds: <String>{...state.completedStepIds, step.id},
        statusMessage: '页面结果已出现。请完成当前讲解后再进入下一步。',
        updatedAt: DateTime.now(),
        logs: _prependLog('完成：${step.title}'),
      );
      unawaited(_persist());
    } on TimeoutException {
      if (token == _revision) {
        state = state.copyWith(
          stepStatus: DemoStepStatus.failed,
          statusMessage: '等待超时：可重试、重置本步或保底下一步。',
        );
      }
    } catch (error) {
      if (token == _revision) {
        state = state.copyWith(
          stepStatus: DemoStepStatus.failed,
          statusMessage: '操作失败：$error。流程未锁死，可重试或保底继续。',
        );
      }
    }
  }

  Future<void> _invoke(String id, Duration timeout) async {
    var action = _actions[id];
    if (action == null) {
      final waiter = _waiters.putIfAbsent(id, Completer<void>.new);
      await waiter.future.timeout(const Duration(seconds: 3));
      action = _actions[id];
    }
    if (action == null) throw StateError('页面操作尚未就绪：$id');
    if (_routeOpenActionIds.contains(id)) {
      // Navigator.push returns a Future that resolves only after the route is
      // closed. For a demo step, opening the native page is the visible result;
      // waiting for pop would make the guide look frozen.
      action();
      return;
    }
    await Future<void>.sync(action).timeout(timeout);
  }

  void openGuide() {
    _revision++;
    state = state.copyWith(
      enabled: true,
      isOpen: true,
      isCollapsed: false,
      traceId: state.traceId.isEmpty ? _newTraceId() : state.traceId,
      statusMessage: state.statusMessage ?? '演示控制台已就绪。',
    );
    unawaited(_persist());
  }

  void closeGuide() {
    _revision++;
    state = state.copyWith(isOpen: false, isCollapsed: false);
    unawaited(_persist());
  }

  void toggleCollapsed() {
    state = state.copyWith(isCollapsed: !state.isCollapsed);
    unawaited(_persist());
  }

  Future<void> advanceAndRun() async {
    if (state.isBusy || state.currentStepIndex >= portAiDemoSteps.length - 1) {
      return;
    }
    final before = state.currentStepIndex;
    completeNarrationAndNext();
    if (state.currentStepIndex == before) return;
    final token = _revision;
    final actionId = state.currentStep.actionId;
    state = state.copyWith(
      stepStatus: DemoStepStatus.running,
      statusMessage: '正在进入并执行下一步…',
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (token != _revision || !state.isOpen) return;
    await triggerAction(actionId);
  }

  void completeNarrationAndNext() {
    if (state.isBusy ||
        (state.stepStatus != DemoStepStatus.resultReady &&
            state.stepStatus != DemoStepStatus.skipped)) {
      return;
    }
    if (state.currentStepIndex >= portAiDemoSteps.length - 1) {
      state = state.copyWith(statusMessage: '演示完成。可重新开始或关闭控制台。');
      return;
    }
    _revision++;
    state = state.copyWith(
      currentStepIndex: state.currentStepIndex + 1,
      stepStatus: DemoStepStatus.idle,
      statusMessage: '下一步已就绪。',
    );
    unawaited(_persist());
  }

  void retryCurrentStep() {
    if (!state.isBusy) {
      state = state.copyWith(
        stepStatus: DemoStepStatus.idle,
        statusMessage: '已就绪，请重试本步。',
      );
    }
  }

  void resetCurrentStep() {
    _revision++;
    final ids = <String>{...state.completedStepIds}
      ..remove(state.currentStep.id);
    state = state.copyWith(
      stepStatus: DemoStepStatus.idle,
      completedStepIds: ids,
      statusMessage: '已重置本步引导状态；后端审计证据不会被伪造或删除。',
    );
    unawaited(_persist());
  }

  void fallbackNext() {
    if (state.isBusy) _revision++;
    state = state.copyWith(
      stepStatus: DemoStepStatus.skipped,
      statusMessage: '本步已保底跳过，可继续演示。',
      logs: _prependLog('保底跳过：${state.currentStep.title}'),
    );
    unawaited(_persist());
  }

  void jumpToStep(int index) {
    if (index < 0 || index >= portAiDemoSteps.length || state.isBusy) return;
    _revision++;
    state = state.copyWith(
      enabled: true,
      isOpen: true,
      currentStepIndex: index,
      stepStatus: state.completedStepIds.contains(portAiDemoSteps[index].id)
          ? DemoStepStatus.resultReady
          : DemoStepStatus.idle,
      statusMessage: '已跳转到指定步骤。',
    );
    unawaited(_persist());
  }

  Future<void> markExternalNavigationPending() async {
    if (!state.enabled || state.currentStep.id != 'handoff') return;
    // Requesting browser navigation does not prove that the destination opened.
    _revision++;
    state = state.copyWith(
      stepStatus: DemoStepStatus.idle,
      completedStepIds: {...state.completedStepIds}..remove('handoff'),
      statusMessage: '已请求打开电脑审批页；返回匹配的结果凭证后，本步才完成。',
    );
    await _persist();
  }

  void acceptExternalReceipt({required String traceId}) {
    if (!state.enabled || state.currentStep.id != 'handoff' ||
        traceId.isEmpty || traceId != state.traceId) return;
    _revision++;
    state = state.copyWith(
      enabled: true,
      isOpen: true,
      stepStatus: DemoStepStatus.resultReady,
      completedStepIds: <String>{
        ...state.completedStepIds,
        state.currentStep.id,
      },
      traceId: traceId.isEmpty ? state.traceId : traceId,
      statusMessage: '目标系统结果凭证已返回，舷鸥和审计链已回收。可完成当前讲解后继续。',
      updatedAt: DateTime.now(),
      logs: _prependLog('跨系统凭证已返回 PortAI'),
    );
    unawaited(_persist());
  }

  void restart() {
    final now = DateTime.now();
    _revision++;
    state = DemoFlowState.initial().copyWith(
      enabled: true,
      isOpen: true,
      stage: DemoFlowStage.stable,
      startedAt: now,
      updatedAt: now,
      traceId: _newTraceId(),
      statusMessage: '新的演示会话已就绪。',
      logs: <DemoFlowLog>[DemoFlowLog(at: now, message: '从头开始 PortAI 现场演示')],
    );
    unawaited(_persist());
  }

  void resetAllGuide() => restart();

  // Backwards-compatible API used by existing gates and tests.
  void setEnabled(bool value) => value ? openGuide() : reset();
  void start() {
    if (!state.enabled) return;
    final now = DateTime.now();
    state = state.copyWith(
      stage: DemoFlowStage.stable,
      startedAt: now,
      updatedAt: now,
      isOpen: true,
      traceId: state.traceId.isEmpty ? _newTraceId() : state.traceId,
      logs: <DemoFlowLog>[DemoFlowLog(at: now, message: '现场演示已启动')],
    );
  }

  void advance() {
    if (!state.enabled) return;
    setStage(switch (state.stage) {
      DemoFlowStage.ready => DemoFlowStage.stable,
      DemoFlowStage.stable => DemoFlowStage.boundary,
      DemoFlowStage.boundary => DemoFlowStage.alert,
      DemoFlowStage.alert => DemoFlowStage.strategy,
      _ => state.stage,
    });
  }

  void markExecutionStarted() {
    if (state.enabled && state.isRunning) setStage(DemoFlowStage.executing);
  }

  void markAuditReady() {
    if (state.enabled && state.isRunning) setStage(DemoFlowStage.audit);
  }

  void setStage(DemoFlowStage stage) {
    if (!state.enabled || stage == state.stage) return;
    final now = DateTime.now();
    state = state.copyWith(
      stage: stage,
      startedAt: state.startedAt ?? now,
      updatedAt: now,
      logs: _prependLog('${stage.timeLabel} · ${stage.headline}'),
    );
  }

  void reset() {
    _revision++;
    state = DemoFlowState.initial();
    unawaited(_clearPrefs());
  }

  List<DemoFlowLog> _prependLog(String message) => <DemoFlowLog>[
    DemoFlowLog(at: DateTime.now(), message: message),
    ...state.logs,
  ].take(12).toList(growable: false);

  String _newTraceId() {
    final random = math.Random()
        .nextInt(0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    return 'PORTAI-${DateTime.now().millisecondsSinceEpoch}-$random'
        .toUpperCase();
  }

  Map<String, Object?> _progressSnapshot(DemoFlowState value) =>
      <String, Object?>{
        'version': 1,
        'enabled': value.enabled,
        'open': value.isOpen,
        'collapsed': value.isCollapsed,
        'step': value.currentStepIndex,
        'step_id': value.currentStep.id,
        'status': value.stepStatus.name,
        'completed': value.completedStepIds.toList(growable: false),
        'trace': value.traceId,
        'stage': value.stage.name,
        'started_at': value.startedAt?.toIso8601String(),
        'updated_at': value.updatedAt?.toIso8601String(),
      };

  Map<String, dynamic>? _decodeProgress(String? raw) {
    if (raw == null || raw.isEmpty || raw.length > 12000) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['version'] != 1 ||
          !portAiDemoSteps.any((step) => step.id == value['step_id'])) {
        return null;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _restore() async {
    final startRevision = _revision;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // A return URL checkpoint can still restore progress without storage.
    }
    if (!ref.mounted || _revision != startRevision) return;

    final fields = readCrossSystemReturnReceipt();
    var snapshot = _decodeProgress(fields['portai_demo_resume']);
    final receiptTrace = fields['trace_id'] ?? '';
    if (snapshot != null &&
        receiptTrace.isNotEmpty &&
        snapshot['trace'] != receiptTrace) {
      snapshot = null;
    }
    snapshot ??= _decodeProgress(prefs?.getString('${_prefsPrefix}snapshot'));
    if (snapshot == null) {
      if (!(prefs?.getBool('${_prefsPrefix}enabled') ?? false)) return;
      final index = (prefs?.getInt('${_prefsPrefix}step') ?? 0).clamp(
        0,
        portAiDemoSteps.length - 1,
      );
      snapshot = <String, dynamic>{
        'enabled': true,
        'open': prefs?.getBool('${_prefsPrefix}open') ?? true,
        'collapsed': prefs?.getBool('${_prefsPrefix}collapsed') ?? false,
        'step_id': portAiDemoSteps[index].id,
        'trace': prefs?.getString('${_prefsPrefix}trace') ?? _newTraceId(),
      };
    }
    if (snapshot['enabled'] != true) return;
    final index = portAiDemoSteps.indexWhere(
      (step) => step.id == snapshot!['step_id'],
    );
    if (index < 0) return;
    final savedStatus = DemoStepStatus.values.firstWhere(
      (value) => value.name == snapshot!['status'],
      orElse: () => DemoStepStatus.idle,
    );
    final knownIds = portAiDemoSteps.map((step) => step.id).toSet();
    final completed = snapshot['completed'];
    final trace = snapshot['trace']?.toString() ?? '';
    state = state.copyWith(
      enabled: true,
      isOpen: snapshot['open'] != false,
      isCollapsed: snapshot['collapsed'] == true,
      currentStepIndex: index,
      // A pending external operation needs its return receipt before completion.
      stepStatus: savedStatus == DemoStepStatus.running
          ? DemoStepStatus.idle
          : savedStatus,
      completedStepIds: completed is List
          ? completed.whereType<String>().where(knownIds.contains).toSet()
          : <String>{},
      traceId: trace.isEmpty ? _newTraceId() : trace,
      stage: DemoFlowStage.values.firstWhere(
        (value) => value.name == snapshot!['stage'],
        orElse: () => DemoFlowStage.stable,
      ),
      startedAt: DateTime.tryParse(snapshot['started_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(snapshot['updated_at']?.toString() ?? ''),
      statusMessage: '已恢复第 ${index + 1} 步演示进度。',
    );
  }

  Future<void> _persist() {
    // Capture one consistent revision before awaiting storage, then serialize
    // writes so an older async save cannot overwrite a newer checkpoint.
    final snapshot = _progressSnapshot(state);
    _writeQueue = _writeQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('${_prefsPrefix}snapshot', jsonEncode(snapshot));
        await Future.wait(<Future<bool>>[
          prefs.setBool('${_prefsPrefix}enabled', snapshot['enabled'] as bool),
          prefs.setBool('${_prefsPrefix}open', snapshot['open'] as bool),
          prefs.setBool(
            '${_prefsPrefix}collapsed',
            snapshot['collapsed'] as bool,
          ),
          prefs.setInt('${_prefsPrefix}step', snapshot['step'] as int),
          prefs.setString('${_prefsPrefix}trace', snapshot['trace'] as String),
        ]);
      } catch (_) {}
    });
    return _writeQueue;
  }

  Future<void> _clearPrefs() {
    _writeQueue = _writeQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await Future.wait(<Future<bool>>[
          for (final key in <String>[
            'snapshot',
            'enabled',
            'open',
            'collapsed',
            'step',
            'trace',
          ])
            prefs.remove('$_prefsPrefix$key'),
        ]);
      } catch (_) {}
    });
    return _writeQueue;
  }
}

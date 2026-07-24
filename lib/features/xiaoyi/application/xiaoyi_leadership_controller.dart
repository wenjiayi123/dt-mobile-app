import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/application/home_tab_notifier.dart';

enum XiaoyiLeadershipCategory {
  executivePanel('AI决策面板'),
  executiveDecision('领导研判'),
  commandLinkage('指令联动');

  const XiaoyiLeadershipCategory(this.label);

  final String label;
}

enum XiaoyiLeadershipActionType {
  startXiaoyi,
  askBrief,
  openSituation,
  openStrategy,
  openAlerts,
  openAudit,
  refreshSituation,
  refreshDashboard,
  linkageHealth,
  dataLinkCheck,
  setEfficiencyPriority,
  setBalancedDispatch,
  setLowCarbonPriority,
  setShorePowerPriority,
  reviewStrategyPortfolio,
  runPolicyTest,
  verifyOnlineDryRun,
  requestRiskEscalation,
  generateMeetingBrief,
  openSimulationDemo,
  openReplayBrief,
}

enum XiaoyiLeadershipExecutionMode { advisory, frontEnd, decision, dryRun }

class XiaoyiLeadershipAction {
  const XiaoyiLeadershipAction({
    required this.id,
    required this.type,
    required this.label,
    required this.command,
    required this.category,
    required this.description,
    required this.leaderValue,
    required this.aliases,
    required this.icon,
    required this.mode,
    this.targetTab,
    this.executivePreference,
    this.requiresConfirmation = false,
  });

  final String id;
  final XiaoyiLeadershipActionType type;
  final String label;
  final String command;
  final XiaoyiLeadershipCategory category;
  final String description;
  final String leaderValue;
  final List<String> aliases;
  final IconData icon;
  final XiaoyiLeadershipExecutionMode mode;
  final HomeTab? targetTab;
  final double? executivePreference;
  final bool requiresConfirmation;
}

class XiaoyiLeadershipLog {
  const XiaoyiLeadershipLog({
    required this.at,
    required this.kind,
    required this.message,
  });

  final DateTime at;
  final String kind;
  final String message;

  String get timeLabel {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class XiaoyiLeadershipState {
  const XiaoyiLeadershipState({
    required this.commandText,
    required this.selectedActionId,
    required this.matchedActionId,
    required this.answer,
    required this.packet,
    required this.logs,
    required this.busy,
    required this.executivePreference,
    required this.lastPanelLabel,
  });

  factory XiaoyiLeadershipState.initial() {
    return XiaoyiLeadershipState(
      commandText: '',
      selectedActionId: '',
      matchedActionId: null,
      answer: '小懿已待命。请发出领导视角指令，或从下方清单直接执行。',
      packet: '等待指令。',
      logs: const <XiaoyiLeadershipLog>[],
      busy: false,
      executivePreference: 0.50,
      lastPanelLabel: '运营总控首页',
    );
  }

  final String commandText;
  final String selectedActionId;
  final String? matchedActionId;
  final String answer;
  final String packet;
  final List<XiaoyiLeadershipLog> logs;
  final bool busy;
  final double executivePreference;
  final String lastPanelLabel;

  XiaoyiLeadershipAction? get matchedAction {
    final id = matchedActionId;
    if (id == null) return null;
    return xiaoyiLeadershipActionsById[id];
  }

  XiaoyiLeadershipState copyWith({
    String? commandText,
    String? selectedActionId,
    Object? matchedActionId = _noValue,
    String? answer,
    String? packet,
    List<XiaoyiLeadershipLog>? logs,
    bool? busy,
    double? executivePreference,
    String? lastPanelLabel,
  }) {
    return XiaoyiLeadershipState(
      commandText: commandText ?? this.commandText,
      selectedActionId: selectedActionId ?? this.selectedActionId,
      matchedActionId: identical(matchedActionId, _noValue)
          ? this.matchedActionId
          : matchedActionId as String?,
      answer: answer ?? this.answer,
      packet: packet ?? this.packet,
      logs: logs ?? this.logs,
      busy: busy ?? this.busy,
      executivePreference: executivePreference ?? this.executivePreference,
      lastPanelLabel: lastPanelLabel ?? this.lastPanelLabel,
    );
  }
}

const Object _noValue = Object();

final xiaoyiLeadershipControllerProvider =
    NotifierProvider<XiaoyiLeadershipController, XiaoyiLeadershipState>(
      XiaoyiLeadershipController.new,
    );

class XiaoyiLeadershipController extends Notifier<XiaoyiLeadershipState> {
  @override
  XiaoyiLeadershipState build() => XiaoyiLeadershipState.initial();

  void setCommand(String value) {
    state = state.copyWith(commandText: value);
  }

  void selectAction(String actionId) {
    state = state.copyWith(selectedActionId: actionId);
  }

  void clear() {
    state = XiaoyiLeadershipState.initial();
  }

  XiaoyiLeadershipAction? judge({
    String? command,
    String? actionId,
    bool updateState = true,
  }) {
    final instruction = (command ?? state.commandText).trim();
    final selected = (actionId ?? state.selectedActionId).trim();
    final action = _resolveAction(instruction: instruction, actionId: selected);

    if (!updateState) return action;

    if (action == null) {
      state = state.copyWith(
        commandText: instruction,
        matchedActionId: null,
        answer: '未匹配到领导联动动作。可以尝试“小懿，生成领导简报”“小懿，打开风险告警”“小懿，验证方案能不能上线”。',
        packet: _packetForNoMatch(instruction),
        logs: _prependLog('JUDGE', '未匹配：$instruction'),
      );
      return null;
    }

    state = state.copyWith(
      commandText: instruction.isEmpty ? action.command : instruction,
      selectedActionId: action.id,
      matchedActionId: action.id,
      answer: _buildJudgement(action),
      packet: _packetFor(action, dryRun: true),
      logs: _prependLog('JUDGE', '识别：${action.label}'),
    );
    return action;
  }

  XiaoyiLeadershipAction? execute({
    String? command,
    String? actionId,
    bool confirmed = true,
  }) {
    final action = judge(
      command: command,
      actionId: actionId,
      updateState: false,
    );
    if (action == null) {
      judge(command: command, actionId: actionId);
      return null;
    }

    if (action.requiresConfirmation && !confirmed) {
      state = state.copyWith(
        matchedActionId: action.id,
        answer: '该动作会形成领导审批意见，需要确认后执行。',
        packet: _packetFor(action, dryRun: true),
        logs: _prependLog('CONFIRM', '${action.label} 等待确认'),
      );
      return action;
    }

    final nextPreference = action.executivePreference;
    state = state.copyWith(
      commandText: action.command,
      selectedActionId: action.id,
      matchedActionId: action.id,
      answer: _buildExecutionResult(action),
      packet: _packetFor(action, dryRun: false),
      executivePreference: nextPreference ?? state.executivePreference,
      lastPanelLabel: _panelLabelFor(action),
      logs: _prependLog('EXEC', '${action.label} · ${_modeLabel(action)}'),
    );
    return action;
  }

  List<XiaoyiLeadershipLog> _prependLog(String kind, String message) {
    return [
      XiaoyiLeadershipLog(at: DateTime.now(), kind: kind, message: message),
      ...state.logs,
    ].take(16).toList();
  }

  XiaoyiLeadershipAction? _resolveAction({
    required String instruction,
    required String actionId,
  }) {
    if (actionId.isNotEmpty) {
      return xiaoyiLeadershipActionsById[actionId];
    }

    final query = _normalize(instruction);
    if (query.isEmpty) return null;

    var bestScore = 0;
    XiaoyiLeadershipAction? best;

    for (final action in xiaoyiLeadershipActions) {
      var score = 0;
      for (final alias in [action.id, action.command, ...action.aliases]) {
        final normalizedAlias = _normalize(alias);
        if (normalizedAlias.isNotEmpty && query.contains(normalizedAlias)) {
          score += 80 + normalizedAlias.length.clamp(0, 20);
        }
      }
      for (final token in action.label.split(RegExp(r'\s+|/'))) {
        final normalizedToken = _normalize(token);
        if (normalizedToken.length >= 2 && query.contains(normalizedToken)) {
          score += 20;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = action;
      }
    }

    return bestScore > 0 ? best : null;
  }
}

String _normalize(String value) {
  return value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

String _buildJudgement(XiaoyiLeadershipAction action) {
  final confirm = action.requiresConfirmation
      ? '需要领导确认后形成审批留痕。'
      : '可直接联动当前 App 页面。';
  return [
    '已识别：${action.label}',
    '领导价值：${action.leaderValue}',
    '将执行：${action.description}',
    confirm,
  ].join('\n');
}

String _buildExecutionResult(XiaoyiLeadershipAction action) {
  switch (action.type) {
    case XiaoyiLeadershipActionType.startXiaoyi:
      return '小懿领导联动已启动：当前以本机 App 内置网关工作，可接入桌面小懿服务与后端动作网关。';
    case XiaoyiLeadershipActionType.askBrief:
      return '已生成领导口径：先看风险等级，再看策略建议、执行边界和审计留痕，不下钻到一线操作细节。';
    case XiaoyiLeadershipActionType.generateMeetingBrief:
      return '已整理会议简报：今日运行、关键风险、候选策略、人工确认边界、可追溯证据链。';
    case XiaoyiLeadershipActionType.setEfficiencyPriority:
    case XiaoyiLeadershipActionType.setBalancedDispatch:
    case XiaoyiLeadershipActionType.setLowCarbonPriority:
    case XiaoyiLeadershipActionType.setShorePowerPriority:
      return '领导偏好已切换为“${action.label}”。App 将以经营指标、风险边界和政策目标解释后续方案。';
    case XiaoyiLeadershipActionType.verifyOnlineDryRun:
      return '上线 dry-run 已进入领导审批口径：只做风险验证和留痕，不直接生产下发。';
    case XiaoyiLeadershipActionType.requestRiskEscalation:
      return '已形成风险升级建议：建议进入告警页确认来源，再到策略页查看候选方案。';
    default:
      return '已执行：${action.label}。\n${action.leaderValue}';
  }
}

String _packetForNoMatch(String instruction) {
  return '''
{
  "gateway": "mobile_xiaoyi_leadership_gateway",
  "matched": false,
  "instruction": "$instruction",
  "message": "未匹配到领导联动动作"
}
''';
}

String _packetFor(XiaoyiLeadershipAction action, {required bool dryRun}) {
  return '''
{
  "gateway": "mobile_xiaoyi_leadership_gateway",
  "matched": true,
  "mode": "${dryRun ? 'dry_run' : 'executed'}",
  "action_id": "${action.id}",
  "action_label": "${action.label}",
  "category": "${action.category.label}",
  "target_tab": "${action.targetTab?.label ?? 'dashboard'}",
  "requires_confirmation": ${action.requiresConfirmation},
  "executive_preference": ${action.executivePreference?.toStringAsFixed(2) ?? 'null'}
}
''';
}

String _modeLabel(XiaoyiLeadershipAction action) {
  return switch (action.mode) {
    XiaoyiLeadershipExecutionMode.advisory => '研判',
    XiaoyiLeadershipExecutionMode.frontEnd => '打开面板',
    XiaoyiLeadershipExecutionMode.decision => '领导决策',
    XiaoyiLeadershipExecutionMode.dryRun => 'dry-run',
  };
}

String _panelLabelFor(XiaoyiLeadershipAction action) {
  if (action.targetTab != null) return action.targetTab!.label;
  return switch (action.type) {
    XiaoyiLeadershipActionType.openSimulationDemo => '证据讲解',
    XiaoyiLeadershipActionType.openReplayBrief => '审计复盘',
    _ => '运营总控首页',
  };
}

const List<XiaoyiLeadershipAction> xiaoyiLeadershipActions = [
  XiaoyiLeadershipAction(
    id: 'start_xiaoyi_ai',
    type: XiaoyiLeadershipActionType.startXiaoyi,
    label: '启动小懿领导助手',
    command: '小懿，启动领导助手',
    category: XiaoyiLeadershipCategory.commandLinkage,
    description: '打开 App 内置小懿联动网关，准备接收领导指令。',
    leaderValue: '让领导在移动端用一句话进入态势、策略、风险和审计闭环。',
    aliases: ['启动小懿', '打开小懿', '领导助手', '小懿AI'],
    icon: Icons.smart_toy_outlined,
    mode: XiaoyiLeadershipExecutionMode.frontEnd,
  ),
  XiaoyiLeadershipAction(
    id: 'ask_xiaoyi_brief',
    type: XiaoyiLeadershipActionType.askBrief,
    label: '询问领导口径',
    command: '小懿，用领导口径解释当前局面',
    category: XiaoyiLeadershipCategory.commandLinkage,
    description: '把当前局面压缩为可汇报的三句话。',
    leaderValue: '减少专业细节噪音，直接回答“风险、影响、下一步”。',
    aliases: ['领导口径', '解释当前局面', '怎么汇报', '问答'],
    icon: Icons.record_voice_over_outlined,
    mode: XiaoyiLeadershipExecutionMode.advisory,
  ),
  XiaoyiLeadershipAction(
    id: 'open_situation_panel',
    type: XiaoyiLeadershipActionType.openSituation,
    label: '打开态势总览',
    command: '小懿，打开态势总览',
    category: XiaoyiLeadershipCategory.executivePanel,
    description: '进入态势页，查看数据来源、派生风险点值和证据边界。',
    leaderValue: '领导先判断系统是否稳定，再决定是否进入策略审批。',
    aliases: ['态势', '态势总览', '看态势', '当前状态'],
    icon: Icons.monitor_heart_outlined,
    mode: XiaoyiLeadershipExecutionMode.frontEnd,
    targetTab: HomeTab.situation,
  ),
  XiaoyiLeadershipAction(
    id: 'open_strategy_panel',
    type: XiaoyiLeadershipActionType.openStrategy,
    label: '打开策略审批',
    command: '小懿，打开策略审批',
    category: XiaoyiLeadershipCategory.executivePanel,
    description: '进入策略页，查看候选策略、影响解释和人工确认边界。',
    leaderValue: '把操作策略升级为“领导是否同意进入执行”的审批视角。',
    aliases: ['策略审批', '策略确认', '候选策略', 'AI方案'],
    icon: Icons.psychology_alt_outlined,
    mode: XiaoyiLeadershipExecutionMode.frontEnd,
    targetTab: HomeTab.strategy,
  ),
  XiaoyiLeadershipAction(
    id: 'open_alerts_panel',
    type: XiaoyiLeadershipActionType.openAlerts,
    label: '打开风险告警',
    command: '小懿，打开风险告警',
    category: XiaoyiLeadershipCategory.executivePanel,
    description: '进入告警页，查看高优风险来源和升级入口。',
    leaderValue: '领导只看高优风险和影响范围，不处理一线告警流细节。',
    aliases: ['告警', '风险告警', '高优告警', '风险升级'],
    icon: Icons.warning_amber_rounded,
    mode: XiaoyiLeadershipExecutionMode.frontEnd,
    targetTab: HomeTab.alerts,
  ),
  XiaoyiLeadershipAction(
    id: 'open_audit_panel',
    type: XiaoyiLeadershipActionType.openAudit,
    label: '打开审计复盘',
    command: '小懿，打开审计复盘',
    category: XiaoyiLeadershipCategory.executivePanel,
    description: '进入审计页，查看人工表态、执行回执与可追溯证据。',
    leaderValue: '把 AI 决策讲清楚、留住证据、方便会后追责复盘。',
    aliases: ['审计', '复盘', '留痕', '追责'],
    icon: Icons.fact_check_outlined,
    mode: XiaoyiLeadershipExecutionMode.frontEnd,
    targetTab: HomeTab.audit,
  ),
  XiaoyiLeadershipAction(
    id: 'refresh_situation',
    type: XiaoyiLeadershipActionType.refreshSituation,
    label: '刷新态势',
    command: '小懿，刷新态势',
    category: XiaoyiLeadershipCategory.executivePanel,
    description: '刷新移动端态势快照，并重新读取后端风险证据。',
    leaderValue: '确保领导看到的是最新可汇报状态。',
    aliases: ['刷新', '刷新态势', '更新态势', '重新同步'],
    icon: Icons.refresh_rounded,
    mode: XiaoyiLeadershipExecutionMode.frontEnd,
    targetTab: HomeTab.situation,
  ),
  XiaoyiLeadershipAction(
    id: 'refresh_dashboard_snapshot',
    type: XiaoyiLeadershipActionType.refreshDashboard,
    label: '同步运营首页',
    command: '小懿，同步运营首页',
    category: XiaoyiLeadershipCategory.executivePanel,
    description: '同步首页摘要、关键事件和数据链路状态。',
    leaderValue: '让首页摘要与态势、策略、告警、审计保持同一口径。',
    aliases: ['同步首页', '刷新首页', '同步仪表盘', '运营首页'],
    icon: Icons.dashboard_customize_outlined,
    mode: XiaoyiLeadershipExecutionMode.frontEnd,
  ),
  XiaoyiLeadershipAction(
    id: 'run_linkage_health_check',
    type: XiaoyiLeadershipActionType.linkageHealth,
    label: '联动健康检查',
    command: '小懿，做一次联动健康检查',
    category: XiaoyiLeadershipCategory.executivePanel,
    description: '检查移动端、后端、小懿、Web 大屏和审计链路是否可用。',
    leaderValue: '给领导一个“系统能不能支撑现场汇报”的答案。',
    aliases: ['健康检查', '联动状态', '系统状态', '接口状态'],
    icon: Icons.health_and_safety_outlined,
    mode: XiaoyiLeadershipExecutionMode.advisory,
  ),
  XiaoyiLeadershipAction(
    id: 'check_data_link',
    type: XiaoyiLeadershipActionType.dataLinkCheck,
    label: '检查数据链路',
    command: '小懿，检查数据链路',
    category: XiaoyiLeadershipCategory.executivePanel,
    description: '汇总数据新鲜度、缓存状态、回执和审计上传状态。',
    leaderValue: '领导关心数据是否可信，而不是接口字段细节。',
    aliases: ['数据链路', '数据新鲜度', '缓存状态', '链路检查'],
    icon: Icons.hub_outlined,
    mode: XiaoyiLeadershipExecutionMode.advisory,
  ),
  XiaoyiLeadershipAction(
    id: 'set_efficiency_priority',
    type: XiaoyiLeadershipActionType.setEfficiencyPriority,
    label: '效率优先',
    command: '小懿，切到效率优先',
    category: XiaoyiLeadershipCategory.executiveDecision,
    description: '把领导偏好切到效率优先，后续策略以吞吐和时效解释。',
    leaderValue: '适合保班期、压延误、抢窗口时使用。',
    aliases: ['效率优先', '保班期', '压延误', '吞吐优先'],
    icon: Icons.speed_outlined,
    mode: XiaoyiLeadershipExecutionMode.decision,
    executivePreference: 0.25,
  ),
  XiaoyiLeadershipAction(
    id: 'set_balanced_dispatch',
    type: XiaoyiLeadershipActionType.setBalancedDispatch,
    label: '均衡调度',
    command: '小懿，切到均衡调度',
    category: XiaoyiLeadershipCategory.executiveDecision,
    description: '把领导偏好切到均衡模式，兼顾效率、成本、低碳和风险。',
    leaderValue: '适合日常运营例会和综合汇报。',
    aliases: ['均衡调度', '平衡', '综合最优', '折中方案'],
    icon: Icons.balance_outlined,
    mode: XiaoyiLeadershipExecutionMode.decision,
    executivePreference: 0.50,
  ),
  XiaoyiLeadershipAction(
    id: 'set_low_carbon_priority',
    type: XiaoyiLeadershipActionType.setLowCarbonPriority,
    label: '低碳优先',
    command: '小懿，切到低碳优先',
    category: XiaoyiLeadershipCategory.executiveDecision,
    description: '把领导偏好切到低碳优先，突出减排和合规收益。',
    leaderValue: '适合双碳汇报、绿色港口展示和政策考核场景。',
    aliases: ['低碳优先', '减排优先', '绿色优先', '碳排最低'],
    icon: Icons.eco_outlined,
    mode: XiaoyiLeadershipExecutionMode.decision,
    executivePreference: 0.82,
  ),
  XiaoyiLeadershipAction(
    id: 'set_shore_power_priority',
    type: XiaoyiLeadershipActionType.setShorePowerPriority,
    label: '岸电优先',
    command: '小懿，切到岸电优先',
    category: XiaoyiLeadershipCategory.executiveDecision,
    description: '把领导偏好切到岸电优先，聚焦靠泊接电和替代减排。',
    leaderValue: '适合岸电使用率考核、示范泊位和绿色作业窗口。',
    aliases: ['岸电优先', '岸电接入', '接电优先', '绿色靠泊'],
    icon: Icons.electrical_services_outlined,
    mode: XiaoyiLeadershipExecutionMode.decision,
    executivePreference: 0.88,
  ),
  XiaoyiLeadershipAction(
    id: 'review_strategy_portfolio',
    type: XiaoyiLeadershipActionType.reviewStrategyPortfolio,
    label: '审阅策略组合',
    command: '小懿，审阅当前策略组合',
    category: XiaoyiLeadershipCategory.executiveDecision,
    description: '进入策略页，查看推荐、备选和风险对照。',
    leaderValue: '把多个算法候选方案整理为“可批、可驳回、可追问”的领导视图。',
    aliases: ['策略组合', '方案组合', '备选方案', '审阅策略'],
    icon: Icons.rule_folder_outlined,
    mode: XiaoyiLeadershipExecutionMode.frontEnd,
    targetTab: HomeTab.strategy,
  ),
  XiaoyiLeadershipAction(
    id: 'run_policy_test',
    type: XiaoyiLeadershipActionType.runPolicyTest,
    label: '运行策略测试',
    command: '小懿，运行策略测试',
    category: XiaoyiLeadershipCategory.executiveDecision,
    description: '以领导摘要方式呈现候选策略的影响、收益和风险。',
    leaderValue: '不是让一线执行，而是帮助领导判断方案是否值得推进。',
    aliases: ['策略测试', '测试方案', '训练后测试', '政策测试'],
    icon: Icons.science_outlined,
    mode: XiaoyiLeadershipExecutionMode.advisory,
    targetTab: HomeTab.strategy,
  ),
  XiaoyiLeadershipAction(
    id: 'verify_policy_for_online',
    type: XiaoyiLeadershipActionType.verifyOnlineDryRun,
    label: '上线验证 dry-run',
    command: '小懿，验证这个策略能不能上线',
    category: XiaoyiLeadershipCategory.executiveDecision,
    description: '做上线前风险验证，只出具审批意见，不生产下发。',
    leaderValue: '保留领导人工确认边界，避免 AI 直接越权。',
    aliases: ['上线验证', '能不能上线', 'dry-run', '上线前校验'],
    icon: Icons.verified_outlined,
    mode: XiaoyiLeadershipExecutionMode.dryRun,
    targetTab: HomeTab.strategy,
    requiresConfirmation: true,
  ),
  XiaoyiLeadershipAction(
    id: 'request_risk_escalation',
    type: XiaoyiLeadershipActionType.requestRiskEscalation,
    label: '风险升级建议',
    command: '小懿，给出风险升级建议',
    category: XiaoyiLeadershipCategory.executiveDecision,
    description: '汇总告警来源和升级理由，建议是否进入策略审批。',
    leaderValue: '帮助领导判断“是否需要开会、升级、人工接管”。',
    aliases: ['风险升级', '升级建议', '人工接管', '开会'],
    icon: Icons.priority_high_rounded,
    mode: XiaoyiLeadershipExecutionMode.advisory,
    targetTab: HomeTab.alerts,
  ),
  XiaoyiLeadershipAction(
    id: 'generate_meeting_brief',
    type: XiaoyiLeadershipActionType.generateMeetingBrief,
    label: '生成会议简报',
    command: '小懿，生成领导会议简报',
    category: XiaoyiLeadershipCategory.commandLinkage,
    description: '把运行状态、风险、策略和审计证据组织成汇报提纲。',
    leaderValue: '直接用于领导会、调度会或现场演示讲解。',
    aliases: ['会议简报', '领导简报', '汇报材料', '生成简报'],
    icon: Icons.summarize_outlined,
    mode: XiaoyiLeadershipExecutionMode.advisory,
  ),
  XiaoyiLeadershipAction(
    id: 'open_simulation_demo',
    type: XiaoyiLeadershipActionType.openSimulationDemo,
    label: '打开证据讲解',
    command: '小懿，打开证据讲解',
    category: XiaoyiLeadershipCategory.commandLinkage,
    description: '打开三维证据界面，核对公开回放标签、缺失现场字段和测试产物。',
    leaderValue: '将布局示意、公开数据和真实测试产物分层展示，避免把界面动画当成业务证据。',
    aliases: ['证据讲解', '3D证据', '数据边界', '仿真证据'],
    icon: Icons.play_circle_outline,
    mode: XiaoyiLeadershipExecutionMode.frontEnd,
    targetTab: HomeTab.situation,
  ),
  XiaoyiLeadershipAction(
    id: 'open_replay_brief',
    type: XiaoyiLeadershipActionType.openReplayBrief,
    label: '打开复盘摘要',
    command: '小懿，打开复盘摘要',
    category: XiaoyiLeadershipCategory.commandLinkage,
    description: '进入审计复盘，查看处置前后、人工表态和执行回执。',
    leaderValue: '让领导看清“为什么这么做、谁确认、效果如何”。',
    aliases: ['复盘摘要', '回放', '处置前后', '回执'],
    icon: Icons.history_toggle_off_outlined,
    mode: XiaoyiLeadershipExecutionMode.frontEnd,
    targetTab: HomeTab.audit,
  ),
];

final Map<String, XiaoyiLeadershipAction> xiaoyiLeadershipActionsById = {
  for (final action in xiaoyiLeadershipActions) action.id: action,
};

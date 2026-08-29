import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  String get timeLabel => switch (this) {
    DemoFlowStage.ready => '待启动',
    DemoFlowStage.stable => 'T+0s',
    DemoFlowStage.boundary => 'T+20s',
    DemoFlowStage.alert => 'T+40s',
    DemoFlowStage.strategy => 'T+60s',
    DemoFlowStage.executing => 'T+90s',
    DemoFlowStage.audit => 'T+120s',
  };

  String get shortLabel => switch (this) {
    DemoFlowStage.ready => '准备',
    DemoFlowStage.stable => '稳态',
    DemoFlowStage.boundary => '预警',
    DemoFlowStage.alert => '告警',
    DemoFlowStage.strategy => '策略',
    DemoFlowStage.executing => '执行',
    DemoFlowStage.audit => '审计',
  };

  String get headline => switch (this) {
    DemoFlowStage.ready => '界面讲解尚未启动',
    DemoFlowStage.stable => '讲解态势数据与证据标签',
    DemoFlowStage.boundary => '讲解风险证据的展示位置',
    DemoFlowStage.alert => '讲解后端告警与离线边界',
    DemoFlowStage.strategy => '讲解真实训练和测试产物',
    DemoFlowStage.executing => '讲解人工表态与生产门禁',
    DemoFlowStage.audit => '讲解审计字段与测试回放',
  };

  String get narrative => switch (this) {
    DemoFlowStage.ready => '该流程只提示页面顺序，不改变态势、告警、训练、执行或审计数据。',
    DemoFlowStage.stable => '核对 dataSource、数据时间和公开历史回放标签。',
    DemoFlowStage.boundary => '这里只指向组件位置，不生成新的风险值。',
    DemoFlowStage.alert => '告警必须来自后端；连接失败时列表不会新增本地事件。',
    DemoFlowStage.strategy => '进度和曲线来自训练 worker，回放来自独立测试集。',
    DemoFlowStage.executing => '公开回放只能 dry-run；适配器真实确认后才可显示生产回执。',
    DemoFlowStage.audit => '核对 job、数据哈希、测试指标、人工选择和服务器审计记录。',
  };

  String get nextActionLabel => switch (this) {
    DemoFlowStage.ready => '开始界面讲解',
    DemoFlowStage.stable => '继续讲解风险证据',
    DemoFlowStage.boundary => '继续讲解告警来源',
    DemoFlowStage.alert => '继续讲解真实训练',
    DemoFlowStage.strategy => '查看人工表态边界',
    DemoFlowStage.executing => '查看审计证据',
    DemoFlowStage.audit => '讲解完成',
  };

  int get targetTabIndex => switch (this) {
    DemoFlowStage.ready || DemoFlowStage.stable || DemoFlowStage.boundary => 0,
    DemoFlowStage.alert => 2,
    DemoFlowStage.strategy || DemoFlowStage.executing => 1,
    DemoFlowStage.audit => 3,
  };
}

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
    this.startedAt,
    this.updatedAt,
  });

  factory DemoFlowState.initial() {
    return const DemoFlowState(
      enabled: false,
      stage: DemoFlowStage.ready,
      logs: <DemoFlowLog>[],
    );
  }

  final bool enabled;
  final DemoFlowStage stage;
  final List<DemoFlowLog> logs;
  final DateTime? startedAt;
  final DateTime? updatedAt;

  bool get isRunning => enabled && stage != DemoFlowStage.ready;
  bool get isComplete => stage == DemoFlowStage.audit;

  double get progress {
    if (stage == DemoFlowStage.ready) return 0;
    return stage.index / DemoFlowStage.audit.index;
  }

  bool get canAdvanceManually =>
      enabled && stage.index <= DemoFlowStage.alert.index;

  DemoFlowState copyWith({
    bool? enabled,
    DemoFlowStage? stage,
    List<DemoFlowLog>? logs,
    Object? startedAt = _unset,
    Object? updatedAt = _unset,
  }) {
    return DemoFlowState(
      enabled: enabled ?? this.enabled,
      stage: stage ?? this.stage,
      logs: logs ?? this.logs,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as DateTime?,
      updatedAt: identical(updatedAt, _unset)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }
}

const Object _unset = Object();

final demoFlowProvider = NotifierProvider<DemoFlowController, DemoFlowState>(
  DemoFlowController.new,
);

class DemoFlowController extends Notifier<DemoFlowState> {
  @override
  DemoFlowState build() => DemoFlowState.initial();

  void setEnabled(bool value) {
    if (value == state.enabled) return;
    final now = DateTime.now();
    state = DemoFlowState(
      enabled: value,
      stage: DemoFlowStage.ready,
      logs: <DemoFlowLog>[
        DemoFlowLog(message: value ? '界面讲解已启用' : '界面讲解已关闭', at: now),
      ],
      updatedAt: now,
    );
  }

  void start() {
    if (!state.enabled) return;
    final now = DateTime.now();
    state = DemoFlowState(
      enabled: true,
      stage: DemoFlowStage.stable,
      startedAt: now,
      updatedAt: now,
      logs: <DemoFlowLog>[DemoFlowLog(at: now, message: '界面讲解启动；业务数据不随讲解阶段变化')],
    );
  }

  void advance() {
    if (!state.enabled) return;
    final next = switch (state.stage) {
      DemoFlowStage.ready => DemoFlowStage.stable,
      DemoFlowStage.stable => DemoFlowStage.boundary,
      DemoFlowStage.boundary => DemoFlowStage.alert,
      DemoFlowStage.alert => DemoFlowStage.strategy,
      DemoFlowStage.strategy ||
      DemoFlowStage.executing ||
      DemoFlowStage.audit => state.stage,
    };
    setStage(next);
  }

  void markExecutionStarted() {
    if (!state.enabled || !state.isRunning) return;
    setStage(DemoFlowStage.executing);
  }

  void markAuditReady() {
    if (!state.enabled || !state.isRunning) return;
    setStage(DemoFlowStage.audit);
  }

  void setStage(DemoFlowStage stage) {
    if (!state.enabled || stage == state.stage) return;
    final now = DateTime.now();
    final startedAt = state.startedAt ?? now;
    final nextLogs = <DemoFlowLog>[
      DemoFlowLog(at: now, message: '${stage.timeLabel} · ${stage.headline}'),
      ...state.logs,
    ].take(8).toList(growable: false);
    state = state.copyWith(
      stage: stage,
      startedAt: startedAt,
      updatedAt: now,
      logs: nextLogs,
    );
  }

  void restart() => start();

  void reset() {
    state = DemoFlowState.initial();
  }
}

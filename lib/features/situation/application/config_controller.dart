import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../../audit/application/audit_controller.dart';
import 'situation_controller.dart';

enum RunMode {
  automatic('自动', 'automatic', '系统自动推进'),
  semiAutomatic('半自动', 'semi_automatic', '系统建议 + 人工确认'),
  manualWatch('人工盯控', 'manual_watch', '人工主导，系统只提示');

  const RunMode(this.label, this.wireName, this.description);

  final String label;
  final String wireName;
  final String description;
}

enum RiskThresholdPreset {
  low('低', 'low', 35),
  medium('中', 'medium', 60),
  high('高', 'high', 80);

  const RiskThresholdPreset(this.label, this.wireName, this.thetaValue);

  final String label;
  final String wireName;
  final int thetaValue;
}

@immutable
class ControlConfigState {
  const ControlConfigState({
    required this.runMode,
    required this.riskThreshold,
    required this.futureWindowMinutes,
    required this.isSyncing,
    required this.lastAppliedAt,
    required this.syncMessage,
  });

  final RunMode runMode;
  final RiskThresholdPreset riskThreshold;
  final int futureWindowMinutes;
  final bool isSyncing;
  final DateTime? lastAppliedAt;
  final String syncMessage;

  String get summaryLine =>
      '模式 ${runMode.label} · θ ${riskThreshold.label}(${riskThreshold.thetaValue}) · τ ${futureWindowMinutes}min';

  ControlConfigState copyWith({
    RunMode? runMode,
    RiskThresholdPreset? riskThreshold,
    int? futureWindowMinutes,
    bool? isSyncing,
    DateTime? lastAppliedAt,
    String? syncMessage,
    bool clearLastAppliedAt = false,
  }) {
    return ControlConfigState(
      runMode: runMode ?? this.runMode,
      riskThreshold: riskThreshold ?? this.riskThreshold,
      futureWindowMinutes: futureWindowMinutes ?? this.futureWindowMinutes,
      isSyncing: isSyncing ?? this.isSyncing,
      lastAppliedAt: clearLastAppliedAt
          ? null
          : (lastAppliedAt ?? this.lastAppliedAt),
      syncMessage: syncMessage ?? this.syncMessage,
    );
  }
}

@immutable
class ControlConfigPayload {
  const ControlConfigPayload({
    required this.runMode,
    required this.riskThreshold,
    required this.futureWindowMinutes,
  });

  final RunMode runMode;
  final RiskThresholdPreset riskThreshold;
  final int futureWindowMinutes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'runMode': runMode.wireName,
      'riskThreshold': riskThreshold.wireName,
      'theta': riskThreshold.thetaValue,
      'futureWindowMinutes': futureWindowMinutes,
    };
  }
}

abstract class ControlRepository {
  Future<void> setConfig(ControlConfigPayload payload);
}

class ApiControlRepository implements ControlRepository {
  const ApiControlRepository(this.dio);

  final Dio dio;

  @override
  Future<void> setConfig(ControlConfigPayload payload) async {
    final response = await dio.post<Object>(
      '/api/control/config',
      data: payload.toJson(),
    );
    final data = response.data is Map
        ? (response.data as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};
    if (data['accepted'] != true ||
        data['scope']?.toString() != 'client_advisory_view' ||
        data['production_applied'] != false) {
      throw StateError('后端未确认客户端审阅参数边界');
    }
  }
}

final controlRepositoryProvider = Provider<ControlRepository>((ref) {
  return ApiControlRepository(ref.read(dioProvider));
});

final configControllerProvider =
    NotifierProvider<ConfigController, ControlConfigState>(
      ConfigController.new,
    );

class ConfigController extends Notifier<ControlConfigState> {
  @override
  ControlConfigState build() {
    return const ControlConfigState(
      runMode: RunMode.semiAutomatic,
      riskThreshold: RiskThresholdPreset.medium,
      futureWindowMinutes: 30,
      isSyncing: false,
      lastAppliedAt: null,
      syncMessage: '等待后端记录 · 不改变生产控制',
    );
  }

  ControlRepository get _repository => ref.read(controlRepositoryProvider);

  Future<void> setRunMode(RunMode value) async {
    if (value == state.runMode) return;
    await _applyConfig(
      nextRunMode: value,
      auditField: 'run_mode',
      auditValueLabel: value.label,
    );
  }

  Future<void> setRiskThreshold(RiskThresholdPreset value) async {
    if (value == state.riskThreshold) return;
    await _applyConfig(
      nextRiskThreshold: value,
      auditField: 'risk_threshold_theta',
      auditValueLabel: '${value.label} (${value.thetaValue})',
    );
  }

  Future<void> setFutureWindowMinutes(int value) async {
    if (value == state.futureWindowMinutes) return;
    await _applyConfig(
      nextFutureWindowMinutes: value,
      auditField: 'future_window_tau',
      auditValueLabel: '$value min',
    );
  }

  Future<void> _applyConfig({
    RunMode? nextRunMode,
    RiskThresholdPreset? nextRiskThreshold,
    int? nextFutureWindowMinutes,
    required String auditField,
    required String auditValueLabel,
  }) async {
    final previous = state;
    final next = previous.copyWith(
      runMode: nextRunMode,
      riskThreshold: nextRiskThreshold,
      futureWindowMinutes: nextFutureWindowMinutes,
      isSyncing: true,
      syncMessage: '正在提交客户端审阅参数...',
    );

    state = next;

    final payload = ControlConfigPayload(
      runMode: next.runMode,
      riskThreshold: next.riskThreshold,
      futureWindowMinutes: next.futureWindowMinutes,
    );

    final situationAsync = ref.read(situationProvider);
    final SituationSnapshot? situation =
        situationAsync is AsyncData<SituationSnapshot>
        ? situationAsync.value
        : null;

    final auditActionType = _resolveAuditActionType(next);

    ref
        .read(auditTimelineProvider.notifier)
        .recordEvent(
          source: AuditEventSource.configChange,
          actionType: auditActionType,
          stateSummary: '正在请求记录客户端审阅参数：${next.summaryLine}',
          policySetSummary: '尚未确认 · 等待 POST /api/control/config 回执',
          humanChoiceSummary: '人工请求调整 $auditField → $auditValueLabel',
          payload: <String, Object?>{
            'source': 'situation_control_panel',
            'actionType': auditActionType.wireName,
            'changedField': auditField,
            'changedValueLabel': auditValueLabel,
            'config': payload.toJson(),
            'backendEndpoint': 'POST /api/control/config',
            'status': 'attempted',
          },
        );

    try {
      await _repository.setConfig(payload);
      ref
          .read(auditTimelineProvider.notifier)
          .recordEvent(
            source: AuditEventSource.configChange,
            actionType: auditActionType,
            stateSummary: _buildStateSummary(situation, next),
            policySetSummary: '后端已记录客户端审阅参数：${next.summaryLine}',
            humanChoiceSummary:
                '人工调整已确认 · $auditField → $auditValueLabel · 未生产下发',
            payload: <String, Object?>{
              'source': 'situation_control_panel',
              'changedField': auditField,
              'changedValueLabel': auditValueLabel,
              'config': payload.toJson(),
              'backendEndpoint': 'POST /api/control/config',
              'status': 'recorded_advisory_only',
              'productionApplied': false,
            },
          );
      state = next.copyWith(
        isSyncing: false,
        lastAppliedAt: DateTime.now(),
        syncMessage: '后端已记录客户端审阅参数 · 未生产下发',
      );
    } catch (error) {
      ref
          .read(auditTimelineProvider.notifier)
          .recordEvent(
            source: AuditEventSource.configChange,
            actionType: auditActionType,
            stateSummary: '客户端审阅参数提交失败，已回退上一版本',
            policySetSummary: '后端未记录：${next.summaryLine}',
            humanChoiceSummary: '人工请求未生效 · $auditField → $auditValueLabel',
            payload: <String, Object?>{
              'source': 'situation_control_panel',
              'changedField': auditField,
              'changedValueLabel': auditValueLabel,
              'status': 'failed',
              'errorType': error.runtimeType.toString(),
              'productionApplied': false,
            },
          );
      state = previous.copyWith(
        isSyncing: false,
        syncMessage: '本次参数应用失败，已回退到上一版本',
      );
    }
  }

  AuditActionType _resolveAuditActionType(ControlConfigState next) {
    if (next.runMode == RunMode.manualWatch) {
      return AuditActionType.override;
    }
    if (next.riskThreshold == RiskThresholdPreset.high) {
      return AuditActionType.override;
    }
    return AuditActionType.guidance;
  }

  String _buildStateSummary(
    SituationSnapshot? snapshot,
    ControlConfigState next,
  ) {
    if (snapshot == null) {
      return '态势快照尚未就绪，已先更新控制参数：${next.summaryLine}';
    }

    return '在 ${snapshot.stabilityLevel.label} 态势下更新控制参数：${next.summaryLine}';
  }
}

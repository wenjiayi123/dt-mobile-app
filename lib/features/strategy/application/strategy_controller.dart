import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/dio_provider.dart';
import '../../audit/application/audit_controller.dart';

enum HumanChoiceType {
  override('人工接管'),
  guidance('指导调整'),
  veto('否决方案');

  const HumanChoiceType(this.label);

  final String label;
}

enum StrategyExecutionStatus {
  submitted('submitted', '已提交'),
  executing('executing', '执行中'),
  dryRunRecorded('dry_run_recorded', '仅记录干跑'),
  acked('acked', '已回执'),
  failed('failed', '失败');

  const StrategyExecutionStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  bool get isTerminal =>
      this == StrategyExecutionStatus.dryRunRecorded ||
      this == StrategyExecutionStatus.acked ||
      this == StrategyExecutionStatus.failed;
}

enum EffectTargetType {
  vessel('vessel'),
  berth('berth'),
  timeWindow('time window'),
  system('system');

  const EffectTargetType(this.label);

  final String label;
}

enum StrategyCandidatesDataSource {
  backendArtifact('后端测试产物'),
  cache('缓存');

  const StrategyCandidatesDataSource(this.label);

  final String label;
}

class EffectItem {
  const EffectItem({
    required this.type,
    required this.targetName,
    required this.impact,
    this.severity = 'medium',
  });

  final EffectTargetType type;
  final String targetName;
  final String impact;
  final String severity;

  String get readableLine => '${type.label} · $targetName：$impact';

  factory EffectItem.fromJson(Object? raw) {
    if (raw is Map<String, dynamic>) {
      final rawType = raw['type']?.toString() ?? 'system';
      final type = _parseType(rawType);
      return EffectItem(
        type: type,
        targetName: raw['targetName']?.toString() ?? 'unknown',
        impact: raw['impact']?.toString() ?? '暂无影响说明',
        severity: raw['severity']?.toString() ?? 'medium',
      );
    }

    if (raw is String && raw.trim().isNotEmpty) {
      return EffectItem(
        type: EffectTargetType.system,
        targetName: 'global',
        impact: raw.trim(),
      );
    }

    return const EffectItem(
      type: EffectTargetType.system,
      targetName: 'global',
      impact: '暂无影响说明',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type.name,
      'targetName': targetName,
      'impact': impact,
      'severity': severity,
    };
  }

  static EffectTargetType _parseType(String raw) {
    switch (raw) {
      case 'vessel':
        return EffectTargetType.vessel;
      case 'berth':
        return EffectTargetType.berth;
      case 'timeWindow':
      case 'time_window':
      case 'time-window':
        return EffectTargetType.timeWindow;
      default:
        return EffectTargetType.system;
    }
  }
}

class StrategyRiskInterval {
  const StrategyRiskInterval({
    required this.low,
    required this.high,
    this.unit = '%',
    this.prefix = '',
  });

  final num low;
  final num high;
  final String unit;
  final String prefix;

  String get displayText {
    final lowText = _formatValue(low);
    final highText = _formatValue(high);
    if (low.toDouble() == high.toDouble()) {
      return '$prefix$lowText$unit';
    }
    return '$prefix$lowText$unit ~ $prefix$highText$unit';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'low': low,
      'high': high,
      'unit': unit,
      'prefix': prefix,
    };
  }

  factory StrategyRiskInterval.fromJson(
    Object? raw, {
    String fallbackPrefix = '',
  }) {
    if (raw is Map<String, dynamic>) {
      final low = raw['low'];
      final high = raw['high'];
      final unit = raw['unit']?.toString() ?? '%';
      final prefix = raw['prefix']?.toString() ?? fallbackPrefix;

      if (low is num && high is num) {
        return StrategyRiskInterval(
          low: low,
          high: high,
          unit: unit,
          prefix: prefix,
        );
      }
    }

    return StrategyRiskInterval(
      low: 0,
      high: 0,
      unit: '%',
      prefix: fallbackPrefix,
    );
  }

  static String _formatValue(num value) {
    if (value is int) return value.toString();

    final doubleValue = value.toDouble();
    if (doubleValue == doubleValue.roundToDouble()) {
      return doubleValue.toInt().toString();
    }

    return doubleValue.toStringAsFixed(1);
  }
}

class CounterfactualItem {
  const CounterfactualItem({
    required this.metricName,
    required this.currentRange,
    required this.baselineRange,
    required this.delta,
    required this.direction,
  });

  final String metricName;
  final String currentRange;
  final String baselineRange;
  final String delta;
  final String direction;

  String get readableLine =>
      '$metricName：当前 $currentRange vs baseline $baselineRange（$delta）';

  factory CounterfactualItem.fromJson(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return CounterfactualItem(
        metricName: raw['metricName']?.toString() ?? '未命名指标',
        currentRange: raw['currentRange']?.toString() ?? '-',
        baselineRange: raw['baselineRange']?.toString() ?? '-',
        delta: raw['delta']?.toString() ?? '差异待补充',
        direction: raw['direction']?.toString() ?? 'flat',
      );
    }

    if (raw is String && raw.trim().isNotEmpty) {
      return CounterfactualItem(
        metricName: '关键差异',
        currentRange: '-',
        baselineRange: '-',
        delta: raw.trim(),
        direction: 'flat',
      );
    }

    return const CounterfactualItem(
      metricName: '关键差异',
      currentRange: '-',
      baselineRange: '-',
      delta: '差异待补充',
      direction: 'flat',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'metricName': metricName,
      'currentRange': currentRange,
      'baselineRange': baselineRange,
      'delta': delta,
      'direction': direction,
    };
  }
}

class AlertLink {
  const AlertLink({
    required this.alertId,
    required this.title,
    required this.severity,
    required this.summary,
    required this.recommendedAction,
  });

  final String alertId;
  final String title;
  final String severity;
  final String summary;
  final String recommendedAction;

  factory AlertLink.fromJson(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return AlertLink(
        alertId: raw['alertId']?.toString() ?? 'unknown_alert',
        title: raw['title']?.toString() ?? '未命名告警',
        severity: raw['severity']?.toString() ?? 'medium',
        summary: raw['summary']?.toString() ?? '暂无摘要',
        recommendedAction:
            raw['recommendedAction']?.toString() ?? '建议人工复核后推进策略。',
      );
    }

    if (raw is String && raw.trim().isNotEmpty) {
      return AlertLink(
        alertId: 'derived_alert',
        title: raw.trim(),
        severity: 'medium',
        summary: raw.trim(),
        recommendedAction: '建议人工复核后推进策略。',
      );
    }

    return const AlertLink(
      alertId: 'unknown_alert',
      title: '未命名告警',
      severity: 'medium',
      summary: '暂无摘要',
      recommendedAction: '建议人工复核后推进策略。',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'alertId': alertId,
      'title': title,
      'severity': severity,
      'summary': summary,
      'recommendedAction': recommendedAction,
    };
  }
}

class StrategyCandidate {
  const StrategyCandidate({
    required this.id,
    required this.title,
    required this.summary,
    required this.priorityHint,
    required this.congestionIndex,
    required this.conflictRisk,
    required this.safetyMargin,
    required this.rewardDelta,
    required this.effects,
    required this.counterfactuals,
    required this.relatedAlerts,
    this.baselinePolicyId,
  });

  final String id;
  final String title;
  final String summary;
  final String priorityHint;
  final StrategyRiskInterval congestionIndex;
  final StrategyRiskInterval conflictRisk;
  final StrategyRiskInterval safetyMargin;
  final StrategyRiskInterval rewardDelta;
  final List<EffectItem> effects;
  final List<CounterfactualItem> counterfactuals;
  final List<AlertLink> relatedAlerts;
  final String? baselinePolicyId;

  factory StrategyCandidate.fromJson(Map<String, dynamic> json) {
    return StrategyCandidate(
      id: json['id']?.toString() ?? 'unknown',
      title: json['title']?.toString() ?? '未命名策略',
      summary: json['summary']?.toString() ?? '暂无摘要',
      priorityHint: json['priorityHint']?.toString() ?? '需人工确认',
      congestionIndex: StrategyRiskInterval.fromJson(
        json['congestionIndex'] ?? json['delayRisk'],
      ),
      conflictRisk: StrategyRiskInterval.fromJson(json['conflictRisk']),
      safetyMargin: StrategyRiskInterval.fromJson(json['safetyMargin']),
      rewardDelta: StrategyRiskInterval.fromJson(
        json['rewardDelta'] ?? json['kpiDelta'],
        fallbackPrefix: '+',
      ),
      effects: _effectsFromJson(json['effects']),
      counterfactuals: _counterfactualsFromJson(json['counterfactuals']),
      relatedAlerts: _alertsFromJson(json['relatedAlerts']),
      baselinePolicyId: json['baselinePolicyId']?.toString(),
    );
  }

  StrategyCandidate copyWith({
    String? id,
    String? title,
    String? summary,
    String? priorityHint,
    StrategyRiskInterval? congestionIndex,
    StrategyRiskInterval? conflictRisk,
    StrategyRiskInterval? safetyMargin,
    StrategyRiskInterval? rewardDelta,
    List<EffectItem>? effects,
    List<CounterfactualItem>? counterfactuals,
    List<AlertLink>? relatedAlerts,
    Object? baselinePolicyId = _noValue,
  }) {
    return StrategyCandidate(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      priorityHint: priorityHint ?? this.priorityHint,
      congestionIndex: congestionIndex ?? this.congestionIndex,
      conflictRisk: conflictRisk ?? this.conflictRisk,
      safetyMargin: safetyMargin ?? this.safetyMargin,
      rewardDelta: rewardDelta ?? this.rewardDelta,
      effects: effects ?? this.effects,
      counterfactuals: counterfactuals ?? this.counterfactuals,
      relatedAlerts: relatedAlerts ?? this.relatedAlerts,
      baselinePolicyId: identical(baselinePolicyId, _noValue)
          ? this.baselinePolicyId
          : baselinePolicyId as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'summary': summary,
      'priorityHint': priorityHint,
      'congestionIndex': congestionIndex.toJson(),
      'conflictRisk': conflictRisk.toJson(),
      'safetyMargin': safetyMargin.toJson(),
      'rewardDelta': rewardDelta.toJson(),
      'effects': effects.map((e) => e.toJson()).toList(),
      'counterfactuals': counterfactuals.map((e) => e.toJson()).toList(),
      'relatedAlerts': relatedAlerts.map((e) => e.toJson()).toList(),
      'baselinePolicyId': baselinePolicyId,
    };
  }

  static List<EffectItem> _effectsFromJson(Object? raw) {
    if (raw is List) {
      return raw.map(EffectItem.fromJson).toList();
    }
    return const [];
  }

  static List<CounterfactualItem> _counterfactualsFromJson(Object? raw) {
    if (raw is List) {
      return raw.map(CounterfactualItem.fromJson).toList();
    }
    return const [];
  }

  static List<AlertLink> _alertsFromJson(Object? raw) {
    if (raw is List) {
      return raw.map(AlertLink.fromJson).toList();
    }
    return const [];
  }
}

class StrategySubmissionDraft {
  const StrategySubmissionDraft({
    required this.policyId,
    required this.policyTitle,
    required this.choiceType,
    required this.remark,
  });

  final String policyId;
  final String policyTitle;
  final HumanChoiceType choiceType;
  final String remark;

  factory StrategySubmissionDraft.empty() {
    return const StrategySubmissionDraft(
      policyId: '',
      policyTitle: '',
      choiceType: HumanChoiceType.guidance,
      remark: '',
    );
  }

  bool get isEmpty => policyId.isEmpty;

  StrategySubmissionDraft copyWith({
    String? policyId,
    String? policyTitle,
    HumanChoiceType? choiceType,
    String? remark,
  }) {
    return StrategySubmissionDraft(
      policyId: policyId ?? this.policyId,
      policyTitle: policyTitle ?? this.policyTitle,
      choiceType: choiceType ?? this.choiceType,
      remark: remark ?? this.remark,
    );
  }
}

class StrategyExecutionUpdate {
  const StrategyExecutionUpdate({
    required this.requestId,
    required this.policyId,
    required this.status,
    required this.at,
    required this.message,
    this.source = 'backend_execution_receipt',
  });

  final String requestId;
  final String policyId;
  final StrategyExecutionStatus status;
  final DateTime at;
  final String message;
  final String source;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestId': requestId,
      'policyId': policyId,
      'executionStatus': status.wireName,
      'executionMessage': message,
      'executionAt': at.toIso8601String(),
      'source': source,
    };
  }
}

class StrategyExecuteReceipt {
  const StrategyExecuteReceipt({
    required this.requestId,
    required this.status,
    required this.acceptedAt,
    required this.message,
  });

  final String requestId;
  final StrategyExecutionStatus status;
  final DateTime acceptedAt;
  final String message;
}

class StrategySubmissionSummary {
  const StrategySubmissionSummary({
    required this.policyId,
    required this.policyTitle,
    required this.choiceType,
    required this.choiceLabel,
    required this.remark,
    required this.requestId,
    required this.submittedAt,
    required this.executionStatus,
    required this.executionMessage,
    required this.lastUpdatedAt,
  });

  final String policyId;
  final String policyTitle;
  final HumanChoiceType choiceType;
  final String choiceLabel;
  final String remark;
  final String requestId;
  final DateTime submittedAt;
  final StrategyExecutionStatus executionStatus;
  final String executionMessage;
  final DateTime lastUpdatedAt;

  String get executionLabel => executionStatus.label;

  StrategySubmissionSummary copyWith({
    String? policyId,
    String? policyTitle,
    HumanChoiceType? choiceType,
    String? choiceLabel,
    String? remark,
    String? requestId,
    DateTime? submittedAt,
    StrategyExecutionStatus? executionStatus,
    String? executionMessage,
    DateTime? lastUpdatedAt,
  }) {
    return StrategySubmissionSummary(
      policyId: policyId ?? this.policyId,
      policyTitle: policyTitle ?? this.policyTitle,
      choiceType: choiceType ?? this.choiceType,
      choiceLabel: choiceLabel ?? this.choiceLabel,
      remark: remark ?? this.remark,
      requestId: requestId ?? this.requestId,
      submittedAt: submittedAt ?? this.submittedAt,
      executionStatus: executionStatus ?? this.executionStatus,
      executionMessage: executionMessage ?? this.executionMessage,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }
}

class StrategyControllerState {
  const StrategyControllerState({
    required this.candidates,
    required this.recommendedPolicyId,
    required this.latestSelectedPolicyId,
    required this.lastSubmission,
    required this.draft,
    required this.isSubmitting,
    required this.isRefreshingCandidates,
    required this.fetchErrorMessage,
    required this.candidatesDataSource,
    required this.lastCandidatesUpdatedAt,
  });

  final List<StrategyCandidate> candidates;
  final String recommendedPolicyId;
  final String? latestSelectedPolicyId;
  final StrategySubmissionSummary? lastSubmission;
  final StrategySubmissionDraft draft;
  final bool isSubmitting;
  final bool isRefreshingCandidates;
  final String? fetchErrorMessage;
  final StrategyCandidatesDataSource candidatesDataSource;
  final DateTime? lastCandidatesUpdatedAt;

  factory StrategyControllerState.initial() {
    return StrategyControllerState(
      candidates: const <StrategyCandidate>[],
      recommendedPolicyId: '',
      latestSelectedPolicyId: null,
      lastSubmission: null,
      draft: StrategySubmissionDraft.empty(),
      isSubmitting: false,
      isRefreshingCandidates: false,
      fetchErrorMessage: null,
      candidatesDataSource: StrategyCandidatesDataSource.cache,
      lastCandidatesUpdatedAt: null,
    );
  }

  StrategyCandidate get recommendedCandidate {
    if (candidates.isEmpty) {
      throw StateError('没有完成留出测试的策略候选。');
    }
    for (final candidate in candidates) {
      if (candidate.id == recommendedPolicyId) {
        return candidate;
      }
    }
    return candidates.first;
  }

  StrategyControllerState copyWith({
    List<StrategyCandidate>? candidates,
    String? recommendedPolicyId,
    Object? latestSelectedPolicyId = _noValue,
    Object? lastSubmission = _noValue,
    StrategySubmissionDraft? draft,
    bool? isSubmitting,
    bool? isRefreshingCandidates,
    Object? fetchErrorMessage = _noValue,
    StrategyCandidatesDataSource? candidatesDataSource,
    Object? lastCandidatesUpdatedAt = _noValue,
  }) {
    return StrategyControllerState(
      candidates: candidates ?? this.candidates,
      recommendedPolicyId: recommendedPolicyId ?? this.recommendedPolicyId,
      latestSelectedPolicyId: identical(latestSelectedPolicyId, _noValue)
          ? this.latestSelectedPolicyId
          : latestSelectedPolicyId as String?,
      lastSubmission: identical(lastSubmission, _noValue)
          ? this.lastSubmission
          : lastSubmission as StrategySubmissionSummary?,
      draft: draft ?? this.draft,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isRefreshingCandidates:
          isRefreshingCandidates ?? this.isRefreshingCandidates,
      fetchErrorMessage: identical(fetchErrorMessage, _noValue)
          ? this.fetchErrorMessage
          : fetchErrorMessage as String?,
      candidatesDataSource: candidatesDataSource ?? this.candidatesDataSource,
      lastCandidatesUpdatedAt: identical(lastCandidatesUpdatedAt, _noValue)
          ? this.lastCandidatesUpdatedAt
          : lastCandidatesUpdatedAt as DateTime?,
    );
  }
}

const Object _noValue = Object();

final strategyApiBaseUrlProvider = Provider<String?>((ref) => null);

final strategyCandidatesEndpointProvider = Provider<String?>(
  (ref) => '/api/mobile/strategy/candidates',
);

final strategyRepositoryProvider = Provider<StrategyRepository>((ref) {
  final dio = ref.read(dioProvider);
  final baseUrl = ref.watch(strategyApiBaseUrlProvider);
  final endpoint = ref.watch(strategyCandidatesEndpointProvider);

  return StrategyRepository(
    dio: dio,
    baseUrl: baseUrl,
    candidatesEndpoint: endpoint,
  );
});

final strategyControllerProvider =
    NotifierProvider<StrategyController, StrategyControllerState>(
      StrategyController.new,
    );

class StrategyController extends Notifier<StrategyControllerState> {
  static const String _cacheKey = 'cache.strategy.candidates.latest.v1';

  StreamSubscription<StrategyExecutionUpdate>? _executionSubscription;
  bool _disposed = false;

  StrategyRepository get _repository => ref.read(strategyRepositoryProvider);

  @override
  StrategyControllerState build() {
    ref.onDispose(() {
      _disposed = true;
      _executionSubscription?.cancel();
    });

    final initial = StrategyControllerState.initial();
    Future.microtask(_bootstrapCandidatesFromCacheThenRefresh);
    return initial;
  }

  Future<void> _bootstrapCandidatesFromCacheThenRefresh() async {
    final cached = await _readCachedCandidates();
    if (_disposed) return;

    if (cached != null && cached.isNotEmpty) {
      final recommendedId = StrategyRepository.pickRecommendedId(cached);
      state = state.copyWith(
        candidates: cached,
        recommendedPolicyId: recommendedId,
        candidatesDataSource: StrategyCandidatesDataSource.cache,
        lastCandidatesUpdatedAt: DateTime.now(),
      );
    }

    await refreshCandidates(silent: true);
  }

  Future<void> refreshCandidates({bool silent = false}) async {
    final previous = state;

    state = state.copyWith(
      isRefreshingCandidates: !silent,
      fetchErrorMessage: null,
    );

    try {
      final candidates = await _repository.getCandidates();
      final recommendedId = StrategyRepository.pickRecommendedId(candidates);
      final latestSelectedId = _resolveLatestSelectedId(
        candidates: candidates,
        previousLatestSelectedId: previous.latestSelectedPolicyId,
      );

      await _writeCachedCandidates(candidates);

      if (_disposed) return;

      state = state.copyWith(
        candidates: candidates,
        recommendedPolicyId: recommendedId,
        latestSelectedPolicyId: latestSelectedId,
        isRefreshingCandidates: false,
        fetchErrorMessage: null,
        candidatesDataSource: StrategyCandidatesDataSource.backendArtifact,
        lastCandidatesUpdatedAt: DateTime.now(),
      );
    } catch (error) {
      if (_disposed) return;

      state = previous.copyWith(
        isRefreshingCandidates: false,
        fetchErrorMessage: error.toString(),
      );
    }
  }

  Future<List<StrategyCandidate>?> _readCachedCandidates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;

      final items = <StrategyCandidate>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          items.add(StrategyCandidate.fromJson(item));
        } else if (item is Map) {
          items.add(
            StrategyCandidate.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      }

      return items.isEmpty ? null : items;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedCandidates(
    List<StrategyCandidate> candidates,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(candidates.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // cache failure should not break strategy flow
    }
  }

  void startDraft({required String policyId, required String policyTitle}) {
    state = state.copyWith(
      draft: StrategySubmissionDraft(
        policyId: policyId,
        policyTitle: policyTitle,
        choiceType: HumanChoiceType.guidance,
        remark: '',
      ),
    );
  }

  void setDraftChoice(HumanChoiceType choiceType) {
    state = state.copyWith(draft: state.draft.copyWith(choiceType: choiceType));
  }

  void setDraftRemark(String remark) {
    state = state.copyWith(draft: state.draft.copyWith(remark: remark));
  }

  void clearDraft() {
    state = state.copyWith(draft: StrategySubmissionDraft.empty());
  }

  Future<AuditEvent> submitDraft() async {
    final draft = state.draft;
    if (draft.isEmpty) {
      throw StateError('当前没有可提交的策略草稿。');
    }
    if (state.isSubmitting) {
      throw StateError('当前已在提交中，请稍后再试。');
    }

    state = state.copyWith(isSubmitting: true);

    try {
      final candidate = state.candidates.firstWhere(
        (item) => item.id == draft.policyId,
        orElse: () => state.recommendedCandidate,
      );

      final actionType = _toAuditActionType(draft.choiceType);
      final trimmedRemark = draft.remark.trim();
      final submittedAt = DateTime.now();

      final executeReceipt = await _repository
          .executePolicy(candidate.id, <String, Object?>{
            'policyTitle': candidate.title,
            'humanChoiceType': draft.choiceType.name,
            'humanChoiceLabel': draft.choiceType.label,
            'remark': trimmedRemark,
            'source': 'strategy_tab',
            'state': _buildStatePayload(candidate),
            'policy_set': _buildPolicySetPayload(candidate),
            'human_choice': _buildHumanChoicePayload(
              choiceType: draft.choiceType,
              remark: trimmedRemark,
              candidate: candidate,
            ),
          });

      final receipt = ref
          .read(auditTimelineProvider.notifier)
          .recordAction(
            'human_override',
            meta: <String, Object?>{
              'source': 'strategy_tab',
              'actionType': actionType.wireName,
              'requestId': executeReceipt.requestId,
              'stateSummary': _buildStateSummary(candidate, draft.choiceType),
              'policySetSummary': _buildPolicySetSummary(candidate),
              'humanChoiceSummary': _buildHumanChoiceSummary(
                choiceType: draft.choiceType,
                remark: trimmedRemark,
              ),
              'executionStatus': executeReceipt.status.wireName,
              'executionMessage': executeReceipt.message,
              'executionUpdatedAt': executeReceipt.acceptedAt.toIso8601String(),
              'targetPolicyId': candidate.id,
              'targetPolicyTitle': candidate.title,
              'human_choice': <String, Object?>{
                'type': draft.choiceType.name,
                'label': draft.choiceType.label,
                'target_policy_id': candidate.id,
                'target_policy_title': candidate.title,
                'remark': trimmedRemark,
              },
              'candidate_snapshot': <String, Object?>{
                'summary': candidate.summary,
                'priorityHint': candidate.priorityHint,
                'congestionIndex': candidate.congestionIndex.toJson(),
                'conflictRisk': candidate.conflictRisk.toJson(),
                'safetyMargin': candidate.safetyMargin.toJson(),
                'rewardDelta': candidate.rewardDelta.toJson(),
                'effects': candidate.effects.map((e) => e.toJson()).toList(),
                'counterfactuals': candidate.counterfactuals
                    .map((item) => item.toJson())
                    .toList(),
                'relatedAlerts': candidate.relatedAlerts
                    .map((item) => item.toJson())
                    .toList(),
                'baselinePolicyId': candidate.baselinePolicyId,
              },
            },
          );

      state = state.copyWith(
        isSubmitting: false,
        latestSelectedPolicyId: candidate.id,
        lastSubmission: StrategySubmissionSummary(
          policyId: candidate.id,
          policyTitle: candidate.title,
          choiceType: draft.choiceType,
          choiceLabel: draft.choiceType.label,
          remark: trimmedRemark,
          requestId: executeReceipt.requestId,
          submittedAt: submittedAt,
          executionStatus: executeReceipt.status,
          executionMessage: executeReceipt.message,
          lastUpdatedAt: executeReceipt.acceptedAt,
        ),
        draft: StrategySubmissionDraft.empty(),
      );

      if (!executeReceipt.status.isTerminal) {
        _startWatchingExecutionReceipt(
          requestId: executeReceipt.requestId,
          candidate: candidate,
          choiceType: draft.choiceType,
        );
      }

      return receipt;
    } catch (error) {
      state = state.copyWith(isSubmitting: false);
      rethrow;
    }
  }

  void applyExecutionFeedback(StrategyExecutionUpdate update) {
    _commitExecutionUpdate(update, fromRemoteStream: true);
  }

  void _startWatchingExecutionReceipt({
    required String requestId,
    required StrategyCandidate candidate,
    required HumanChoiceType choiceType,
  }) {
    _executionSubscription?.cancel();
    _executionSubscription = _repository
        .watchExecutionReceipt(
          requestId: requestId,
          policyId: candidate.id,
          choiceType: choiceType,
        )
        .listen(
          (update) => _commitExecutionUpdate(update),
          onError: (Object error, StackTrace stackTrace) {
            _commitExecutionUpdate(
              StrategyExecutionUpdate(
                requestId: requestId,
                policyId: candidate.id,
                status: StrategyExecutionStatus.failed,
                at: DateTime.now(),
                message: '后端执行回执流异常：$error',
                source: 'backend_execution_stream_error',
              ),
            );
          },
        );
  }

  void _commitExecutionUpdate(
    StrategyExecutionUpdate update, {
    bool fromRemoteStream = false,
  }) {
    final latest = state.lastSubmission;
    if (latest == null || latest.requestId != update.requestId) {
      return;
    }

    state = state.copyWith(
      lastSubmission: latest.copyWith(
        executionStatus: update.status,
        executionMessage: update.message,
        lastUpdatedAt: update.at,
      ),
    );

    ref
        .read(auditTimelineProvider.notifier)
        .recordAction(
          'execution_feedback',
          meta: <String, Object?>{
            'source': fromRemoteStream
                ? 'strategy_backend_push'
                : 'strategy_backend_poll',
            'actionType': latest.choiceType == HumanChoiceType.veto
                ? AuditActionType.veto.wireName
                : AuditActionType.guidance.wireName,
            'requestId': update.requestId,
            'targetPolicyId': update.policyId,
            'executionStatus': update.status.wireName,
            'executionMessage': update.message,
            'executionUpdatedAt': update.at.toIso8601String(),
            'stateSummary': '执行链路状态更新：${update.status.label}',
            'policySetSummary': latest.policyTitle,
            'humanChoiceSummary': latest.remark.isEmpty
                ? '人工表态：${latest.choiceLabel}'
                : '人工表态：${latest.choiceLabel} · 备注：${latest.remark}',
            'execution_feedback': update.toJson(),
          },
        );

    if (update.status.isTerminal) {
      _executionSubscription?.cancel();
      _executionSubscription = null;
    }
  }

  AuditActionType _toAuditActionType(HumanChoiceType choiceType) {
    switch (choiceType) {
      case HumanChoiceType.override:
        return AuditActionType.override;
      case HumanChoiceType.guidance:
        return AuditActionType.guidance;
      case HumanChoiceType.veto:
        return AuditActionType.veto;
    }
  }

  String _buildStateSummary(
    StrategyCandidate candidate,
    HumanChoiceType choiceType,
  ) {
    switch (choiceType) {
      case HumanChoiceType.override:
        return '人工在策略页覆盖系统建议，选定策略：${candidate.title}';
      case HumanChoiceType.guidance:
        return '人工确认以 guidance 方式推进策略：${candidate.title}';
      case HumanChoiceType.veto:
        return '人工否决当前默认建议，并标记策略：${candidate.title}';
    }
  }

  String _buildPolicySetSummary(StrategyCandidate candidate) {
    return '${candidate.title} · 测试拥堵 ${candidate.congestionIndex.displayText} · '
        '冲突风险 ${candidate.conflictRisk.displayText} · '
        '安全余量 ${candidate.safetyMargin.displayText} · '
        '相对声明基线改善 ${candidate.rewardDelta.displayText}';
  }

  String _buildHumanChoiceSummary({
    required HumanChoiceType choiceType,
    required String remark,
  }) {
    if (remark.isEmpty) {
      return '人工表态：${choiceType.label}';
    }
    return '人工表态：${choiceType.label} · 备注：$remark';
  }

  Map<String, Object?> _buildStatePayload(StrategyCandidate candidate) {
    return <String, Object?>{
      'policyId': candidate.id,
      'policyTitle': candidate.title,
      'summary': candidate.summary,
      'priorityHint': candidate.priorityHint,
      'congestionIndex': candidate.congestionIndex.toJson(),
      'conflictRisk': candidate.conflictRisk.toJson(),
      'safetyMargin': candidate.safetyMargin.toJson(),
      'rewardDelta': candidate.rewardDelta.toJson(),
    };
  }

  Map<String, Object?> _buildPolicySetPayload(StrategyCandidate candidate) {
    return <String, Object?>{
      'policyId': candidate.id,
      'policyTitle': candidate.title,
      'baselinePolicyId': candidate.baselinePolicyId,
      'effects': candidate.effects.map((item) => item.toJson()).toList(),
      'counterfactuals': candidate.counterfactuals
          .map((item) => item.toJson())
          .toList(),
      'relatedAlerts': candidate.relatedAlerts
          .map((item) => item.toJson())
          .toList(),
    };
  }

  Map<String, Object?> _buildHumanChoicePayload({
    required HumanChoiceType choiceType,
    required String remark,
    required StrategyCandidate candidate,
  }) {
    return <String, Object?>{
      'type': choiceType.name,
      'label': choiceType.label,
      'remark': remark,
      'targetPolicyId': candidate.id,
      'targetPolicyTitle': candidate.title,
    };
  }

  String? _resolveLatestSelectedId({
    required List<StrategyCandidate> candidates,
    required String? previousLatestSelectedId,
  }) {
    if (previousLatestSelectedId == null) return null;

    final exists = candidates.any(
      (item) => item.id == previousLatestSelectedId,
    );
    return exists ? previousLatestSelectedId : null;
  }
}

class StrategyRepository {
  StrategyRepository({
    required this.dio,
    required this.baseUrl,
    required this.candidatesEndpoint,
  });

  final Dio dio;
  final String? baseUrl;
  final String? candidatesEndpoint;

  static String pickRecommendedId(List<StrategyCandidate> candidates) {
    if (candidates.isEmpty) {
      throw StateError('后端未返回任何完成留出测试的策略产物。');
    }
    for (final candidate in candidates) {
      if (candidate.priorityHint.contains('默认推荐')) {
        return candidate.id;
      }
    }
    return candidates.first.id;
  }

  Future<List<StrategyCandidate>> getCandidates() async {
    final endpoint = candidatesEndpoint?.trim() ?? '';
    if (endpoint.isEmpty) {
      throw StateError('未配置策略候选 API。');
    }

    try {
      final response = await dio.getUri(_buildUri(endpoint));
      final data = response.data;

      if (data is List) {
        final parsed = data
            .whereType<Map<String, dynamic>>()
            .map(StrategyCandidate.fromJson)
            .toList();

        if (parsed.isNotEmpty) return parsed;
      }

      if (data is Map<String, dynamic>) {
        final nested = data['items'] ?? data['candidates'] ?? data['data'];
        if (nested is List) {
          final parsed = nested
              .whereType<Map<String, dynamic>>()
              .map(StrategyCandidate.fromJson)
              .toList();
          if (parsed.isNotEmpty) return parsed;
        }
      }
    } catch (error) {
      throw StateError('读取真实策略产物失败：$error');
    }

    throw StateError('后端尚无完成留出测试的策略产物。');
  }

  Future<StrategyExecuteReceipt> executePolicy(
    String policyId,
    Map<String, Object?> payload,
  ) async {
    final idempotencyKey =
        'dt-mobile-${DateTime.now().microsecondsSinceEpoch}-$policyId';
    final response = await dio.post<Object>(
      '/api/mobile/strategy/decisions',
      data: <String, Object?>{
        ...payload,
        'target_policy_id': policyId,
        'client_ts': DateTime.now().toUtc().toIso8601String(),
        'source': 'dt_mobile_app',
        'requested_by': 'mobile_operator',
        'production_dispatch': false,
      },
      options: Options(
        headers: <String, Object?>{'Idempotency-Key': idempotencyKey},
      ),
    );
    final data = response.data is Map
        ? (response.data as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};
    return parseDryRunReceipt(data, acceptedAt: DateTime.now());
  }

  Stream<StrategyExecutionUpdate> watchExecutionReceipt({
    required String requestId,
    required String policyId,
    required HumanChoiceType choiceType,
  }) async* {
    for (var attempt = 0; attempt < 60; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final response = await dio.get<Object>(
        '/api/mobile/strategy/decisions/$requestId',
      );
      final data = response.data is Map
          ? (response.data as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : <String, dynamic>{};
      if (data['production_dispatch'] != false) {
        throw StateError('服务端回执未明确 production_dispatch=false，移动端已失效安全阻断。');
      }
      final status = _parseExecutionStatus(data['execution_status']);
      if (status == StrategyExecutionStatus.executing ||
          status == StrategyExecutionStatus.acked) {
        throw StateError('移动端仅允许 dry-run 回执，拒绝生产执行状态 ${status.wireName}。');
      }
      yield StrategyExecutionUpdate(
        requestId: requestId,
        policyId: policyId,
        status: status,
        at:
            DateTime.tryParse(data['updated_at']?.toString() ?? '') ??
            DateTime.now(),
        message: data['message']?.toString() ?? '后端执行状态已更新',
      );
      if (status.isTerminal) return;
    }
    throw StateError('等待真实执行回执超时；未生成成功回执。');
  }

  static StrategyExecutionStatus _parseExecutionStatus(Object? raw) {
    return switch (raw?.toString().toLowerCase()) {
      'executing' => StrategyExecutionStatus.executing,
      'dry_run_recorded' => StrategyExecutionStatus.dryRunRecorded,
      'acked' => StrategyExecutionStatus.acked,
      'failed' => StrategyExecutionStatus.failed,
      _ => StrategyExecutionStatus.submitted,
    };
  }

  static StrategyExecuteReceipt parseDryRunReceipt(
    Map<String, dynamic> data, {
    required DateTime acceptedAt,
  }) {
    if (data['accepted'] != true) {
      throw StateError(data['message']?.toString() ?? '后端拒绝策略表态。');
    }
    if (data['production_dispatch'] != false) {
      throw StateError('服务端未明确返回 production_dispatch=false，移动端已失效安全阻断。');
    }
    final requestId = data['request_id']?.toString().trim() ?? '';
    if (requestId.isEmpty) {
      throw StateError('后端未返回可审计的 request_id。');
    }
    final status = _parseExecutionStatus(data['execution_status']);
    if (status != StrategyExecutionStatus.dryRunRecorded) {
      throw StateError('移动端只接受 dry_run_recorded，实际为 ${status.wireName}。');
    }
    return StrategyExecuteReceipt(
      requestId: requestId,
      status: status,
      acceptedAt: acceptedAt,
      message: data['message']?.toString() ?? '后端已记录人工表态',
    );
  }

  Uri _buildUri(String endpoint) {
    if (baseUrl == null || baseUrl!.trim().isEmpty) {
      return Uri.parse(endpoint);
    }

    final base = Uri.parse(baseUrl!.trim());
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      return Uri.parse(endpoint);
    }

    final cleanBasePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final cleanEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';

    return base.replace(path: '$cleanBasePath$cleanEndpoint');
  }
}

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dt_mobile_app/core/network/dio_provider.dart';

enum AuditActionType { override, guidance, veto }

enum AuditEventSource {
  aiSuggestion,
  humanOverride,
  triggerReplan,
  configChange,
  executionFeedback,
}

enum AuditUploadStatus { pending, success, failed, notConfigured }

extension AuditActionTypeX on AuditActionType {
  String get wireName {
    switch (this) {
      case AuditActionType.override:
        return 'override';
      case AuditActionType.guidance:
        return 'guidance';
      case AuditActionType.veto:
        return 'veto';
    }
  }

  static AuditActionType fromWire(Object? raw) {
    if (raw is String) {
      switch (raw) {
        case 'override':
          return AuditActionType.override;
        case 'guidance':
          return AuditActionType.guidance;
        case 'veto':
          return AuditActionType.veto;
      }
    }
    return AuditActionType.guidance;
  }
}

extension AuditEventSourceX on AuditEventSource {
  String get wireName {
    switch (this) {
      case AuditEventSource.aiSuggestion:
        return 'ai_suggestion';
      case AuditEventSource.humanOverride:
        return 'human_override';
      case AuditEventSource.triggerReplan:
        return 'trigger_replan';
      case AuditEventSource.configChange:
        return 'config_change';
      case AuditEventSource.executionFeedback:
        return 'execution_feedback';
    }
  }

  static AuditEventSource fromWire(Object? raw) {
    if (raw is String) {
      switch (raw) {
        case 'ai_suggestion':
          return AuditEventSource.aiSuggestion;
        case 'human_override':
          return AuditEventSource.humanOverride;
        case 'trigger_replan':
          return AuditEventSource.triggerReplan;
        case 'config_change':
          return AuditEventSource.configChange;
        case 'execution_feedback':
          return AuditEventSource.executionFeedback;
      }
    }
    return AuditEventSource.executionFeedback;
  }
}

extension AuditUploadStatusX on AuditUploadStatus {
  String get wireName {
    switch (this) {
      case AuditUploadStatus.pending:
        return 'pending';
      case AuditUploadStatus.success:
        return 'success';
      case AuditUploadStatus.failed:
        return 'failed';
      case AuditUploadStatus.notConfigured:
        return 'notConfigured';
    }
  }

  static AuditUploadStatus fromWire(Object? raw) {
    if (raw is String) {
      switch (raw) {
        case 'pending':
          return AuditUploadStatus.pending;
        case 'success':
          return AuditUploadStatus.success;
        case 'failed':
          return AuditUploadStatus.failed;
        case 'notConfigured':
          return AuditUploadStatus.notConfigured;
      }
    }
    return AuditUploadStatus.notConfigured;
  }
}

String _buildReplayPrimaryLabel(AuditEventSource source) {
  switch (source) {
    case AuditEventSource.executionFeedback:
      return '回放（高亮相邻记录）';
    case AuditEventSource.aiSuggestion:
    case AuditEventSource.humanOverride:
    case AuditEventSource.triggerReplan:
    case AuditEventSource.configChange:
      return '进入回放';
  }
}

String _buildReplayHint(AuditEventSource source) {
  switch (source) {
    case AuditEventSource.executionFeedback:
      return '核对提交与执行回执记录';
    case AuditEventSource.aiSuggestion:
    case AuditEventSource.humanOverride:
    case AuditEventSource.triggerReplan:
    case AuditEventSource.configChange:
      return '回看本次事件链路';
  }
}

String _buildReplayViewLabel(AuditEventSource source) {
  switch (source) {
    case AuditEventSource.executionFeedback:
      return '进入复盘视图';
    case AuditEventSource.aiSuggestion:
    case AuditEventSource.humanOverride:
    case AuditEventSource.triggerReplan:
    case AuditEventSource.configChange:
      return '进入回放';
  }
}

@immutable
class AuditEvent {
  const AuditEvent({
    required this.eventId,
    required this.time,
    required this.source,
    required this.actionType,
    required this.stateSummary,
    required this.policySetSummary,
    required this.humanChoiceSummary,
    this.payload = const <String, Object?>{},
  });

  final String eventId;
  final DateTime time;
  final AuditEventSource source;
  final AuditActionType actionType;
  final String stateSummary;
  final String policySetSummary;
  final String humanChoiceSummary;
  final Map<String, Object?> payload;

  String get requestId => eventId;

  DateTime get at => time;

  String get actionLabel => '${source.wireName} · ${actionType.wireName}';

  Map<String, Object?> get meta => payload;

  AuditUploadStatus get uploadStatus =>
      AuditUploadStatusX.fromWire(payload['uploadStatus']);

  AuditEvent copyWith({
    String? eventId,
    DateTime? time,
    AuditEventSource? source,
    AuditActionType? actionType,
    String? stateSummary,
    String? policySetSummary,
    String? humanChoiceSummary,
    Map<String, Object?>? payload,
  }) {
    return AuditEvent(
      eventId: eventId ?? this.eventId,
      time: time ?? this.time,
      source: source ?? this.source,
      actionType: actionType ?? this.actionType,
      stateSummary: stateSummary ?? this.stateSummary,
      policySetSummary: policySetSummary ?? this.policySetSummary,
      humanChoiceSummary: humanChoiceSummary ?? this.humanChoiceSummary,
      payload: payload ?? this.payload,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'eventId': eventId,
      'time': time.toIso8601String(),
      'source': source.wireName,
      'actionType': actionType.wireName,
      'stateSummary': stateSummary,
      'policySetSummary': policySetSummary,
      'humanChoiceSummary': humanChoiceSummary,
      'payload': payload,
    };
  }

  static AuditEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;

    try {
      final map = raw.map((key, value) => MapEntry(key.toString(), value));

      final payloadRaw = map['payload'];
      final payload = payloadRaw is Map
          ? payloadRaw.map((key, value) => MapEntry(key.toString(), value))
          : <String, Object?>{};

      return AuditEvent(
        eventId: map['eventId']?.toString() ?? '',
        time: DateTime.parse(map['time']?.toString() ?? ''),
        source: AuditEventSourceX.fromWire(map['source']),
        actionType: AuditActionTypeX.fromWire(map['actionType']),
        stateSummary: map['stateSummary']?.toString() ?? '',
        policySetSummary: map['policySetSummary']?.toString() ?? '',
        humanChoiceSummary: map['humanChoiceSummary']?.toString() ?? '',
        payload: payload,
      );
    } catch (_) {
      return null;
    }
  }
}

@immutable
class AuditTimeline {
  const AuditTimeline({
    required this.latest,
    required this.items,
    required this.maxKeep,
  });

  final AuditEvent? latest;
  final List<AuditEvent> items;
  final int maxKeep;

  int get count => items.length;
}

@immutable
class AuditUploadResult {
  const AuditUploadResult({
    required this.status,
    required this.message,
    this.statusCode,
  });

  final AuditUploadStatus status;
  final String message;
  final int? statusCode;
}

abstract class AuditRepository {
  Future<AuditEvent> saveLocal(AuditEvent event);

  Future<AuditEvent> updateLocal(AuditEvent event);

  Future<AuditUploadResult> upload(AuditEvent event);
}

class LocalAuditRepository implements AuditRepository {
  LocalAuditRepository({required Dio dio, required bool uploadEnabled})
    : _dio = dio,
      _uploadEnabled = uploadEnabled;

  final Dio _dio;
  final bool _uploadEnabled;

  final List<AuditEvent> _memory = <AuditEvent>[];

  @override
  Future<AuditEvent> saveLocal(AuditEvent event) async {
    _memory.removeWhere((e) => e.eventId == event.eventId);
    _memory.insert(0, event);
    return event;
  }

  @override
  Future<AuditEvent> updateLocal(AuditEvent event) async {
    final index = _memory.indexWhere((e) => e.eventId == event.eventId);
    if (index >= 0) {
      _memory[index] = event;
    } else {
      _memory.insert(0, event);
    }
    return event;
  }

  @override
  Future<AuditUploadResult> upload(AuditEvent event) async {
    if (!_uploadEnabled) {
      return const AuditUploadResult(
        status: AuditUploadStatus.notConfigured,
        message: '审计上传未配置',
      );
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/mobile/audit/events',
        data: <String, Object?>{
          'eventId': event.eventId,
          'time': event.time.toIso8601String(),
          'source': event.source.wireName,
          'actionType': event.actionType.wireName,
          'stateSummary': event.stateSummary,
          'policySetSummary': event.policySetSummary,
          'humanChoiceSummary': event.humanChoiceSummary,
          'payload': event.payload,
        },
      );

      final code = response.statusCode ?? 200;
      if (code >= 200 && code < 300) {
        return AuditUploadResult(
          status: AuditUploadStatus.success,
          message: '审计上传成功',
          statusCode: code,
        );
      }

      return AuditUploadResult(
        status: AuditUploadStatus.failed,
        message: '审计上传失败（HTTP $code）',
        statusCode: code,
      );
    } catch (error) {
      final appError = mapToAppNetworkException(error);
      return AuditUploadResult(
        status: AuditUploadStatus.failed,
        message: appError.message,
        statusCode: appError.statusCode,
      );
    }
  }
}

final auditUploadEnabledProvider = Provider<bool>((ref) {
  return const bool.fromEnvironment('AUDIT_UPLOAD_ENABLED', defaultValue: true);
});

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final uploadEnabled = ref.watch(auditUploadEnabledProvider);

  return LocalAuditRepository(dio: dio, uploadEnabled: uploadEnabled);
});

final auditTimelineProvider =
    NotifierProvider<AuditTimelineNotifier, AuditTimeline>(
      AuditTimelineNotifier.new,
    );

class AuditTimelineNotifier extends Notifier<AuditTimeline> {
  static const int kDefaultMaxKeep = 200;
  static const String _cacheKey = 'cache.audit.timeline.latest.v1';

  final Random _rand = Random();

  @override
  AuditTimeline build() {
    Future.microtask(_restoreCachedTimeline);
    return const AuditTimeline(
      latest: null,
      items: <AuditEvent>[],
      maxKeep: kDefaultMaxKeep,
    );
  }

  AuditRepository get _repository => ref.read(auditRepositoryProvider);

  bool get _uploadEnabled => ref.read(auditUploadEnabledProvider);

  Future<void> _restoreCachedTimeline() async {
    final cached = await _readCache();
    if (cached == null) return;
    state = cached;
  }

  String _newEventId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final salt = _rand.nextInt(9000) + 1000;
    return 'audit-$ts-$salt';
  }

  AuditEventSource _parseSource(String raw) {
    switch (raw) {
      case 'ai_suggestion':
        return AuditEventSource.aiSuggestion;
      case 'human_override':
        return AuditEventSource.humanOverride;
      case 'trigger_replan':
        return AuditEventSource.triggerReplan;
      case 'config_change':
        return AuditEventSource.configChange;
      case 'execution_feedback':
        return AuditEventSource.executionFeedback;
      default:
        return AuditEventSource.executionFeedback;
    }
  }

  AuditActionType _parseActionType(Object? raw) {
    if (raw is String) {
      switch (raw) {
        case 'override':
          return AuditActionType.override;
        case 'veto':
          return AuditActionType.veto;
        case 'guidance':
          return AuditActionType.guidance;
      }
    }
    return AuditActionType.guidance;
  }

  String _normalizeExecutionStatus(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    switch (value) {
      case 'submitted':
      case 'executing':
      case 'dry_run_recorded':
      case 'acked':
      case 'failed':
        return value!;
      default:
        return 'submitted';
    }
  }

  String _buildExecutionStateSummary({
    required String policyTitle,
    required String status,
    String? message,
  }) {
    final normalized = _normalizeExecutionStatus(status);
    final suffix = message != null && message.trim().isNotEmpty
        ? ' · ${message.trim()}'
        : '';

    switch (normalized) {
      case 'submitted':
        return '策略 $policyTitle 已提交执行队列$suffix';
      case 'executing':
        return '策略 $policyTitle 正在执行中$suffix';
      case 'dry_run_recorded':
        return '策略 $policyTitle 仅记录公开回放干跑，未生产下发$suffix';
      case 'acked':
        return '策略 $policyTitle 已收到执行回执$suffix';
      case 'failed':
        return '策略 $policyTitle 执行失败，等待人工处理$suffix';
      default:
        return '策略 $policyTitle 执行状态已更新$suffix';
    }
  }

  AuditActionType _actionTypeFromWireOrFallback(Object? raw) {
    if (raw is String) {
      switch (raw) {
        case 'override':
          return AuditActionType.override;
        case 'veto':
          return AuditActionType.veto;
        case 'guidance':
          return AuditActionType.guidance;
      }
    }
    return AuditActionType.guidance;
  }

  String _readString(
    Map<String, Object?> data,
    String key, {
    required String fallback,
  }) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  Map<String, Object?> _withUploadFields(
    Map<String, Object?> payload, {
    required AuditUploadStatus status,
    String? uploadMessage,
    int? uploadStatusCode,
    DateTime? uploadedAt,
  }) {
    return <String, Object?>{
      ...payload,
      'uploadStatus': status.wireName,
      'uploadMessage': ?uploadMessage,
      'uploadStatusCode': ?uploadStatusCode,
      if (uploadedAt != null) 'uploadedAt': uploadedAt.toIso8601String(),
    };
  }

  AuditTimeline _append(AuditEvent event) {
    final nextItems = <AuditEvent>[event, ...state.items];
    final trimmed = nextItems.length <= state.maxKeep
        ? nextItems
        : nextItems.sublist(0, state.maxKeep);

    final next = AuditTimeline(
      latest: event,
      items: trimmed,
      maxKeep: state.maxKeep,
    );

    state = next;
    _persistCache(next);
    return next;
  }

  void _replaceEvent(AuditEvent event) {
    final nextItems = state.items
        .map((item) => item.eventId == event.eventId ? event : item)
        .toList(growable: false);

    final nextLatest = state.latest?.eventId == event.eventId
        ? event
        : state.latest;

    final next = AuditTimeline(
      latest: nextLatest,
      items: nextItems,
      maxKeep: state.maxKeep,
    );

    state = next;
    _persistCache(next);
  }

  Future<void> _attemptUpload(AuditEvent event) async {
    final result = await _repository.upload(event);

    if (result.status == AuditUploadStatus.notConfigured) {
      final updated = event.copyWith(
        payload: _withUploadFields(
          event.payload,
          status: AuditUploadStatus.notConfigured,
          uploadMessage: result.message,
        ),
      );
      await _repository.updateLocal(updated);
      _replaceEvent(updated);
      return;
    }

    final updated = event.copyWith(
      payload: _withUploadFields(
        event.payload,
        status: result.status,
        uploadMessage: result.message,
        uploadStatusCode: result.statusCode,
        uploadedAt: result.status == AuditUploadStatus.success
            ? DateTime.now()
            : null,
      ),
    );

    await _repository.updateLocal(updated);
    _replaceEvent(updated);
  }

  AuditEvent recordEvent({
    required AuditEventSource source,
    required AuditActionType actionType,
    required String stateSummary,
    required String policySetSummary,
    required String humanChoiceSummary,
    Map<String, Object?> payload = const <String, Object?>{},
    DateTime? time,
    String? eventId,
  }) {
    final initialUploadStatus = _uploadEnabled
        ? AuditUploadStatus.pending
        : AuditUploadStatus.notConfigured;

    final event = AuditEvent(
      eventId: eventId ?? _newEventId(),
      time: time ?? DateTime.now(),
      source: source,
      actionType: actionType,
      stateSummary: stateSummary,
      policySetSummary: policySetSummary,
      humanChoiceSummary: humanChoiceSummary,
      payload: _withUploadFields(
        payload,
        status: initialUploadStatus,
        uploadMessage: _uploadEnabled ? '审计上传排队中' : '审计上传未配置',
      ),
    );

    _repository.saveLocal(event);
    _append(event);
    _attemptUpload(event);

    return event;
  }

  AuditEvent recordAction(
    String actionLabel, {
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final source = _parseSource(actionLabel);
    final actionType = _parseActionType(meta['actionType']);

    final sourceAlertTitle = meta['sourceAlertTitle'];
    final status = meta['status'];
    final replayPrimaryLabel = _buildReplayPrimaryLabel(source);
    final replayHint = _buildReplayHint(source);
    final replayViewLabel = _buildReplayViewLabel(source);

    final String defaultStateSummary = switch (source) {
      AuditEventSource.triggerReplan =>
        sourceAlertTitle is String && sourceAlertTitle.trim().isNotEmpty
            ? '由告警触发重规划：$sourceAlertTitle'
            : '人工从告警页触发重规划',
      AuditEventSource.aiSuggestion => '算法或测试候选证据已记录，等待人工表态',
      AuditEventSource.humanOverride => '人工对当前策略进行了覆盖，可继续回看本次事件链路',
      AuditEventSource.configChange => '运行参数或策略配置发生变化，可继续进入回放核对影响范围',
      AuditEventSource.executionFeedback => '执行链路回传了结果或状态更新，适合核对提交与回执记录',
    };

    final String defaultPolicySummary = switch (source) {
      AuditEventSource.triggerReplan => '重规划审阅申请已登记，以绑定的测试产物为准',
      AuditEventSource.aiSuggestion => '候选证据已记录，以完成的留出测试产物为准',
      AuditEventSource.humanOverride => '原策略被人工替换，可继续进入回放',
      AuditEventSource.configChange => '客户端审阅参数已记录，未改变生产控制',
      AuditEventSource.executionFeedback => '执行反馈已关联至当前策略集，可核对相邻审计记录',
    };

    final String defaultHumanChoiceSummary = switch (actionType) {
      AuditActionType.override => '人工选择覆盖系统建议',
      AuditActionType.guidance => '人工给出指导，是否执行以真实回执和门禁为准',
      AuditActionType.veto => '人工否决当前建议/动作',
    };

    return recordEvent(
      source: source,
      actionType: actionType,
      stateSummary: _readString(
        meta,
        'stateSummary',
        fallback: defaultStateSummary,
      ),
      policySetSummary: _readString(
        meta,
        'policySetSummary',
        fallback: defaultPolicySummary,
      ),
      humanChoiceSummary: _readString(
        meta,
        'humanChoiceSummary',
        fallback: status is String && status.trim().isNotEmpty
            ? '$defaultHumanChoiceSummary（当前状态：${status.trim()}）'
            : defaultHumanChoiceSummary,
      ),
      payload: <String, Object?>{
        'sourceWire': source.wireName,
        'actionTypeWire': actionType.wireName,
        'replayEntryLabel': replayPrimaryLabel,
        'replayHint': replayHint,
        'replayViewLabel': replayViewLabel,
        ...meta,
      },
    );
  }

  AuditEvent recordExecutionFeedback({
    required String requestId,
    required String policyId,
    required String policyTitle,
    required String status,
    String? message,
    String? stateSummary,
    String? policySetSummary,
    String? humanChoiceSummary,
    String source = 'strategy_tab',
    String? actionType,
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final normalizedStatus = _normalizeExecutionStatus(status);
    final resolvedActionType = _actionTypeFromWireOrFallback(actionType);
    final mergedFeedback = <String, Object?>{
      'requestId': requestId,
      'policyId': policyId,
      'policyTitle': policyTitle,
      'executionStatus': normalizedStatus,
      if (message != null && message.trim().isNotEmpty)
        'executionMessage': message.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
      ...meta,
    };

    return recordAction(
      'execution_feedback',
      meta: <String, Object?>{
        'source': source,
        'actionType': resolvedActionType.wireName,
        'requestId': requestId,
        'targetPolicyId': policyId,
        'targetPolicyTitle': policyTitle,
        'executionStatus': normalizedStatus,
        if (message != null && message.trim().isNotEmpty)
          'executionMessage': message.trim(),
        'replayEntryLabel': '回放（高亮相邻记录）',
        'replayHint': '核对提交与执行回执记录',
        'replayViewLabel': '进入复盘视图',
        'execution_feedback': mergedFeedback,
        'stateSummary':
            stateSummary ??
            _buildExecutionStateSummary(
              policyTitle: policyTitle,
              status: normalizedStatus,
              message: message,
            ),
        'policySetSummary':
            policySetSummary ?? '执行反馈已关联到策略 $policyTitle，可直接进入回放',
        'humanChoiceSummary':
            humanChoiceSummary ??
            '执行链路状态：${normalizedStatus.toUpperCase()} · 可核对提交与执行回执记录',
      },
    );
  }

  void clear() {
    final next = AuditTimeline(
      latest: null,
      items: const <AuditEvent>[],
      maxKeep: state.maxKeep,
    );
    state = next;
    _persistCache(next);
  }

  void updateMaxKeep(int value) {
    final normalized = value < 1 ? 1 : value;
    final trimmed = state.items.length <= normalized
        ? state.items
        : state.items.sublist(0, normalized);

    final next = AuditTimeline(
      latest: trimmed.isEmpty ? null : trimmed.first,
      items: trimmed,
      maxKeep: normalized,
    );
    state = next;
    _persistCache(next);
  }

  Future<AuditTimeline?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final map = decoded.map((key, value) => MapEntry(key.toString(), value));
      final maxKeepRaw = map['maxKeep'];
      final itemsRaw = map['items'];

      if (itemsRaw is! List) return null;

      final items = itemsRaw
          .map(AuditEvent.fromJson)
          .whereType<AuditEvent>()
          .toList(growable: false);

      final maxKeep = maxKeepRaw is num ? maxKeepRaw.toInt() : kDefaultMaxKeep;

      return AuditTimeline(
        latest: items.isEmpty ? null : items.first,
        items: items.take(maxKeep).toList(growable: false),
        maxKeep: maxKeep,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistCache(AuditTimeline timeline) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, Object?>{
        'maxKeep': timeline.maxKeep,
        'items': timeline.items.map((e) => e.toJson()).toList(),
      };
      await prefs.setString(_cacheKey, jsonEncode(payload));
    } catch (_) {
      // cache failure should not break audit flow
    }
  }
}

bool isStrategyAuditEvent(AuditEvent event) {
  if (event.source == AuditEventSource.humanOverride) return true;
  if (event.source == AuditEventSource.executionFeedback) return true;
  if (event.meta['source'] == 'strategy_tab') return true;
  if (event.meta['human_choice'] is Map<String, Object?>) return true;
  if (event.meta['execution_feedback'] is Map<String, Object?>) return true;
  if (event.meta['executionStatus'] != null) return true;
  return false;
}

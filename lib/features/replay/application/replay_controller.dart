import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/domain/models.dart';
import 'package:dt_mobile_app/features/audit/application/audit_controller.dart';

@immutable
class ReplayPolicyItem {
  const ReplayPolicyItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.scoreHint,
    required this.isSelected,
  });

  final String id;
  final String title;
  final String summary;
  final int scoreHint;
  final bool isSelected;
}

@immutable
class ReplayHumanAction {
  const ReplayHumanAction({
    required this.actionTypeLabel,
    required this.summary,
    this.remark,
  });

  final String actionTypeLabel;
  final String summary;
  final String? remark;
}

@immutable
class ReplayAlertItem {
  const ReplayAlertItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.severityLabel,
    required this.time,
  });

  final String id;
  final String title;
  final String detail;
  final String severityLabel;
  final DateTime time;
}

@immutable
class ReplayFrame {
  const ReplayFrame({
    required this.frameId,
    required this.eventId,
    required this.time,
    required this.snapshot,
    required this.policies,
    this.humanAction,
    this.alerts = const <ReplayAlertItem>[],
  });

  final String frameId;
  final String eventId;
  final DateTime time;
  final SituationSnapshot snapshot;
  final List<ReplayPolicyItem> policies;
  final ReplayHumanAction? humanAction;
  final List<ReplayAlertItem> alerts;
}

enum ReplayHighlightMode { anchorOnly, interventionDiff }

@immutable
class ReplayEntryContext {
  const ReplayEntryContext({
    required this.eventId,
    required this.requestId,
    required this.sourcePage,
    required this.highlightMode,
    required this.title,
    required this.summary,
    required this.replayAnchor,
  });

  final String eventId;
  final String? requestId;
  final String sourcePage;
  final ReplayHighlightMode highlightMode;
  final String title;
  final String summary;
  final String replayAnchor;

  ReplayEntryContext copyWith({
    String? eventId,
    String? requestId,
    String? sourcePage,
    ReplayHighlightMode? highlightMode,
    String? title,
    String? summary,
    String? replayAnchor,
  }) {
    return ReplayEntryContext(
      eventId: eventId ?? this.eventId,
      requestId: requestId ?? this.requestId,
      sourcePage: sourcePage ?? this.sourcePage,
      highlightMode: highlightMode ?? this.highlightMode,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      replayAnchor: replayAnchor ?? this.replayAnchor,
    );
  }
}

@immutable
class ReplayTimeline {
  const ReplayTimeline({
    required this.anchorEventId,
    required this.frames,
    required this.selectedFrameIndex,
    this.entryContext,
  });

  final String anchorEventId;
  final List<ReplayFrame> frames;
  final int selectedFrameIndex;
  final ReplayEntryContext? entryContext;

  bool get isEmpty => frames.isEmpty;

  ReplayFrame? get selectedFrame {
    if (frames.isEmpty) return null;
    final safeIndex = selectedFrameIndex.clamp(0, frames.length - 1);
    return frames[safeIndex];
  }

  int get frameCount => frames.length;

  ReplayTimeline copyWith({
    String? anchorEventId,
    List<ReplayFrame>? frames,
    int? selectedFrameIndex,
    ReplayEntryContext? entryContext,
  }) {
    return ReplayTimeline(
      anchorEventId: anchorEventId ?? this.anchorEventId,
      frames: frames ?? this.frames,
      selectedFrameIndex: selectedFrameIndex ?? this.selectedFrameIndex,
      entryContext: entryContext ?? this.entryContext,
    );
  }
}

abstract class ReplayRepository {
  Future<ReplayTimeline> getTimeline(
    String anchorEventId, {
    ReplayEntryContext? entryContext,
  });
}

class LocalAuditReplayRepository implements ReplayRepository {
  const LocalAuditReplayRepository(this.ref);

  final Ref ref;

  @override
  Future<ReplayTimeline> getTimeline(
    String anchorEventId, {
    ReplayEntryContext? entryContext,
  }) async {
    final auditTimeline = ref.read(auditTimelineProvider);
    final items = auditTimeline.items;

    if (items.isEmpty) {
      return ReplayTimeline(
        anchorEventId: anchorEventId,
        frames: const <ReplayFrame>[],
        selectedFrameIndex: 0,
        entryContext: entryContext,
      );
    }

    final anchorIndex = _findAnchorIndex(items, anchorEventId);
    final anchorEvent = items[anchorIndex];
    final resolvedEntryContext =
        entryContext ?? _buildEntryContextFromEvent(anchorEvent);
    final frames = <ReplayFrame>[];

    final windowStart = (anchorIndex - 1).clamp(0, items.length - 1);
    final windowEnd = (anchorIndex + 1).clamp(0, items.length - 1);

    for (var i = windowStart; i <= windowEnd; i++) {
      final event = items[i];
      final frame = _buildFrameFromAuditEvent(
        event: event,
        entryContext: resolvedEntryContext,
      );
      if (frame != null) frames.add(frame);
    }

    final resolvedFrames = frames..sort((a, b) => a.time.compareTo(b.time));

    var selectedIndex = resolvedFrames.length - 1;
    for (var i = 0; i < resolvedFrames.length; i++) {
      if (resolvedFrames[i].eventId == anchorEventId) {
        selectedIndex = i;
        break;
      }
    }

    return ReplayTimeline(
      anchorEventId: anchorEventId,
      frames: resolvedFrames,
      selectedFrameIndex: selectedIndex,
      entryContext: resolvedEntryContext,
    );
  }

  int _findAnchorIndex(List<AuditEvent> items, String anchorEventId) {
    final index = items.indexWhere((event) => event.eventId == anchorEventId);
    if (index >= 0) return index;
    return 0;
  }

  ReplayFrame? _buildFrameFromAuditEvent({
    required AuditEvent event,
    required ReplayEntryContext entryContext,
  }) {
    final snapshot = _buildSnapshot(event, entryContext);
    if (snapshot == null) return null;
    final policies = _buildPolicies(event);
    final humanAction = _buildHumanAction(event);
    final alerts = _buildAlerts(event);

    return ReplayFrame(
      frameId: 'frame-${event.eventId}',
      eventId: event.eventId,
      time: event.at,
      snapshot: snapshot,
      policies: policies,
      humanAction: humanAction,
      alerts: alerts,
    );
  }

  SituationSnapshot? _buildSnapshot(
    AuditEvent event,
    ReplayEntryContext entryContext,
  ) {
    final candidate = event.meta['candidate_snapshot'];
    if (candidate is! Map) return null;
    final candidateMap = candidate.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final riskRaw = candidateMap['conflictRisk'];
    if (riskRaw is! Map) return null;
    final riskMap = riskRaw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final lowRaw = riskMap['low'];
    final highRaw = riskMap['high'];
    if (lowRaw is! num || highRaw is! num) return null;
    final low = lowRaw.round().clamp(0, 100);
    final high = highRaw.round().clamp(low, 100);
    final risk = RiskInterval(low: low, high: high);
    final congestion = _readMetricPoint(candidateMap, 'congestionIndex');
    final safetyMargin = _readMetricPoint(candidateMap, 'safetyMargin');
    final executionStatus = _readExecutionStatus(event.meta);
    final stability = risk.high >= 80
        ? SituationStabilityLevel.critical
        : risk.high >= 60
        ? SituationStabilityLevel.watch
        : SituationStabilityLevel.stable;
    final systemScore = safetyMargin ?? 0;
    final strategyPressure = congestion ?? 0;
    final constraintHeadroom = safetyMargin ?? 0;
    final stateText = _buildSnapshotSummary(
      event: event,
      entryContext: entryContext,
      risk: risk,
      executionStatus: executionStatus,
    );

    return SituationSnapshot(
      stabilityLevel: stability,
      systemScore: systemScore,
      strategyPressure: strategyPressure,
      constraintHeadroom: constraintHeadroom,
      riskInterval: risk,
      trendProjection: SituationTrendProjection(
        points: <double>[risk.high.toDouble()],
      ),
      summaryText: stateText,
      refreshAt: event.at,
    );
  }

  String _buildSnapshotSummary({
    required AuditEvent event,
    required ReplayEntryContext entryContext,
    required RiskInterval risk,
    required String? executionStatus,
  }) {
    final rawState = event.stateSummary.trim();
    if (rawState.isNotEmpty) {
      return rawState;
    }

    final targetTitle =
        _readTargetPolicyTitle(event.meta) ?? entryContext.title;
    final humanLabel =
        _readHumanChoiceLabel(event.meta) ?? _readActionLabel(event);
    final executionLabel = _executionStatusLabel(executionStatus);

    if (executionStatus != null) {
      return '$targetTitle 已进入$executionLabel，记录的测试冲突风险为 ${risk.displayText}；请继续核对提交与回执证据。';
    }

    return '当前围绕“$humanLabel”回看审计记录，焦点策略为 $targetTitle，测试冲突风险 ${risk.displayText}。';
  }

  int? _readMetricPoint(Map<String, Object?> snapshot, String field) {
    final raw = snapshot[field];
    if (raw is! Map) return null;
    final high = raw['high'];
    if (high is! num) return null;
    return high.round().clamp(0, 100);
  }

  List<ReplayPolicyItem> _buildPolicies(AuditEvent event) {
    final targetTitle =
        _readTargetPolicyTitle(event.meta) ??
        '策略候选 · ${_readActionLabel(event)}';
    final policySummary = event.policySetSummary.trim().isNotEmpty
        ? event.policySetSummary.trim()
        : '当前关键帧缺少结构化策略集，先保留为单条候选策略摘要，便于继续追问。';

    return <ReplayPolicyItem>[
      ReplayPolicyItem(
        id: 'policy-${event.eventId}',
        title: targetTitle,
        summary: policySummary,
        scoreHint: _inferPolicyScoreHint(event),
        isSelected: true,
      ),
    ];
  }

  ReplayHumanAction? _buildHumanAction(AuditEvent event) {
    final label = _readHumanChoiceLabel(event.meta) ?? _readActionLabel(event);
    final remark = _readHumanRemark(event.meta);
    final humanSummary = event.humanChoiceSummary.trim();

    if (humanSummary.isEmpty && remark == null && label.isEmpty) {
      return null;
    }

    return ReplayHumanAction(
      actionTypeLabel: label,
      summary: humanSummary.isNotEmpty
          ? humanSummary
          : '该关键帧记录了人工表态，当前可继续对照前后风险变化与执行反馈。',
      remark: remark,
    );
  }

  List<ReplayAlertItem> _buildAlerts(AuditEvent event) {
    final alerts = <ReplayAlertItem>[];
    final candidate = event.meta['candidate_snapshot'];
    final related = candidate is Map ? candidate['relatedAlerts'] : null;
    if (related is List) {
      for (final raw in related) {
        if (raw is! Map) continue;
        final map = raw.map((key, value) => MapEntry(key.toString(), value));
        alerts.add(
          ReplayAlertItem(
            id:
                map['id']?.toString() ??
                'related-${event.eventId}-${alerts.length}',
            title: map['title']?.toString() ?? '关联告警',
            detail: map['summary']?.toString() ?? '',
            severityLabel: map['severity']?.toString().toUpperCase() ?? 'INFO',
            time: event.at,
          ),
        );
      }
    }

    return alerts;
  }

  ReplayEntryContext _buildEntryContextFromEvent(AuditEvent event) {
    final executionStatus = _readExecutionStatus(event.meta);
    final title = _readTargetPolicyTitle(event.meta) ?? '审计事件 ${event.eventId}';
    final humanLabel =
        _readHumanChoiceLabel(event.meta) ?? _readActionLabel(event);
    final summary = event.humanChoiceSummary.trim().isNotEmpty
        ? '这次回放围绕“${event.humanChoiceSummary.trim()}”展开，重点核对相邻审计记录；不作干预因果归因。'
        : '这次回放围绕“$humanLabel”展开，重点核对相邻审计记录；不作干预因果归因。';

    return ReplayEntryContext(
      eventId: event.eventId,
      requestId: _readRequestId(event.meta),
      sourcePage: 'audit',
      highlightMode: executionStatus == null
          ? ReplayHighlightMode.anchorOnly
          : ReplayHighlightMode.interventionDiff,
      title: title,
      summary: summary,
      replayAnchor: event.eventId,
    );
  }

  int _inferPolicyScoreHint(AuditEvent event) {
    final candidate = event.meta['candidate_snapshot'];
    final conflict = candidate is Map ? candidate['conflictRisk'] : null;
    final high = conflict is Map ? conflict['high'] : null;
    return high is num ? (100 - high.round()).clamp(0, 100) : 0;
  }

  String? _readExecutionStatus(Map<String, Object?> meta) {
    final direct = meta['executionStatus'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }

    final feedback = meta['execution_feedback'];
    if (feedback is Map<String, Object?>) {
      final nested = feedback['executionStatus'];
      if (nested is String && nested.trim().isNotEmpty) {
        return nested.trim();
      }
    }

    return null;
  }

  String? _readTargetPolicyTitle(Map<String, Object?> meta) {
    final directTitle = meta['targetPolicyTitle'];
    if (directTitle is String && directTitle.trim().isNotEmpty) {
      return directTitle.trim();
    }

    final humanChoice = meta['human_choice'];
    if (humanChoice is Map<String, Object?>) {
      final nestedTitle = humanChoice['target_policy_title'];
      if (nestedTitle is String && nestedTitle.trim().isNotEmpty) {
        return nestedTitle.trim();
      }
    }

    return null;
  }

  String? _readHumanChoiceLabel(Map<String, Object?> meta) {
    final humanChoice = meta['human_choice'];
    if (humanChoice is Map<String, Object?>) {
      final label = humanChoice['label'];
      if (label is String && label.trim().isNotEmpty) {
        return label.trim();
      }
    }
    return null;
  }

  String? _readHumanRemark(Map<String, Object?> meta) {
    final humanChoice = meta['human_choice'];
    if (humanChoice is Map<String, Object?>) {
      final remark = humanChoice['remark'];
      if (remark is String && remark.trim().isNotEmpty) {
        return remark.trim();
      }
    }
    return null;
  }

  String? _readRequestId(Map<String, Object?> meta) {
    final direct = meta['requestId'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }

    final replay = meta['replay'];
    if (replay is Map<String, Object?>) {
      final nested = replay['requestId'];
      if (nested is String && nested.trim().isNotEmpty) {
        return nested.trim();
      }
    }

    return null;
  }

  String _readActionLabel(AuditEvent event) {
    switch (event.actionType) {
      case AuditActionType.override:
        return '人工接管';
      case AuditActionType.guidance:
        return '人工引导';
      case AuditActionType.veto:
        return '人工否决';
    }
  }

  String _executionStatusLabel(String? status) {
    switch (status) {
      case 'dry_run_recorded':
        return '仅记录干跑';
      case 'acked':
        return '已确认';
      case 'executing':
        return '执行中';
      case 'submitted':
        return '已提交';
      case 'failed':
        return '失败待处理';
      default:
        return '处理中';
    }
  }
}

final replayRepositoryProvider = Provider<ReplayRepository>((ref) {
  return LocalAuditReplayRepository(ref);
});

@immutable
class ReplayRouteSelection {
  const ReplayRouteSelection({
    required this.anchorEventId,
    required this.selectedFrameIndex,
    this.entryContext,
  });

  final String? anchorEventId;
  final int selectedFrameIndex;
  final ReplayEntryContext? entryContext;

  ReplayRouteSelection copyWith({
    String? anchorEventId,
    int? selectedFrameIndex,
    ReplayEntryContext? entryContext,
  }) {
    return ReplayRouteSelection(
      anchorEventId: anchorEventId ?? this.anchorEventId,
      selectedFrameIndex: selectedFrameIndex ?? this.selectedFrameIndex,
      entryContext: entryContext ?? this.entryContext,
    );
  }
}

final replayRouteSelectionProvider =
    NotifierProvider<ReplayRouteSelectionNotifier, ReplayRouteSelection>(
      ReplayRouteSelectionNotifier.new,
    );

class ReplayRouteSelectionNotifier extends Notifier<ReplayRouteSelection> {
  @override
  ReplayRouteSelection build() {
    return const ReplayRouteSelection(
      anchorEventId: null,
      selectedFrameIndex: 0,
    );
  }

  void selectAnchor(String eventId) {
    state = ReplayRouteSelection(
      anchorEventId: eventId,
      selectedFrameIndex: 0,
      entryContext: state.entryContext,
    );
  }

  void selectEntry(ReplayEntryContext entry) {
    state = ReplayRouteSelection(
      anchorEventId: entry.replayAnchor,
      selectedFrameIndex: 0,
      entryContext: entry,
    );
  }

  void selectFrameIndex(int index) {
    state = state.copyWith(selectedFrameIndex: index);
  }

  void clear() {
    state = const ReplayRouteSelection(
      anchorEventId: null,
      selectedFrameIndex: 0,
    );
  }
}

final replayTimelineProvider =
    AsyncNotifierProvider<ReplayTimelineNotifier, ReplayTimeline?>(
      ReplayTimelineNotifier.new,
    );

class ReplayTimelineNotifier extends AsyncNotifier<ReplayTimeline?> {
  @override
  Future<ReplayTimeline?> build() async {
    final routeSelection = ref.watch(replayRouteSelectionProvider);
    final anchorEventId = routeSelection.anchorEventId;

    if (anchorEventId == null || anchorEventId.trim().isEmpty) {
      return null;
    }

    final repository = ref.read(replayRepositoryProvider);
    final timeline = await repository.getTimeline(
      anchorEventId,
      entryContext: routeSelection.entryContext,
    );

    final selectedIndex = _safeIndex(
      routeSelection.selectedFrameIndex,
      timeline.frameCount,
    );

    if (selectedIndex == timeline.selectedFrameIndex) {
      return timeline;
    }

    return timeline.copyWith(selectedFrameIndex: selectedIndex);
  }

  Future<void> load(String anchorEventId) async {
    ref.read(replayRouteSelectionProvider.notifier).selectAnchor(anchorEventId);
    state = const AsyncLoading<ReplayTimeline?>();

    state = await AsyncValue.guard<ReplayTimeline?>(() async {
      final repository = ref.read(replayRepositoryProvider);
      return repository.getTimeline(anchorEventId);
    });
  }

  Future<void> loadEntry(ReplayEntryContext entry) async {
    ref.read(replayRouteSelectionProvider.notifier).selectEntry(entry);
    state = const AsyncLoading<ReplayTimeline?>();

    state = await AsyncValue.guard<ReplayTimeline?>(() async {
      final repository = ref.read(replayRepositoryProvider);
      return repository.getTimeline(entry.replayAnchor, entryContext: entry);
    });
  }

  Future<void> selectFrame(int index) async {
    final current = _readTimelineFromAsync(state);
    if (current == null || current.frames.isEmpty) return;

    final safeIndex = _safeIndex(index, current.frameCount);
    ref.read(replayRouteSelectionProvider.notifier).selectFrameIndex(safeIndex);

    state = AsyncData<ReplayTimeline?>(
      current.copyWith(selectedFrameIndex: safeIndex),
    );
  }

  Future<void> refreshCurrent() async {
    final routeSelection = ref.read(replayRouteSelectionProvider);
    final anchorEventId = routeSelection.anchorEventId;
    if (anchorEventId == null || anchorEventId.trim().isEmpty) {
      state = const AsyncData<ReplayTimeline?>(null);
      return;
    }

    state = const AsyncLoading<ReplayTimeline?>();

    state = await AsyncValue.guard<ReplayTimeline?>(() async {
      final repository = ref.read(replayRepositoryProvider);
      final timeline = await repository.getTimeline(
        anchorEventId,
        entryContext: routeSelection.entryContext,
      );
      final selectedIndex = _safeIndex(
        routeSelection.selectedFrameIndex,
        timeline.frameCount,
      );
      return timeline.copyWith(selectedFrameIndex: selectedIndex);
    });
  }

  void clearSelection() {
    ref.read(replayRouteSelectionProvider.notifier).clear();
    state = const AsyncData<ReplayTimeline?>(null);
  }

  int _safeIndex(int index, int frameCount) {
    if (frameCount <= 0) return 0;
    if (index < 0) return 0;
    if (index >= frameCount) return frameCount - 1;
    return index;
  }
}

final replayDetailProvider = Provider<ReplayFrame?>((ref) {
  final asyncTimeline = ref.watch(replayTimelineProvider);
  final timeline = _readTimelineFromAsync(asyncTimeline);
  return timeline?.selectedFrame;
});

ReplayTimeline? _readTimelineFromAsync(AsyncValue<ReplayTimeline?> asyncValue) {
  return asyncValue.when(
    data: (value) => value,
    loading: () => null,
    error: (error, stackTrace) => null,
  );
}

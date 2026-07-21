import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/features/alerts/application/alerts_controller.dart';

enum InAppNotificationSource { alerts, strategyExecution, situation, system }

enum InAppNotificationSeverity { info, warn, critical }

class InAppNotificationItem {
  const InAppNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.source,
    required this.severity,
    required this.createdAt,
    required this.isRead,
    this.relatedEntityId,
    this.meta = const <String, Object?>{},
  });

  final String id;
  final String title;
  final String body;
  final InAppNotificationSource source;
  final InAppNotificationSeverity severity;
  final DateTime createdAt;
  final bool isRead;
  final String? relatedEntityId;
  final Map<String, Object?> meta;

  InAppNotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    InAppNotificationSource? source,
    InAppNotificationSeverity? severity,
    DateTime? createdAt,
    bool? isRead,
    String? relatedEntityId,
    Map<String, Object?>? meta,
  }) {
    return InAppNotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      source: source ?? this.source,
      severity: severity ?? this.severity,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      relatedEntityId: relatedEntityId ?? this.relatedEntityId,
      meta: meta ?? this.meta,
    );
  }
}

class NotificationCenterState {
  const NotificationCenterState({
    required this.items,
    required this.unreadCount,
    required this.lastUpdatedAt,
  });

  final List<InAppNotificationItem> items;
  final int unreadCount;
  final DateTime? lastUpdatedAt;

  NotificationCenterState copyWith({
    List<InAppNotificationItem>? items,
    int? unreadCount,
    DateTime? lastUpdatedAt,
  }) {
    return NotificationCenterState(
      items: items ?? this.items,
      unreadCount: unreadCount ?? this.unreadCount,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }

  static const empty = NotificationCenterState(
    items: <InAppNotificationItem>[],
    unreadCount: 0,
    lastUpdatedAt: null,
  );
}

class NotificationPerfStats {
  const NotificationPerfStats({
    required this.receivedNotificationsLastSecond,
    required this.receivedNotificationsLastMinute,
    required this.lastFlushNotificationCount,
    required this.totalFlushCount,
    required this.lastEventAt,
    required this.lastFlushAt,
    required this.throttleWindowMs,
  });

  final int receivedNotificationsLastSecond;
  final int receivedNotificationsLastMinute;
  final int lastFlushNotificationCount;
  final int totalFlushCount;
  final DateTime? lastEventAt;
  final DateTime? lastFlushAt;
  final int throttleWindowMs;

  NotificationPerfStats copyWith({
    int? receivedNotificationsLastSecond,
    int? receivedNotificationsLastMinute,
    int? lastFlushNotificationCount,
    int? totalFlushCount,
    DateTime? lastEventAt,
    DateTime? lastFlushAt,
    int? throttleWindowMs,
  }) {
    return NotificationPerfStats(
      receivedNotificationsLastSecond:
          receivedNotificationsLastSecond ??
          this.receivedNotificationsLastSecond,
      receivedNotificationsLastMinute:
          receivedNotificationsLastMinute ??
          this.receivedNotificationsLastMinute,
      lastFlushNotificationCount:
          lastFlushNotificationCount ?? this.lastFlushNotificationCount,
      totalFlushCount: totalFlushCount ?? this.totalFlushCount,
      lastEventAt: lastEventAt ?? this.lastEventAt,
      lastFlushAt: lastFlushAt ?? this.lastFlushAt,
      throttleWindowMs: throttleWindowMs ?? this.throttleWindowMs,
    );
  }

  static const empty = NotificationPerfStats(
    receivedNotificationsLastSecond: 0,
    receivedNotificationsLastMinute: 0,
    lastFlushNotificationCount: 0,
    totalFlushCount: 0,
    lastEventAt: null,
    lastFlushAt: null,
    throttleWindowMs: kNotificationBatchWindowMs,
  );
}

const int kMaxNotificationItems = 200;
const int kNotificationBatchWindowMs = 1000;

final notificationCenterProvider =
    NotifierProvider<NotificationCenterNotifier, NotificationCenterState>(
      NotificationCenterNotifier.new,
    );

final unreadNotificationsCountProvider = Provider<int>((ref) {
  return ref.watch(notificationCenterProvider).unreadCount;
});

final notificationPerfStatsProvider = Provider<NotificationPerfStats>((ref) {
  return ref.watch(notificationCenterProvider.notifier).perfStats;
});

class NotificationCenterNotifier extends Notifier<NotificationCenterState> {
  StreamSubscription<AlertsFeedEvent>? _alertsSubscription;
  Timer? _flushTimer;

  final Set<String> _alertDerivedIds = <String>{};
  final List<InAppNotificationItem> _pendingItems = <InAppNotificationItem>[];
  final List<DateTime> _receivedNotificationMarks = <DateTime>[];

  NotificationPerfStats _perfStats = NotificationPerfStats.empty;
  int _localSeq = 0;

  NotificationPerfStats get perfStats => _perfStats;

  @override
  NotificationCenterState build() {
    ref.onDispose(() {
      _flushTimer?.cancel();
      _alertsSubscription?.cancel();
    });

    _bindAlertsFeed();
    return NotificationCenterState.empty;
  }

  void _bindAlertsFeed() {
    _alertsSubscription?.cancel();

    final service = ref.read(alertsFeedServiceProvider);
    _alertsSubscription = service.watchEvents().listen(
      _onAlertsFeedEvent,
      onError: (Object error, StackTrace stackTrace) {
        // 通知中心不因为告警流报错而崩掉。
        // 当前阶段保留已有通知，静默容错即可。
      },
    );
  }

  void _onAlertsFeedEvent(AlertsFeedEvent event) {
    if (!event.hasAlert) return;

    final alert = event.item!;
    final derivedId = 'alert:${alert.id}';
    if (_alertDerivedIds.contains(derivedId)) return;

    _alertDerivedIds.add(derivedId);

    final item = InAppNotificationItem(
      id: derivedId,
      title: _buildAlertNotificationTitle(alert),
      body: alert.detail,
      source: InAppNotificationSource.alerts,
      severity: _mapAlertSeverity(alert.severity),
      createdAt: alert.createdAt,
      isRead: false,
      relatedEntityId: alert.id,
      meta: <String, Object?>{
        'alertId': alert.id,
        'alertTitle': alert.title,
        'alertSource': alert.source,
        'alertSeverity': alert.severity.name,
        'createdAt': alert.createdAt.toIso8601String(),
      },
    );

    _enqueue(item);
  }

  Future<void> pushStrategyExecutionReceipt({
    required String policyId,
    required String status,
    required String title,
    String? body,
    Map<String, Object?> meta = const <String, Object?>{},
  }) async {
    final item = InAppNotificationItem(
      id: 'strategy:$policyId:$status:${_nextSeq()}',
      title: title,
      body: body ?? '策略执行状态已更新：$status',
      source: InAppNotificationSource.strategyExecution,
      severity: _strategyStatusSeverity(status),
      createdAt: DateTime.now(),
      isRead: false,
      relatedEntityId: policyId,
      meta: <String, Object?>{'policyId': policyId, 'status': status, ...meta},
    );

    _enqueue(item);
  }

  Future<void> pushSituationChange({
    required String situationId,
    required String title,
    required String body,
    InAppNotificationSeverity severity = InAppNotificationSeverity.info,
    Map<String, Object?> meta = const <String, Object?>{},
  }) async {
    final item = InAppNotificationItem(
      id: 'situation:$situationId:${_nextSeq()}',
      title: title,
      body: body,
      source: InAppNotificationSource.situation,
      severity: severity,
      createdAt: DateTime.now(),
      isRead: false,
      relatedEntityId: situationId,
      meta: <String, Object?>{'situationId': situationId, ...meta},
    );

    _enqueue(item);
  }

  Future<void> pushSystemNotice({
    required String title,
    required String body,
    InAppNotificationSeverity severity = InAppNotificationSeverity.info,
    Map<String, Object?> meta = const <String, Object?>{},
  }) async {
    final item = InAppNotificationItem(
      id: 'system:${_nextSeq()}',
      title: title,
      body: body,
      source: InAppNotificationSource.system,
      severity: severity,
      createdAt: DateTime.now(),
      isRead: false,
      meta: meta,
    );

    _enqueue(item);
  }

  void markRead(String id) {
    final nextItems = state.items
        .map((item) => item.id == id ? item.copyWith(isRead: true) : item)
        .toList(growable: false);

    state = state.copyWith(
      items: nextItems,
      unreadCount: nextItems.where((item) => !item.isRead).length,
      lastUpdatedAt: state.lastUpdatedAt,
    );
  }

  void markAllRead() {
    final nextItems = state.items
        .map((item) => item.isRead ? item : item.copyWith(isRead: true))
        .toList(growable: false);

    state = state.copyWith(
      items: nextItems,
      unreadCount: 0,
      lastUpdatedAt: state.lastUpdatedAt,
    );
  }

  void clear() {
    _pendingItems.clear();
    _receivedNotificationMarks.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    _perfStats = NotificationPerfStats.empty;
    state = NotificationCenterState.empty;
    _alertDerivedIds.clear();
  }

  void _enqueue(InAppNotificationItem item) {
    _pendingItems.removeWhere((e) => e.id == item.id);
    _pendingItems.add(item);

    final now = DateTime.now();
    _receivedNotificationMarks.add(now);
    _prunePerfMarks(now);

    _flushTimer ??= Timer(
      const Duration(milliseconds: kNotificationBatchWindowMs),
      _flushPendingItems,
    );
  }

  void _flushPendingItems() {
    _flushTimer?.cancel();
    _flushTimer = null;

    if (_pendingItems.isEmpty) return;

    final List<InAppNotificationItem> incoming = _pendingItems.reversed.toList(
      growable: false,
    );
    _pendingItems.clear();

    final Set<String> incomingIds = incoming.map((e) => e.id).toSet();
    final List<InAppNotificationItem> dedupedExisting = state.items
        .where((e) => !incomingIds.contains(e.id))
        .toList(growable: false);

    final List<InAppNotificationItem> nextItems = <InAppNotificationItem>[
      ...incoming,
      ...dedupedExisting,
    ].take(kMaxNotificationItems).toList(growable: false);

    final now = DateTime.now();
    _prunePerfMarks(now);

    _perfStats = _perfStats.copyWith(
      receivedNotificationsLastSecond: _countWithinWindow(
        _receivedNotificationMarks,
        now,
        const Duration(seconds: 1),
      ),
      receivedNotificationsLastMinute: _receivedNotificationMarks.length,
      lastFlushNotificationCount: incoming.length,
      totalFlushCount: _perfStats.totalFlushCount + 1,
      lastEventAt: incoming.first.createdAt,
      lastFlushAt: now,
      throttleWindowMs: kNotificationBatchWindowMs,
    );

    state = state.copyWith(
      items: nextItems,
      unreadCount: nextItems.where((e) => !e.isRead).length,
      lastUpdatedAt: incoming.first.createdAt,
    );
  }

  void _prunePerfMarks(DateTime now) {
    final cutoff = now.subtract(const Duration(minutes: 1));
    _receivedNotificationMarks.removeWhere((t) => t.isBefore(cutoff));
  }

  int _countWithinWindow(List<DateTime> marks, DateTime now, Duration window) {
    final cutoff = now.subtract(window);
    return marks.where((t) => !t.isBefore(cutoff)).length;
  }

  String _buildAlertNotificationTitle(AlertItem alert) {
    switch (alert.severity) {
      case AlertSeverity.critical:
        return '紧急告警：${alert.title}';
      case AlertSeverity.warn:
        return '风险提醒：${alert.title}';
      case AlertSeverity.info:
        return '状态更新：${alert.title}';
    }
  }

  InAppNotificationSeverity _mapAlertSeverity(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.info:
        return InAppNotificationSeverity.info;
      case AlertSeverity.warn:
        return InAppNotificationSeverity.warn;
      case AlertSeverity.critical:
        return InAppNotificationSeverity.critical;
    }
  }

  InAppNotificationSeverity _strategyStatusSeverity(String status) {
    switch (status.trim().toLowerCase()) {
      case 'failed':
      case 'error':
      case 'rejected':
        return InAppNotificationSeverity.critical;
      case 'submitted':
      case 'executing':
      case 'pending':
        return InAppNotificationSeverity.warn;
      case 'acked':
      case 'success':
      case 'completed':
        return InAppNotificationSeverity.info;
      default:
        return InAppNotificationSeverity.info;
    }
  }

  int _nextSeq() {
    _localSeq += 1;
    return _localSeq;
  }
}

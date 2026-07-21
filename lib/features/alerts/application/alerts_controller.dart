import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:dt_mobile_app/core/config/app_config.dart';
import 'package:dt_mobile_app/core/network/dio_provider.dart';
import 'package:dt_mobile_app/features/audit/application/audit_controller.dart';

enum AlertSeverity { info, warn, critical }

enum ReplanTriggerStatus { idle, submitting, success, failure }

enum AlertsConnectionStatus { connecting, connected, disconnected }

enum AlertsFeedMode { websocket, offline }

class AlertItem {
  const AlertItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.severity,
    required this.createdAt,
    required this.source,
    required this.isAcknowledged,
  });

  final String id;
  final String title;
  final String detail;
  final AlertSeverity severity;
  final DateTime createdAt;
  final String source;
  final bool isAcknowledged;

  AlertItem copyWith({
    String? id,
    String? title,
    String? detail,
    AlertSeverity? severity,
    DateTime? createdAt,
    String? source,
    bool? isAcknowledged,
  }) {
    return AlertItem(
      id: id ?? this.id,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      severity: severity ?? this.severity,
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
      isAcknowledged: isAcknowledged ?? this.isAcknowledged,
    );
  }
}

class AlertsPerfStats {
  const AlertsPerfStats({
    required this.receivedAlertsLastSecond,
    required this.receivedAlertsLastMinute,
    required this.receivedEventsLastSecond,
    required this.receivedEventsLastMinute,
    required this.lastFlushAlertCount,
    required this.totalFlushCount,
    required this.lastEventAt,
    required this.lastFlushAt,
    required this.throttleWindowMs,
  });

  final int receivedAlertsLastSecond;
  final int receivedAlertsLastMinute;
  final int receivedEventsLastSecond;
  final int receivedEventsLastMinute;
  final int lastFlushAlertCount;
  final int totalFlushCount;
  final DateTime? lastEventAt;
  final DateTime? lastFlushAt;
  final int throttleWindowMs;

  AlertsPerfStats copyWith({
    int? receivedAlertsLastSecond,
    int? receivedAlertsLastMinute,
    int? receivedEventsLastSecond,
    int? receivedEventsLastMinute,
    int? lastFlushAlertCount,
    int? totalFlushCount,
    DateTime? lastEventAt,
    DateTime? lastFlushAt,
    int? throttleWindowMs,
  }) {
    return AlertsPerfStats(
      receivedAlertsLastSecond:
          receivedAlertsLastSecond ?? this.receivedAlertsLastSecond,
      receivedAlertsLastMinute:
          receivedAlertsLastMinute ?? this.receivedAlertsLastMinute,
      receivedEventsLastSecond:
          receivedEventsLastSecond ?? this.receivedEventsLastSecond,
      receivedEventsLastMinute:
          receivedEventsLastMinute ?? this.receivedEventsLastMinute,
      lastFlushAlertCount: lastFlushAlertCount ?? this.lastFlushAlertCount,
      totalFlushCount: totalFlushCount ?? this.totalFlushCount,
      lastEventAt: lastEventAt ?? this.lastEventAt,
      lastFlushAt: lastFlushAt ?? this.lastFlushAt,
      throttleWindowMs: throttleWindowMs ?? this.throttleWindowMs,
    );
  }

  static const empty = AlertsPerfStats(
    receivedAlertsLastSecond: 0,
    receivedAlertsLastMinute: 0,
    receivedEventsLastSecond: 0,
    receivedEventsLastMinute: 0,
    lastFlushAlertCount: 0,
    totalFlushCount: 0,
    lastEventAt: null,
    lastFlushAt: null,
    throttleWindowMs: kAlertsBatchWindowMs,
  );
}

class AlertsSnapshot {
  const AlertsSnapshot({
    required this.items,
    required this.unreadCount,
    required this.lastUpdatedAt,
    required this.isLive,
    required this.connectionStatus,
    required this.feedMode,
    required this.statusMessage,
    required this.reconnectAttempt,
    required this.perfStats,
  });

  final List<AlertItem> items;
  final int unreadCount;
  final DateTime? lastUpdatedAt;
  final bool isLive;
  final AlertsConnectionStatus connectionStatus;
  final AlertsFeedMode feedMode;
  final String statusMessage;
  final int reconnectAttempt;
  final AlertsPerfStats perfStats;

  AlertsSnapshot copyWith({
    List<AlertItem>? items,
    int? unreadCount,
    DateTime? lastUpdatedAt,
    bool? isLive,
    AlertsConnectionStatus? connectionStatus,
    AlertsFeedMode? feedMode,
    String? statusMessage,
    int? reconnectAttempt,
    AlertsPerfStats? perfStats,
  }) {
    return AlertsSnapshot(
      items: items ?? this.items,
      unreadCount: unreadCount ?? this.unreadCount,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      isLive: isLive ?? this.isLive,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      feedMode: feedMode ?? this.feedMode,
      statusMessage: statusMessage ?? this.statusMessage,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      perfStats: perfStats ?? this.perfStats,
    );
  }

  static const empty = AlertsSnapshot(
    items: <AlertItem>[],
    unreadCount: 0,
    lastUpdatedAt: null,
    isLive: false,
    connectionStatus: AlertsConnectionStatus.connecting,
    feedMode: AlertsFeedMode.offline,
    statusMessage: '正在建立连接…',
    reconnectAttempt: 0,
    perfStats: AlertsPerfStats.empty,
  );
}

class ReplanTriggerState {
  const ReplanTriggerState({
    required this.status,
    required this.message,
    required this.lastTriggerAt,
    this.lastSourceAlertId,
  });

  final ReplanTriggerStatus status;
  final String? message;
  final DateTime? lastTriggerAt;
  final String? lastSourceAlertId;

  const ReplanTriggerState.idle()
    : status = ReplanTriggerStatus.idle,
      message = null,
      lastTriggerAt = null,
      lastSourceAlertId = null;
}

class AlertsFeedEvent {
  const AlertsFeedEvent._({
    this.item,
    required this.connectionStatus,
    required this.feedMode,
    required this.statusMessage,
    required this.reconnectAttempt,
    required this.isBootstrap,
  });

  final AlertItem? item;
  final AlertsConnectionStatus connectionStatus;
  final AlertsFeedMode feedMode;
  final String statusMessage;
  final int reconnectAttempt;
  final bool isBootstrap;

  bool get hasAlert => item != null;

  factory AlertsFeedEvent.status({
    required AlertsConnectionStatus connectionStatus,
    required AlertsFeedMode feedMode,
    required String statusMessage,
    required int reconnectAttempt,
  }) {
    return AlertsFeedEvent._(
      item: null,
      connectionStatus: connectionStatus,
      feedMode: feedMode,
      statusMessage: statusMessage,
      reconnectAttempt: reconnectAttempt,
      isBootstrap: false,
    );
  }

  factory AlertsFeedEvent.alert({
    required AlertItem item,
    required AlertsConnectionStatus connectionStatus,
    required AlertsFeedMode feedMode,
    required String statusMessage,
    required int reconnectAttempt,
    bool isBootstrap = false,
  }) {
    return AlertsFeedEvent._(
      item: item,
      connectionStatus: connectionStatus,
      feedMode: feedMode,
      statusMessage: statusMessage,
      reconnectAttempt: reconnectAttempt,
      isBootstrap: isBootstrap,
    );
  }
}

abstract class AlertsFeedService {
  Stream<AlertsFeedEvent> watchEvents();
  Future<void> reconnect();
  void failNextReconnectOnce();
  void dispose();
}

final alertsFeedServiceProvider = Provider<AlertsFeedService>((ref) {
  final dio = ref.read(dioProvider);
  final service = AdaptiveAlertsFeedService(dio: dio);
  ref.onDispose(service.dispose);
  return service;
});

class AdaptiveAlertsFeedService implements AlertsFeedService {
  AdaptiveAlertsFeedService({required Dio dio}) : _dio = dio {
    _controller = StreamController<AlertsFeedEvent>.broadcast(
      onListen: _ensureStarted,
      onCancel: _maybeStop,
    );
  }

  static const String _defaultWsPath = '/ws/alerts';
  static const String _bootstrapUrl = String.fromEnvironment(
    'ALERTS_BOOTSTRAP_URL',
    defaultValue: '/api/alerts',
  );
  static const String _wsUrl = String.fromEnvironment(
    'ALERTS_WS_URL',
    defaultValue: '',
  );

  final Dio _dio;
  late final StreamController<AlertsFeedEvent> _controller;

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;

  bool _started = false;
  bool _offline = true;
  bool _failNextReconnect = false;
  bool _bootstrapLoaded = false;

  int _seq = 0;
  int _reconnectAttempt = 0;

  @override
  Stream<AlertsFeedEvent> watchEvents() => _controller.stream;

  @override
  Future<void> reconnect() async {
    if (_failNextReconnect) {
      _failNextReconnect = false;
      throw StateError('alerts_reconnect_failed');
    }

    _cancelReconnectTimer();
    await _closeSocket();

    _emitStatus(
      connectionStatus: AlertsConnectionStatus.connecting,
      feedMode: _offline ? AlertsFeedMode.offline : AlertsFeedMode.websocket,
      statusMessage: '手动刷新：正在重新建立告警连接…',
    );

    await _tryBootstrapIfNeeded(forceRefresh: true);
    await _connectWebSocket(forceRestart: true);
  }

  @override
  void failNextReconnectOnce() {
    _failNextReconnect = true;
  }

  void _ensureStarted() {
    if (_started) return;
    _started = true;
    unawaited(_startFlow());
  }

  Future<void> _startFlow() async {
    await _tryBootstrapIfNeeded();
    await _connectWebSocket();
  }

  void _maybeStop() {
    if (_controller.hasListener) return;

    _started = false;
    _cancelReconnectTimer();
    unawaited(_closeSocket());
  }

  Future<void> _tryBootstrapIfNeeded({bool forceRefresh = false}) async {
    if (_bootstrapUrl.trim().isEmpty) return;
    if (_bootstrapLoaded && !forceRefresh) return;

    _emitStatus(
      connectionStatus: AlertsConnectionStatus.connecting,
      feedMode: AlertsFeedMode.websocket,
      statusMessage: '正在拉取初始告警快照…',
    );

    try {
      final items = await _fetchBootstrapAlerts(_bootstrapUrl.trim());

      if (items.isEmpty) {
        _bootstrapLoaded = true;
        _emitStatus(
          connectionStatus: AlertsConnectionStatus.connecting,
          feedMode: AlertsFeedMode.websocket,
          statusMessage: '初始快照为空，继续建立实时连接…',
        );
        return;
      }

      _bootstrapLoaded = true;

      for (final item in items) {
        _controller.add(
          AlertsFeedEvent.alert(
            item: item,
            connectionStatus: AlertsConnectionStatus.connecting,
            feedMode: AlertsFeedMode.websocket,
            statusMessage: '已加载初始告警快照，正在接入实时流…',
            reconnectAttempt: _reconnectAttempt,
            isBootstrap: true,
          ),
        );
      }
    } catch (_) {
      _emitStatus(
        connectionStatus: AlertsConnectionStatus.connecting,
        feedMode: AlertsFeedMode.websocket,
        statusMessage: '初始快照拉取失败，继续尝试实时连接…',
      );
    }
  }

  Future<List<AlertItem>> _fetchBootstrapAlerts(String rawUrl) async {
    try {
      final response = await _dio.get<dynamic>(rawUrl);

      final List<AlertItem> items = _extractAlertList(
        response.data,
      ).map(_parseBootstrapPayload).toList(growable: false);

      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items.take(8).toList(growable: false);
    } catch (error) {
      final appError = mapToAppNetworkException(error);
      throw StateError('bootstrap_failed:${appError.message}');
    }
  }

  List<dynamic> _extractAlertList(dynamic decoded) {
    if (decoded is List) return decoded;

    if (decoded is Map<String, dynamic>) {
      const candidates = <String>[
        'items',
        'data',
        'alerts',
        'results',
        'events',
        'rows',
        'records',
      ];

      for (final key in candidates) {
        final value = decoded[key];
        if (value is List) return value;
      }

      final nestedData = decoded['data'];
      if (nestedData is Map<String, dynamic>) {
        for (final key in candidates) {
          final value = nestedData[key];
          if (value is List) return value;
        }
      }

      return <dynamic>[decoded];
    }

    return const <dynamic>[];
  }

  Future<void> _connectWebSocket({bool forceRestart = false}) async {
    if (!_started && !forceRestart) return;

    _emitStatus(
      connectionStatus: AlertsConnectionStatus.connecting,
      feedMode: AlertsFeedMode.websocket,
      statusMessage: _reconnectAttempt == 0
          ? '正在连接 WebSocket…'
          : '正在重连 WebSocket（第 $_reconnectAttempt 次）…',
    );

    final uri = _buildAlertsWsUri();

    try {
      final socket = WebSocketChannel.connect(uri);
      await socket.ready.timeout(const Duration(seconds: 3));

      await _closeSocket();

      _socket = socket;
      _offline = false;
      _reconnectAttempt = 0;

      _emitStatus(
        connectionStatus: AlertsConnectionStatus.connected,
        feedMode: AlertsFeedMode.websocket,
        statusMessage: _bootstrapLoaded
            ? '初始快照 + WebSocket 已接通'
            : 'WebSocket 已连接',
      );

      _socketSub = socket.stream.listen(
        _handleSocketMessage,
        onError: (Object error, StackTrace stackTrace) {
          _handleSocketClosed(reason: 'WebSocket 出错，准备降级/重连');
        },
        onDone: () {
          _handleSocketClosed(reason: 'WebSocket 已断开，准备降级/重连');
        },
        cancelOnError: true,
      );
    } catch (_) {
      _enterOffline(
        reason: _bootstrapLoaded
            ? '实时流连接失败；保留后端初始快照，未生成本地告警'
            : 'WebSocket 连接失败；当前无真实告警数据',
      );
      _scheduleReconnect();
    }
  }

  void _handleSocketMessage(dynamic raw) {
    final AlertItem item = _parseSocketPayload(raw);
    _emitAlert(item);
  }

  void _handleSocketClosed({required String reason}) {
    _emitStatus(
      connectionStatus: AlertsConnectionStatus.disconnected,
      feedMode: AlertsFeedMode.websocket,
      statusMessage: reason,
    );

    _enterOffline(
      reason: _bootstrapLoaded ? '连接中断；保留后端快照，未生成本地告警' : '连接中断；当前无真实告警数据',
    );

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_started) return;
    if (_reconnectTimer != null) return;

    _reconnectAttempt += 1;

    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnectTimer = null;
      if (!_started) return;
      unawaited(_connectWebSocket());
    });
  }

  void _enterOffline({required String reason}) {
    _offline = true;
    _emitStatus(
      connectionStatus: AlertsConnectionStatus.disconnected,
      feedMode: AlertsFeedMode.offline,
      statusMessage: reason,
    );
  }

  AlertItem _parseBootstrapPayload(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return AlertItem(
        id:
            _firstString(raw, const [
              'id',
              'event_id',
              'alert_id',
              'request_id',
            ]) ??
            'bootstrap-${DateTime.now().millisecondsSinceEpoch}-${_nextSeq()}',
        title:
            _firstString(raw, const [
              'title',
              'headline',
              'name',
              'alert',
              'event',
            ]) ??
            '历史告警',
        detail:
            _firstString(raw, const [
              'detail',
              'message',
              'description',
              'reason',
              'summary',
            ]) ??
            '已加载一条初始告警快照。',
        severity: _parseSeverity(
          _firstString(raw, const [
                'severity',
                'level',
                'priority',
                'risk_level',
              ]) ??
              'info',
        ),
        createdAt:
            _firstDateTime(raw, const [
              'createdAt',
              'created_at',
              'ts',
              'timestamp',
              'time',
              'occurred_at',
            ]) ??
            DateTime.now(),
        source:
            _firstString(raw, const [
              'source',
              'topic',
              'module',
              'domain',
              'capability',
            ]) ??
            'bootstrap/http',
        isAcknowledged: false,
      );
    }

    return _buildAlert(
      title: '历史告警',
      detail: raw.toString(),
      severity: AlertSeverity.info,
      source: 'bootstrap/http',
      createdAt: DateTime.now(),
    );
  }

  AlertItem _parseSocketPayload(dynamic raw) {
    try {
      final dynamic decoded = raw is String ? jsonDecode(raw) : raw;

      if (decoded is Map<String, dynamic>) {
        final dynamic nested = _unwrapRealtimePayload(decoded);
        if (nested is Map<String, dynamic>) {
          return AlertItem(
            id:
                _firstString(nested, const [
                  'id',
                  'event_id',
                  'alert_id',
                  'request_id',
                ]) ??
                'alert-${DateTime.now().millisecondsSinceEpoch}-${_nextSeq()}',
            title:
                _firstString(nested, const [
                  'title',
                  'headline',
                  'event',
                  'alert',
                  'name',
                ]) ??
                '实时告警',
            detail:
                _firstString(nested, const [
                  'detail',
                  'message',
                  'description',
                  'reason',
                  'summary',
                ]) ??
                '收到一条实时事件',
            severity: _parseSeverity(
              _firstString(nested, const [
                    'severity',
                    'level',
                    'priority',
                    'risk_level',
                  ]) ??
                  'info',
            ),
            createdAt:
                _firstDateTime(nested, const [
                  'createdAt',
                  'created_at',
                  'ts',
                  'timestamp',
                  'time',
                  'occurred_at',
                ]) ??
                DateTime.now(),
            source:
                _firstString(nested, const [
                  'source',
                  'topic',
                  'module',
                  'domain',
                  'capability',
                ]) ??
                'ws/alerts',
            isAcknowledged: false,
          );
        }
      }
    } catch (_) {
      // fall through
    }

    return _buildAlert(
      title: '实时告警事件',
      detail: raw.toString(),
      severity: AlertSeverity.info,
      source: 'ws/raw',
      createdAt: DateTime.now(),
    );
  }

  dynamic _unwrapRealtimePayload(Map<String, dynamic> decoded) {
    const candidates = <String>['data', 'payload', 'event', 'alert', 'item'];

    for (final key in candidates) {
      final value = decoded[key];
      if (value is Map<String, dynamic>) return value;
    }

    return decoded;
  }

  String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final dynamic value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  DateTime? _firstDateTime(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final dynamic value = map[key];
      final parsed = _toDateTime(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) return value;

    if (value is int) {
      return _epochToDateTime(value);
    }

    if (value is double) {
      return _epochToDateTime(value.toInt());
    }

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    final asInt = int.tryParse(text);
    if (asInt != null) {
      return _epochToDateTime(asInt);
    }

    return DateTime.tryParse(text)?.toLocal();
  }

  DateTime _epochToDateTime(int epoch) {
    if (epoch > 999999999999) {
      return DateTime.fromMillisecondsSinceEpoch(epoch).toLocal();
    }

    return DateTime.fromMillisecondsSinceEpoch(epoch * 1000).toLocal();
  }

  AlertSeverity _parseSeverity(String raw) {
    final normalized = raw.trim().toLowerCase();

    if (normalized.contains('critical') ||
        normalized.contains('high') ||
        normalized.contains('severe') ||
        normalized.contains('error')) {
      return AlertSeverity.critical;
    }

    if (normalized.contains('warn') ||
        normalized.contains('medium') ||
        normalized.contains('risk')) {
      return AlertSeverity.warn;
    }

    return AlertSeverity.info;
  }

  AlertItem _buildAlert({
    required String title,
    required String detail,
    required AlertSeverity severity,
    required String source,
    required DateTime createdAt,
  }) {
    return AlertItem(
      id: 'alert-${createdAt.millisecondsSinceEpoch}-${_nextSeq()}',
      title: title,
      detail: detail,
      severity: severity,
      source: source,
      createdAt: createdAt,
      isAcknowledged: false,
    );
  }

  int _nextSeq() {
    _seq += 1;
    return _seq;
  }

  Uri _buildAlertsWsUri() {
    if (_wsUrl.trim().isNotEmpty) {
      return Uri.parse(_wsUrl.trim());
    }

    final base = Uri.parse(AppConfig.apiBaseUrl);
    final secure = base.scheme == 'https';
    final scheme = secure ? 'wss' : 'ws';

    return base.replace(
      scheme: scheme,
      path: _normalizeWsPath(base.path),
      queryParameters: null,
      fragment: null,
    );
  }

  String _normalizeWsPath(String basePath) {
    final cleanedBase = basePath.trim();
    if (cleanedBase.isEmpty || cleanedBase == '/') {
      return _defaultWsPath;
    }

    final withoutTrailing = cleanedBase.endsWith('/')
        ? cleanedBase.substring(0, cleanedBase.length - 1)
        : cleanedBase;

    if (withoutTrailing.endsWith(_defaultWsPath)) {
      return withoutTrailing;
    }

    return '$withoutTrailing$_defaultWsPath';
  }

  void _emitStatus({
    required AlertsConnectionStatus connectionStatus,
    required AlertsFeedMode feedMode,
    required String statusMessage,
  }) {
    if (_controller.isClosed) return;

    _controller.add(
      AlertsFeedEvent.status(
        connectionStatus: connectionStatus,
        feedMode: feedMode,
        statusMessage: statusMessage,
        reconnectAttempt: _reconnectAttempt,
      ),
    );
  }

  void _emitAlert(
    AlertItem item, {
    bool isBootstrap = false,
    String? statusMessage,
  }) {
    if (_controller.isClosed) return;

    _controller.add(
      AlertsFeedEvent.alert(
        item: item,
        connectionStatus: AlertsConnectionStatus.connected,
        feedMode: _offline ? AlertsFeedMode.offline : AlertsFeedMode.websocket,
        statusMessage:
            statusMessage ??
            (isBootstrap
                ? '已载入初始快照'
                : (_offline ? '离线；未生成本地告警' : 'WebSocket 实时流中')),
        reconnectAttempt: _reconnectAttempt,
        isBootstrap: isBootstrap,
      ),
    );
  }

  Future<void> _closeSocket() async {
    await _socketSub?.cancel();
    _socketSub = null;

    final socket = _socket;
    _socket = null;

    if (socket != null) {
      try {
        await socket.sink.close();
      } catch (_) {}
    }
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  @override
  void dispose() {
    _started = false;
    _cancelReconnectTimer();
    unawaited(_closeSocket());
    _controller.close();
  }
}

const int kMaxAlertItems = 200;
const int kAlertsBatchWindowMs = 1000;

final alertsSnapshotProvider =
    AsyncNotifierProvider<AlertsSnapshotNotifier, AlertsSnapshot>(
      AlertsSnapshotNotifier.new,
    );

final alertsPerfStatsProvider = Provider<AlertsPerfStats>((ref) {
  final snapshotAsync = ref.watch(alertsSnapshotProvider);
  return snapshotAsync.maybeWhen(
    data: (snapshot) => snapshot.perfStats,
    orElse: () => AlertsPerfStats.empty,
  );
});

class AlertsSnapshotNotifier extends AsyncNotifier<AlertsSnapshot> {
  StreamSubscription<AlertsFeedEvent>? _subscription;
  Timer? _flushTimer;

  AlertsSnapshot _snapshot = AlertsSnapshot.empty;
  final List<AlertsFeedEvent> _pendingEvents = <AlertsFeedEvent>[];
  final List<DateTime> _receivedEventMarks = <DateTime>[];
  final List<DateTime> _receivedAlertMarks = <DateTime>[];

  bool _failNextRefresh = false;

  @override
  Future<AlertsSnapshot> build() async {
    ref.onDispose(() {
      _flushTimer?.cancel();
      _subscription?.cancel();
    });

    _subscribe();
    return _snapshot;
  }

  void _subscribe() {
    _subscription?.cancel();

    final service = ref.read(alertsFeedServiceProvider);
    _subscription = service.watchEvents().listen(
      _enqueueFeedEvent,
      onError: (Object error, StackTrace stackTrace) {
        state = AsyncError(error, stackTrace);
      },
    );
  }

  void _enqueueFeedEvent(AlertsFeedEvent event) {
    final now = DateTime.now();
    _pendingEvents.add(event);
    _receivedEventMarks.add(now);
    if (event.hasAlert) {
      _receivedAlertMarks.add(now);
    }
    _prunePerfMarks(now);

    _flushTimer ??= Timer(
      const Duration(milliseconds: kAlertsBatchWindowMs),
      _flushPendingEvents,
    );
  }

  void _flushPendingEvents() {
    _flushTimer?.cancel();
    _flushTimer = null;

    if (_pendingEvents.isEmpty) return;

    final List<AlertsFeedEvent> batch = List<AlertsFeedEvent>.from(
      _pendingEvents,
      growable: false,
    );
    _pendingEvents.clear();

    final AlertsFeedEvent latestEvent = batch.last;

    DateTime? lastUpdatedAt = _snapshot.lastUpdatedAt;
    final List<AlertItem> incomingAlerts = _extractNewestUniqueAlerts(batch);

    if (incomingAlerts.isNotEmpty) {
      lastUpdatedAt = incomingAlerts.first.createdAt;
    }

    final Set<String> incomingIds = incomingAlerts.map((e) => e.id).toSet();
    final List<AlertItem> mergedItems = <AlertItem>[
      ...incomingAlerts,
      ..._snapshot.items.where((e) => !incomingIds.contains(e.id)),
    ].take(kMaxAlertItems).toList(growable: false);

    final now = DateTime.now();
    _prunePerfMarks(now);

    _snapshot = _snapshot.copyWith(
      items: mergedItems,
      unreadCount: mergedItems.where((e) => !e.isAcknowledged).length,
      lastUpdatedAt: lastUpdatedAt,
      isLive: latestEvent.connectionStatus == AlertsConnectionStatus.connected,
      connectionStatus: latestEvent.connectionStatus,
      feedMode: latestEvent.feedMode,
      statusMessage: latestEvent.statusMessage,
      reconnectAttempt: latestEvent.reconnectAttempt,
      perfStats: _snapshot.perfStats.copyWith(
        receivedAlertsLastSecond: _countWithinWindow(
          _receivedAlertMarks,
          now,
          const Duration(seconds: 1),
        ),
        receivedAlertsLastMinute: _receivedAlertMarks.length,
        receivedEventsLastSecond: _countWithinWindow(
          _receivedEventMarks,
          now,
          const Duration(seconds: 1),
        ),
        receivedEventsLastMinute: _receivedEventMarks.length,
        lastFlushAlertCount: incomingAlerts.length,
        totalFlushCount: _snapshot.perfStats.totalFlushCount + 1,
        lastEventAt: now,
        lastFlushAt: now,
        throttleWindowMs: kAlertsBatchWindowMs,
      ),
    );

    state = AsyncData(_snapshot);
  }

  List<AlertItem> _extractNewestUniqueAlerts(List<AlertsFeedEvent> batch) {
    final List<AlertItem> incoming = <AlertItem>[];
    final Set<String> seen = <String>{};

    for (int i = batch.length - 1; i >= 0; i--) {
      final event = batch[i];
      if (!event.hasAlert) continue;

      final item = event.item!;
      if (seen.add(item.id)) {
        incoming.add(item);
      }
    }

    return incoming;
  }

  void _prunePerfMarks(DateTime now) {
    final cutoff = now.subtract(const Duration(minutes: 1));
    _receivedEventMarks.removeWhere((t) => t.isBefore(cutoff));
    _receivedAlertMarks.removeWhere((t) => t.isBefore(cutoff));
  }

  int _countWithinWindow(List<DateTime> marks, DateTime now, Duration window) {
    final cutoff = now.subtract(window);
    return marks.where((t) => !t.isBefore(cutoff)).length;
  }

  Future<void> refreshNow() async {
    if (_failNextRefresh) {
      _failNextRefresh = false;
      state = AsyncError(
        StateError('alerts_snapshot_refresh_failed'),
        StackTrace.current,
      );
      return;
    }

    final service = ref.read(alertsFeedServiceProvider);
    await service.reconnect();
  }

  void failNextFetchOnce() {
    _failNextRefresh = true;
  }

  void acknowledgeAlert(String id) {
    final updated = _snapshot.items
        .map((e) => e.id == id ? e.copyWith(isAcknowledged: true) : e)
        .toList(growable: false);

    _snapshot = _snapshot.copyWith(
      items: updated,
      unreadCount: updated.where((e) => !e.isAcknowledged).length,
    );

    state = AsyncData(_snapshot);
  }

  void clearAll() {
    _pendingEvents.clear();
    _receivedAlertMarks.clear();
    _receivedEventMarks.clear();
    _snapshot = AlertsSnapshot.empty;
    state = const AsyncData(AlertsSnapshot.empty);
  }
}

final unreadAlertsCountProvider =
    AsyncNotifierProvider<UnreadAlertsCountNotifier, int>(
      UnreadAlertsCountNotifier.new,
    );

class UnreadAlertsCountNotifier extends AsyncNotifier<int> {
  ProviderSubscription<AsyncValue<AlertsSnapshot>>? _snapshotSub;

  @override
  Future<int> build() async {
    _snapshotSub?.close();

    _snapshotSub = ref.listen<AsyncValue<AlertsSnapshot>>(
      alertsSnapshotProvider,
      (previous, next) {
        next.when(
          data: (snapshot) {
            state = AsyncData(snapshot.unreadCount);
          },
          loading: () {
            state = const AsyncLoading();
          },
          error: (error, stackTrace) {
            state = AsyncError(error, stackTrace);
          },
        );
      },
      fireImmediately: true,
    );

    ref.onDispose(() {
      _snapshotSub?.close();
    });

    final snapshotAsync = ref.read(alertsSnapshotProvider);
    return snapshotAsync.maybeWhen(
      data: (snapshot) => snapshot.unreadCount,
      orElse: () => 0,
    );
  }

  Future<void> refreshNow() async {
    await ref.read(alertsSnapshotProvider.notifier).refreshNow();
  }

  void failNextFetchOnce() {
    ref.read(alertsSnapshotProvider.notifier).failNextFetchOnce();
  }

  void resetCount() {
    ref.read(alertsSnapshotProvider.notifier).clearAll();
    state = const AsyncData(0);
  }
}

final quickReplanProvider =
    NotifierProvider<QuickReplanNotifier, ReplanTriggerState>(
      QuickReplanNotifier.new,
    );

class QuickReplanNotifier extends Notifier<ReplanTriggerState> {
  @override
  ReplanTriggerState build() => const ReplanTriggerState.idle();

  Future<void> triggerQuickReplan({
    String? sourceAlertId,
    String trigger = 'replan',
  }) async {
    state = ReplanTriggerState(
      status: ReplanTriggerStatus.submitting,
      message: '正在触发重规划…',
      lastTriggerAt: DateTime.now(),
      lastSourceAlertId: sourceAlertId,
    );

    try {
      final response = await ref
          .read(dioProvider)
          .post<Object>(
            '/api/strategy/replan',
            data: <String, Object?>{
              'source_alert_id': sourceAlertId,
              'trigger': trigger,
            },
          );
      final payload = response.data is Map
          ? (response.data as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : <String, dynamic>{};
      if (payload['accepted'] != true ||
          payload['status']?.toString() != 'review_required') {
        throw StateError('后端未接受重规划审阅申请');
      }
      final requestId = payload['request_id']?.toString() ?? '';
      if (requestId.isEmpty) throw StateError('后端未返回申请编号');

      state = ReplanTriggerState(
        status: ReplanTriggerStatus.success,
        message: '审阅申请 $requestId 已登记 · 未生产下发',
        lastTriggerAt: DateTime.now(),
        lastSourceAlertId: sourceAlertId,
      );

      final alertSnapshot = ref
          .read(alertsSnapshotProvider)
          .maybeWhen(data: (value) => value, orElse: () => null);
      AlertItem? sourceAlert;
      if (sourceAlertId != null && alertSnapshot != null) {
        for (final item in alertSnapshot.items) {
          if (item.id == sourceAlertId) {
            sourceAlert = item;
            break;
          }
        }
      }
      ref
          .read(auditTimelineProvider.notifier)
          .recordAction(
            'trigger_replan',
            meta: <String, Object?>{
              'source': 'alerts_tab',
              'sourceAlertId': sourceAlertId,
              'sourceAlertTitle': sourceAlert?.title,
              'requestId': requestId,
              'candidateJobId': payload['candidate_job_id'],
              'status': 'review_required',
              'stateSummary': sourceAlert == null
                  ? '人工从告警页触发重规划'
                  : '由告警触发重规划：${sourceAlert.title}',
              'policySetSummary':
                  '已绑定完成留出测试的候选 ${payload['candidate_job_id']}；等待策略页人工审阅',
              'humanChoiceSummary': '人工确认告警并发起重规划',
            },
          );
    } catch (error) {
      state = ReplanTriggerState(
        status: ReplanTriggerStatus.failure,
        message: '重规划审阅申请失败：$error',
        lastTriggerAt: DateTime.now(),
        lastSourceAlertId: sourceAlertId,
      );
    }
  }

  void reset() {
    state = const ReplanTriggerState.idle();
  }
}

import 'package:flutter/foundation.dart';

/// App 级统一配置。
///
/// Day 25：环境分层 / 联调准备
/// 目标：
/// 1) 给 Dio / 首页 / 设置页 / Debug 面板提供同一个配置来源
/// 2) 统一 API / WS / 环境标签 / 传输语义
/// 3) 继续保持实现简单，方便用 dart-define 覆盖
class AppConfig {
  const AppConfig._();

  static const String _defaultApiBaseUrl = 'http://10.0.2.2:8000';

  /// 可通过：
  /// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
  /// flutter run --dart-define=APP_ENV=public_replay --dart-define=API_BASE_URL=http://127.0.0.1:8000
  /// 来覆盖。
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultApiBaseUrl,
  );

  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'public_replay',
  );

  /// 连接超时（毫秒）
  static const int connectTimeoutMs = int.fromEnvironment(
    'API_CONNECT_TIMEOUT_MS',
    defaultValue: 8000,
  );

  /// 接收超时（毫秒）
  static const int receiveTimeoutMs = int.fromEnvironment(
    'API_RECEIVE_TIMEOUT_MS',
    defaultValue: 10000,
  );

  /// 发送超时（毫秒）
  static const int sendTimeoutMs = int.fromEnvironment(
    'API_SEND_TIMEOUT_MS',
    defaultValue: 10000,
  );

  /// 当前是否启用网络摘要日志。
  static bool get enableNetworkLog => kDebugMode;

  /// 当前是否使用安全传输。
  static bool get isSecureTransport {
    final normalized = apiBaseUrl.trim().toLowerCase();
    return normalized.startsWith('https://');
  }

  /// 给 WebSocket 使用的地址。
  static String get wsBaseUrl {
    final normalized = apiBaseUrl.trim();
    if (normalized.isEmpty) {
      return 'ws://10.0.2.2:8000/ws';
    }
    if (normalized.startsWith('https://')) {
      return 'wss://${normalized.substring('https://'.length)}/ws';
    }
    if (normalized.startsWith('http://')) {
      return 'ws://${normalized.substring('http://'.length)}/ws';
    }
    return 'ws://$normalized/ws';
  }

  /// 是否本地联调地址。
  static bool get usesLocalApi {
    final value = apiBaseUrl.trim().toLowerCase();
    return value.contains('10.0.2.2') ||
        value.contains('127.0.0.1') ||
        value.contains('localhost');
  }

  /// 环境标签：DEV / REPLAY / DEMO / PROD
  static String get environmentLabel {
    final env = appEnv.trim().toLowerCase();
    if (env == 'prod' || env == 'production') return 'PROD';
    if (env == 'public_replay' || env == 'replay') return 'REPLAY';
    if (env == 'demo' || env == 'staging' || env == 'test') return 'DEMO';

    final value = apiBaseUrl.trim().toLowerCase();
    if (value.contains('demo') ||
        value.contains('staging') ||
        value.contains('test')) {
      return 'DEMO';
    }
    if (usesLocalApi) return 'DEV';
    return 'PROD';
  }

  /// 部署语义：本地联调 / 演示链路 / 生产链路
  static String get deploymentHint {
    switch (environmentLabel) {
      case 'DEV':
        return '本地联调';
      case 'DEMO':
        return '演示链路';
      case 'REPLAY':
        return '公开历史回放';
      case 'PROD':
        return '生产链路';
      default:
        return '未识别环境';
    }
  }

  /// 链路语义：Local API / Demo backend / Live backend
  static String get sourceHint {
    switch (environmentLabel) {
      case 'DEV':
        return 'Local API / fail-closed';
      case 'DEMO':
        return 'Public replay backend';
      case 'REPLAY':
        return 'Public historical replay backend';
      case 'PROD':
        return 'Live backend';
      default:
        return 'Unknown backend';
    }
  }

  static String get transportLabel =>
      isSecureTransport ? 'HTTPS/WSS' : 'HTTP/WS';

  /// 首页 / 设置页 / 调试页可直接复用的一眼摘要。
  static String runtimeSummary() {
    return '$environmentLabel · $deploymentHint · $sourceHint · $transportLabel';
  }

  /// 统一默认请求头。
  ///
  /// 注意：
  /// - token 先不在这里拼；
  /// - token 属于运行时状态，应该由 auth / interceptor 注入。
  static Map<String, String> defaultHeaders() {
    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Client-Platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'X-Client-App': 'dt_mobile_app',
      'X-Client-Mode': 'mobile-decision-terminal',
      'X-App-Env': environmentLabel,
    };
  }

  /// 给设置页 / 调试页 / 日志输出用的轻量摘要。
  static Map<String, Object> debugSummary() {
    return <String, Object>{
      'appEnv': appEnv,
      'environmentLabel': environmentLabel,
      'deploymentHint': deploymentHint,
      'sourceHint': sourceHint,
      'apiBaseUrl': apiBaseUrl,
      'wsBaseUrl': wsBaseUrl,
      'transportLabel': transportLabel,
      'usesLocalApi': usesLocalApi,
      'connectTimeoutMs': connectTimeoutMs,
      'receiveTimeoutMs': receiveTimeoutMs,
      'sendTimeoutMs': sendTimeoutMs,
      'enableNetworkLog': enableNetworkLog,
      'defaultHeaders': defaultHeaders(),
    };
  }
}

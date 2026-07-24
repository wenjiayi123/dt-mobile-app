import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../debug/debug_config.dart';

@immutable
class AuthState {
  const AuthState._({required this.token});

  const AuthState.unauthenticated() : this._(token: null);

  AuthState.authenticated(String token) : this._(token: _normalizeToken(token));

  final String? token;

  bool get isLoggedIn => token != null && token!.trim().isNotEmpty;

  String get statusLabel => isLoggedIn ? '凭证已配置（未验证）' : '凭证未配置';

  String? get maskedToken => token == null ? null : maskSensitiveToken(token!);

  AuthState copyWith({String? token, bool clearToken = false}) {
    if (clearToken) {
      return const AuthState.unauthenticated();
    }

    final normalized = _normalizeToken(token);
    if (normalized == null) {
      return const AuthState.unauthenticated();
    }

    return AuthState.authenticated(normalized);
  }

  static String? _normalizeToken(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  @override
  String toString() {
    return 'AuthState(status: $statusLabel, token: ${maskedToken ?? 'null'})';
  }

  @override
  bool operator ==(Object other) {
    return other is AuthState && other.token == token;
  }

  @override
  int get hashCode => token.hashCode;
}

class AuthStateNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    return const AuthState.unauthenticated();
  }

  void setToken(String rawToken) {
    final normalized = rawToken.trim();
    if (normalized.isEmpty) {
      clearToken();
      return;
    }

    state = AuthState.authenticated(normalized);
  }

  void clearToken() {
    state = const AuthState.unauthenticated();
  }
}

final authStateProvider = NotifierProvider<AuthStateNotifier, AuthState>(
  AuthStateNotifier.new,
);

/// 当前运行态里用于注入请求头的认证令牌。
///
/// 这层 provider 让 App 的控制动作不依赖页面局部状态，
/// 也让设置页里的“鉴权状态 / Integration”说明能和真实网络层对上。
final authTokenProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).token;
});

/// 是否输出工程语义化网络日志。
///
/// 打开后，日志会带上运行环境、请求类别、响应语义和错误映射，
/// 便于在联调或演示时说明“状态从哪里来、动作是否有回执”。
final networkLogEnabledProvider = Provider<bool>((ref) {
  final debugConfig = ref.watch(debugConfigProvider);
  return debugConfig.networkLogEnabled || AppConfig.enableNetworkLog;
});

/// 统一的网络入口。
///
/// 这层把 App 和 Backend 的关系固定下来：
/// - REST: 拉取当前状态、提交控制动作、读取审计结果
/// - WebSocket: 负责实时事件与执行回执（当前代码先在设置页做结构说明）
/// - Header 注入: 统一带上鉴权与运行模式，保证 Web / App 口径一致
/// - 日志与错误映射: 把底层网络结果翻译成页面可理解的工程语义
final dioProvider = Provider<Dio>((ref) {
  final enableNetworkLog = ref.watch(networkLogEnabledProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: Duration(milliseconds: AppConfig.connectTimeoutMs),
      receiveTimeout: Duration(milliseconds: AppConfig.receiveTimeoutMs),
      sendTimeout: Duration(milliseconds: AppConfig.sendTimeoutMs),
      headers: AppConfig.defaultHeaders(),
      responseType: ResponseType.json,
      contentType: Headers.jsonContentType,
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        // 请求阶段承担两类职责：
        // 1) 补齐运行时上下文（token / 环境）
        // 2) 让每个动作在进入后端前就带上可解释的工程标签
        final token = ref.read(authTokenProvider);

        final mergedHeaders = <String, Object?>{
          ...options.headers,
          ...AppConfig.defaultHeaders(),
        };

        if (token != null && token.trim().isNotEmpty) {
          mergedHeaders['Authorization'] = 'Bearer $token';
        }

        options.headers = mergedHeaders;

        if (enableNetworkLog) {
          final requestUrl = '${options.baseUrl}${options.path}';
          final runtimeLabel = _buildRuntimeLogLabel();

          final requestCategory = _inferRequestCategory(options);
          final requestRole = _describeRequestCategory(requestCategory);

          debugPrint('[DIO][REQ] $runtimeLabel ${options.method} $requestUrl');
          debugPrint('[DIO][REQ_ROLE] $requestCategory · $requestRole');
          debugPrint(
            '[DIO][REQ_HEADERS] ${_sanitizeHeadersForLog(options.headers)}',
          );
          if (options.queryParameters.isNotEmpty) {
            debugPrint(
              '[DIO][REQ_QUERY] ${_sanitizeMapForLog(options.queryParameters)}',
            );
          }
          if (options.data != null) {
            debugPrint('[DIO][REQ_BODY] ${_summarizePayload(options.data)}');
          }
        }

        handler.next(options);
      },
      onResponse: (response, handler) {
        // 响应阶段负责把后端结果翻译为“状态快照 / 控制回执 / 审计读取”等语义，
        // 这样设置页里的 Integration 说明和真实日志能互相印证。
        if (enableNetworkLog) {
          final request = response.requestOptions;
          final requestUrl = '${request.baseUrl}${request.path}';
          final runtimeLabel = _buildRuntimeLogLabel();

          final requestCategory = _inferRequestCategory(request);
          final responseRole = _describeResponseRole(
            requestCategory: requestCategory,
            statusCode: response.statusCode,
          );

          debugPrint(
            '[DIO][RES] $runtimeLabel '
            '${response.statusCode} ${request.method} $requestUrl',
          );
          debugPrint('[DIO][RES_ROLE] $responseRole');
          debugPrint('[DIO][RES_BODY] ${_summarizePayload(response.data)}');
        }
        handler.next(response);
      },
      onError: (error, handler) {
        // 错误阶段不直接把 Dio 原始异常甩给 UI，
        // 而是先保留工程日志，再由 mapToAppNetworkException 做统一映射。
        if (enableNetworkLog) {
          final request = error.requestOptions;
          final requestUrl = '${request.baseUrl}${request.path}';
          final runtimeLabel = _buildRuntimeLogLabel();

          final requestCategory = _inferRequestCategory(request);
          final errorRole = _describeErrorRole(
            requestCategory: requestCategory,
            error: error,
          );

          debugPrint('[DIO][ERR] $runtimeLabel ${request.method} $requestUrl');
          debugPrint('[DIO][ERR_ROLE] $errorRole');
          debugPrint(
            '[DIO][ERR_HEADERS] ${_sanitizeHeadersForLog(request.headers)}',
          );
          if (request.queryParameters.isNotEmpty) {
            debugPrint(
              '[DIO][ERR_QUERY] ${_sanitizeMapForLog(request.queryParameters)}',
            );
          }
          debugPrint('[DIO][ERR_TYPE] ${error.type}');
          debugPrint('[DIO][ERR_MSG] ${error.message}');
          if (error.response != null) {
            debugPrint('[DIO][ERR_STATUS] ${error.response?.statusCode}');
            debugPrint(
              '[DIO][ERR_BODY] ${_summarizePayload(error.response?.data)}',
            );
          }
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});

/// 运行时标签会进入每一条请求 / 响应 / 错误日志，
/// 用来说明当前链路是在哪个环境、哪种传输假设、哪种本地韧性模式下发生的。

String _inferRequestCategory(RequestOptions options) {
  final method = options.method.toUpperCase();
  final path = options.path.toLowerCase();

  if (path.contains('audit') || path.contains('replay')) {
    return 'audit-read';
  }
  if (path.contains('ws') || path.contains('socket')) {
    return 'event-bridge';
  }
  if (path.contains('execute') ||
      path.contains('submit') ||
      path.contains('apply') ||
      path.contains('confirm') ||
      method == 'POST' ||
      method == 'PUT' ||
      method == 'PATCH' ||
      method == 'DELETE') {
    return 'control-write';
  }
  if (path.contains('alert') ||
      path.contains('state') ||
      path.contains('status') ||
      path.contains('snapshot') ||
      path.contains('situation') ||
      method == 'GET') {
    return 'state-read';
  }

  return 'integration-call';
}

String _describeRequestCategory(String category) {
  switch (category) {
    case 'state-read':
      return '拉取状态快照 / 刷新页面来源';
    case 'control-write':
      return '提交控制动作 / 等待执行回执';
    case 'audit-read':
      return '读取审计与回放链路';
    case 'event-bridge':
      return '事件桥接 / 预留实时推送语义';
    default:
      return '通用集成调用';
  }
}

String _describeResponseRole({
  required String requestCategory,
  required int? statusCode,
}) {
  final status = statusCode ?? 0;
  final suffix = status >= 200 && status < 300 ? '已完成' : '待进一步检查';

  switch (requestCategory) {
    case 'state-read':
      return '状态来源已返回 · $suffix';
    case 'control-write':
      return '控制动作已受理，后续应结合执行回执或审计链路继续观察 · $suffix';
    case 'audit-read':
      return '审计 / 回放记录已返回 · $suffix';
    case 'event-bridge':
      return '实时链路语义已返回 · $suffix';
    default:
      return '集成调用已返回 · $suffix';
  }
}

String _describeErrorRole({
  required String requestCategory,
  required DioException error,
}) {
  final mapped = mapToAppNetworkException(error);
  final scope = switch (requestCategory) {
    'state-read' => '状态读取',
    'control-write' => '控制动作',
    'audit-read' => '审计读取',
    'event-bridge' => '实时链路',
    _ => '集成调用',
  };

  if (mapped.isUnauthorized) {
    return '$scope失败 · 鉴权失效';
  }
  if (mapped.isTimeout) {
    return '$scope失败 · 请求超时';
  }
  if (mapped.isServerError) {
    return '$scope失败 · 服务端暂不可用';
  }
  return '$scope失败 · 等待重试或人工复核';
}

String _buildRuntimeLogLabel() {
  final env = AppConfig.environmentLabel;
  final deployment = AppConfig.deploymentHint;
  final source = AppConfig.sourceHint;
  final transport = AppConfig.transportLabel;
  return '[ENV=$env][$deployment][$source][$transport]';
}

Map<String, Object?> _sanitizeHeadersForLog(Map<String, dynamic> headers) {
  final sanitized = <String, Object?>{};

  headers.forEach((key, value) {
    final lowerKey = key.toLowerCase();

    if (lowerKey == 'authorization') {
      sanitized[key] = _maskAuthorizationHeader(value?.toString());
      return;
    }

    if (_isSensitiveKey(lowerKey)) {
      sanitized[key] = '***';
      return;
    }

    sanitized[key] = value;
  });

  return sanitized;
}

Map<String, Object?> _sanitizeMapForLog(Map<String, dynamic> values) {
  final sanitized = <String, Object?>{};

  values.forEach((key, value) {
    final lowerKey = key.toLowerCase();
    if (_isSensitiveKey(lowerKey)) {
      sanitized[key] = '***';
      return;
    }

    sanitized[key] = _summarizeScalar(value);
  });

  return sanitized;
}

bool _isSensitiveKey(String key) {
  return key.contains('token') ||
      key.contains('authorization') ||
      key.contains('secret') ||
      key.contains('password') ||
      key.contains('cookie') ||
      key.contains('session') ||
      key.contains('credential');
}

Object? _summarizeScalar(Object? value) {
  if (value == null) return null;
  if (value is num || value is bool) return value;

  final raw = value.toString().trim();
  if (raw.isEmpty) return 'empty';
  if (raw.length <= 48) return raw;
  return '${raw.substring(0, 48)}...';
}

String _maskAuthorizationHeader(String? rawValue) {
  if (rawValue == null || rawValue.trim().isEmpty) {
    return '***';
  }

  final trimmed = rawValue.trim();
  const bearerPrefix = 'Bearer ';

  if (trimmed.startsWith(bearerPrefix)) {
    final token = trimmed.substring(bearerPrefix.length).trim();
    return '$bearerPrefix${maskSensitiveToken(token)}';
  }

  return maskSensitiveToken(trimmed);
}

String maskSensitiveToken(String token) {
  final trimmed = token.trim();
  if (trimmed.isEmpty) return '***';

  if (trimmed.length <= 2) {
    return '${trimmed.substring(0, 1)}***';
  }

  if (trimmed.length <= 6) {
    return '${trimmed.substring(0, 1)}***${trimmed.substring(trimmed.length - 1)}';
  }

  final head = trimmed.substring(0, 4);
  final tail = trimmed.substring(trimmed.length - 2);
  return '$head***$tail';
}

String _summarizePayload(Object? data) {
  if (data == null) return 'null';

  if (data is Map<String, dynamic>) {
    return _sanitizeMapForLog(data).toString();
  }

  if (data is Iterable) {
    final preview = data.take(3).map(_summarizeScalar).toList();
    final suffix = data.length > 3 ? ' ... (len=${data.length})' : '';
    return '$preview$suffix';
  }

  final raw = data.toString().trim();
  if (raw.isEmpty) return 'empty';

  if (raw.length <= 220) return raw;
  return '${raw.substring(0, 220)}...';
}

@immutable
/// 页面层统一消费的网络异常。
///
/// 它屏蔽 Dio 的底层细节，把错误收敛成页面更容易展示的工程语义：
/// 超时、未授权、服务端异常、一般请求失败。
class AppNetworkException implements Exception {
  const AppNetworkException({
    required this.message,
    this.statusCode,
    this.isTimeout = false,
    this.isUnauthorized = false,
    this.isServerError = false,
    this.raw,
  });

  final String message;
  final int? statusCode;
  final bool isTimeout;
  final bool isUnauthorized;
  final bool isServerError;
  final Object? raw;

  @override
  String toString() {
    return 'AppNetworkException('
        'message: $message, '
        'statusCode: $statusCode, '
        'isTimeout: $isTimeout, '
        'isUnauthorized: $isUnauthorized, '
        'isServerError: $isServerError'
        ')';
  }
}

/// 把底层异常映射成页面可消费的统一错误模型。
///
/// 这一步是 Day 33 里“错误映射”最关键的落点：
/// UI 不需要知道 Dio 的枚举细节，只需要知道这是超时、鉴权失效、
/// 服务端不可用，还是普通请求失败。
AppNetworkException mapToAppNetworkException(Object error) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return AppNetworkException(
          message: '请求超时，请稍后重试。',
          statusCode: statusCode,
          isTimeout: true,
          raw: error,
        );

      case DioExceptionType.badResponse:
        if (statusCode == 401) {
          return AppNetworkException(
            message: '服务器拒绝了当前凭证，请重新配置。',
            statusCode: statusCode,
            isUnauthorized: true,
            raw: error,
          );
        }

        if (statusCode != null && statusCode >= 500) {
          return AppNetworkException(
            message: '服务暂时不可用，请稍后再试。',
            statusCode: statusCode,
            isServerError: true,
            raw: error,
          );
        }

        return AppNetworkException(
          message: _extractServerMessage(error) ?? '请求失败，请检查参数或稍后重试。',
          statusCode: statusCode,
          raw: error,
        );

      case DioExceptionType.cancel:
        return AppNetworkException(
          message: '请求已取消。',
          statusCode: statusCode,
          raw: error,
        );

      case DioExceptionType.connectionError:
        return AppNetworkException(
          message: '网络连接失败，请检查网络后重试。',
          statusCode: statusCode,
          raw: error,
        );

      case DioExceptionType.badCertificate:
        return AppNetworkException(
          message: '证书校验失败，无法建立安全连接。',
          statusCode: statusCode,
          raw: error,
        );

      case DioExceptionType.unknown:
        return AppNetworkException(
          message: _extractServerMessage(error) ?? '网络异常，请稍后重试。',
          statusCode: statusCode,
          raw: error,
        );
    }
  }

  return AppNetworkException(message: '发生未知错误，请稍后重试。', raw: error);
}

String? _extractServerMessage(DioException error) {
  final data = error.response?.data;

  if (data is Map<String, dynamic>) {
    final candidates = <String?>[
      data['message']?.toString(),
      data['error']?.toString(),
      data['detail']?.toString(),
    ];

    for (final item in candidates) {
      if (item != null && item.trim().isNotEmpty) {
        return item.trim();
      }
    }
  }

  if (data is String && data.trim().isNotEmpty) {
    return data.trim();
  }

  return null;
}

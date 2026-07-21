import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/core/config/app_config.dart';

/// Day 17：调试面板 v1
/// Day 23：性能 v1 补充
/// Day 25：环境语义收口
///
/// 这个文件只负责“调试配置状态”本身：
/// - network log on/off
/// - token 状态是否展示
/// - stream perf stats 是否展示
/// - 对外提供统一调试摘要，方便 settings / 日志 / 首页状态条直接复用
class DebugConfigState {
  const DebugConfigState({
    required this.networkLogEnabled,
    required this.showTokenStatus,
    required this.showStreamPerfStats,
  });

  /// 是否打印网络日志摘要
  final bool networkLogEnabled;

  /// 是否在调试面板显示 token 状态
  final bool showTokenStatus;

  /// 是否在调试面板显示实时流更新频率统计
  final bool showStreamPerfStats;

  DebugConfigState copyWith({
    bool? networkLogEnabled,
    bool? showTokenStatus,
    bool? showStreamPerfStats,
  }) {
    return DebugConfigState(
      networkLogEnabled: networkLogEnabled ?? this.networkLogEnabled,
      showTokenStatus: showTokenStatus ?? this.showTokenStatus,
      showStreamPerfStats: showStreamPerfStats ?? this.showStreamPerfStats,
    );
  }

  String get networkLogLabel =>
      networkLogEnabled ? 'NET_LOG=ON' : 'NET_LOG=OFF';

  String get tokenVisibilityLabel =>
      showTokenStatus ? 'TOKEN_VIS=ON' : 'TOKEN_VIS=OFF';

  String get streamPerfStatsLabel =>
      showStreamPerfStats ? 'STREAM_STATS=ON' : 'STREAM_STATS=OFF';

  /// 当前环境标签，来自 AppConfig。
  String get environmentLabel => AppConfig.environmentLabel;

  /// 当前部署语义，来自 AppConfig。
  String get deploymentHint => AppConfig.deploymentHint;

  /// 当前链路语义，来自 AppConfig。
  String get sourceHint => AppConfig.sourceHint;

  /// 当前运行模式，用于首页 / 设置页一眼判断。
  String get runtimeModeLabel => '真实接口优先';

  /// 当前传输语义。
  String get transportLabel =>
      AppConfig.isSecureTransport ? 'HTTPS/WSS' : 'HTTP/WS';

  /// 给设置页小摘要使用：尽量一眼结论，不堆过长文本。
  String get shortSummary =>
      '$environmentLabel · $runtimeModeLabel · $networkLogLabel · $tokenVisibilityLabel';

  /// 给调试卡片 / 未来复制摘要使用的键值对。
  Map<String, String> toSummaryMap() {
    return <String, String>{
      'environment': environmentLabel,
      'deployment': deploymentHint,
      'source': sourceHint,
      'runtimeMode': runtimeModeLabel,
      'transport': transportLabel,
      'networkLog': networkLogEnabled ? 'ON' : 'OFF',
      'tokenVisibility': showTokenStatus ? 'ON' : 'OFF',
      'streamStats': showStreamPerfStats ? 'ON' : 'OFF',
    };
  }

  /// 给设置页开发者面板使用的完整标签。
  ///
  /// 保持单行可读，不打印敏感信息；token 只表达存在性。
  String debugLabel({String? baseUrl, String? wsUrl, bool? hasToken}) {
    final parts = <String>[
      'ENV=$environmentLabel',
      deploymentHint,
      sourceHint,
      runtimeModeLabel,
      transportLabel,
      networkLogLabel,
      tokenVisibilityLabel,
      streamPerfStatsLabel,
    ];

    if (baseUrl != null && baseUrl.trim().isNotEmpty) {
      parts.add('API=${baseUrl.trim()}');
    }

    if (wsUrl != null && wsUrl.trim().isNotEmpty) {
      parts.add('WS=${wsUrl.trim()}');
    }

    if (hasToken != null) {
      parts.add(hasToken ? 'TOKEN=EXISTS' : 'TOKEN=EMPTY');
    }

    return parts.join(' | ');
  }
}

class DebugConfigNotifier extends Notifier<DebugConfigState> {
  @override
  DebugConfigState build() {
    return const DebugConfigState(
      networkLogEnabled: false,
      showTokenStatus: true,
      showStreamPerfStats: true,
    );
  }

  void setNetworkLogEnabled(bool value) {
    state = state.copyWith(networkLogEnabled: value);
  }

  void toggleNetworkLogEnabled() {
    state = state.copyWith(networkLogEnabled: !state.networkLogEnabled);
  }

  void setShowTokenStatus(bool value) {
    state = state.copyWith(showTokenStatus: value);
  }

  void toggleShowTokenStatus() {
    state = state.copyWith(showTokenStatus: !state.showTokenStatus);
  }

  void setShowStreamPerfStats(bool value) {
    state = state.copyWith(showStreamPerfStats: value);
  }

  void toggleShowStreamPerfStats() {
    state = state.copyWith(showStreamPerfStats: !state.showStreamPerfStats);
  }

  void reset() {
    state = const DebugConfigState(
      networkLogEnabled: false,
      showTokenStatus: true,
      showStreamPerfStats: true,
    );
  }
}

final debugConfigProvider =
    NotifierProvider<DebugConfigNotifier, DebugConfigState>(
      DebugConfigNotifier.new,
    );

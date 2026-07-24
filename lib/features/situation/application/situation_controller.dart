import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dt_mobile_app/core/network/dio_provider.dart';

enum SituationStabilityLevel {
  stable('稳定'),
  watch('需盯'),
  critical('临界');

  const SituationStabilityLevel(this.label);
  final String label;
}

enum SituationDataSource {
  live('实时'),
  publicReplay('公开历史回放'),
  cache('缓存');

  const SituationDataSource(this.label);
  final String label;
}

class SituationSnapshot {
  const SituationSnapshot({
    required this.stabilityLevel,
    required this.systemScore,
    required this.strategyPressure,
    required this.constraintHeadroom,
    required this.riskIntervalLow,
    required this.riskIntervalHigh,
    required this.trendPoints,
    required this.summaryText,
    required this.refreshAt,
    required this.dataSource,
    this.businessDatasetId,
    this.businessTestRows,
    this.berthImprovementPercent,
    this.waitReductionPercent,
    this.costReductionPercent,
  });

  final SituationStabilityLevel stabilityLevel;
  final int systemScore;
  final int strategyPressure;
  final int constraintHeadroom;
  final int riskIntervalLow;
  final int riskIntervalHigh;
  final List<double> trendPoints;
  final String summaryText;
  final DateTime refreshAt;
  final SituationDataSource dataSource;
  final String? businessDatasetId;
  final int? businessTestRows;
  final double? berthImprovementPercent;
  final double? waitReductionPercent;
  final double? costReductionPercent;

  SituationSnapshot copyWith({
    SituationStabilityLevel? stabilityLevel,
    int? systemScore,
    int? strategyPressure,
    int? constraintHeadroom,
    int? riskIntervalLow,
    int? riskIntervalHigh,
    List<double>? trendPoints,
    String? summaryText,
    DateTime? refreshAt,
    SituationDataSource? dataSource,
    String? businessDatasetId,
    int? businessTestRows,
    double? berthImprovementPercent,
    double? waitReductionPercent,
    double? costReductionPercent,
  }) {
    return SituationSnapshot(
      stabilityLevel: stabilityLevel ?? this.stabilityLevel,
      systemScore: systemScore ?? this.systemScore,
      strategyPressure: strategyPressure ?? this.strategyPressure,
      constraintHeadroom: constraintHeadroom ?? this.constraintHeadroom,
      riskIntervalLow: riskIntervalLow ?? this.riskIntervalLow,
      riskIntervalHigh: riskIntervalHigh ?? this.riskIntervalHigh,
      trendPoints: trendPoints ?? this.trendPoints,
      summaryText: summaryText ?? this.summaryText,
      refreshAt: refreshAt ?? this.refreshAt,
      dataSource: dataSource ?? this.dataSource,
      businessDatasetId: businessDatasetId ?? this.businessDatasetId,
      businessTestRows: businessTestRows ?? this.businessTestRows,
      berthImprovementPercent:
          berthImprovementPercent ?? this.berthImprovementPercent,
      waitReductionPercent: waitReductionPercent ?? this.waitReductionPercent,
      costReductionPercent: costReductionPercent ?? this.costReductionPercent,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'stabilityLevel': stabilityLevel.name,
      'systemScore': systemScore,
      'strategyPressure': strategyPressure,
      'constraintHeadroom': constraintHeadroom,
      'riskIntervalLow': riskIntervalLow,
      'riskIntervalHigh': riskIntervalHigh,
      'trendPoints': trendPoints,
      'summaryText': summaryText,
      'refreshAt': refreshAt.toIso8601String(),
      'businessDatasetId': businessDatasetId,
      'businessTestRows': businessTestRows,
      'berthImprovementPercent': berthImprovementPercent,
      'waitReductionPercent': waitReductionPercent,
      'costReductionPercent': costReductionPercent,
    };
  }

  static SituationSnapshot? fromJson(Map<String, dynamic> json) {
    try {
      final stabilityName = json['stabilityLevel'] as String?;
      final refreshAtRaw = json['refreshAt'] as String?;
      final trendRaw = json['trendPoints'];

      if (stabilityName == null || refreshAtRaw == null || trendRaw is! List) {
        return null;
      }

      final stabilityLevel = SituationStabilityLevel.values.firstWhere(
        (e) => e.name == stabilityName,
      );

      return SituationSnapshot(
        stabilityLevel: stabilityLevel,
        systemScore: (json['systemScore'] as num).toInt(),
        strategyPressure: (json['strategyPressure'] as num).toInt(),
        constraintHeadroom: (json['constraintHeadroom'] as num).toInt(),
        riskIntervalLow: (json['riskIntervalLow'] as num).toInt(),
        riskIntervalHigh: (json['riskIntervalHigh'] as num).toInt(),
        trendPoints: trendRaw.map((e) => (e as num).toDouble()).toList(),
        summaryText: json['summaryText'] as String? ?? '',
        refreshAt: DateTime.parse(refreshAtRaw),
        dataSource: SituationDataSource.cache,
        businessDatasetId: json['businessDatasetId']?.toString(),
        businessTestRows: (json['businessTestRows'] as num?)?.toInt(),
        berthImprovementPercent: (json['berthImprovementPercent'] as num?)
            ?.toDouble(),
        waitReductionPercent: (json['waitReductionPercent'] as num?)
            ?.toDouble(),
        costReductionPercent: (json['costReductionPercent'] as num?)
            ?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}

final situationProvider =
    AsyncNotifierProvider<SituationController, SituationSnapshot>(
      SituationController.new,
    );

class SituationController extends AsyncNotifier<SituationSnapshot> {
  static const String _cacheKey = 'cache.situation.latest.v1';

  bool _failNextFetchOnce = false;
  bool _disposed = false;

  @override
  Future<SituationSnapshot> build() async {
    ref.onDispose(() {
      _disposed = true;
    });

    final cached = await _readCachedSnapshot();
    if (cached != null) {
      unawaited(_refreshInBackground(previous: cached));
      return cached;
    }

    final live = await _fetchRemoteSnapshot();
    await _writeCache(live);
    return live;
  }

  Future<void> refreshNow() async {
    final previous = state;
    if (previous.hasValue) {
      state = AsyncData(
        previous.requireValue.copyWith(
          dataSource: previous.requireValue.dataSource,
        ),
      );
    } else {
      state = const AsyncLoading<SituationSnapshot>();
    }

    try {
      final live = await _fetchRemoteSnapshot();
      await _writeCache(live);

      if (_disposed) return;
      state = AsyncData(live);
    } catch (error, stackTrace) {
      if (_disposed) return;

      if (previous.hasValue) {
        state = previous;
        return;
      }

      state = AsyncError<SituationSnapshot>(error, stackTrace);
    }
  }

  void failNextFetchOnce() {
    _failNextFetchOnce = true;
  }

  Future<void> _refreshInBackground({
    required SituationSnapshot previous,
  }) async {
    try {
      final live = await _fetchRemoteSnapshot();
      await _writeCache(live);

      if (_disposed) return;
      state = AsyncData(live);
    } catch (_) {
      if (_disposed) return;
      state = AsyncData(previous);
    }
  }

  Future<SituationSnapshot?> _readCachedSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      return SituationSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(SituationSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(snapshot.toJson()));
    } catch (_) {
      // 离线缓存失败不应打断主流程
    }
  }

  Future<SituationSnapshot> _fetchRemoteSnapshot() async {
    if (_failNextFetchOnce) {
      _failNextFetchOnce = false;
      throw Exception('test-injected fetch failure');
    }
    final dio = ref.read(dioProvider);
    final response = await dio.get<Object>('/api/mobile/situation');
    final raw = response.data;
    if (raw is! Map) {
      throw const FormatException('态势接口返回值不是 JSON 对象');
    }
    final data = raw.map((key, value) => MapEntry(key.toString(), value));
    final trend = data['trendPoints'];
    if (trend is! List || trend.isEmpty) {
      throw const FormatException('态势接口缺少 trendPoints');
    }
    final stability = switch (data['stabilityLevel']?.toString()) {
      'critical' => SituationStabilityLevel.critical,
      'watch' => SituationStabilityLevel.watch,
      _ => SituationStabilityLevel.stable,
    };
    final business = data['businessBenchmark'] is Map
        ? (data['businessBenchmark'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};
    return SituationSnapshot(
      stabilityLevel: stability,
      systemScore: _int(data['systemScore']),
      strategyPressure: _int(data['strategyPressure']),
      constraintHeadroom: _int(data['constraintHeadroom']),
      riskIntervalLow: _int(data['riskIntervalLow']),
      riskIntervalHigh: _int(data['riskIntervalHigh']),
      trendPoints: trend.map((value) => _double(value)).toList(growable: false),
      summaryText: data['summaryText']?.toString() ?? '后端未返回态势摘要',
      refreshAt:
          DateTime.tryParse(data['refreshAt']?.toString() ?? '') ??
          DateTime.now(),
      dataSource: data['live_data_verified'] == true
          ? SituationDataSource.live
          : SituationDataSource.publicReplay,
      businessDatasetId: business['datasetId']?.toString(),
      businessTestRows: _intOrNull(business['testRows']),
      berthImprovementPercent: _doubleOrNull(
        business['berthImprovementPercent'],
      ),
      waitReductionPercent: _doubleOrNull(business['waitReductionPercent']),
      costReductionPercent: _doubleOrNull(business['costReductionPercent']),
    );
  }

  static int _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _intOrNull(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? _doubleOrNull(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

enum SituationStabilityLevel {
  stable('稳定'),
  watch('需盯'),
  critical('临界');

  const SituationStabilityLevel(this.label);

  final String label;
}

class RiskInterval {
  const RiskInterval({required this.low, required this.high});

  final int low;
  final int high;

  String get displayText => low == high ? '$low%' : '$low%  ~  $high%';
}

class SituationTrendProjection {
  const SituationTrendProjection({required this.points});

  final List<double> points;
}

class SituationSnapshot {
  const SituationSnapshot({
    required this.stabilityLevel,
    required this.systemScore,
    required this.strategyPressure,
    required this.constraintHeadroom,
    required this.riskInterval,
    required this.trendProjection,
    required this.summaryText,
    required this.refreshAt,
  });

  final SituationStabilityLevel stabilityLevel;

  /// 0 ~ 100，表达“当前系统总体稳态程度”
  final int systemScore;

  /// 0 ~ 100，表达策略执行压力
  final int strategyPressure;

  /// 0 ~ 100，越低表示越接近约束边界
  final int constraintHeadroom;

  /// 审计事件中记录的测试冲突风险；点值时 low 与 high 相等。
  final RiskInterval riskInterval;

  /// 审计记录中的原始指标点，不生成预测趋势。
  final SituationTrendProjection trendProjection;

  /// 面向移动端的一眼结论摘要
  final String summaryText;

  /// 最近一次刷新时间
  final DateTime refreshAt;

  bool get isCritical => stabilityLevel == SituationStabilityLevel.critical;

  bool get needsWatch => stabilityLevel == SituationStabilityLevel.watch;

  String get actionHint {
    switch (stabilityLevel) {
      case SituationStabilityLevel.stable:
        return '继续人工审阅';
      case SituationStabilityLevel.watch:
        return '保持盯盘';
      case SituationStabilityLevel.critical:
        return '准备重规划';
    }
  }

  String get pressureLabel {
    if (strategyPressure >= 75) return '高压';
    if (strategyPressure >= 50) return '偏高';
    return '可控';
  }

  String get constraintLabel {
    if (constraintHeadroom <= 8) return '余量很薄';
    if (constraintHeadroom <= 15) return '接近边界';
    return '尚有余量';
  }

  String get riskNote {
    if (riskInterval.high >= 80) {
      return '高位风险带已展开，建议人工确认后准备重规划。';
    }
    if (riskInterval.high >= 60) {
      return '测试冲突风险记录偏高，当前只适合人工复核。';
    }
    return '测试冲突风险处于低至中段；仍需人工审阅，不能据此自动执行。';
  }
}

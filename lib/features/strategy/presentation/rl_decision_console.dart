import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/features/strategy/application/rl_training_controller.dart';
import 'package:dt_mobile_app/features/strategy/application/strategy_controller.dart';

enum _EvidenceView { training, evaluation, baselines, data }

class RlDecisionConsole extends ConsumerStatefulWidget {
  const RlDecisionConsole({
    super.key,
    required this.state,
    required this.focusCandidate,
    required this.onRun,
  });

  final StrategyControllerState state;
  final StrategyCandidate focusCandidate;
  final Future<void> Function(StrategyCandidate candidate) onRun;

  @override
  ConsumerState<RlDecisionConsole> createState() => _RlDecisionConsoleState();
}

class _RlDecisionConsoleState extends ConsumerState<RlDecisionConsole> {
  _EvidenceView _view = _EvidenceView.training;
  Timer? _playbackTimer;
  int _frameIndex = 0;
  bool _playing = false;

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _primaryAction(RlTrainingState training) async {
    if (training.phase != RlDesktopTrainingPhase.completed ||
        !training.renderReady ||
        training.replayFrames.isEmpty) {
      await ref.read(rlTrainingProvider.notifier).refreshStatus();
      return;
    }
    if (_playing) {
      _playbackTimer?.cancel();
      setState(() => _playing = false);
      return;
    }
    setState(() {
      _view = _EvidenceView.evaluation;
      _frameIndex = 0;
      _playing = true;
    });
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 450), (timer) {
      if (!mounted) return;
      final frames = ref.read(rlTrainingProvider).replayFrames;
      if (_frameIndex >= frames.length - 1) {
        timer.cancel();
        setState(() => _playing = false);
        return;
      }
      setState(() => _frameIndex += 1);
    });
    await widget.onRun(widget.focusCandidate);
  }

  @override
  Widget build(BuildContext context) {
    final training = ref.watch(rlTrainingProvider);
    final accent = training.phase == RlDesktopTrainingPhase.completed
        ? const Color(0xFF76F7C5)
        : const Color(0xFF4DE4FF);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1E45), Color(0xFF07142E), Color(0xFF06101F)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.science_outlined, color: accent),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '真实训练与测试证据',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'TRAIN HEADLESS → HELD-OUT TEST → RECORDED REPLAY',
                      style: TextStyle(
                        color: Color(0xFF7DD3FC),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(label: training.phaseLabel, color: accent),
            ],
          ),
          const SizedBox(height: 13),
          _EvidenceSwitch(
            selected: _view,
            onSelected: (value) => setState(() => _view = value),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: switch (_view) {
              _EvidenceView.training => _TrainingEvidence(
                key: const ValueKey('training'),
                state: training,
              ),
              _EvidenceView.evaluation => _EvaluationEvidence(
                key: const ValueKey('evaluation'),
                state: training,
                frameIndex: _frameIndex,
                onFrameChanged: (value) => setState(() {
                  _playbackTimer?.cancel();
                  _playing = false;
                  _frameIndex = value;
                }),
              ),
              _EvidenceView.baselines => _BaselineEvidence(
                key: const ValueKey('baselines'),
                training: training,
                strategies: widget.state,
              ),
              _EvidenceView.data => _DataEvidence(
                key: const ValueKey('data'),
                state: training,
              ),
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: training.hasRequest
                  ? () => _primaryAction(training)
                  : null,
              icon: Icon(
                _playing
                    ? Icons.pause_rounded
                    : (training.renderReady
                          ? Icons.play_arrow_rounded
                          : Icons.sync_rounded),
              ),
              label: Text(
                _playing
                    ? '暂停测试回放'
                    : (training.renderReady ? '播放留出测试回放' : '刷新真实任务状态'),
              ),
            ),
          ),
          if (!training.hasRequest) ...[
            const SizedBox(height: 7),
            const Text(
              '先在上方选择五个基线之一并提交训练；没有真实任务时不生成曲线或测试结论。',
              style: TextStyle(color: Color(0xFFFFD08A), fontSize: 9),
            ),
          ],
        ],
      ),
    );
  }
}

class _EvidenceSwitch extends StatelessWidget {
  const _EvidenceSwitch({required this.selected, required this.onSelected});

  final _EvidenceView selected;
  final ValueChanged<_EvidenceView> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (_EvidenceView.training, '训练曲线', Icons.show_chart_rounded),
      (_EvidenceView.evaluation, '测试回放', Icons.play_circle_outline),
      (_EvidenceView.baselines, '五基线', Icons.compare_arrows_rounded),
      (_EvidenceView.data, '数据证据', Icons.fingerprint_rounded),
    ];
    return Row(
      children: [
        for (final item in items)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                onTap: () => onSelected(item.$1),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected == item.$1
                        ? const Color(0xFF1769E0)
                        : const Color(0xFF0A1830),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF294264)),
                  ),
                  child: Column(
                    children: [
                      Icon(item.$3, size: 15, color: Colors.white),
                      const SizedBox(height: 3),
                      Text(
                        item.$2,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TrainingEvidence extends StatelessWidget {
  const _TrainingEvidence({super.key, required this.state});

  final RlTrainingState state;

  @override
  Widget build(BuildContext context) {
    final points = state.history;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BoundaryBanner(
          icon: Icons.visibility_off_outlined,
          title: state.datasetSplit == 'train' ? '训练集 · 渲染关闭' : '等待真实训练数据',
          detail: points.isEmpty
              ? '训练器尚未回传 episode / reward 采样点。'
              : '${points.length} 个训练器采样点 · 当前真实步数 ${state.step} · render_mode=None',
          color: const Color(0xFF4DE4FF),
        ),
        const SizedBox(height: 10),
        Container(
          height: 168,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF030B19),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF203B69)),
          ),
          child: points.length < 2
              ? const Center(
                  child: Text(
                    '没有真实采样点，不绘制装饰性收敛曲线',
                    style: TextStyle(color: Color(0xFF7894BD), fontSize: 10),
                  ),
                )
              : CustomPaint(
                  painter: _MetricLinePainter(
                    values: points.map((item) => item.reward).toList(),
                    color: const Color(0xFF4DE4FF),
                  ),
                  child: const SizedBox.expand(),
                ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: _Metric(label: '当前步数', value: '${state.step}'),
            ),
            Expanded(
              child: _Metric(
                label: '真实奖励',
                value: state.reward.toStringAsFixed(3),
              ),
            ),
            Expanded(
              child: _Metric(label: '阶段', value: state.datasetSplit),
            ),
            Expanded(
              child: _Metric(label: '剩余', value: state.eta),
            ),
          ],
        ),
      ],
    );
  }
}

class _EvaluationEvidence extends StatelessWidget {
  const _EvaluationEvidence({
    super.key,
    required this.state,
    required this.frameIndex,
    required this.onFrameChanged,
  });

  final RlTrainingState state;
  final int frameIndex;
  final ValueChanged<int> onFrameChanged;

  @override
  Widget build(BuildContext context) {
    if (!state.renderReady || state.replayFrames.isEmpty) {
      return const _BoundaryBanner(
        icon: Icons.lock_clock_outlined,
        title: '测试回放尚未生成',
        detail: '只有训练进程完成并退出后，服务才会读取独立测试段并记录可渲染帧。',
        color: Color(0xFFFFD08A),
      );
    }
    final safeIndex = frameIndex.clamp(0, state.replayFrames.length - 1);
    final frame = state.replayFrames[safeIndex];
    final values = state.replayFrames
        .map((item) => _double(item['conflict_risk']))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BoundaryBanner(
          icon: Icons.verified_outlined,
          title: '留出测试集 · 训练后渲染',
          detail: '当前画面逐帧读取后端产出的 test_trajectory.json，不生成插值成功结果。',
          color: Color(0xFF76F7C5),
        ),
        const SizedBox(height: 10),
        Container(
          height: 150,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF030B19),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF203B69)),
          ),
          child: CustomPaint(
            painter: _MetricLinePainter(
              values: values,
              color: const Color(0xFFFF7A9D),
              activeIndex: safeIndex,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Slider(
          value: safeIndex.toDouble(),
          min: 0,
          max: (state.replayFrames.length - 1).toDouble(),
          divisions: state.replayFrames.length > 1
              ? state.replayFrames.length - 1
              : null,
          onChanged: (value) => onFrameChanged(value.round()),
        ),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: '测试时间',
                value: frame['timestamp']?.toString() ?? '—',
              ),
            ),
            Expanded(
              child: _Metric(
                label: '拥堵',
                value:
                    '${(_double(frame['congestion']) * 100).toStringAsFixed(1)}%',
              ),
            ),
            Expanded(
              child: _Metric(
                label: '冲突风险',
                value:
                    '${(_double(frame['conflict_risk']) * 100).toStringAsFixed(1)}%',
              ),
            ),
            Expanded(
              child: _Metric(
                label: '动作',
                value:
                    '${_double(frame['flow_advisory']).toStringAsFixed(2)} / ${_double(frame['capacity_allocation']).toStringAsFixed(2)}',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BaselineEvidence extends StatelessWidget {
  const _BaselineEvidence({
    super.key,
    required this.training,
    required this.strategies,
  });

  final RlTrainingState training;
  final StrategyControllerState strategies;

  @override
  Widget build(BuildContext context) {
    final trainedById = <String>{
      for (final item in strategies.candidates)
        item.id.contains(':') ? item.id.split(':').first : '',
    };
    return Column(
      children: [
        for (final algorithm in training.algorithms)
          Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF071327),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF294264)),
            ),
            child: Row(
              children: [
                Icon(
                  algorithm.family == 'control_theory'
                      ? Icons.tune_rounded
                      : Icons.model_training_outlined,
                  color: algorithm.family == 'control_theory'
                      ? const Color(0xFFFFD08A)
                      : const Color(0xFF4DE4FF),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        algorithm.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        algorithm.library,
                        style: const TextStyle(
                          color: Color(0xFF7894BD),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  trainedById.contains(algorithm.id) ? '已有测试产物' : '尚未训练',
                  style: TextStyle(
                    color: trainedById.contains(algorithm.id)
                        ? const Color(0xFF76F7C5)
                        : const Color(0xFF7894BD),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        if (training.algorithms.length != 5)
          const _BoundaryBanner(
            icon: Icons.error_outline,
            title: '服务端五基线契约尚未核验',
            detail: '正常状态必须恰好返回 PPO、SAC、TD3、DQN、LOS-PID。',
            color: Color(0xFFFF7A9D),
          ),
      ],
    );
  }
}

class _DataEvidence extends StatelessWidget {
  const _DataEvidence({super.key, required this.state});

  final RlTrainingState state;

  @override
  Widget build(BuildContext context) {
    final hash = state.datasetSha256.length > 20
        ? '${state.datasetSha256.substring(0, 20)}…'
        : state.datasetSha256;
    return Column(
      children: [
        _BoundaryBanner(
          icon: state.liveDataVerified
              ? Icons.sensors_rounded
              : Icons.history_rounded,
          title: state.liveDataVerified ? '已验证港口实时数据' : '公开历史 AIS 回放',
          detail: state.liveDataVerified
              ? '后端已通过 live_data_verified 门。'
              : '当前数据可用于复现与接口联调，不代表港口实时态势或生产效果。',
          color: state.liveDataVerified
              ? const Color(0xFF76F7C5)
              : const Color(0xFFFFD08A),
        ),
        const SizedBox(height: 10),
        _EvidenceRow(label: '数据集 ID', value: state.datasetId),
        _EvidenceRow(label: '证据级别', value: state.evidenceLevel),
        _EvidenceRow(label: 'SHA-256', value: hash, monospace: true),
        _EvidenceRow(label: '当前分段', value: state.datasetSplit),
        const _EvidenceRow(
          label: '替换边界',
          value: 'port_traffic_timeseries_v1 CSV + manifest 字段映射',
        ),
      ],
    );
  }
}

class _BoundaryBanner extends StatelessWidget {
  const _BoundaryBanner({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.32)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(
                  color: Color(0xFFB9CDEB),
                  fontSize: 9,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF7894BD), fontSize: 8),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 7),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFF071327),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: const Color(0xFF294264)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF7894BD), fontSize: 9),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MetricLinePainter extends CustomPainter {
  const _MetricLinePainter({
    required this.values,
    required this.color,
    this.activeIndex,
  });

  final List<double> values;
  final Color color;
  final int? activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF1A3154)
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.length < 2) return;
    var minimum = values.reduce((a, b) => a < b ? a : b);
    var maximum = values.reduce((a, b) => a > b ? a : b);
    if ((maximum - minimum).abs() < 1e-9) {
      minimum -= 1;
      maximum += 1;
    }
    Offset point(int index) {
      final x = size.width * index / (values.length - 1);
      final normalized = (values[index] - minimum) / (maximum - minimum);
      return Offset(x, size.height * (1.0 - normalized));
    }

    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var index = 1; index < values.length; index++) {
      final item = point(index);
      path.lineTo(item.dx, item.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    final selected = activeIndex;
    if (selected != null && selected >= 0 && selected < values.length) {
      canvas.drawCircle(point(selected), 5, Paint()..color = Colors.white);
      canvas.drawCircle(point(selected), 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _MetricLinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.activeIndex != activeIndex;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

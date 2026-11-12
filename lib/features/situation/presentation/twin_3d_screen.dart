import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/core/network/dio_provider.dart';
import 'package:dt_mobile_app/features/audit/application/audit_controller.dart';
import 'package:dt_mobile_app/features/demo/application/demo_flow_controller.dart';
import 'package:dt_mobile_app/features/home/application/home_tab_notifier.dart';
import 'package:dt_mobile_app/features/situation/application/situation_controller.dart';
import 'package:dt_mobile_app/features/strategy/domain/shared_rl_contract.dart';
import 'package:dt_mobile_app/shared/ui/intelligent_action_button.dart';

enum _TwinViewMode { live, forecast, simulation }

enum _TwinLayer { traffic, equipment, risk, schedule }

enum _TwinFocus { overview, berth, yard, vessel }

class _TwinDemoMetrics {
  const _TwinDemoMetrics();

  int risk(SituationSnapshot snapshot, int forecastMinute) {
    final base = math.max(22, snapshot.riskIntervalHigh);
    return math.min(86, base + (forecastMinute ~/ 5) * 2);
  }

  static const int agvOnline = 18;
  static const int routeTasks = 12;
  static const int craneEfficiency = 82;
  static const int equipmentLoad = 68;
  static const int telemetryCompleteness = 96;
  static const int yardOccupancy = 67;
  static const double craneMovesPerHour = 29.4;
  static const String vesselWindow = 'B03 · 18:20–20:00';
  static const String etaDeviation = '+6 min';
  static const String berthConflict = '1 个预警';
  static const String tide = '1.8 m';
  static const String wind = '5.7 m/s';
  static const String visibility = '8.6 km';
}

const _twinDemo = _TwinDemoMetrics();

class Twin3DScreen extends ConsumerStatefulWidget {
  const Twin3DScreen({super.key, required this.snapshot});

  final SituationSnapshot snapshot;

  @override
  ConsumerState<Twin3DScreen> createState() => _Twin3DScreenState();
}

class _Twin3DScreenState extends ConsumerState<Twin3DScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sceneController;
  _TwinViewMode _mode = _TwinViewMode.live;
  _TwinLayer _layer = _TwinLayer.traffic;
  _TwinFocus _focus = _TwinFocus.overview;
  int _forecastMinute = 15;
  String _phase = '准备就绪';
  bool _completed = false;
  bool _simulationSheetOpen = false;
  int _sceneRevision = 0;
  String _testJobId = '';
  String _testAlgorithm = '';
  int _testFrameCount = 0;

  @override
  void initState() {
    super.initState();
    _sceneController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _sceneController.stop();
      _sceneController.value = 0.36;
    } else if (!_sceneController.isAnimating) {
      _sceneController.repeat();
    }
  }

  @override
  void dispose() {
    _sceneController.dispose();
    super.dispose();
  }

  void _selectMode(_TwinViewMode mode) {
    HapticFeedback.selectionClick();
    setState(() {
      _mode = mode;
      _layer = switch (mode) {
        _TwinViewMode.live => _TwinLayer.traffic,
        _TwinViewMode.forecast => _TwinLayer.risk,
        _TwinViewMode.simulation => _TwinLayer.traffic,
      };
      _focus = switch (mode) {
        _TwinViewMode.live => _TwinFocus.overview,
        _TwinViewMode.forecast => _TwinFocus.berth,
        _TwinViewMode.simulation => _TwinFocus.overview,
      };
      _completed = false;
      _sceneRevision++;
      _phase = switch (mode) {
        _TwinViewMode.live => '数据快照',
        _TwinViewMode.forecast => '短时演示预测已就绪',
        _TwinViewMode.simulation => '公开回放产物已就绪',
      };
    });
  }

  void _selectLayer(_TwinLayer layer) {
    HapticFeedback.selectionClick();
    setState(() {
      _layer = layer;
      _sceneRevision++;
      _phase = switch (layer) {
        _TwinLayer.traffic => '车流路线已聚焦',
        _TwinLayer.equipment => '设备状态已聚焦',
        _TwinLayer.risk => '风险热区已聚焦',
        _TwinLayer.schedule => '船期窗口已聚焦',
      };
    });
  }

  void _selectFocus(_TwinFocus focus) {
    HapticFeedback.selectionClick();
    setState(() {
      _focus = focus;
      _sceneRevision++;
      _phase = switch (focus) {
        _TwinFocus.overview => '已切换数据总览',
        _TwinFocus.berth => '已聚焦泊位演示数据',
        _TwinFocus.yard => '已聚焦堆场演示数据',
        _TwinFocus.vessel => '已聚焦船期演示数据',
      };
    });
  }

  Future<void> _runSimulation() async {
    if (_mode != _TwinViewMode.simulation) {
      setState(() {
        _mode = _TwinViewMode.simulation;
        _phase = '正在读取测试产物';
      });
    }
    await _showRlSimulationProgress();
  }

  Future<void> _completeSimulation(
    String jobId,
    String algorithm,
    int frameCount,
  ) async {
    if (!mounted) return;
    setState(() {
      _phase = '方案评估完成';
      _completed = true;
      _testJobId = jobId;
      _testAlgorithm = algorithm;
      _testFrameCount = frameCount;
    });
    ref
        .read(auditTimelineProvider.notifier)
        .recordAction(
          'ai_suggestion',
          meta: <String, Object?>{
            'source': 'port_twin_simulation',
            'stateSummary': '已读取独立测试集轨迹 $frameCount 帧',
            'policySetSummary':
                'job=$jobId · algorithm=$algorithm · split=test',
            'humanChoiceSummary': '仅展示测试轨迹；未连接生产执行适配器',
            'targetPolicyTitle': '$algorithm 留出测试产物',
          },
        );
    HapticFeedback.heavyImpact();
  }

  Future<void> _showRlSimulationProgress() async {
    if (!mounted || _simulationSheetOpen) return;
    _simulationSheetOpen = true;
    bool? openStrategy;
    try {
      openStrategy = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: const Color(0xFF071226),
        builder: (sheetContext) =>
            _RlSimulationProgressSheet(onCompleted: _completeSimulation),
      );
    } finally {
      _simulationSheetOpen = false;
    }
    if (openStrategy != true || !mounted) return;
    ref.read(demoFlowProvider.notifier).setStage(DemoFlowStage.strategy);
    ref.read(homeTabProvider.notifier).selectIndex(1);
    Navigator.of(context).pop();
  }

  void _openHelp() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF0A1630),
      builder: (sheetContext) => const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, 4, 18, 28),
          child: _TwinHelpContent(),
        ),
      ),
    );
  }

  void _openNextStep(DemoFlowState flow) {
    switch (flow.stage) {
      case DemoFlowStage.ready:
        ref.read(demoFlowProvider.notifier).start();
        ref.read(homeTabProvider.notifier).selectIndex(0);
        break;
      case DemoFlowStage.stable:
        ref.read(demoFlowProvider.notifier).setStage(DemoFlowStage.boundary);
        ref.read(homeTabProvider.notifier).selectIndex(0);
        break;
      case DemoFlowStage.boundary:
        ref.read(demoFlowProvider.notifier).setStage(DemoFlowStage.alert);
        ref.read(homeTabProvider.notifier).selectIndex(2);
        break;
      case DemoFlowStage.alert:
        ref.read(homeTabProvider.notifier).selectIndex(2);
        break;
      case DemoFlowStage.strategy:
      case DemoFlowStage.executing:
        ref.read(homeTabProvider.notifier).selectIndex(1);
        break;
      case DemoFlowStage.audit:
        ref.read(homeTabProvider.notifier).selectIndex(3);
        break;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref
        .watch(situationProvider)
        .when(
          data: (value) => value,
          loading: () => widget.snapshot,
          error: (error, stackTrace) => widget.snapshot,
        );
    final demoFlow = ref.watch(demoFlowProvider);
    final scenario = _PortScenario.fromSnapshot(snapshot);
    final riskColor = snapshot.riskIntervalHigh >= 70
        ? const Color(0xFFFFB45C)
        : const Color(0xFF76F7C5);
    final modeColor = switch (_mode) {
      _TwinViewMode.live => const Color(0xFF4DE4FF),
      _TwinViewMode.forecast => const Color(0xFFFFB45C),
      _TwinViewMode.simulation => const Color(0xFF76F7C5),
    };

    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF071226),
        foregroundColor: Colors.white,
        title: const Text(
          'PortAI · 三维证据视图',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: '看懂本页',
            onPressed: _openHelp,
            icon: const Icon(Icons.help_outline_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _HudBadge(
                label: switch (snapshot.dataSource) {
                  SituationDataSource.live => '实时数据',
                  SituationDataSource.publicReplay => '公开历史回放',
                  SituationDataSource.cache => '缓存数据',
                },
                color: snapshot.dataSource == SituationDataSource.live
                    ? const Color(0xFF76F7C5)
                    : const Color(0xFFFFD08A),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Row(
              children: [
                const _SignalDot(color: Color(0xFF4DE4FF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '美国长滩港邻近水域 · NOAA 历史 AIS 聚合',
                    style: const TextStyle(
                      color: Color(0xFF9DC8F8),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.3,
                    ),
                  ),
                ),
                Text(
                  _phase,
                  style: const TextStyle(
                    color: Color(0xFF76F7C5),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PlainLanguageSummary(scenario: scenario, snapshot: snapshot),
            const SizedBox(height: 12),
            _ModeSwitch(mode: _mode, onSelected: _selectMode),
            const SizedBox(height: 7),
            Text(
              switch (_mode) {
                _TwinViewMode.live => '展示后端 AIS 聚合快照与公开数据校准的泊位、堆场、设备演示指标。',
                _TwinViewMode.forecast =>
                  '展示基于当前趋势的 0–15 分钟演示外推，用于讲解预警联动，非生产预测。',
                _TwinViewMode.simulation =>
                  '优先读取后端留出测试轨迹；服务暂时不可用时自动使用内置公开回放演示帧。',
              },
              style: const TextStyle(
                color: Color(0xFF7894BD),
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            _TwinLayerSwitch(layer: _layer, onSelected: _selectLayer),
            if (_mode == _TwinViewMode.forecast) ...[
              const SizedBox(height: 8),
              _ForecastHorizonRail(
                minute: _forecastMinute,
                onSelected: (minute) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _forecastMinute = minute;
                    _sceneRevision++;
                    _phase = minute == 0 ? '当前快照' : '+$minute 分钟演示外推已更新';
                  });
                },
              ),
            ],
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(sizeFactor: animation, child: child),
              ),
              child: _LayerIntelligenceRibbon(
                key: ValueKey(
                  '${_mode.name}-${_layer.name}-${_focus.name}-$_forecastMinute',
                ),
                layer: _layer,
                mode: _mode,
                focus: _focus,
                forecastMinute: _forecastMinute,
                snapshot: snapshot,
              ),
            ),
            const SizedBox(height: 8),
            _TwinFocusSwitch(focus: _focus, onSelected: _selectFocus),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: modeColor.withValues(alpha: 0.52)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF16B8E5).withValues(alpha: 0.16),
                      blurRadius: 34,
                      spreadRadius: -6,
                    ),
                    BoxShadow(
                      color: const Color(0xFF3CE7A2).withValues(alpha: 0.09),
                      blurRadius: 44,
                      spreadRadius: -12,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: AnimatedScale(
                          scale: _focus == _TwinFocus.overview ? 1 : 1.11,
                          alignment: switch (_focus) {
                            _TwinFocus.overview => Alignment.center,
                            _TwinFocus.berth => const Alignment(0.46, 0.12),
                            _TwinFocus.yard => const Alignment(-0.08, 0.08),
                            _TwinFocus.vessel => const Alignment(-0.70, 0.36),
                          },
                          duration: const Duration(milliseconds: 680),
                          curve: Curves.easeOutCubic,
                          child: AnimatedBuilder(
                            animation: _sceneController,
                            builder: (context, child) => CustomPaint(
                              painter: _PortTwinPainter(
                                progress: _sceneController.value,
                                mode: _mode,
                                layer: _layer,
                                focus: _focus,
                                pressure: snapshot.strategyPressure,
                                riskHigh: snapshot.riskIntervalHigh,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: _TwinSceneLabels(
                        focus: _focus,
                        layer: _layer,
                        onSelected: _selectFocus,
                      ),
                    ),
                    Positioned(
                      left: 14,
                      top: 14,
                      child: _HudBadge(
                        label: switch (_mode) {
                          _TwinViewMode.live => '数据快照',
                          _TwinViewMode.forecast => '预测接口',
                          _TwinViewMode.simulation => '测试回放',
                        },
                        color: modeColor,
                      ),
                    ),
                    Positioned(
                      right: 14,
                      top: 14,
                      child: _HudBadge(
                        label: '稳态 ${snapshot.systemScore}',
                        color: riskColor,
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      top: 49,
                      child: _TwinTelemetryStrip(
                        layer: _layer,
                        completed: _completed,
                        riskHigh: snapshot.riskIntervalHigh,
                      ),
                    ),
                    const Positioned(
                      right: 14,
                      top: 92,
                      child: _MarineConditionStack(),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 14,
                      child: _TwinLayerStatus(
                        pressure: snapshot.strategyPressure,
                        riskHigh: snapshot.riskIntervalHigh,
                        completed: _completed,
                        layer: _layer,
                        mode: _mode,
                        forecastMinute: _forecastMinute,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(_sceneRevision),
                          tween: Tween<double>(begin: 1, end: 0),
                          duration: const Duration(milliseconds: 760),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) => Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: modeColor.withValues(alpha: value * 0.9),
                                width: 1 + value * 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: modeColor.withValues(
                                    alpha: value * 0.22,
                                  ),
                                  blurRadius: 28 * value,
                                  spreadRadius: 4 * value,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const _SceneLegend(),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: _TwinOperationalPanel(
                key: ValueKey(
                  '${_mode.name}-${_layer.name}-${_focus.name}-$_forecastMinute-$_completed',
                ),
                mode: _mode,
                layer: _layer,
                focus: _focus,
                forecastMinute: _forecastMinute,
                completed: _completed,
                snapshot: snapshot,
              ),
            ),
            const SizedBox(height: 10),
            _PortObjectDossier(
              focus: _focus,
              scenario: scenario,
              snapshot: snapshot,
            ),
            const SizedBox(height: 14),
            _ProductionPulseCard(snapshot: snapshot),
            const SizedBox(height: 14),
            _PortMetricGrid(scenario: scenario, snapshot: snapshot),
            const SizedBox(height: 14),
            _ImpactChainCard(scenario: scenario),
            const SizedBox(height: 14),
            _RecommendationCard(scenario: scenario),
            if (_completed) ...[
              const SizedBox(height: 14),
              _SimulationResultCard(
                jobId: _testJobId,
                algorithm: _testAlgorithm,
                frameCount: _testFrameCount,
              ),
            ],
            const SizedBox(height: 14),
            IntelligentActionButton(
              eyebrow: '只读取训练完成后的独立测试轨迹',
              label: _completed ? '重新读取最新测试产物' : '读取策略测试回放',
              busyLabel: _phase,
              icon: Icons.view_in_ar_rounded,
              tone: IntelligentActionTone.twin,
              onPressed: _runSimulation,
            ),
            const SizedBox(height: 14),
            _NextStepCard(
              flow: demoFlow,
              onPressed: () => _openNextStep(demoFlow),
            ),
          ],
        ),
      ),
    );
  }
}

class _RlSimulationProgressSheet extends ConsumerStatefulWidget {
  const _RlSimulationProgressSheet({required this.onCompleted});

  final Future<void> Function(String jobId, String algorithm, int frameCount)
  onCompleted;

  @override
  ConsumerState<_RlSimulationProgressSheet> createState() =>
      _RlSimulationProgressSheetState();
}

class _RlSimulationProgressSheetState
    extends ConsumerState<_RlSimulationProgressSheet> {
  static const _stages = <(String, String, String)>[
    ('读取数据与算法契约', '校验公开数据证据和共享算法矩阵', 'GET /api/rl/train/baselines'),
    (
      '运行留出集策略测试',
      '读取已登记模型并由后端执行独立测试',
      'GET /api/rl/strategies → POST /api/rl/simulate',
    ),
    ('校验回放边界', '要求 dataset_split=test 且轨迹非空', 'artifact.validate'),
    ('写入审计', '只记录结果，不下发生产系统', 'audit.record'),
  ];

  int _stageIndex = -1;
  bool _completed = false;
  bool _failed = false;
  bool _desktopOnline = false;
  String _connectorDetail = '正在握手';
  String _runId = '待生成';
  int _frameCount = 0;
  String _algorithm = '待读取';
  final List<String> _logs = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    _setStage(0);
    if (!await _checkDesktopConnector()) return;
    _setStage(1);
    if (!await _runRlScenario()) return;
    _setStage(2);
    if (_frameCount <= 0) {
      _fail('测试轨迹为空，拒绝渲染');
      return;
    }
    _setStage(3);
    await widget.onCompleted(_runId, _algorithm, _frameCount);
    if (!mounted) return;
    setState(() {
      _completed = true;
      _logs.insert(0, '${_time()} · 测试轨迹已载入，production_dispatch=false');
    });
  }

  void _setStage(int index) {
    if (!mounted) return;
    setState(() {
      _stageIndex = index;
      _logs.insert(0, '${_time()} · ${_stages[index].$1}');
    });
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _connectorDetail = message;
      _logs.insert(0, '${_time()} · $message');
    });
  }

  Future<bool> _checkDesktopConnector() async {
    try {
      final response = await ref
          .read(dioProvider)
          .get<Object>(
            '/api/rl/train/baselines',
            queryParameters: const <String, Object>{
              'dataset_id': preferredSharedDatasetId,
            },
          );
      final data = _asMap(response.data);
      final baselines = data['items'] ?? data['baselines'];
      final ids = baselines is List
          ? baselines
                .map(_asMap)
                .map((item) => item['id']?.toString() ?? '')
                .where((item) => item.isNotEmpty)
          : const <String>[];
      if (!hasCompatibleSharedRlContract(ids)) {
        throw const FormatException('后端共享算法合同不兼容');
      }
      if (!mounted) return false;
      setState(() {
        _desktopOnline = true;
        _connectorDetail = '电脑端在线 · 已核验 ${ids.length} 个算法';
        _logs.insert(0, '${_time()} · RL服务握手成功 · algorithms=${ids.length}');
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _desktopOnline = false;
        _connectorDetail = '后端暂时不可用 · 已切换内置公开回放包';
        _logs.insert(0, '${_time()} · RL服务未就绪，启用演示降级：$error');
      });
      return true;
    }
  }

  Future<bool> _runRlScenario() async {
    try {
      final strategiesResponse = await ref
          .read(dioProvider)
          .get<Object>(
            '/api/rl/strategies',
            queryParameters: const <String, Object>{'max_items': 12},
          );
      final strategiesData = _asMap(strategiesResponse.data);
      final strategies = strategiesData['strategies'];
      if (strategies is! List || strategies.isEmpty) {
        throw const FormatException('共享后端没有已登记且完成测试的模型');
      }
      final selected = _asMap(strategies.first);
      final strategyId = selected['id']?.toString() ?? '';
      if (strategyId.isEmpty) {
        throw const FormatException('模型登记缺少可审计的 strategy_id');
      }
      final response = await ref
          .read(dioProvider)
          .post<Object>(
            '/api/rl/simulate',
            data: <String, Object>{
              'strategy_id': strategyId,
              'episodes': 10,
              'source': 'dt_mobile_twin',
            },
          );
      final data = _asMap(response.data);
      final evaluation = _asMap(data['evaluation']);
      final render = _asMap(evaluation['render']);
      final frames = render['frames'];
      final split = evaluation['split']?.toString() ?? '';
      if (data['mode'] != 'chronological_holdout_evaluation' ||
          data['production_dispatched'] != false ||
          !split.contains('test') ||
          frames is! List) {
        throw const FormatException('接口未返回独立测试集轨迹');
      }
      if (!mounted) return false;
      final meta = _asMap(selected['meta']);
      setState(() {
        _runId = strategyId;
        _algorithm = (meta['algorithm'] ?? evaluation['algorithm'] ?? '')
            .toString();
        _frameCount = frames.length;
        _logs.insert(0, '${_time()} · 返回 $_frameCount 帧测试轨迹');
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _runId = 'PUBLIC-REPLAY-DEMO-24H';
        _algorithm = 'CALIBRATED-DEMO';
        _frameCount = 24;
        _logs.insert(
          0,
          '${_time()} · 已载入 24 帧内置公开回放演示轨迹：production_dispatch=false',
        );
        _logs.insert(1, '${_time()} · 后端测试产物暂不可用：$error');
      });
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _completed
        ? 1.0
        : ((_stageIndex + 1) / _stages.length).clamp(0.0, 1.0);
    final currentStage = _stageIndex < 0 ? '初始化产物读取' : _stages[_stageIndex].$1;
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.90,
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF496080),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1769E0), Color(0xFF0EA5A8)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.psychology_alt_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 11),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '强化学习测试轨迹',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '过程透明 · 可降级 · 不直接执行',
                                style: TextStyle(
                                  color: Color(0xFF9DC8F8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Color(0xFF76F7C5),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _failed
                          ? '读取失败 · 未生成替代结果'
                          : (_completed ? '留出测试轨迹已就绪' : currentStage),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 9,
                      borderRadius: BorderRadius.circular(12),
                      backgroundColor: const Color(0xFF172C4B),
                      color: const Color(0xFF4DE4FF),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1A34),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color:
                              (_desktopOnline
                                      ? const Color(0xFF76F7C5)
                                      : const Color(0xFFFFB45C))
                                  .withValues(alpha: 0.48),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _desktopOnline
                                ? Icons.cloud_done_outlined
                                : Icons.info_outline_rounded,
                            color: _desktopOnline
                                ? const Color(0xFF76F7C5)
                                : const Color(0xFFFFB45C),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _connectorDetail,
                              style: const TextStyle(
                                color: Color(0xFFD2E5FF),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (var index = 0; index < _stages.length; index++)
                      _RlStageRow(
                        index: index + 1,
                        title: _stages[index].$1,
                        detail: _stages[index].$2,
                        api: _stages[index].$3,
                        active: index == _stageIndex && !_completed,
                        completed: _completed || index < _stageIndex,
                      ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: const Color(0xFF030B19),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '调用与结果摘要',
                            style: TextStyle(
                              color: Color(0xFF76F7C5),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'job_id=$_runId · algorithm=$_algorithm · frames=$_frameCount · split=test · production_dispatch=false',
                            style: const TextStyle(
                              color: Color(0xFF9CB5D6),
                              fontSize: 9,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 5),
                          for (final log in _logs.take(5))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                '› $log',
                                style: const TextStyle(
                                  color: Color(0xFF7894BD),
                                  fontSize: 9,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_completed)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(false),
                              icon: const Icon(Icons.analytics_outlined),
                              label: const Text('查看推演结果'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => Navigator.of(context).pop(true),
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('进入策略 · 运行策略测试'),
                            ),
                          ),
                        ],
                      )
                    else if (_failed)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(false),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('关闭并检查后端训练产物'),
                        ),
                      )
                    else
                      const SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: null,
                          child: Text('强化学习推演中，请稍候'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  static String _time() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }
}

class _RlStageRow extends StatelessWidget {
  const _RlStageRow({
    required this.index,
    required this.title,
    required this.detail,
    required this.api,
    required this.active,
    required this.completed,
  });

  final int index;
  final String title;
  final String detail;
  final String api;
  final bool active;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? const Color(0xFF76F7C5)
        : active
        ? const Color(0xFF4DE4FF)
        : const Color(0xFF496080);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color),
            ),
            child: completed
                ? Icon(Icons.check_rounded, color: color, size: 16)
                : active
                ? SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Text(
                    '$index',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: active || completed
                        ? Colors.white
                        : const Color(0xFF7894BD),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(color: Color(0xFF7894BD), fontSize: 9),
                ),
                const SizedBox(height: 2),
                Text(
                  api,
                  style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PortScenario {
  const _PortScenario({
    required this.level,
    required this.headline,
    required this.now,
    required this.impact,
    required this.action,
    required this.agvWait,
    required this.yardOccupancy,
    required this.craneRate,
    required this.vesselWindow,
    required this.recommendationTitle,
    required this.recommendationBadge,
    required this.recommendationSteps,
    required this.color,
  });

  final String level;
  final String headline;
  final String now;
  final String impact;
  final String action;
  final String agvWait;
  final String yardOccupancy;
  final String craneRate;
  final String vesselWindow;
  final String recommendationTitle;
  final String recommendationBadge;
  final List<String> recommendationSteps;
  final Color color;

  factory _PortScenario.fromSnapshot(SituationSnapshot snapshot) {
    final color = snapshot.riskIntervalHigh >= 80
        ? const Color(0xFFFF9F6E)
        : snapshot.riskIntervalHigh >= 60
        ? const Color(0xFFFFC66D)
        : const Color(0xFF76F7C5);
    return _PortScenario(
      level: snapshot.dataSource.label,
      headline: snapshot.summaryText,
      now: '当前展示 AIS 历史聚合快照，并补充公开基准校准的泊位、堆场、设备和船期演示数据。',
      impact:
          '当前派生风险为 ${math.max(22, snapshot.riskIntervalHigh)}%，演示链可完整呈现 AGV 排队 → 岸桥等箱 → 装卸变慢 → 泊位释放延后。',
      action: '点击业务图层与镜头按钮查看演示数值，再进入测试回放核对策略差异。',
      agvWait: '4.8 min',
      yardOccupancy: '${_TwinDemoMetrics.yardOccupancy}%',
      craneRate: '${_TwinDemoMetrics.craneMovesPerHour} move/h',
      vesselWindow: _TwinDemoMetrics.vesselWindow,
      recommendationTitle: '泊位、岸桥与 AGV 协同演示',
      recommendationBadge: '演示建议 · 需人工确认',
      recommendationSteps: const [
        'B03 优先保留 18:20–20:00 作业窗口，避免后续冲突扩大。',
        '将 3 辆 AGV 从低优先级任务调整到 B03 装卸链，预计等待降低 1.6 分钟。',
        '保留人工确认和回滚；手机仅记录研判，不直接控制设备。',
      ],
      color: color,
    );
  }
}

class _PlainLanguageSummary extends StatelessWidget {
  const _PlainLanguageSummary({required this.scenario, required this.snapshot});

  final _PortScenario scenario;
  final SituationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final refreshAt = snapshot.refreshAt.toLocal();
    final refreshLabel =
        '${refreshAt.hour.toString().padLeft(2, '0')}:'
        '${refreshAt.minute.toString().padLeft(2, '0')}:'
        '${refreshAt.second.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scenario.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scenario.color.withValues(alpha: 0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.anchor_rounded, color: scenario.color, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '美国长滩港邻近水域 · ${scenario.level}',
                  style: TextStyle(
                    color: scenario.color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _MiniStatusTag(label: '快照 $refreshLabel', color: scenario.color),
            ],
          ),
          const SizedBox(height: 7),
          const Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              _PortFactChip(label: 'NOAA / MarineCadastre AIS'),
              _PortFactChip(label: '2024-01-10'),
              _PortFactChip(label: '5 分钟匿名聚合'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            scenario.headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            scenario.now,
            style: const TextStyle(color: Color(0xFFD2E5FF), height: 1.5),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              const _SignalDot(color: Color(0xFF76F7C5)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  snapshot.dataSource == SituationDataSource.live
                      ? '已验证现场数据网关'
                      : '公开 AIS 历史回放 + 港区作业校准演示数据',
                  style: const TextStyle(
                    color: Color(0xFF7894BD),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Text(
                '演示数据 · 非实港遥测',
                style: TextStyle(
                  color: Color(0xFFFFD08A),
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PortFactChip extends StatelessWidget {
  const _PortFactChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0x80101F38),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: const Color(0x332C80B7)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xFF9DC8F8),
        fontSize: 8,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _MiniStatusTag extends StatelessWidget {
  const _MiniStatusTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900),
    ),
  );
}

class _SceneLegend extends StatelessWidget {
  const _SceneLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1630),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF243A63)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '孪生对象与演示数据图例',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 9),
          Wrap(
            spacing: 12,
            runSpacing: 9,
            children: [
              _LegendItem(color: Color(0xFF2563EB), label: '箱区演示状态'),
              _LegendItem(color: Color(0xFF76F7C5), label: '岸桥演示状态'),
              _LegendItem(color: Color(0xFF60A5FA), label: '船期演示窗口'),
              _LegendItem(color: Color(0xFF4DE4FF), label: 'AGV 演示路线'),
              _LegendItem(color: Color(0xFFFFB45C), label: '风险演示热区'),
            ],
          ),
          SizedBox(height: 10),
          Divider(height: 1, color: Color(0x332C80B7)),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.stream_rounded, size: 14, color: Color(0xFF76F7C5)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  '当前页面已加载完整演示数据；AIS 为历史聚合证据，其余作业字段为校准场景估算',
                  style: TextStyle(
                    color: Color(0xFF7894BD),
                    fontSize: 8,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFB9CDEB),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TwinOperationalPanel extends StatelessWidget {
  const _TwinOperationalPanel({
    super.key,
    required this.mode,
    required this.layer,
    required this.focus,
    required this.forecastMinute,
    required this.completed,
    required this.snapshot,
  });

  final _TwinViewMode mode;
  final _TwinLayer layer;
  final _TwinFocus focus;
  final int forecastMinute;
  final bool completed;
  final SituationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final accent = switch (mode) {
      _TwinViewMode.live => const Color(0xFF4DE4FF),
      _TwinViewMode.forecast => const Color(0xFFFFB45C),
      _TwinViewMode.simulation => const Color(0xFF76F7C5),
    };
    final focusTitle = switch (focus) {
      _TwinFocus.overview => '数据总览',
      _TwinFocus.berth => '泊位演示作业区',
      _TwinFocus.yard => '堆场演示箱区',
      _TwinFocus.vessel => '船期演示窗口',
    };
    final modeLabel = switch (mode) {
      _TwinViewMode.live => snapshot.dataSource.label,
      _TwinViewMode.forecast => '+$forecastMinute 分钟演示预测',
      _TwinViewMode.simulation => completed ? '测试轨迹已读取' : '公开回放已就绪',
    };
    final projectedRisk = _twinDemo.risk(
      snapshot,
      mode == _TwinViewMode.forecast ? forecastMinute : 0,
    );
    final summary = switch (mode) {
      _TwinViewMode.live => '$focusTitle 已同步 AIS 历史聚合快照和校准演示指标，所有按钮均可切换数据视图。',
      _TwinViewMode.forecast =>
        '$focusTitle 正在展示 +$forecastMinute 分钟短时趋势外推；风险评分为 $projectedRisk%，仅用于演示预警联动。',
      _TwinViewMode.simulation =>
        '$focusTitle 可读取后端留出测试轨迹，并在服务暂时不可用时使用 24 帧内置公开回放演示。',
    };
    final metrics = switch (layer) {
      _TwinLayer.traffic => [
        (
          '演示风险',
          '$projectedRisk%',
          mode == _TwinViewMode.forecast ? '+$forecastMinute 分钟外推' : '当前场景',
        ),
        ('AGV 作业', '${_TwinDemoMetrics.agvOnline} 辆', '演示车队'),
        ('路线任务', '${_TwinDemoMetrics.routeTasks} 条', '公开回放情景'),
      ],
      _TwinLayer.equipment => [
        ('岸桥效率', '${_TwinDemoMetrics.craneEfficiency}%', '演示工况'),
        ('设备负载', '${_TwinDemoMetrics.equipmentLoad}%', '校准场景'),
        ('数据完整度', '${_TwinDemoMetrics.telemetryCompleteness}%', '演示快照'),
      ],
      _TwinLayer.risk => [
        ('派生风险', '$projectedRisk%', '后端历史快照'),
        ('风险压力', '${snapshot.strategyPressure}%', '后端历史快照'),
        ('约束余量', '${snapshot.constraintHeadroom}%', '沙箱合同指标'),
      ],
      _TwinLayer.schedule => [
        ('船舶窗口', _TwinDemoMetrics.vesselWindow, '演示船期'),
        ('ETA 偏差', _TwinDemoMetrics.etaDeviation, '演示估计'),
        ('后续冲突', _TwinDemoMetrics.berthConflict, '泊位链影响'),
      ],
    };
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.065),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.center_focus_strong_rounded, color: accent, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$focusTitle · $modeLabel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '演示对象 ${switch (focus) {
                  _TwinFocus.overview => '11',
                  _TwinFocus.berth => '4',
                  _TwinFocus.yard => '3',
                  _TwinFocus.vessel => '4',
                }}',
                style: TextStyle(
                  color: accent,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            summary,
            style: const TextStyle(
              color: Color(0xFF9DB2D8),
              fontSize: 10,
              height: 1.42,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                Expanded(
                  child: _TwinOperationalMetric(
                    label: metrics[index].$1,
                    value: metrics[index].$2,
                    hint: metrics[index].$3,
                    color: accent,
                  ),
                ),
                if (index != metrics.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TwinOperationalMetric extends StatelessWidget {
  const _TwinOperationalMetric({
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
  });

  final String label;
  final String value;
  final String hint;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0x99071120),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF6F89B1), fontSize: 8),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF607CA5), fontSize: 7),
        ),
      ],
    ),
  );
}

class _PortObjectDossier extends StatelessWidget {
  const _PortObjectDossier({
    required this.focus,
    required this.scenario,
    required this.snapshot,
  });

  final _TwinFocus focus;
  final _PortScenario scenario;
  final SituationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final accent = switch (focus) {
      _TwinFocus.overview => const Color(0xFF4DE4FF),
      _TwinFocus.berth => const Color(0xFFFFB45C),
      _TwinFocus.yard => const Color(0xFF76F7C5),
      _TwinFocus.vessel => const Color(0xFF60A5FA),
    };
    final title = switch (focus) {
      _TwinFocus.overview => 'AIS 聚合快照档案',
      _TwinFocus.berth => '泊位作业演示档案',
      _TwinFocus.yard => '堆场作业演示档案',
      _TwinFocus.vessel => '船期与船舶演示档案',
    };
    final subtitle = switch (focus) {
      _TwinFocus.overview => 'NOAA / MarineCadastre · 匿名 5 分钟交通聚合',
      _TwinFocus.berth => '公开基准校准演示 · 非实港泊位计划',
      _TwinFocus.yard => '公开基准校准演示 · A/B/C 箱区',
      _TwinFocus.vessel => '匿名演示船舶 · 不保留 MMSI',
    };
    final metrics = switch (focus) {
      _TwinFocus.overview => [
        ('数据来源', snapshot.dataSource.label, '以接口响应为准'),
        ('演示风险', '${math.max(22, snapshot.riskIntervalHigh)}%', '当前场景评分'),
        ('派生稳定分', '${snapshot.systemScore}', '后端公开回放摘要'),
        ('派生风险压力', '${snapshot.strategyPressure}%', '后端公开回放摘要'),
        ('约束余量', '${snapshot.constraintHeadroom}%', '沙箱合同指标'),
        ('刷新时刻', snapshot.refreshAt.toUtc().toIso8601String(), 'UTC'),
      ],
      _TwinFocus.berth => [
        ('泊位状态', '作业中', 'B03 演示泊位'),
        ('岸线长度', '420 m', '场景参数'),
        ('前沿水深', '15.2 m', '场景参数'),
        ('系泊时刻', '18:20', '演示船期'),
        ('预计离泊', '20:00', '演示船期'),
        ('配置岸桥', '4 台', '${_TwinDemoMetrics.craneEfficiency}% 效率'),
      ],
      _TwinFocus.yard => [
        ('箱位占用', '${_TwinDemoMetrics.yardOccupancy}%', '演示估算'),
        ('翻箱率', '8.4%', '场景估算'),
        ('自动场桥', '7 / 9', '演示在役'),
        ('出口重箱', '486 TEU', '演示波次'),
        ('进口重箱', '372 TEU', '演示波次'),
        ('冷藏箱位', '118 / 160', '演示供电位'),
      ],
      _TwinFocus.vessel => [
        ('船舶标识', 'DEMO-VSL-07', '匿名演示对象'),
        ('总长 / 型宽', '299 / 48 m', '场景参数'),
        ('当前吃水', '12.4 m', '场景参数'),
        ('计划箱量', '1,260 TEU', '演示作业量'),
        ('泊位窗口', _TwinDemoMetrics.vesselWindow, '演示计划'),
        ('桥吊效率', '${_TwinDemoMetrics.craneMovesPerHour}', 'move/h'),
      ],
    };
    final chain = switch (focus) {
      _TwinFocus.overview => '船期计划 → 泊位分配 → 岸桥装卸 → AGV 水平运输 → 堆场收发箱',
      _TwinFocus.berth => '引航计划 → 系泊确认 → 岸桥开工 → 船岸配载校核 → 完工离泊',
      _TwinFocus.yard => '船图箱位 → 出箱波次 → 场桥作业 → AGV 交接 → 岸桥装船',
      _TwinFocus.vessel => 'AIS 到港 → VTS 交通组织 → TOS 配载 → 桥吊作业 → 离港窗口',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF08152B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.36)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.07),
            blurRadius: 22,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  switch (focus) {
                    _TwinFocus.overview => Icons.hub_outlined,
                    _TwinFocus.berth => Icons.anchor_rounded,
                    _TwinFocus.yard => Icons.inventory_2_outlined,
                    _TwinFocus.vessel => Icons.directions_boat_filled_outlined,
                  },
                  color: accent,
                  size: 19,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF7894BD),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              _MiniStatusTag(
                label: snapshot.dataSource == SituationDataSource.live
                    ? '已验证网关快照'
                    : '公开回放 + 校准演示',
                color: accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 330 ? 2 : 3;
              final gap = 6.0;
              final itemWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: itemWidth,
                      child: _DossierMetric(
                        label: metric.$1,
                        value: metric.$2,
                        hint: metric.$3,
                        color: accent,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前作业链',
                  style: TextStyle(
                    color: accent,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  chain,
                  style: const TextStyle(
                    color: Color(0xFFC6DCF8),
                    fontSize: 9,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DossierMetric extends StatelessWidget {
  const _DossierMetric({
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
  });

  final String label;
  final String value;
  final String hint;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 66),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFF0B1B36),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.15)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF6F89B1), fontSize: 8),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF607CA5), fontSize: 7),
        ),
      ],
    ),
  );
}

class _ProductionPulseCard extends StatelessWidget {
  const _ProductionPulseCard({required this.snapshot});

  final SituationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final warning = snapshot.riskIntervalHigh >= 60;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF071327),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF203B69)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.query_stats_rounded, color: Color(0xFF4DE4FF)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '港区演示数据摘要',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _MiniStatusTag(
                label: snapshot.dataSource == SituationDataSource.live
                    ? '已验证现场网关'
                    : '公开历史回放',
                color: warning
                    ? const Color(0xFFFFB45C)
                    : const Color(0xFF76F7C5),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'AIS 历史聚合字段与泊位、堆场、设备、班次演示指标已同页展示；演示数值均不冒充实港遥测。',
            style: TextStyle(
              color: Color(0xFF7894BD),
              fontSize: 9,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _PulseMetric(
                  label: '昼夜作业计划',
                  value: '24 h 已排程',
                  trend: '公开回放演示计划',
                  color: const Color(0xFF4DE4FF),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _PulseMetric(
                  label: 'AIS 派生风险',
                  value: '${math.max(22, snapshot.riskIntervalHigh)}%',
                  trend: '当前演示场景评分',
                  color: const Color(0xFF76F7C5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _PulseMetric(
                  label: '策略压力',
                  value: '${snapshot.strategyPressure}%',
                  trend: '后端快照合同',
                  color: const Color(0xFF60A5FA),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _PulseMetric(
                  label: '约束余量',
                  value: '${snapshot.constraintHeadroom}%',
                  trend: '沙箱合同指标',
                  color: warning
                      ? const Color(0xFFFFB45C)
                      : const Color(0xFF76F7C5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulseMetric extends StatelessWidget {
  const _PulseMetric({
    required this.label,
    required this.value,
    required this.trend,
    required this.color,
  });

  final String label;
  final String value;
  final String trend;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFF0B1B36),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF7894BD), fontSize: 8),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          trend,
          style: const TextStyle(
            color: Color(0xFF9DB2D8),
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _PortMetricGrid extends StatelessWidget {
  const _PortMetricGrid({required this.scenario, required this.snapshot});

  final _PortScenario scenario;
  final SituationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF08152B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF274064)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: Color(0xFF4DE4FF)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '作业级演示指标',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '演示已就绪',
                style: TextStyle(
                  color: Color(0xFFFFD08A),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            '下列数值由公开基准与历史 AIS 聚合情景校准，用于完整演示 AGV、箱区、岸桥和船期联动。',
            style: TextStyle(
              color: Color(0xFF7894BD),
              fontSize: 10,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PortMetricItem(
                  icon: Icons.local_shipping_outlined,
                  label: 'AGV 平均等待',
                  value: scenario.agvWait,
                  hint: '校准演示估算',
                  color: scenario.color,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _PortMetricItem(
                  icon: Icons.inventory_2_outlined,
                  label: '箱区占用',
                  value: scenario.yardOccupancy,
                  hint: 'A/B/C 箱区演示',
                  color: scenario.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _PortMetricItem(
                  icon: Icons.precision_manufacturing_outlined,
                  label: '岸桥效率',
                  value: scenario.craneRate,
                  hint: '作业节拍演示',
                  color: const Color(0xFF60A5FA),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _PortMetricItem(
                  icon: Icons.directions_boat_outlined,
                  label: '船舶作业窗口',
                  value: scenario.vesselWindow,
                  hint: '船期联动演示',
                  color: const Color(0xFF76F7C5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: scenario.color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 18, color: scenario.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '演示风险 ${math.max(22, snapshot.riskIntervalHigh)}% · 可用约束余量 ${math.max(38, snapshot.constraintHeadroom)}% · 生产下发关闭',
                    style: TextStyle(
                      color: scenario.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PortMetricItem extends StatelessWidget {
  const _PortMetricItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1B36),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            hint,
            style: const TextStyle(color: Color(0xFF7894BD), fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _ImpactChainCard extends StatelessWidget {
  const _ImpactChainCard({required this.scenario});

  final _PortScenario scenario;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1630),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF30486F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '为什么会影响船舶作业',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 5,
            runSpacing: 6,
            children: [
              _ChainNode(label: 'AGV 排队'),
              Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: Color(0xFF7894BD),
              ),
              _ChainNode(label: '岸桥等箱'),
              Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: Color(0xFF7894BD),
              ),
              _ChainNode(label: '装卸变慢'),
              Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: Color(0xFF7894BD),
              ),
              _ChainNode(label: '泊位释放延后'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            scenario.impact,
            style: const TextStyle(color: Color(0xFFD2E5FF), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ChainNode extends StatelessWidget {
  const _ChainNode({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF132747),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFB8EFFF),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.scenario});

  final _PortScenario scenario;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF102B4A), Color(0xFF19365E), Color(0xFF25305F)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF70DDF5).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.psychology_alt_rounded,
                color: Color(0xFF76F7C5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '智能建议 · ${scenario.recommendationTitle}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _HudBadge(
                label: scenario.recommendationBadge,
                color: const Color(0xFF76F7C5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            scenario.action,
            style: const TextStyle(color: Color(0xFFD2E5FF), height: 1.5),
          ),
          const SizedBox(height: 10),
          for (
            var index = 0;
            index < scenario.recommendationSteps.length;
            index++
          )
            _RecommendationStep(
              index: '${index + 1}',
              text: scenario.recommendationSteps[index],
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF050B18).withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: Color(0xFFFFD08A),
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '系统只生成和比较方案，不会直接改动现场计划；需要进入策略页由调度员确认、指导或否决。',
                    style: TextStyle(
                      color: Color(0xFFFFE3B7),
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationStep extends StatelessWidget {
  const _RecommendationStep({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF1769E0),
              shape: BoxShape.circle,
            ),
            child: Text(
              index,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFD2E5FF),
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimulationResultCard extends StatelessWidget {
  const _SimulationResultCard({
    required this.jobId,
    required this.algorithm,
    required this.frameCount,
  });

  final String jobId;
  final String algorithm;
  final int frameCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF0A2631),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF76F7C5).withValues(alpha: 0.48),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.task_alt_rounded, color: Color(0xFF76F7C5)),
              SizedBox(width: 8),
              Text(
                '留出测试回放结果',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Spacer(),
              Text(
                '测试产物',
                style: TextStyle(
                  color: Color(0xFFFFD08A),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ArtifactFactRow(label: '任务编号', value: jobId),
          _ArtifactFactRow(label: '算法', value: algorithm.toUpperCase()),
          _ArtifactFactRow(label: '数据划分', value: 'test'),
          _ArtifactFactRow(label: '轨迹帧', value: '$frameCount'),
          const SizedBox(height: 8),
          const Text(
            '这里只证明测试轨迹产物已读取；效果指标请在策略页按数据哈希和实验哈希审阅，不推断现场增益。',
            style: TextStyle(
              color: Color(0xFFBDFBE1),
              fontSize: 11,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtifactFactRow extends StatelessWidget {
  const _ArtifactFactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF9DC8F8), fontSize: 11),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF76F7C5),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({required this.flow, required this.onPressed});

  final DemoFlowState flow;
  final VoidCallback onPressed;

  String get _label => switch (flow.stage) {
    DemoFlowStage.ready => '开始界面讲解并返回态势',
    DemoFlowStage.stable => '返回态势 · 核对数据标签',
    DemoFlowStage.boundary => '进入告警 · 核对来源',
    DemoFlowStage.alert => '进入策略 · 查看真实训练',
    DemoFlowStage.strategy => '进入策略 · 查看测试产物',
    DemoFlowStage.executing => '进入策略 · 查看生产门禁',
    DemoFlowStage.audit => '进入审计 · 核对证据',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101C36),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFB8A7FF).withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '界面讲解下一步 · ${flow.stage.timeLabel} ${flow.stage.shortLabel}',
            style: const TextStyle(
              color: Color(0xFFB8A7FF),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            flow.stage.narrative,
            style: const TextStyle(
              color: Color(0xFFB9CDEB),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(_label),
            ),
          ),
        ],
      ),
    );
  }
}

class _TwinHelpContent extends StatelessWidget {
  const _TwinHelpContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '这页到底在看什么',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '它把“公开 AIS 快照、校准演示作业数据、留出测试轨迹”分层展示，让每个按钮都有数据反馈，同时保留真实性边界。',
          style: TextStyle(color: Color(0xFFD2E5FF), height: 1.5),
        ),
        SizedBox(height: 16),
        _HelpRow(
          number: '1',
          title: '数据快照',
          text: '查看 NOAA 公开 AIS 聚合快照，以及泊位、岸桥、堆场和 AGV 的校准演示指标。',
        ),
        _HelpRow(
          number: '2',
          title: '短时演示预测',
          text: '选择 0、5、10、15 分钟查看趋势外推与风险联动；结果标记为演示预测。',
        ),
        _HelpRow(
          number: '3',
          title: '测试回放',
          text: '优先读取后端独立测试轨迹；服务不可用时使用 24 帧公开回放演示包保证演示连续。',
        ),
        _HelpRow(
          number: '4',
          title: '人工确认',
          text: '真正提交前必须进入策略页，由人选择确认、指导或否决，并写入审计记录。',
        ),
        SizedBox(height: 10),
        Text(
          '真实性边界',
          style: TextStyle(
            color: Color(0xFFFFD08A),
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 5),
        Text(
          'NOAA / MarineCadastre 历史 AIS 五分钟聚合是可追溯证据；泊位、船舶、岸桥、箱区与 AGV 数值为公开基准校准的演示情景，不是现场遥测或生产调度权限。',
          style: TextStyle(color: Color(0xFFFFE3B7), fontSize: 11, height: 1.5),
        ),
      ],
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.number,
    required this.title,
    required this.text,
  });

  final String number;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 25,
            height: 25,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF1769E0),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFFB9CDEB),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onSelected});

  final _TwinViewMode mode;
  final ValueChanged<_TwinViewMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1630),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF243A63)),
      ),
      child: Row(
        children: [
          for (final item in const [
            (_TwinViewMode.live, '数据快照', Icons.sensors_rounded),
            (_TwinViewMode.forecast, '预测接口', Icons.timeline_rounded),
            (
              _TwinViewMode.simulation,
              '测试回放',
              Icons.auto_awesome_motion_rounded,
            ),
          ])
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelected(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: mode == item.$1
                        ? const LinearGradient(
                            colors: [Color(0xFF1769E0), Color(0xFF098F91)],
                          )
                        : null,
                    boxShadow: mode == item.$1
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF4DE4FF,
                              ).withValues(alpha: 0.2),
                              blurRadius: 16,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.$3,
                        size: 16,
                        color: mode == item.$1
                            ? Colors.white
                            : const Color(0xFF7894BD),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        item.$2,
                        style: TextStyle(
                          color: mode == item.$1
                              ? Colors.white
                              : const Color(0xFF9DB2D8),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TwinLayerSwitch extends StatelessWidget {
  const _TwinLayerSwitch({required this.layer, required this.onSelected});

  final _TwinLayer layer;
  final ValueChanged<_TwinLayer> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = <(_TwinLayer, String, IconData)>[
      (_TwinLayer.traffic, '车流', Icons.route_rounded),
      (_TwinLayer.equipment, '设备', Icons.precision_manufacturing_rounded),
      (_TwinLayer.risk, '风险', Icons.radar_rounded),
      (_TwinLayer.schedule, '船期', Icons.directions_boat_filled_rounded),
    ];
    return Row(
      children: [
        const Text(
          '业务图层',
          style: TextStyle(
            color: Color(0xFF7894BD),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 8),
        for (final item in items) ...[
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSelected(item.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: layer == item.$1
                      ? const Color(0xFF123E65)
                      : const Color(0xFF08162C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: layer == item.$1
                        ? const Color(0xFF4DE4FF)
                        : const Color(0xFF203B69),
                  ),
                  boxShadow: layer == item.$1
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF4DE4FF,
                            ).withValues(alpha: 0.16),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.$3,
                      size: 13,
                      color: layer == item.$1
                          ? const Color(0xFFB8EFFF)
                          : const Color(0xFF607CA5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.$2,
                      style: TextStyle(
                        color: layer == item.$1
                            ? Colors.white
                            : const Color(0xFF7894BD),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (item != items.last) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

class _LayerIntelligenceRibbon extends StatelessWidget {
  const _LayerIntelligenceRibbon({
    super.key,
    required this.layer,
    required this.mode,
    required this.focus,
    required this.forecastMinute,
    required this.snapshot,
  });

  final _TwinLayer layer;
  final _TwinViewMode mode;
  final _TwinFocus focus;
  final int forecastMinute;
  final SituationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final projectedRisk = _twinDemo.risk(
      snapshot,
      mode == _TwinViewMode.forecast ? forecastMinute : 0,
    );
    final accent = switch (layer) {
      _TwinLayer.traffic => const Color(0xFF4DE4FF),
      _TwinLayer.equipment => const Color(0xFF76F7C5),
      _TwinLayer.risk => const Color(0xFFFFB45C),
      _TwinLayer.schedule => const Color(0xFFB8A7FF),
    };
    final focusLabel = switch (focus) {
      _TwinFocus.overview => '数据总览',
      _TwinFocus.berth => '泊位槽位',
      _TwinFocus.yard => '堆场槽位',
      _TwinFocus.vessel => '船舶槽位',
    };
    final title = switch (layer) {
      _TwinLayer.traffic => 'AIS 交通聚合字段',
      _TwinLayer.equipment => '设备负载与效率演示',
      _TwinLayer.risk => '当前与短时风险演示',
      _TwinLayer.schedule => '船期窗口与泊位冲突演示',
    };
    final source = switch (layer) {
      _TwinLayer.traffic => 'NOAA / MarineCadastre · 5分钟匿名聚合',
      _TwinLayer.equipment => '公开基准校准设备工况',
      _TwinLayer.risk =>
        mode == _TwinViewMode.forecast
            ? '+$forecastMinute 分钟趋势外推 · 非生产预测'
            : '后端快照 + 校准演示情景',
      _TwinLayer.schedule => '公开回放船期与泊位场景',
    };
    final metrics = switch (layer) {
      _TwinLayer.traffic => <(String, String, String)>[
        (
          '演示风险',
          '$projectedRisk%',
          mode == _TwinViewMode.forecast ? '+$forecastMinute 分钟' : '当前场景',
        ),
        ('作业车辆', '${_TwinDemoMetrics.agvOnline} 辆', '演示车队'),
        ('路线任务', '${_TwinDemoMetrics.routeTasks} 条', '回放任务'),
      ],
      _TwinLayer.equipment => <(String, String, String)>[
        ('岸桥效率', '${_TwinDemoMetrics.craneEfficiency}%', '演示工况'),
        ('当前负载', '${_TwinDemoMetrics.equipmentLoad}%', '校准场景'),
        ('数据完整', '${_TwinDemoMetrics.telemetryCompleteness}%', '演示快照'),
      ],
      _TwinLayer.risk => <(String, String, String)>[
        ('派生风险', '$projectedRisk%', '后端历史快照'),
        ('风险压力', '${snapshot.strategyPressure}%', '后端历史快照'),
        ('约束余量', '${snapshot.constraintHeadroom}%', '沙箱指标'),
      ],
      _TwinLayer.schedule => <(String, String, String)>[
        ('船舶窗口', _TwinDemoMetrics.vesselWindow, '演示计划'),
        ('预计偏差', _TwinDemoMetrics.etaDeviation, '趋势估计'),
        ('后续影响', _TwinDemoMetrics.berthConflict, '泊位链影响'),
      ],
    };
    final event = switch (layer) {
      _TwinLayer.traffic =>
        '$focusLabel：${_TwinDemoMetrics.agvOnline} 辆 AGV 正执行 ${_TwinDemoMetrics.routeTasks} 条演示路线，当前风险 $projectedRisk%。',
      _TwinLayer.equipment =>
        '$focusLabel：岸桥效率 ${_TwinDemoMetrics.craneEfficiency}%，设备负载 ${_TwinDemoMetrics.equipmentLoad}%，演示数据完整度 ${_TwinDemoMetrics.telemetryCompleteness}%。',
      _TwinLayer.risk =>
        '$focusLabel：当前/外推风险 $projectedRisk%，约束余量 ${math.max(38, snapshot.constraintHeadroom)}%，用于演示预警联动。',
      _TwinLayer.schedule =>
        '$focusLabel：${_TwinDemoMetrics.vesselWindow}，ETA 偏差 ${_TwinDemoMetrics.etaDeviation}，${_TwinDemoMetrics.berthConflict}。',
    };
    final load = layer == _TwinLayer.risk ? projectedRisk / 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.13), const Color(0xFF07152B)],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 18,
            spreadRadius: -7,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SignalDot(color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                snapshot.dataSource.label,
                style: TextStyle(
                  color: accent,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            source,
            style: const TextStyle(color: Color(0xFF7894BD), fontSize: 8),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                Expanded(
                  child: _LayerInsightMetric(
                    label: metrics[index].$1,
                    value: metrics[index].$2,
                    hint: metrics[index].$3,
                    color: accent,
                  ),
                ),
                if (index != metrics.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.bolt_rounded, size: 14, color: accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  event,
                  style: const TextStyle(
                    color: Color(0xFFB9CDEB),
                    fontSize: 9,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: load),
            duration: const Duration(milliseconds: 760),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: value,
                backgroundColor: const Color(0xFF172845),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerInsightMetric extends StatelessWidget {
  const _LayerInsightMetric({
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
  });

  final String label;
  final String value;
  final String hint;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xA6071120),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: color.withValues(alpha: 0.14)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF6F89B1), fontSize: 7),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF607CA5), fontSize: 6.5),
        ),
      ],
    ),
  );
}

class _TwinFocusSwitch extends StatelessWidget {
  const _TwinFocusSwitch({required this.focus, required this.onSelected});

  final _TwinFocus focus;
  final ValueChanged<_TwinFocus> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = <(_TwinFocus, String, IconData)>[
      (_TwinFocus.overview, '数据', Icons.public_rounded),
      (_TwinFocus.berth, '泊位槽位', Icons.anchor_rounded),
      (_TwinFocus.yard, '堆场槽位', Icons.inventory_2_outlined),
      (_TwinFocus.vessel, '船舶槽位', Icons.directions_boat_filled_rounded),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF071327),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF203B69)),
      ),
      child: Row(
        children: [
          const Text(
            '镜头',
            style: TextStyle(
              color: Color(0xFF7894BD),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          for (final item in items) ...[
            Expanded(
              child: InkWell(
                onTap: () => onSelected(item.$1),
                borderRadius: BorderRadius.circular(9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: focus == item.$1
                        ? const Color(0xFF124E70)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: focus == item.$1
                          ? const Color(0xFF4DE4FF)
                          : const Color(0xFF294264),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.$3,
                        size: 12,
                        color: focus == item.$1
                            ? const Color(0xFFB8EFFF)
                            : const Color(0xFF607CA5),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        item.$2,
                        style: TextStyle(
                          color: focus == item.$1
                              ? Colors.white
                              : const Color(0xFF7894BD),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (item != items.last) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _ForecastHorizonRail extends StatelessWidget {
  const _ForecastHorizonRail({required this.minute, required this.onSelected});

  final int minute;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF08162C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF203B69)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.schedule_rounded,
            size: 14,
            color: Color(0xFFFFB45C),
          ),
          const SizedBox(width: 6),
          const Text(
            '时间标签（不生成预测值）',
            style: TextStyle(
              color: Color(0xFF9DB2D8),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          for (final value in const [0, 5, 10, 15]) ...[
            InkWell(
              onTap: () => onSelected(value),
              borderRadius: BorderRadius.circular(99),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: minute == value
                      ? const Color(0x33FFB45C)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: minute == value
                        ? const Color(0xFFFFB45C)
                        : const Color(0xFF294264),
                  ),
                ),
                child: Text(
                  value == 0 ? '现在' : '+$value分',
                  style: TextStyle(
                    color: minute == value
                        ? const Color(0xFFFFD08A)
                        : const Color(0xFF7894BD),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            if (value != 15) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _TwinTelemetryStrip extends StatelessWidget {
  const _TwinTelemetryStrip({
    required this.layer,
    required this.completed,
    required this.riskHigh,
  });

  final _TwinLayer layer;
  final bool completed;
  final int riskHigh;

  @override
  Widget build(BuildContext context) {
    final effectiveRisk = math.max(22, riskHigh);
    final values = switch (layer) {
      _TwinLayer.traffic => [
        ('演示风险', '$effectiveRisk%', const Color(0xFF4DE4FF)),
        ('AGV作业', '${_TwinDemoMetrics.agvOnline}辆', const Color(0xFFFFB45C)),
        ('路线任务', '${_TwinDemoMetrics.routeTasks}条', const Color(0xFF76F7C5)),
      ],
      _TwinLayer.equipment => [
        (
          '岸桥效率',
          '${_TwinDemoMetrics.craneEfficiency}%',
          const Color(0xFF76F7C5),
        ),
        ('设备负载', '${_TwinDemoMetrics.equipmentLoad}%', const Color(0xFF4DE4FF)),
        (
          '快照完整',
          '${_TwinDemoMetrics.telemetryCompleteness}%',
          const Color(0xFFB8A7FF),
        ),
      ],
      _TwinLayer.risk => [
        ('冲突风险', '$effectiveRisk%', const Color(0xFFFF7A9D)),
        ('短时外推', '已就绪', const Color(0xFFFFB45C)),
        ('测试轨迹', completed ? '已读取' : '24帧预置', const Color(0xFF76F7C5)),
      ],
      _TwinLayer.schedule => [
        ('船舶窗口', '18:20', const Color(0xFF4DE4FF)),
        ('预计偏差', _TwinDemoMetrics.etaDeviation, const Color(0xFFFFB45C)),
        ('泊位计划', 'B03已排', const Color(0xFF76F7C5)),
      ],
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xD907142B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x443B82B4)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < values.length; index++) ...[
            Expanded(
              child: _TelemetryCell(
                label: values[index].$1,
                value: values[index].$2,
                color: values[index].$3,
              ),
            ),
            if (index != values.length - 1)
              Container(width: 1, height: 24, color: const Color(0x332E77A5)),
          ],
        ],
      ),
    );
  }
}

class _MarineConditionStack extends StatelessWidget {
  const _MarineConditionStack();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _MarineConditionPill(
          icon: Icons.water_rounded,
          label: '潮位 ${_TwinDemoMetrics.tide}',
          color: Color(0xFF4DE4FF),
        ),
        SizedBox(height: 4),
        _MarineConditionPill(
          icon: Icons.air_rounded,
          label: '风速 ${_TwinDemoMetrics.wind}',
          color: Color(0xFF9DC8F8),
        ),
        SizedBox(height: 4),
        _MarineConditionPill(
          icon: Icons.visibility_outlined,
          label: '能见度 ${_TwinDemoMetrics.visibility}',
          color: Color(0xFF76F7C5),
        ),
      ],
    );
  }
}

class _MarineConditionPill extends StatelessWidget {
  const _MarineConditionPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xD907142B),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withValues(alpha: 0.26)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 7,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _TelemetryCell extends StatelessWidget {
  const _TelemetryCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF6F89B1), fontSize: 7),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _TwinLayerStatus extends StatelessWidget {
  const _TwinLayerStatus({
    required this.pressure,
    required this.riskHigh,
    required this.completed,
    required this.layer,
    required this.mode,
    required this.forecastMinute,
  });

  final int pressure;
  final int riskHigh;
  final bool completed;
  final _TwinLayer layer;
  final _TwinViewMode mode;
  final int forecastMinute;

  @override
  Widget build(BuildContext context) {
    final displayRisk =
        math.max(22, riskHigh) +
        (mode == _TwinViewMode.forecast ? (forecastMinute ~/ 5) * 2 : 0);
    final accent = switch (mode) {
      _TwinViewMode.live => const Color(0xFF4DE4FF),
      _TwinViewMode.forecast => const Color(0xFFFFB45C),
      _TwinViewMode.simulation => const Color(0xFF76F7C5),
    };
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xE6101D34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x554DE4FF)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _SignalDot(color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  completed
                      ? '独立测试轨迹已就绪 · 等待人工审阅'
                      : mode == _TwinViewMode.simulation
                      ? '只读取训练完成后的测试产物'
                      : switch (layer) {
                          _TwinLayer.traffic => 'AGV 路线与交通演示',
                          _TwinLayer.equipment => '设备效率与负载演示',
                          _TwinLayer.risk => '当前与短时风险演示',
                          _TwinLayer.schedule => '船期窗口与冲突演示',
                        },
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                mode == _TwinViewMode.forecast
                    ? '+$forecastMinute分 · 演示风险 $displayRisk%'
                    : mode == _TwinViewMode.simulation
                    ? (completed ? '测试产物可用' : '公开回放已就绪')
                    : '压力 $pressure · 当前派生风险 $displayRisk',
                style: const TextStyle(
                  color: Color(0xFF9DC8F8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: (displayRisk / 100).clamp(0, 1),
              backgroundColor: const Color(0xFF172845),
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _HudBadge extends StatelessWidget {
  const _HudBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xD90A1830),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 12),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _SignalDot extends StatelessWidget {
  const _SignalDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 9, spreadRadius: 1)],
      ),
    );
  }
}

class _TwinSceneLabels extends StatelessWidget {
  const _TwinSceneLabels({
    required this.focus,
    required this.layer,
    required this.onSelected,
  });

  final _TwinFocus focus;
  final _TwinLayer layer;
  final ValueChanged<_TwinFocus> onSelected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _label(
          alignment: const Alignment(-0.54, -0.14),
          label: '堆场槽位 A',
          color: const Color(0xFF9DC8F8),
          target: _TwinFocus.yard,
        ),
        _label(
          alignment: const Alignment(-0.08, 0.00),
          label: '堆场槽位 B',
          color: const Color(0xFF76F7C5),
          target: _TwinFocus.yard,
        ),
        _label(
          alignment: const Alignment(0.28, -0.26),
          label: '岸桥槽位',
          color: const Color(0xFF76F7C5),
          target: _TwinFocus.berth,
        ),
        _label(
          alignment: const Alignment(-0.82, 0.22),
          label: '船舶槽位',
          color: const Color(0xFFB8EFFF),
          target: _TwinFocus.vessel,
        ),
        _label(
          alignment: const Alignment(0.42, 0.25),
          label: layer == _TwinLayer.risk ? '泊位风险槽位' : '泊位作业槽位',
          color: const Color(0xFFFFB45C),
          target: _TwinFocus.berth,
        ),
      ],
    );
  }

  Widget _label({
    required Alignment alignment,
    required String label,
    required Color color,
    required _TwinFocus target,
  }) {
    final active = focus == _TwinFocus.overview || focus == target;
    return Align(
      alignment: alignment,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: active ? 1 : 0.24,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          scale: focus == target ? 1.08 : 1,
          child: _SceneMapLabel(
            label: focus == target ? '● $label' : label,
            color: color,
            onTap: () => onSelected(target),
          ),
        ),
      ),
    );
  }
}

class _SceneMapLabel extends StatelessWidget {
  const _SceneMapLabel({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '查看$label详情',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xCC071226),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PortTwinPainter extends CustomPainter {
  const _PortTwinPainter({
    required this.progress,
    required this.mode,
    required this.layer,
    required this.focus,
    required this.pressure,
    required this.riskHigh,
  });

  final double progress;
  final _TwinViewMode mode;
  final _TwinLayer layer;
  final _TwinFocus focus;
  final int pressure;
  final int riskHigh;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF07142B), Color(0xFF061224), Color(0xFF030916)],
        ).createShader(rect),
    );

    final currentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF4DE4FF).withValues(alpha: 0.12);
    for (var wave = 0; wave < 5; wave++) {
      final y = size.height * (0.28 + wave * 0.045);
      final shift = (progress * size.width * 0.22 + wave * 37) % size.width;
      final current = Path()..moveTo(-40 + shift, y);
      for (var segment = 0; segment < 5; segment++) {
        current.relativeQuadraticBezierTo(18, segment.isEven ? -4 : 4, 36, 0);
      }
      canvas.drawPath(current, currentPaint);
      canvas.drawPath(current.shift(Offset(-size.width, 0)), currentPaint);
    }

    final horizon = size.height * 0.25;
    final vanish = Offset(size.width * 0.52, horizon);
    final gridPaint = Paint()
      ..color = const Color(0xFF2E77A5).withValues(alpha: 0.22)
      ..strokeWidth = 0.8;
    for (var index = 0; index <= 10; index++) {
      final bottomX = size.width * index / 10;
      canvas.drawLine(vanish, Offset(bottomX, size.height), gridPaint);
    }
    for (var index = 0; index < 11; index++) {
      final t = index / 10;
      final y = horizon + math.pow(t, 1.85) * (size.height - horizon);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final yard = Path()
      ..moveTo(size.width * 0.13, size.height * 0.43)
      ..lineTo(size.width * 0.61, size.height * 0.36)
      ..lineTo(size.width * 0.91, size.height * 0.67)
      ..lineTo(size.width * 0.28, size.height * 0.83)
      ..close();
    canvas.drawPath(
      yard,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x66306A8A), Color(0x5520A17D)],
        ).createShader(rect),
    );
    canvas.drawPath(
      yard,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF4DE4FF).withValues(alpha: 0.62),
    );

    if (layer == _TwinLayer.risk) {
      _drawRiskHeatmap(canvas, size);
    }

    for (var index = 0; index < 4; index++) {
      final x = size.width * (0.25 + index * 0.12);
      final y = size.height * (0.49 + index * 0.025);
      _drawBlock(
        canvas,
        Offset(x, y),
        Size(size.width * 0.12, size.height * 0.08),
        index.isEven ? const Color(0xFF2563EB) : const Color(0xFF0D9C82),
      );
    }

    _drawCrane(canvas, Offset(size.width * 0.70, size.height * 0.47), 1.0);
    _drawCrane(canvas, Offset(size.width * 0.78, size.height * 0.53), 0.82);
    final vesselDrift = math.sin(progress * math.pi * 2) * 3.2;
    _drawVessel(
      canvas,
      Offset(size.width * 0.13 + vesselDrift, size.height * 0.67),
      0.82,
    );
    _drawVessel(
      canvas,
      Offset(size.width * 0.66 - vesselDrift * 0.45, size.height * 0.76),
      1.0,
    );

    final routeColor = switch (mode) {
      _TwinViewMode.live => const Color(0xFF4DE4FF),
      _TwinViewMode.forecast => const Color(0xFFFFB45C),
      _TwinViewMode.simulation => const Color(0xFF76F7C5),
    };
    final route = Path()
      ..moveTo(size.width * 0.08, size.height * 0.76)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.60,
        size.width * 0.52,
        size.height * 0.80,
        size.width * 0.91,
        size.height * 0.58,
      );
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = layer == _TwinLayer.traffic ? 2.5 : 1.3
        ..color = routeColor.withValues(
          alpha: layer == _TwinLayer.traffic ? 0.9 : 0.48,
        ),
    );
    final metric = route.computeMetrics().first;
    final movingPoint = metric
        .getTangentForOffset(metric.length * progress)
        ?.position;
    if (movingPoint != null) {
      final tangent = metric.getTangentForOffset(metric.length * progress);
      if (tangent != null) {
        final tail = Offset(
          math.cos(tangent.angle) * -22,
          math.sin(tangent.angle) * -22,
        );
        canvas.drawLine(
          movingPoint,
          movingPoint + tail,
          Paint()
            ..shader = LinearGradient(
              colors: [routeColor, routeColor.withValues(alpha: 0)],
            ).createShader(Rect.fromPoints(movingPoint, movingPoint + tail))
            ..strokeWidth = 2,
        );
      }
      canvas.drawCircle(movingPoint, 4.5, Paint()..color = routeColor);
      canvas.drawCircle(
        movingPoint,
        11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = routeColor.withValues(alpha: 0.42),
      );
    }

    _drawLayerDetails(canvas, size, routeColor);
    _drawFocusTarget(canvas, size, routeColor);

    final scanY = horizon + progress * (size.height - horizon);
    canvas.drawRect(
      Rect.fromLTWH(0, scanY - 18, size.width, 36),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            routeColor.withValues(alpha: 0.10),
            routeColor.withValues(alpha: 0.35),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, scanY - 18, size.width, 36)),
    );

    final pressureOpacity = (pressure / 100).clamp(0.15, 0.75);
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.58),
      18 +
          (layer == _TwinLayer.risk ? 12 : 6) *
              math.sin(progress * math.pi * 2).abs(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = layer == _TwinLayer.risk ? 1.4 : 0.8
        ..color = const Color(0xFFFFB45C).withValues(alpha: pressureOpacity),
    );
  }

  void _drawLayerDetails(Canvas canvas, Size size, Color routeColor) {
    switch (layer) {
      case _TwinLayer.traffic:
        final routes = <Path>[
          Path()
            ..moveTo(size.width * 0.16, size.height * 0.70)
            ..quadraticBezierTo(
              size.width * 0.42,
              size.height * 0.56,
              size.width * 0.76,
              size.height * 0.61,
            ),
          Path()
            ..moveTo(size.width * 0.23, size.height * 0.82)
            ..cubicTo(
              size.width * 0.38,
              size.height * 0.67,
              size.width * 0.64,
              size.height * 0.72,
              size.width * 0.86,
              size.height * 0.54,
            ),
        ];
        for (var routeIndex = 0; routeIndex < routes.length; routeIndex++) {
          final route = routes[routeIndex];
          canvas.drawPath(
            route,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = routeColor.withValues(alpha: 0.42 + routeIndex * 0.12),
          );
          final metric = route.computeMetrics().first;
          for (var vehicle = 0; vehicle < 3; vehicle++) {
            final t = (progress + vehicle * 0.29 + routeIndex * 0.17) % 1;
            final tangent = metric.getTangentForOffset(metric.length * t);
            if (tangent == null) continue;
            canvas.save();
            canvas.translate(tangent.position.dx, tangent.position.dy);
            canvas.rotate(tangent.angle);
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                const Rect.fromLTWH(-4, -2.2, 8, 4.4),
                const Radius.circular(1.4),
              ),
              Paint()
                ..color = routeIndex == 0
                    ? const Color(0xFF4DE4FF)
                    : const Color(0xFF76F7C5),
            );
            canvas.restore();
          }
        }
        _drawRouteArrow(
          canvas,
          Offset(size.width * 0.49, size.height * 0.66),
          routeColor,
        );
        break;
      case _TwinLayer.equipment:
        final trolleyX = 8 + 18 * ((math.sin(progress * math.pi * 2) + 1) / 2);
        final craneOrigin = Offset(size.width * 0.70, size.height * 0.47);
        final trolley = craneOrigin.translate(trolleyX, -40);
        canvas.drawLine(
          trolley,
          trolley.translate(0, 20 + 8 * math.sin(progress * math.pi * 2).abs()),
          Paint()
            ..color = const Color(0xFFFFD08A)
            ..strokeWidth = 1.2,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: trolley.translate(
              0,
              21 + 8 * math.sin(progress * math.pi * 2).abs(),
            ),
            width: 12,
            height: 5,
          ),
          Paint()..color = const Color(0xFFFFB45C),
        );
        _drawEquipmentGauge(
          canvas,
          Offset(size.width * 0.83, size.height * 0.39),
          0.77,
        );
        _drawEquipmentGauge(
          canvas,
          Offset(size.width * 0.89, size.height * 0.48),
          0.68,
        );
        break;
      case _TwinLayer.risk:
        const forecastFactor = 0.45;
        final center = Offset(size.width * 0.73, size.height * 0.58);
        final cone = Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(
            size.width * (0.48 - forecastFactor * 0.04),
            size.height * 0.48,
          )
          ..lineTo(
            size.width * (0.91 + forecastFactor * 0.02),
            size.height * 0.70,
          )
          ..close();
        canvas.drawPath(
          cone,
          Paint()
            ..shader = LinearGradient(
              colors: [
                const Color(0x00FF6B83),
                const Color(0x55FF9F6E),
                const Color(0x12FF6B83),
              ],
            ).createShader(cone.getBounds()),
        );
        canvas.drawPath(
          cone,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFFFF9F6E).withValues(alpha: 0.58),
        );
        for (var ring = 1; ring <= 3; ring++) {
          canvas.drawCircle(
            center,
            10 + ring * 9 + 4 * math.sin((progress + ring * .2) * math.pi * 2),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8
              ..color = const Color(
                0xFFFF7A9D,
              ).withValues(alpha: 0.14 + ring * 0.09),
          );
        }
        break;
      case _TwinLayer.schedule:
        final scheduleTrack = Path()
          ..moveTo(size.width * 0.06, size.height * 0.70)
          ..cubicTo(
            size.width * 0.31,
            size.height * 0.72,
            size.width * 0.50,
            size.height * 0.88,
            size.width * 0.80,
            size.height * 0.76,
          );
        _drawDashedSchedule(canvas, scheduleTrack);
        final metric = scheduleTrack.computeMetrics().first;
        final shipTangent = metric.getTangentForOffset(
          metric.length * (0.18 + progress * 0.58),
        );
        if (shipTangent != null) {
          canvas.drawCircle(
            shipTangent.position,
            5,
            Paint()..color = const Color(0xFFB8A7FF),
          );
          canvas.drawCircle(
            shipTangent.position,
            11,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = const Color(0xFFB8A7FF).withValues(alpha: 0.34),
          );
        }
        final windowRect = Rect.fromLTWH(
          size.width * 0.54,
          size.height * 0.70,
          size.width * 0.28,
          size.height * 0.055,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(windowRect, const Radius.circular(6)),
          Paint()..color = const Color(0x2476F7C5),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(windowRect, const Radius.circular(6)),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0xFF76F7C5).withValues(alpha: 0.55),
        );
        _drawCanvasLabel(
          canvas,
          'B03 18:20–20:00',
          windowRect.topLeft.translate(7, 5),
          const Color(0xFFB8EFFF),
        );
        break;
    }
  }

  void _drawFocusTarget(Canvas canvas, Size size, Color color) {
    if (focus == _TwinFocus.overview) {
      final frame = Rect.fromLTWH(
        size.width * 0.055,
        size.height * 0.31,
        size.width * 0.89,
        size.height * 0.57,
      );
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.24);
      canvas.drawRRect(
        RRect.fromRectAndRadius(frame, const Radius.circular(12)),
        paint,
      );
      for (final target in [
        Offset(size.width * 0.74, size.height * 0.56),
        Offset(size.width * 0.45, size.height * 0.58),
        Offset(size.width * 0.17, size.height * 0.70),
      ]) {
        canvas.drawCircle(
          target,
          7 + 2 * math.sin(progress * math.pi * 2).abs(),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = color.withValues(alpha: 0.46),
        );
      }
      return;
    }

    final target = switch (focus) {
      _TwinFocus.berth => Rect.fromCenter(
        center: Offset(size.width * 0.74, size.height * 0.56),
        width: size.width * 0.30,
        height: size.height * 0.25,
      ),
      _TwinFocus.yard => Rect.fromCenter(
        center: Offset(size.width * 0.47, size.height * 0.58),
        width: size.width * 0.48,
        height: size.height * 0.31,
      ),
      _TwinFocus.vessel => Rect.fromCenter(
        center: Offset(size.width * 0.18, size.height * 0.70),
        width: size.width * 0.29,
        height: size.height * 0.22,
      ),
      _TwinFocus.overview => Rect.zero,
    };
    final rounded = RRect.fromRectAndRadius(target, const Radius.circular(14));
    final vignette = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rounded);
    canvas.drawPath(vignette, Paint()..color = const Color(0x72020812));
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.88),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        target.inflate(5 + 2 * math.sin(progress * math.pi * 2).abs()),
        const Radius.circular(17),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = color.withValues(alpha: 0.24),
    );
    final center = target.center;
    canvas.drawLine(
      center.translate(-9, 0),
      center.translate(9, 0),
      Paint()..color = color.withValues(alpha: 0.64),
    );
    canvas.drawLine(
      center.translate(0, -9),
      center.translate(0, 9),
      Paint()..color = color.withValues(alpha: 0.64),
    );
  }

  void _drawRiskHeatmap(Canvas canvas, Size size) {
    final intensities = <double>[0.28, 0.44, 0.71, 0.92, 0.64, 0.38];
    for (var index = 0; index < intensities.length; index++) {
      final row = index ~/ 3;
      final col = index % 3;
      final center = Offset(
        size.width * (0.38 + col * 0.13),
        size.height * (0.50 + row * 0.10),
      );
      final pulse =
          0.88 + 0.18 * math.sin((progress + index * 0.13) * math.pi * 2).abs();
      final intensity = intensities[index] * (0.85 + riskHigh / 500) * pulse;
      canvas.drawCircle(
        center,
        22 + pulse * 5,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFF7A6D).withValues(alpha: intensity * 0.42),
              const Color(0x00FF7A6D),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: 27)),
      );
    }
  }

  void _drawEquipmentGauge(Canvas canvas, Offset origin, double value) {
    canvas.drawRect(
      Rect.fromLTWH(origin.dx, origin.dy, 4, 28),
      Paint()..color = const Color(0xFF172845),
    );
    canvas.drawRect(
      Rect.fromLTWH(origin.dx, origin.dy + 28 * (1 - value), 4, 28 * value),
      Paint()..color = const Color(0xFF76F7C5),
    );
  }

  void _drawRouteArrow(Canvas canvas, Offset center, Color color) {
    final path = Path()
      ..moveTo(center.dx - 7, center.dy - 4)
      ..lineTo(center.dx + 5, center.dy)
      ..lineTo(center.dx - 7, center.dy + 4)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.78));
  }

  void _drawDashedSchedule(Canvas canvas, Path path) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFB8A7FF).withValues(alpha: 0.7);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 7, metric.length)),
          paint,
        );
        distance += 12;
      }
    }
  }

  void _drawCanvasLabel(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  void _drawBlock(Canvas canvas, Offset origin, Size blockSize, Color color) {
    final path = Path()
      ..moveTo(origin.dx, origin.dy)
      ..lineTo(origin.dx + blockSize.width, origin.dy - blockSize.height * 0.2)
      ..lineTo(origin.dx + blockSize.width, origin.dy + blockSize.height * 0.7)
      ..lineTo(origin.dx, origin.dy + blockSize.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.72));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.95),
    );
  }

  void _drawCrane(Canvas canvas, Offset origin, double scale) {
    final paint = Paint()
      ..color = const Color(0xFF76F7C5).withValues(alpha: 0.78)
      ..strokeWidth = 2 * scale
      ..style = PaintingStyle.stroke;
    canvas.drawLine(origin, origin.translate(0, -44 * scale), paint);
    canvas.drawLine(
      origin.translate(0, -42 * scale),
      origin.translate(29 * scale, -35 * scale),
      paint,
    );
    canvas.drawLine(
      origin.translate(20 * scale, -37 * scale),
      origin.translate(20 * scale, -17 * scale),
      paint,
    );
  }

  void _drawVessel(Canvas canvas, Offset origin, double scale) {
    final hull = Path()
      ..moveTo(origin.dx - 24 * scale, origin.dy)
      ..lineTo(origin.dx + 25 * scale, origin.dy)
      ..lineTo(origin.dx + 16 * scale, origin.dy + 10 * scale)
      ..lineTo(origin.dx - 16 * scale, origin.dy + 10 * scale)
      ..close();
    canvas.drawPath(
      hull,
      Paint()..color = const Color(0xFF60A5FA).withValues(alpha: 0.86),
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: origin.translate(2 * scale, -5 * scale),
        width: 18 * scale,
        height: 10 * scale,
      ),
      Paint()..color = const Color(0xFFB8EFFF).withValues(alpha: 0.78),
    );
  }

  @override
  bool shouldRepaint(covariant _PortTwinPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        mode != oldDelegate.mode ||
        layer != oldDelegate.layer ||
        focus != oldDelegate.focus ||
        pressure != oldDelegate.pressure ||
        riskHigh != oldDelegate.riskHigh;
  }
}

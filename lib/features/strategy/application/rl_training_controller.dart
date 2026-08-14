import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../domain/shared_rl_contract.dart';

enum RlDesktopTrainingPhase {
  idle,
  checkingConnection,
  preparingRequest,
  waitingDesktopApproval,
  approved,
  training,
  evaluating,
  completed,
  rejected,
  failed,
}

@immutable
class RlTrainingConfig {
  const RlTrainingConfig({
    this.algorithm = 'ppo',
    this.objective = 'multi_objective',
    this.scenario = 'public_benchmark_replay',
    this.assetGroup = 'integrated_port_ops',
    this.totalSteps = 20000,
    this.batchSize = 256,
    this.learningRate = 0.0003,
    this.gamma = 0.995,
    this.tau = 0.005,
    this.entropyCoef = 0.02,
    this.replayBuffer = 50000,
    this.seed = 42,
    this.guardrail = 'strict',
    this.demandCapKw = 3500,
    this.costWeight = 0.22,
    this.carbonWeight = 0.18,
    this.peakWeight = 0.18,
    this.safetyWeight = 0.25,
  });

  final String algorithm;
  final String objective;
  final String scenario;
  final String assetGroup;
  final int totalSteps;
  final int batchSize;
  final double learningRate;
  final double gamma;
  final double tau;
  final double entropyCoef;
  final int replayBuffer;
  final int seed;
  final String guardrail;
  final double demandCapKw;
  final double costWeight;
  final double carbonWeight;
  final double peakWeight;
  final double safetyWeight;

  String get algorithmLabel => switch (algorithm) {
    'sac' => 'SAC 连续控制',
    'ppo' => 'PPO 策略优化',
    'td3' => 'TD3 双延迟策略',
    'dqn' => 'DQN 离散调度',
    'a2c' => 'A2C 优势演员评论家',
    'tqc' => 'TQC 截断分位数评论家',
    'qrdqn' => 'QR-DQN 分位数离散控制',
    'trpo' => 'TRPO 信赖域策略优化',
    'recurrent_ppo' => 'Recurrent PPO 时序策略',
    'ars' => 'ARS 随机搜索策略',
    'mpc' => 'MPC 模型预测控制基线',
    'fcfs' => 'FCFS 中性规则基线',
    _ => algorithm.toUpperCase(),
  };

  bool get isTrainable => !sharedNonTrainableAlgorithmIds.contains(algorithm);

  String get objectiveLabel => switch (objective) {
    'traffic_flow_safety' => '交通流与安全余量',
    'agv_turnaround' => 'AGV 周转效率',
    'safety_guard' => '安全约束优先',
    'multi_objective' => '综合多目标',
    'crane_productivity' => '岸桥作业效率',
    'vessel_turnaround' => '船舶在港时长',
    'yard_balance' => '堆场箱区均衡',
    'energy_peak' => '能耗与需量削峰',
    'emission_reduction' => '单位吞吐碳排',
    'disruption_resilience' => '扰动恢复韧性',
    _ => '交通流与安全余量',
  };

  String get guardrailLabel => switch (guardrail) {
    'balanced' => '均衡',
    'explore' => '探索',
    _ => '严格',
  };

  RlTrainingConfig copyWith({
    String? algorithm,
    String? objective,
    int? totalSteps,
    int? batchSize,
    double? learningRate,
    double? gamma,
    int? seed,
    String? guardrail,
    double? safetyWeight,
  }) {
    return RlTrainingConfig(
      algorithm: algorithm ?? this.algorithm,
      objective: objective ?? this.objective,
      scenario: scenario,
      assetGroup: assetGroup,
      totalSteps: totalSteps ?? this.totalSteps,
      batchSize: batchSize ?? this.batchSize,
      learningRate: learningRate ?? this.learningRate,
      gamma: gamma ?? this.gamma,
      tau: tau,
      entropyCoef: entropyCoef,
      replayBuffer: replayBuffer,
      seed: seed ?? this.seed,
      guardrail: guardrail ?? this.guardrail,
      demandCapKw: demandCapKw,
      costWeight: costWeight,
      carbonWeight: carbonWeight,
      peakWeight: peakWeight,
      safetyWeight: safetyWeight ?? this.safetyWeight,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'algorithm': algorithm,
    'objective': objective,
    'scenario': scenario,
    'asset_group': assetGroup,
    'max_episode_steps': 120,
    'episode_hours': 12,
    'evaluation_episodes': 10,
    'rollout_horizon': 256,
    'total_steps': totalSteps,
    'batch_size': batchSize,
    'learning_rate': learningRate,
    'gamma': gamma,
    'tau': tau,
    'entropy_coef': entropyCoef,
    'replay_buffer': replayBuffer,
    'seed': seed,
    'guardrail': guardrail,
    'demand_cap_kw': demandCapKw,
    'cost_weight': costWeight,
    'carbon_weight': carbonWeight,
    'peak_weight': peakWeight,
    'safety_weight': safetyWeight,
  };
}

@immutable
class RlMetricPoint {
  const RlMetricPoint({
    required this.step,
    required this.reward,
    required this.episodes,
  });

  final int step;
  final double reward;
  final int episodes;
}

@immutable
class RlAlgorithmDescriptor {
  const RlAlgorithmDescriptor({
    required this.id,
    required this.label,
    required this.family,
    required this.library,
    this.trainable = true,
    this.status = 'AVAILABLE',
    this.multiSeedReady = false,
  });

  final String id;
  final String label;
  final String family;
  final String library;
  final bool trainable;
  final String status;
  final bool multiSeedReady;
}

@immutable
class RlTrainingState {
  const RlTrainingState({
    this.phase = RlDesktopTrainingPhase.idle,
    this.config = const RlTrainingConfig(),
    this.configSource = 'default',
    this.desktopOnline = false,
    this.desktopPanelActive = false,
    this.desktopLaunchInProgress = false,
    this.desktopPanelUrl = 'http://127.0.0.1:8000/rl-panel',
    this.desktopLaunchMessage = '尚未从手机启动电脑端强化学习系统',
    this.requestId,
    this.jobId,
    this.progress = 0,
    this.stage = '尚未提交训练申请',
    this.step = 0,
    this.reward = 0,
    this.entropy = 0,
    this.policyVersion = '—',
    this.eta = '—',
    this.totalStepsReported = 0,
    this.datasetSplit = '—',
    this.datasetId = '—',
    this.datasetTitle = '尚未读取数据登记',
    this.datasetBoundary = '尚未读取数据使用边界',
    this.sourcePublishers = '—',
    this.datasetSha256 = '—',
    this.datasetRows = 0,
    this.independentSourceObservations = 0,
    this.trainRows = 0,
    this.testRows = 0,
    this.environmentVersion = '—',
    this.portProfileId = '—',
    this.observationDimensions = 0,
    this.actionDimensions = 0,
    this.availableFactorCount = 0,
    this.totalFactorCount = sharedRealityFactorCount,
    this.shortGapInterpolationCount = 0,
    this.formalRlRunCount = 0,
    this.formalControlBaselineCount = 0,
    this.formalAlgorithmReadyCount = 0,
    this.evidenceLevel = '尚未读取',
    this.liveDataVerified = false,
    this.renderReady = false,
    this.history = const <RlMetricPoint>[],
    this.evaluationMetrics = const <String, double>{},
    this.replayFrames = const <Map<String, dynamic>>[],
    this.algorithms = const <RlAlgorithmDescriptor>[],
    this.approvedBy,
    this.logs = const <String>[],
    this.errorMessage,
    this.updatedAt,
  });

  final RlDesktopTrainingPhase phase;
  final RlTrainingConfig config;
  final String configSource;
  final bool desktopOnline;
  final bool desktopPanelActive;
  final bool desktopLaunchInProgress;
  final String desktopPanelUrl;
  final String desktopLaunchMessage;
  final String? requestId;
  final String? jobId;
  final double progress;
  final String stage;
  final int step;
  final double reward;
  final double entropy;
  final String policyVersion;
  final String eta;
  final int totalStepsReported;
  final String datasetSplit;
  final String datasetId;
  final String datasetTitle;
  final String datasetBoundary;
  final String sourcePublishers;
  final String datasetSha256;
  final int datasetRows;
  final int independentSourceObservations;
  final int trainRows;
  final int testRows;
  final String environmentVersion;
  final String portProfileId;
  final int observationDimensions;
  final int actionDimensions;
  final int availableFactorCount;
  final int totalFactorCount;
  final int shortGapInterpolationCount;
  final int formalRlRunCount;
  final int formalControlBaselineCount;
  final int formalAlgorithmReadyCount;
  final String evidenceLevel;
  final bool liveDataVerified;
  final bool renderReady;
  final List<RlMetricPoint> history;
  final Map<String, double> evaluationMetrics;
  final List<Map<String, dynamic>> replayFrames;
  final List<RlAlgorithmDescriptor> algorithms;
  final String? approvedBy;
  final List<String> logs;
  final String? errorMessage;
  final DateTime? updatedAt;

  bool get isBusy =>
      phase == RlDesktopTrainingPhase.checkingConnection ||
      phase == RlDesktopTrainingPhase.preparingRequest ||
      desktopLaunchInProgress;

  String get configSourceLabel => switch (configSource) {
    'xiaoyi_recommended' => '小懿推荐参数',
    'manual' => '人工配置参数',
    _ => '系统默认参数',
  };

  bool get hasRequest => requestId != null;

  bool get sharedContractVerified =>
      hasCompatibleSharedRlContract(algorithms.map((item) => item.id)) &&
      datasetId == preferredSharedDatasetId &&
      supportedSharedEnvironmentVersions.contains(environmentVersion) &&
      observationDimensions == sharedObservationDimensions &&
      actionDimensions == sharedActionDimensions;

  String get phaseLabel => switch (phase) {
    RlDesktopTrainingPhase.idle => desktopOnline ? '电脑端已连接' : '待连接电脑端',
    RlDesktopTrainingPhase.checkingConnection => '正在检查链路',
    RlDesktopTrainingPhase.preparingRequest => '正在提交申请',
    RlDesktopTrainingPhase.waitingDesktopApproval => '等待电脑端人工确认',
    RlDesktopTrainingPhase.approved => '电脑端已批准',
    RlDesktopTrainingPhase.training => '无渲染训练中',
    RlDesktopTrainingPhase.evaluating => '留出测试回放中',
    RlDesktopTrainingPhase.completed => '训练已完成',
    RlDesktopTrainingPhase.rejected => '电脑端已拒绝',
    RlDesktopTrainingPhase.failed => '联动异常',
  };

  RlTrainingState copyWith({
    RlDesktopTrainingPhase? phase,
    RlTrainingConfig? config,
    String? configSource,
    bool? desktopOnline,
    bool? desktopPanelActive,
    bool? desktopLaunchInProgress,
    String? desktopPanelUrl,
    String? desktopLaunchMessage,
    Object? requestId = _unset,
    Object? jobId = _unset,
    double? progress,
    String? stage,
    int? step,
    double? reward,
    double? entropy,
    String? policyVersion,
    String? eta,
    int? totalStepsReported,
    String? datasetSplit,
    String? datasetId,
    String? datasetTitle,
    String? datasetBoundary,
    String? sourcePublishers,
    String? datasetSha256,
    int? datasetRows,
    int? independentSourceObservations,
    int? trainRows,
    int? testRows,
    String? environmentVersion,
    String? portProfileId,
    int? observationDimensions,
    int? actionDimensions,
    int? availableFactorCount,
    int? totalFactorCount,
    int? shortGapInterpolationCount,
    int? formalRlRunCount,
    int? formalControlBaselineCount,
    int? formalAlgorithmReadyCount,
    String? evidenceLevel,
    bool? liveDataVerified,
    bool? renderReady,
    List<RlMetricPoint>? history,
    Map<String, double>? evaluationMetrics,
    List<Map<String, dynamic>>? replayFrames,
    List<RlAlgorithmDescriptor>? algorithms,
    Object? approvedBy = _unset,
    List<String>? logs,
    Object? errorMessage = _unset,
    DateTime? updatedAt,
  }) {
    return RlTrainingState(
      phase: phase ?? this.phase,
      config: config ?? this.config,
      configSource: configSource ?? this.configSource,
      desktopOnline: desktopOnline ?? this.desktopOnline,
      desktopPanelActive: desktopPanelActive ?? this.desktopPanelActive,
      desktopLaunchInProgress:
          desktopLaunchInProgress ?? this.desktopLaunchInProgress,
      desktopPanelUrl: desktopPanelUrl ?? this.desktopPanelUrl,
      desktopLaunchMessage: desktopLaunchMessage ?? this.desktopLaunchMessage,
      requestId: identical(requestId, _unset)
          ? this.requestId
          : requestId as String?,
      jobId: identical(jobId, _unset) ? this.jobId : jobId as String?,
      progress: progress ?? this.progress,
      stage: stage ?? this.stage,
      step: step ?? this.step,
      reward: reward ?? this.reward,
      entropy: entropy ?? this.entropy,
      policyVersion: policyVersion ?? this.policyVersion,
      eta: eta ?? this.eta,
      totalStepsReported: totalStepsReported ?? this.totalStepsReported,
      datasetSplit: datasetSplit ?? this.datasetSplit,
      datasetId: datasetId ?? this.datasetId,
      datasetTitle: datasetTitle ?? this.datasetTitle,
      datasetBoundary: datasetBoundary ?? this.datasetBoundary,
      sourcePublishers: sourcePublishers ?? this.sourcePublishers,
      datasetSha256: datasetSha256 ?? this.datasetSha256,
      datasetRows: datasetRows ?? this.datasetRows,
      independentSourceObservations:
          independentSourceObservations ?? this.independentSourceObservations,
      trainRows: trainRows ?? this.trainRows,
      testRows: testRows ?? this.testRows,
      environmentVersion: environmentVersion ?? this.environmentVersion,
      portProfileId: portProfileId ?? this.portProfileId,
      observationDimensions:
          observationDimensions ?? this.observationDimensions,
      actionDimensions: actionDimensions ?? this.actionDimensions,
      availableFactorCount: availableFactorCount ?? this.availableFactorCount,
      totalFactorCount: totalFactorCount ?? this.totalFactorCount,
      shortGapInterpolationCount:
          shortGapInterpolationCount ?? this.shortGapInterpolationCount,
      formalRlRunCount: formalRlRunCount ?? this.formalRlRunCount,
      formalControlBaselineCount:
          formalControlBaselineCount ?? this.formalControlBaselineCount,
      formalAlgorithmReadyCount:
          formalAlgorithmReadyCount ?? this.formalAlgorithmReadyCount,
      evidenceLevel: evidenceLevel ?? this.evidenceLevel,
      liveDataVerified: liveDataVerified ?? this.liveDataVerified,
      renderReady: renderReady ?? this.renderReady,
      history: history ?? this.history,
      evaluationMetrics: evaluationMetrics ?? this.evaluationMetrics,
      replayFrames: replayFrames ?? this.replayFrames,
      algorithms: algorithms ?? this.algorithms,
      approvedBy: identical(approvedBy, _unset)
          ? this.approvedBy
          : approvedBy as String?,
      logs: logs ?? this.logs,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const Object _unset = Object();

final rlTrainingProvider =
    NotifierProvider<RlTrainingController, RlTrainingState>(
      RlTrainingController.new,
    );

class RlTrainingController extends Notifier<RlTrainingState> {
  Timer? _pollTimer;
  bool _polling = false;
  bool _desktopStatusPolling = false;

  Dio get _dio => ref.read(dioProvider);

  @override
  RlTrainingState build() {
    ref.onDispose(() => _pollTimer?.cancel());
    return const RlTrainingState();
  }

  void updateConfig(RlTrainingConfig config) {
    if (state.phase == RlDesktopTrainingPhase.waitingDesktopApproval ||
        state.phase == RlDesktopTrainingPhase.training ||
        state.phase == RlDesktopTrainingPhase.evaluating) {
      return;
    }
    state = state.copyWith(
      config: config,
      configSource: 'manual',
      stage: state.hasRequest ? state.stage : '人工训练参数已保存，等待启动电脑端',
      logs: _prependLog('人工已保存训练参数 · ${config.algorithmLabel}'),
      errorMessage: null,
    );
  }

  void applyXiaoyiRecommendedConfig() {
    if (state.phase == RlDesktopTrainingPhase.waitingDesktopApproval ||
        state.phase == RlDesktopTrainingPhase.training ||
        state.phase == RlDesktopTrainingPhase.evaluating) {
      return;
    }
    const recommended = RlTrainingConfig(
      algorithm: 'ppo',
      objective: 'multi_objective',
      totalSteps: 20000,
      batchSize: 256,
      learningRate: 0.0003,
      gamma: 0.995,
      seed: 42,
      guardrail: 'strict',
      safetyWeight: 0.25,
    );
    state = state.copyWith(
      config: recommended,
      configSource: 'xiaoyi_recommended',
      stage: '已按当前公开数据契约生成可复现的 PPO 起始参数',
      logs: _prependLog('参数建议 · PPO / 2万步 / 10窗口测试 / 种子42'),
      errorMessage: null,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> checkConnection() async {
    if (state.isBusy) return;
    final previousPhase = state.phase;
    state = state.copyWith(
      phase: RlDesktopTrainingPhase.checkingConnection,
      errorMessage: null,
    );
    try {
      final evidenceOptions = Options(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
      );
      final capabilitiesResponse = await _dio.get<Object>(
        '/api/rl/engine/capabilities',
        options: evidenceOptions,
      );
      final benchmarkResponse = await _dio.get<Object>(
        '/api/rl/benchmarks/summary',
        queryParameters: const <String, Object>{
          'dataset_id': preferredSharedDatasetId,
        },
        options: evidenceOptions,
      );
      final capabilitiesData = _asMap(capabilitiesResponse.data);
      final benchmarkData = _asMap(benchmarkResponse.data);
      final datasets = capabilitiesData['datasets'];
      final datasetData = datasets is List
          ? datasets
                .map(_asMap)
                .firstWhere(
                  (item) => item['dataset_id'] == preferredSharedDatasetId,
                  orElse: () => <String, dynamic>{},
                )
          : <String, dynamic>{};
      if (datasetData.isEmpty) {
        throw FormatException('共享后端未登记所选数据集 $preferredSharedDatasetId');
      }
      final quality = _asMap(datasetData['quality']);
      final contracts = _asMap(capabilitiesData['contracts']);
      final environment = _asMap(
        contracts[datasetData['environment_version']?.toString()],
      );
      final benchmarkAlgorithms = benchmarkData['algorithms'] is List
          ? (benchmarkData['algorithms'] as List).map(_asMap).toList()
          : const <Map<String, dynamic>>[];
      final benchmarkById = <String, Map<String, dynamic>>{
        for (final item in benchmarkAlgorithms)
          if (item['id'] != null) item['id'].toString(): item,
      };
      final rawAlgorithms = capabilitiesData['algorithms'];
      final algorithmItems = rawAlgorithms is List
          ? rawAlgorithms
                .map(_asMap)
                .where((item) => item['id'] != null)
                .map(
                  (item) => RlAlgorithmDescriptor(
                    id: item['id'].toString(),
                    label:
                        item['label']?.toString() ??
                        item['name']?.toString() ??
                        item['id'].toString(),
                    family: item['family']?.toString() ?? 'unknown',
                    library:
                        item['library']?.toString() ??
                        item['implementation']?.toString() ??
                        'unknown',
                    trainable: item['trainable'] != false,
                    status:
                        item['status']?.toString() ??
                        (benchmarkById.containsKey(item['id']?.toString())
                            ? 'EVALUATED'
                            : 'AVAILABLE'),
                    multiSeedReady:
                        benchmarkById[item['id']
                            ?.toString()]?['multi_seed_ready'] ==
                        true,
                  ),
                )
                .toList(growable: false)
          : const <RlAlgorithmDescriptor>[];
      if (!hasCompatibleSharedRlContract(
        algorithmItems.map((item) => item.id),
      )) {
        throw const FormatException('共享后端算法合同缺少核心方法或包含未登记方法');
      }
      final environmentVersion =
          datasetData['environment_version']?.toString() ?? '—';
      final observationDimensions = _toInt(
        environment['observation_dimensions'],
      );
      final actionDimensions = _toInt(
        environment['continuous_action_dimensions'],
      );
      if (!supportedSharedEnvironmentVersions.contains(environmentVersion) ||
          observationDimensions != sharedObservationDimensions ||
          actionDimensions != sharedActionDimensions) {
        throw const FormatException('共享后端未返回 port_ops_v2/v3 37维观测/5维动作契约');
      }
      final formalRlRunCount = benchmarkAlgorithms
          .where(
            (item) => !sharedNonTrainableAlgorithmIds.contains(
              item['id']?.toString(),
            ),
          )
          .fold<int>(
            0,
            (sum, item) => sum + _toInt(item['claim_eligible_runs']),
          );
      final formalControlBaselineCount = benchmarkAlgorithms
          .where(
            (item) =>
                sharedNonTrainableAlgorithmIds.contains(item['id']?.toString()),
          )
          .fold<int>(
            0,
            (sum, item) => sum + _toInt(item['claim_eligible_runs']),
          );
      final formalAlgorithmReadyCount = benchmarkAlgorithms
          .where((item) => item['multi_seed_ready'] == true)
          .length;
      final interpolationCounts = _asMap(
        datasetData['short_gap_interpolation_counts'],
      );
      final rawSources = datasetData['sources'];
      final sourcePublishers = rawSources is List
          ? rawSources
                .map(_asMap)
                .map((item) => item['publisher']?.toString() ?? '')
                .where((item) => item.isNotEmpty)
                .toSet()
                .join(' + ')
          : '—';
      final shortGapInterpolationCount = interpolationCounts.values.fold<int>(
        0,
        (sum, value) => sum + _toInt(value),
      );
      final desktopStatus = await _readDesktopPanelStatus();
      state = state.copyWith(
        phase: previousPhase == RlDesktopTrainingPhase.failed
            ? RlDesktopTrainingPhase.idle
            : previousPhase,
        desktopOnline: true,
        desktopPanelActive: desktopStatus.$1,
        desktopPanelUrl: desktopStatus.$2,
        desktopLaunchMessage: desktopStatus.$3,
        algorithms: algorithmItems,
        datasetId: datasetData['dataset_id']?.toString() ?? '—',
        datasetTitle: datasetData['title']?.toString() ?? '未命名数据登记',
        datasetBoundary: datasetData['warning']?.toString() ?? '未声明数据使用边界',
        sourcePublishers: sourcePublishers,
        datasetSha256: datasetData['sha256']?.toString() ?? '—',
        datasetRows: _toInt(datasetData['rows']),
        independentSourceObservations: _toInt(
          datasetData['independent_source_observations'],
        ),
        trainRows: _toInt(datasetData['train_rows']),
        testRows: _toInt(datasetData['test_rows']),
        environmentVersion: environmentVersion,
        portProfileId: datasetData['port_profile_id']?.toString() ?? '—',
        observationDimensions: observationDimensions,
        actionDimensions: actionDimensions,
        availableFactorCount: _toInt(quality['available_factor_count']),
        totalFactorCount: _toInt(quality['factor_count']),
        shortGapInterpolationCount: shortGapInterpolationCount,
        formalRlRunCount: formalRlRunCount,
        formalControlBaselineCount: formalControlBaselineCount,
        formalAlgorithmReadyCount: formalAlgorithmReadyCount,
        datasetSplit:
            '${_toInt(datasetData['train_rows'])}/${_toInt(datasetData['test_rows'])} 时序划分',
        evidenceLevel: datasetData['evidence_tier']?.toString() ?? '未声明证据级别',
        liveDataVerified: datasetData['live_data_verified'] == true,
        stage: state.hasRequest
            ? state.stage
            : '${algorithmItems.length}方法、$environmentVersion 与公开数据指纹已核验，等待提交',
        updatedAt: DateTime.now(),
      );
    } on DioException catch (error) {
      state = state.copyWith(
        phase: state.hasRequest ? previousPhase : RlDesktopTrainingPhase.failed,
        desktopOnline: false,
        stage: '无法连接电脑端训练服务',
        errorMessage: _friendlyDioError(error),
        updatedAt: DateTime.now(),
      );
    } on FormatException catch (error) {
      state = state.copyWith(
        phase: state.hasRequest ? previousPhase : RlDesktopTrainingPhase.failed,
        desktopOnline: false,
        stage: '共享训练契约校验失败',
        errorMessage: error.message,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<bool> launchDesktopPanel() async {
    if (state.desktopLaunchInProgress) return false;
    state = state.copyWith(
      desktopLaunchInProgress: true,
      desktopLaunchMessage: '正在向电脑发送桌面系统启动命令…',
      errorMessage: null,
      updatedAt: DateTime.now(),
    );
    try {
      final response = await _dio.post<Object>('/api/rl/desktop/launch');
      final data = _asMap(response.data);
      final launched = data['launched'] == true;
      final url = data['url']?.toString() ?? state.desktopPanelUrl;
      state = state.copyWith(
        desktopOnline: true,
        desktopPanelUrl: url,
        desktopLaunchMessage: launched
            ? '启动命令已发送，等待电脑端审批页回报在线'
            : (data['message']?.toString() ?? '电脑端未确认启动'),
        logs: _prependLog('POST /api/rl/desktop/launch · 桌面端启动命令已发送'),
        updatedAt: DateTime.now(),
      );
      for (var attempt = 0; attempt < 8; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        await refreshDesktopPanelStatus();
        if (state.desktopPanelActive) break;
      }
      return launched;
    } on DioException catch (error) {
      state = state.copyWith(
        desktopOnline: false,
        desktopLaunchMessage: '电脑端系统启动失败',
        errorMessage: _friendlyDioError(error),
        updatedAt: DateTime.now(),
      );
      return false;
    } finally {
      state = state.copyWith(desktopLaunchInProgress: false);
    }
  }

  Future<void> refreshDesktopPanelStatus() async {
    if (_desktopStatusPolling) return;
    _desktopStatusPolling = true;
    try {
      final status = await _readDesktopPanelStatus();
      state = state.copyWith(
        desktopOnline: true,
        desktopPanelActive: status.$1,
        desktopPanelUrl: status.$2,
        desktopLaunchMessage: status.$3,
        updatedAt: DateTime.now(),
      );
    } on DioException catch (error) {
      state = state.copyWith(
        desktopPanelActive: false,
        desktopLaunchMessage: '未收到电脑端审批页心跳',
        errorMessage: _friendlyDioError(error),
        updatedAt: DateTime.now(),
      );
    } finally {
      _desktopStatusPolling = false;
    }
  }

  Future<(bool, String, String)> _readDesktopPanelStatus() async {
    final response = await _dio.get<Object>('/api/rl/desktop/status');
    final data = _asMap(response.data);
    final active = data['panel_active'] == true;
    final url = data['url']?.toString() ?? state.desktopPanelUrl;
    final message = active
        ? '电脑端强化学习审批页已打开，可切换到电脑操作'
        : (data['message']?.toString() ?? '电脑端服务在线，审批页尚未打开');
    return (active, url, message);
  }

  Future<bool> submitTrainingRequest() async {
    if (state.isBusy ||
        state.phase == RlDesktopTrainingPhase.waitingDesktopApproval ||
        state.phase == RlDesktopTrainingPhase.training ||
        state.phase == RlDesktopTrainingPhase.evaluating) {
      return false;
    }
    state = state.copyWith(
      phase: RlDesktopTrainingPhase.preparingRequest,
      stage: '封装数据指纹、训练参数与人工审批边界',
      progress: 0,
      logs: <String>[
        '已锁定数据集 ${state.datasetId} · ${_shortHash(state.datasetSha256)}',
        '已校验手机端无训练直启权限',
      ],
      errorMessage: null,
    );
    try {
      final response = await _dio.post<Object>(
        '/api/rl/train/requests',
        data: <String, Object>{
          'source': 'dt_mobile_app',
          'requested_by': '移动端值班调度员',
          'config': <String, Object>{
            ...state.config.toJson(),
            'dataset_id': state.datasetId,
          },
          'scenario_snapshot': <String, Object>{
            'dataset_id': state.datasetId,
            'dataset_sha256': state.datasetSha256,
            'evidence_level': state.evidenceLevel,
            'live_data_verified': state.liveDataVerified,
          },
          'policy_context': <String, Object>{
            'summary': '港口交通流与安全余量策略训练',
            'human_confirmation_required': true,
            'production_dispatch': false,
          },
        },
      );
      final data = _asMap(response.data);
      final requestId = data['request_id']?.toString();
      if (requestId == null || requestId.isEmpty) {
        throw StateError('电脑端未返回训练申请编号');
      }
      state = state.copyWith(
        phase: RlDesktopTrainingPhase.waitingDesktopApproval,
        desktopOnline: true,
        requestId: requestId,
        jobId: null,
        stage: '申请已到达电脑端，尚未创建训练任务',
        logs: <String>[
          'POST /api/rl/train/requests · 电脑端已接收',
          '申请编号 $requestId',
          '等待电脑端点击“电脑端批准并启动训练”',
          ...state.logs,
        ],
        updatedAt: DateTime.now(),
      );
      _startPolling();
      return true;
    } on DioException catch (error) {
      _setFailure(_friendlyDioError(error));
    } catch (error) {
      _setFailure(error.toString());
    }
    return false;
  }

  Future<void> refreshStatus() async {
    if (_polling) return;
    final requestId = state.requestId;
    if (requestId == null) {
      await checkConnection();
      return;
    }
    _polling = true;
    try {
      final response = await _dio.get<Object>(
        '/api/rl/train/requests/$requestId',
      );
      final request = _asMap(response.data);
      final requestStatus = request['status']?.toString();
      if (requestStatus == 'rejected') {
        _pollTimer?.cancel();
        state = state.copyWith(
          phase: RlDesktopTrainingPhase.rejected,
          desktopOnline: true,
          stage: '电脑端人工复核后拒绝，本次训练未启动',
          approvedBy: null,
          errorMessage: request['rejection_reason']?.toString(),
          logs: _prependLog('电脑端已拒绝申请 · 未创建训练任务'),
          updatedAt: DateTime.now(),
        );
        return;
      }

      final jobId = request['job_id']?.toString();
      final approvedBy = request['approved_by']?.toString();
      final embeddedStatus = _asMap(request['training_status']);
      if (jobId != null && jobId.isNotEmpty) {
        state = state.copyWith(
          phase: RlDesktopTrainingPhase.approved,
          desktopOnline: true,
          jobId: jobId,
          approvedBy: approvedBy,
          stage: '电脑端人工批准，训练任务 $jobId 已创建',
          logs: state.jobId == null
              ? _prependLog('电脑端 $approvedBy 已批准 · Job $jobId')
              : state.logs,
          updatedAt: DateTime.now(),
        );
        if (embeddedStatus.isNotEmpty) {
          _applyTrainingStatus(embeddedStatus);
        } else {
          await _refreshJobStatus(jobId);
        }
        if (state.phase == RlDesktopTrainingPhase.completed &&
            state.replayFrames.isEmpty) {
          await _refreshReplay(jobId);
        }
      } else {
        state = state.copyWith(
          phase: RlDesktopTrainingPhase.waitingDesktopApproval,
          desktopOnline: true,
          stage: '电脑端已收到申请，等待人工批准',
          updatedAt: DateTime.now(),
        );
      }
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        _pollTimer?.cancel();
        state = state.copyWith(
          phase: RlDesktopTrainingPhase.failed,
          desktopOnline: true,
          requestId: null,
          jobId: null,
          stage: '电脑端已重启，原训练申请失效，请重新提交',
          errorMessage: '原申请只存在于上一次电脑端进程，本次未启动训练',
          logs: _prependLog('电脑端会话已更新 · 原申请未执行'),
          updatedAt: DateTime.now(),
        );
      } else {
        state = state.copyWith(
          desktopOnline: false,
          errorMessage: _friendlyDioError(error),
          updatedAt: DateTime.now(),
        );
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _refreshJobStatus(String jobId) async {
    final response = await _dio.get<Object>(
      '/api/rl/train/status',
      queryParameters: <String, Object>{'job_id': jobId},
    );
    final wrapper = _asMap(response.data);
    _applyTrainingStatus(
      _asMap(wrapper['status']).isNotEmpty
          ? _asMap(wrapper['status'])
          : wrapper,
    );
    if (state.phase == RlDesktopTrainingPhase.completed &&
        state.replayFrames.isEmpty) {
      await _refreshReplay(jobId);
    }
  }

  void _applyTrainingStatus(Map<String, dynamic> status) {
    final metrics = _asMap(status['metrics']);
    final statusName = (status['status'] ?? '').toString().toUpperCase();
    final progress = _toDouble(status['progress']).clamp(0, 100).toDouble();
    final step = _toInt(status['step'] ?? metrics['step']);
    final totalSteps = _toInt(
      status['total_steps'] ??
          metrics['total_steps'] ??
          state.config.totalSteps,
    );
    final rate = _toDouble(status['step_rate_per_second']);
    final remainingSeconds = totalSteps > step && rate > 0
        ? ((totalSteps - step) / rate).ceil()
        : null;
    final phase = switch (statusName) {
      'COMPLETED' => RlDesktopTrainingPhase.completed,
      'EVALUATING' || 'TRAINED' => RlDesktopTrainingPhase.evaluating,
      'RUNNING' || 'STARTING' || 'PAUSED' => RlDesktopTrainingPhase.training,
      'FAILED' => RlDesktopTrainingPhase.failed,
      _ => RlDesktopTrainingPhase.approved,
    };
    final history = status['history'] is List
        ? (status['history'] as List)
              .map(_asMap)
              .map(
                (item) => RlMetricPoint(
                  step: _toInt(item['step']),
                  reward: _toDouble(item['reward']),
                  episodes: _toInt(item['episodes']),
                ),
              )
              .toList(growable: false)
        : state.history;
    final aggregate = _asMap(status['aggregate_metrics']);
    final evaluationMetrics = <String, double>{
      for (final entry in aggregate.entries)
        if (entry.value is num) entry.key: (entry.value as num).toDouble(),
    };
    final incomingLogs = status['logs'] is List
        ? (status['logs'] as List)
              .map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .take(8)
              .toList(growable: false)
        : const <String>[];
    state = state.copyWith(
      phase: phase,
      desktopOnline: true,
      progress: progress,
      stage: status['stage']?.toString() ?? state.stage,
      step: step,
      reward: _toDouble(status['reward'] ?? metrics['reward']),
      entropy: _toDouble(status['entropy'] ?? metrics['entropy']),
      policyVersion: state.jobId ?? '—',
      eta: phase == RlDesktopTrainingPhase.completed
          ? '已完成'
          : (remainingSeconds == null
                ? '由训练器计算中'
                : _durationLabel(remainingSeconds)),
      totalStepsReported: totalSteps,
      datasetSplit: status['dataset_split']?.toString() ?? state.datasetSplit,
      datasetSha256:
          status['dataset_sha256']?.toString() ?? state.datasetSha256,
      renderReady: status['render_ready'] == true,
      history: history,
      evaluationMetrics: evaluationMetrics.isEmpty
          ? state.evaluationMetrics
          : evaluationMetrics,
      logs: incomingLogs.isEmpty ? state.logs : incomingLogs,
      errorMessage: null,
      updatedAt: DateTime.now(),
    );
    if (phase == RlDesktopTrainingPhase.completed) {
      _pollTimer?.cancel();
    }
  }

  Future<void> _refreshReplay(String jobId) async {
    try {
      final response = await _dio.get<Object>(
        '/api/rl/artifacts/$jobId/replay',
      );
      final data = _asMap(response.data);
      final frames = data['frames'] is List
          ? (data['frames'] as List).map(_asMap).toList(growable: false)
          : const <Map<String, dynamic>>[];
      final aggregate = _asMap(data['aggregate_metrics']);
      state = state.copyWith(
        replayFrames: frames,
        renderReady: frames.isNotEmpty,
        evaluationMetrics: <String, double>{
          for (final entry in aggregate.entries)
            if (entry.value is num) entry.key: (entry.value as num).toDouble(),
        },
        logs: _prependLog('留出测试轨迹已读取 · ${frames.length} 帧'),
        updatedAt: DateTime.now(),
      );
    } on DioException catch (error) {
      state = state.copyWith(errorMessage: _friendlyDioError(error));
    }
  }

  void reset() {
    _pollTimer?.cancel();
    state = RlTrainingState(
      config: state.config,
      configSource: state.configSource,
      desktopOnline: state.desktopOnline,
      desktopPanelActive: state.desktopPanelActive,
      desktopPanelUrl: state.desktopPanelUrl,
      desktopLaunchMessage: state.desktopLaunchMessage,
      datasetId: state.datasetId,
      datasetTitle: state.datasetTitle,
      datasetBoundary: state.datasetBoundary,
      sourcePublishers: state.sourcePublishers,
      datasetSha256: state.datasetSha256,
      datasetRows: state.datasetRows,
      independentSourceObservations: state.independentSourceObservations,
      trainRows: state.trainRows,
      testRows: state.testRows,
      environmentVersion: state.environmentVersion,
      portProfileId: state.portProfileId,
      observationDimensions: state.observationDimensions,
      actionDimensions: state.actionDimensions,
      availableFactorCount: state.availableFactorCount,
      totalFactorCount: state.totalFactorCount,
      shortGapInterpolationCount: state.shortGapInterpolationCount,
      formalRlRunCount: state.formalRlRunCount,
      formalControlBaselineCount: state.formalControlBaselineCount,
      formalAlgorithmReadyCount: state.formalAlgorithmReadyCount,
      evidenceLevel: state.evidenceLevel,
      liveDataVerified: state.liveDataVerified,
      algorithms: state.algorithms,
    );
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(refreshStatus()),
    );
  }

  void _setFailure(String message) {
    _pollTimer?.cancel();
    state = state.copyWith(
      phase: RlDesktopTrainingPhase.failed,
      desktopOnline: false,
      stage: '训练申请未提交，电脑端没有收到任务',
      errorMessage: message,
      logs: _prependLog('联动失败 · $message'),
      updatedAt: DateTime.now(),
    );
  }

  List<String> _prependLog(String message) =>
      <String>[message, ...state.logs].take(8).toList(growable: false);

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  static int _toInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _shortHash(String value) {
    if (value.length <= 12) return value;
    return value.substring(0, 12);
  }

  static String _durationLabel(int seconds) {
    if (seconds < 60) return '约 $seconds 秒';
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '约 $minutes 分钟';
    final hours = (minutes / 60).ceil();
    return '约 $hours 小时';
  }

  static String _friendlyDioError(DioException error) {
    final status = error.response?.statusCode;
    if (status != null) {
      return '电脑端返回 $status，请在电脑端强化学习面板检查申请状态';
    }
    return '未连接电脑端（10.0.2.2:8000），请先启动电脑端港口平台';
  }
}

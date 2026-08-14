const String preferredSharedDatasetId = String.fromEnvironment(
  'RL_DATASET_ID',
  defaultValue: 'public_us_la_6min_v1',
);
const Set<String> supportedSharedEnvironmentVersions = <String>{
  'port_ops_v2',
  'port_ops_v3',
};

const int sharedObservationDimensions = 37;
const int sharedActionDimensions = 5;
const int sharedRealityFactorCount = 12;

/// 所有共享 Web 后端必须保留的核心合同。
const Set<String> requiredSharedAlgorithmIds = <String>{
  'sac',
  'ppo',
  'td3',
  'dqn',
  'a2c',
  'tqc',
  'mpc',
};

/// 当前 V3.2 Web 后端公开的完整能力集合。
const Set<String> supportedSharedAlgorithmIds = <String>{
  ...requiredSharedAlgorithmIds,
  'qrdqn',
  'trpo',
  'recurrent_ppo',
  'ars',
  'fcfs',
};

const Set<String> sharedNonTrainableAlgorithmIds = <String>{'mpc', 'fcfs'};

const Map<String, String> sharedRlAlgorithmLabels = <String, String>{
  'sac': 'SAC · 最大熵连续控制',
  'ppo': 'PPO · 稳定策略优化',
  'td3': 'TD3 · 双延迟连续控制',
  'dqn': 'DQN · 离散调度',
  'a2c': 'A2C · 同步优势演员评论家',
  'tqc': 'TQC · 截断分位数评论家',
  'qrdqn': 'QR-DQN · 分位数离散控制',
  'trpo': 'TRPO · 信赖域策略优化',
  'recurrent_ppo': 'Recurrent PPO · 时序记忆策略',
  'ars': 'ARS · 随机搜索鲁棒基线',
  'mpc': 'MPC · 模型预测控制基线',
  'fcfs': 'FCFS · 中性规则基线',
};

bool hasCompatibleSharedRlContract(Iterable<String> algorithmIds) {
  final ids = algorithmIds.toSet();
  return requiredSharedAlgorithmIds.difference(ids).isEmpty &&
      ids.difference(supportedSharedAlgorithmIds).isEmpty;
}

const String preferredSharedDatasetId = String.fromEnvironment(
  'RL_DATASET_ID',
  defaultValue: 'public_us_la_6min_v1',
);
const String preferredSharedEnvironmentVersion = 'port_ops_v2';

const int sharedObservationDimensions = 37;
const int sharedActionDimensions = 5;
const int sharedRealityFactorCount = 12;

const Set<String> sharedRlAlgorithmIds = <String>{
  'sac',
  'ppo',
  'td3',
  'dqn',
  'a2c',
  'tqc',
  'mpc',
};

const Map<String, String> sharedRlAlgorithmLabels = <String, String>{
  'sac': 'SAC · 最大熵连续控制',
  'ppo': 'PPO · 稳定策略优化',
  'td3': 'TD3 · 双延迟连续控制',
  'dqn': 'DQN · 离散调度',
  'a2c': 'A2C · 同步优势演员评论家',
  'tqc': 'TQC · 截断分位数评论家',
  'mpc': 'MPC · 模型预测控制基线',
};

bool hasExactSharedRlContract(Iterable<String> algorithmIds) {
  return algorithmIds.toSet().difference(sharedRlAlgorithmIds).isEmpty &&
      sharedRlAlgorithmIds.difference(algorithmIds.toSet()).isEmpty;
}

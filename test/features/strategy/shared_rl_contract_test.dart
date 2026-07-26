import 'package:flutter_test/flutter_test.dart';

import 'package:dt_mobile_app/core/config/app_config.dart';
import 'package:dt_mobile_app/features/strategy/application/rl_training_controller.dart';
import 'package:dt_mobile_app/features/strategy/domain/shared_rl_contract.dart';

void main() {
  group('shared Web RL contract', () {
    test('accepts exactly six RL algorithms plus MPC', () {
      expect(
        hasExactSharedRlContract(const <String>[
          'mpc',
          'tqc',
          'a2c',
          'dqn',
          'td3',
          'ppo',
          'sac',
        ]),
        isTrue,
      );
      expect(
        hasExactSharedRlContract(const <String>[
          'sac',
          'ppo',
          'td3',
          'dqn',
          'mpc',
        ]),
        isFalse,
      );
    });

    test('uses the port_ops_v2 public benchmark defaults', () {
      const config = RlTrainingConfig();

      expect(preferredSharedDatasetId, 'public_us_la_6min_v1');
      expect(preferredSharedEnvironmentVersion, 'port_ops_v2');
      expect(sharedObservationDimensions, 37);
      expect(sharedActionDimensions, 5);
      expect(sharedRealityFactorCount, 12);
      expect(config.objective, 'multi_objective');
      expect(config.scenario, 'public_benchmark_replay');
      expect(config.toJson()['evaluation_episodes'], 10);
      expect(config.toJson()['episode_hours'], 12);
    });

    test('uses only shared-backend CORS-approved default headers', () {
      expect(AppConfig.defaultHeaders(), const <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      });
    });
  });
}

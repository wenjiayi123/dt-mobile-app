import 'package:flutter_test/flutter_test.dart';

import 'package:dt_mobile_app/core/config/app_config.dart';
import 'package:dt_mobile_app/features/strategy/application/rl_training_controller.dart';
import 'package:dt_mobile_app/features/strategy/domain/shared_rl_contract.dart';

void main() {
  group('shared Web RL contract', () {
    test(
      'requires the core contract and accepts registered V3.2 expansion',
      () {
        expect(
          hasCompatibleSharedRlContract(const <String>[
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
          hasCompatibleSharedRlContract(const <String>[
            'sac',
            'ppo',
            'td3',
            'dqn',
            'mpc',
          ]),
          isFalse,
        );
        expect(
          hasCompatibleSharedRlContract(const <String>[
            'sac',
            'ppo',
            'td3',
            'dqn',
            'a2c',
            'tqc',
            'qrdqn',
            'trpo',
            'recurrent_ppo',
            'ars',
            'mpc',
            'fcfs',
          ]),
          isTrue,
        );
        expect(
          hasCompatibleSharedRlContract(<String>{
            ...requiredSharedAlgorithmIds,
            'unregistered_method',
          }),
          isFalse,
        );
      },
    );

    test('uses the port_ops_v2 public benchmark defaults', () {
      const config = RlTrainingConfig();

      expect(preferredSharedDatasetId, 'public_us_la_6min_v1');
      expect(
        supportedSharedEnvironmentVersions,
        containsAll(['port_ops_v2', 'port_ops_v3']),
      );
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

    test('uses localhost for Flutter Web and emulator mapping for Android', () {
      expect(
        AppConfig.resolveApiBaseUrl(configured: '', web: true),
        'http://127.0.0.1:8000',
      );
      expect(
        AppConfig.resolveApiBaseUrl(configured: '', web: false),
        'http://10.0.2.2:8000',
      );
      expect(
        AppConfig.resolveApiBaseUrl(
          configured: ' https://port.example/api ',
          web: true,
        ),
        'https://port.example/api',
      );
    });
  });
}

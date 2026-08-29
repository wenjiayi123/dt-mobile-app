import 'package:dt_mobile_app/features/home/application/shared_system_evidence_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the current shared system evidence contract', () {
    final evidence = SharedSystemEvidence.fromJson(<String, dynamic>{
      'backend_id': 'port-dt-multi',
      'shared_backend_verified': true,
      'frontends': <String>['web', 'flutter_mobile'],
      'business_benchmark': <String, dynamic>{
        'dataset_id': 'public_port_ops_v1',
        'test_rows': 8760,
        'berth_utilization_point_gain': 7.454,
        'summary_metrics_percent': <String, dynamic>{
          'berth_utilization_relative_improvement_percent': 9,
          'average_waiting_time_reduction_percent': 17,
          'scenario_energy_cost_reduction_percent': 12,
        },
      },
      'mobile_workflow_benchmark': <String, dynamic>{
        'operations': 500,
        'results': <String, dynamic>{
          'audit_chain_valid': true,
          'unsafe_dispatch_block_percent': 100,
          'duplicate_suppression_percent': 100,
        },
      },
      'audit': <String, dynamic>{'valid': true},
    });

    expect(evidence.backendId, 'port-dt-multi');
    expect(evidence.testRows, 8760);
    expect(evidence.berthImprovementPercent, 9);
    expect(evidence.berthPointGain, closeTo(7.454, 0.001));
    expect(evidence.waitReductionPercent, 17);
    expect(evidence.costReductionPercent, 12);
    expect(evidence.workflowOperations, 500);
    expect(evidence.auditChainValid, isTrue);
  });

  test('keeps compatibility with the legacy claims field', () {
    final evidence = SharedSystemEvidence.fromJson(<String, dynamic>{
      'backend_id': 'port-dt-multi',
      'shared_backend_verified': true,
      'frontends': <String>['web', 'flutter_mobile'],
      'business_benchmark': <String, dynamic>{
        'dataset_id': 'legacy_dataset',
        'test_rows': 12,
        'claims_percent': <String, dynamic>{
          'berth_utilization_relative_improvement_percent': 4,
          'average_waiting_time_reduction_percent': 5,
          'scenario_energy_cost_reduction_percent': 6,
        },
      },
      'mobile_workflow_benchmark': <String, dynamic>{
        'operations': 10,
        'results': <String, dynamic>{
          'audit_chain_valid': true,
          'unsafe_dispatch_block_percent': 100,
          'duplicate_suppression_percent': 100,
        },
      },
      'audit': <String, dynamic>{'valid': true},
    });

    expect(evidence.berthImprovementPercent, 4);
    expect(evidence.waitReductionPercent, 5);
    expect(evidence.costReductionPercent, 6);
  });

  test('rejects a response that is not the shared Web/mobile backend', () {
    expect(
      () => SharedSystemEvidence.fromJson(<String, dynamic>{
        'backend_id': 'unknown',
        'shared_backend_verified': false,
        'frontends': <String>['flutter_mobile'],
      }),
      throwsFormatException,
    );
  });
}

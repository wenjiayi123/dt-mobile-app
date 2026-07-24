import 'package:dt_mobile_app/features/home/application/shared_system_evidence_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the shared system and mobile workflow evidence separately', () {
    final evidence = SharedSystemEvidence.fromJson(<String, dynamic>{
      'backend_id': 'port-dt-multi',
      'business_benchmark': <String, dynamic>{
        'dataset_id': 'public_port_ops_v1',
        'test_rows': 8760,
        'berth_utilization_point_gain': 7.454,
        'claims_percent': <String, dynamic>{
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
    expect(evidence.workflowOperations, 500);
    expect(evidence.auditChainValid, isTrue);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/core/network/dio_provider.dart';

@immutable
class SharedSystemEvidence {
  const SharedSystemEvidence({
    required this.backendId,
    required this.datasetId,
    required this.testRows,
    required this.berthImprovementPercent,
    required this.berthPointGain,
    required this.waitReductionPercent,
    required this.costReductionPercent,
    required this.workflowOperations,
    required this.auditChainValid,
    required this.unsafeDispatchBlockPercent,
    required this.duplicateSuppressionPercent,
  });

  final String backendId;
  final String datasetId;
  final int testRows;
  final double berthImprovementPercent;
  final double berthPointGain;
  final double waitReductionPercent;
  final double costReductionPercent;
  final int workflowOperations;
  final bool auditChainValid;
  final double unsafeDispatchBlockPercent;
  final double duplicateSuppressionPercent;

  factory SharedSystemEvidence.fromJson(Map<String, dynamic> json) {
    final business = _map(json['business_benchmark']);
    final claims = _map(business['claims_percent']);
    final workflow = _map(json['mobile_workflow_benchmark']);
    final results = _map(workflow['results']);
    final runtimeAudit = _map(json['audit']);
    return SharedSystemEvidence(
      backendId: json['backend_id']?.toString() ?? 'unknown',
      datasetId: business['dataset_id']?.toString() ?? 'unknown',
      testRows: _int(business['test_rows']),
      berthImprovementPercent: _double(
        claims['berth_utilization_relative_improvement_percent'],
      ),
      berthPointGain: _double(business['berth_utilization_point_gain']),
      waitReductionPercent: _double(
        claims['average_waiting_time_reduction_percent'],
      ),
      costReductionPercent: _double(
        claims['scenario_energy_cost_reduction_percent'],
      ),
      workflowOperations: _int(workflow['operations']),
      auditChainValid:
          results['audit_chain_valid'] == true && runtimeAudit['valid'] == true,
      unsafeDispatchBlockPercent: _double(
        results['unsafe_dispatch_block_percent'],
      ),
      duplicateSuppressionPercent: _double(
        results['duplicate_suppression_percent'],
      ),
    );
  }

  static Map<String, dynamic> _map(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  static int _int(Object? raw) =>
      raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;

  static double _double(Object? raw) =>
      raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
}

final sharedSystemEvidenceProvider =
    FutureProvider.autoDispose<SharedSystemEvidence>((ref) async {
      final response = await ref
          .read(dioProvider)
          .get<Object>('/api/mobile/status');
      final raw = response.data;
      if (raw is! Map) {
        throw const FormatException('共享后端状态不是 JSON 对象');
      }
      return SharedSystemEvidence.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    });

import 'package:dt_mobile_app/features/strategy/application/strategy_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final acceptedAt = DateTime.utc(2026, 7, 24);

  test('accepts only an explicit auditable dry-run receipt', () {
    final receipt = StrategyRepository.parseDryRunReceipt(<String, dynamic>{
      'accepted': true,
      'request_id': 'decision-0123456789abcdef',
      'execution_status': 'dry_run_recorded',
      'production_dispatch': false,
      'message': 'recorded',
    }, acceptedAt: acceptedAt);

    expect(receipt.requestId, 'decision-0123456789abcdef');
    expect(receipt.status, StrategyExecutionStatus.dryRunRecorded);
    expect(receipt.acceptedAt, acceptedAt);
  });

  test('fails closed when the server omits the production boundary', () {
    expect(
      () => StrategyRepository.parseDryRunReceipt(<String, dynamic>{
        'accepted': true,
        'request_id': 'decision-0123456789abcdef',
        'execution_status': 'dry_run_recorded',
      }, acceptedAt: acceptedAt),
      throwsStateError,
    );
  });

  test('rejects a production execution acknowledgement', () {
    expect(
      () => StrategyRepository.parseDryRunReceipt(<String, dynamic>{
        'accepted': true,
        'request_id': 'decision-0123456789abcdef',
        'execution_status': 'acked',
        'production_dispatch': true,
      }, acceptedAt: acceptedAt),
      throwsStateError,
    );
  });
}

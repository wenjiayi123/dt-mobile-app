import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dt_mobile_app/features/audit/application/audit_controller.dart';

class _DelayedAuditRepository implements AuditRepository {
  final Completer<AuditUploadResult> uploadCompleter =
      Completer<AuditUploadResult>();

  @override
  Future<AuditEvent> saveLocal(AuditEvent event) async => event;

  @override
  Future<AuditEvent> updateLocal(AuditEvent event) async => event;

  @override
  Future<AuditUploadResult> upload(AuditEvent event) =>
      uploadCompleter.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('late audit upload does not access a disposed provider ref', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = _DelayedAuditRepository();
    final uncaught = <Object>[];

    await runZonedGuarded(() async {
      final container = ProviderContainer(
        overrides: [
          auditRepositoryProvider.overrideWithValue(repository),
          auditUploadEnabledProvider.overrideWithValue(true),
        ],
      );

      container
          .read(auditTimelineProvider.notifier)
          .recordEvent(
            source: AuditEventSource.executionFeedback,
            actionType: AuditActionType.guidance,
            stateSummary: '页面关闭前已记录',
            policySetSummary: '等待服务端回执',
            humanChoiceSummary: '人工确认',
            eventId: 'dispose-race',
          );

      container.dispose();
      repository.uploadCompleter.complete(
        const AuditUploadResult(
          status: AuditUploadStatus.success,
          message: 'late success',
          statusCode: 200,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }, (error, _) {
      uncaught.add(error);
    });

    expect(uncaught, isEmpty);
  });
}

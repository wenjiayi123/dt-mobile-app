import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dt_mobile_app/features/audit/application/audit_controller.dart';
import 'package:dt_mobile_app/features/replay/application/replay_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'audit event without structured metrics does not synthesize replay',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(auditTimelineProvider.notifier)
          .recordEvent(
            source: AuditEventSource.executionFeedback,
            actionType: AuditActionType.guidance,
            stateSummary: '执行回执已返回',
            policySetSummary: '未附结构化指标',
            humanChoiceSummary: '人工表态：Guidance',
            eventId: 'no-metrics',
          );

      final timeline = await container
          .read(replayRepositoryProvider)
          .getTimeline('no-metrics');

      expect(timeline.frames, isEmpty);
    },
  );

  test(
    'structured candidate metrics produce one evidence-backed frame',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(auditTimelineProvider.notifier)
          .recordEvent(
            source: AuditEventSource.executionFeedback,
            actionType: AuditActionType.guidance,
            stateSummary: '留出测试策略已记录',
            policySetSummary: 'PPO held-out test',
            humanChoiceSummary: '仅 dry-run',
            eventId: 'structured-anchor',
            payload: const <String, Object?>{
              'executionStatus': 'acked',
              'candidate_snapshot': <String, Object?>{
                'conflictRisk': <String, Object?>{'low': 21, 'high': 27},
                'relatedAlerts': <Object?>[],
              },
            },
          );

      final timeline = await container
          .read(replayRepositoryProvider)
          .getTimeline('structured-anchor');

      expect(timeline.frames, hasLength(1));
      expect(timeline.selectedFrame?.eventId, 'structured-anchor');
      expect(timeline.selectedFrame?.snapshot.riskInterval.low, 21);
      expect(timeline.selectedFrame?.snapshot.riskInterval.high, 27);
    },
  );
}

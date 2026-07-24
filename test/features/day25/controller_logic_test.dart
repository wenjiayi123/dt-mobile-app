import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dt_mobile_app/features/audit/application/audit_controller.dart';
import 'package:dt_mobile_app/features/situation/application/situation_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuditTimelineNotifier', () {
    test('recordEvent / limit / clear works', () async {
      SharedPreferences.setMockInitialValues({});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(auditTimelineProvider.notifier);

      notifier.updateMaxKeep(2);

      notifier.recordEvent(
        source: AuditEventSource.aiSuggestion,
        actionType: AuditActionType.guidance,
        stateSummary: 'state 1',
        policySetSummary: 'policy 1',
        humanChoiceSummary: 'choice 1',
        eventId: 'a1',
        time: DateTime(2026, 1, 1, 10, 0, 0),
      );

      notifier.recordEvent(
        source: AuditEventSource.humanOverride,
        actionType: AuditActionType.override,
        stateSummary: 'state 2',
        policySetSummary: 'policy 2',
        humanChoiceSummary: 'choice 2',
        eventId: 'a2',
        time: DateTime(2026, 1, 1, 10, 1, 0),
      );

      notifier.recordEvent(
        source: AuditEventSource.executionFeedback,
        actionType: AuditActionType.veto,
        stateSummary: 'state 3',
        policySetSummary: 'policy 3',
        humanChoiceSummary: 'choice 3',
        eventId: 'a3',
        time: DateTime(2026, 1, 1, 10, 2, 0),
      );

      final timeline = container.read(auditTimelineProvider);

      expect(timeline.items.length, 2);
      expect(timeline.latest?.eventId, 'a3');
      expect(timeline.items.first.eventId, 'a3');
      expect(timeline.items.last.eventId, 'a2');

      notifier.clear();

      final cleared = container.read(auditTimelineProvider);
      expect(cleared.items, isEmpty);
      expect(cleared.latest, isNull);
      expect(cleared.maxKeep, 2);
    });
  });

  group('SituationController', () {
    test('returns cached snapshot first when cache exists', () async {
      SharedPreferences.setMockInitialValues({
        'cache.situation.latest.v1': '''
{
  "stabilityLevel": "watch",
  "systemScore": 67,
  "strategyPressure": 64,
  "constraintHeadroom": 12,
  "riskIntervalLow": 42,
  "riskIntervalHigh": 71,
  "trendPoints": [0.41, 0.46, 0.52, 0.55, 0.59, 0.62, 0.66],
  "summaryText": "cached snapshot",
  "refreshAt": "2026-03-31T08:00:00.000"
}
''',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final snapshot = await container.read(situationProvider.future);

      expect(snapshot.dataSource, SituationDataSource.cache);
      expect(snapshot.stabilityLevel, SituationStabilityLevel.watch);
      expect(snapshot.systemScore, 67);
      expect(snapshot.strategyPressure, 64);
      expect(snapshot.constraintHeadroom, 12);
      expect(snapshot.riskIntervalLow, 42);
      expect(snapshot.riskIntervalHigh, 71);
      expect(snapshot.trendPoints, isNotEmpty);
      expect(snapshot.summaryText, 'cached snapshot');
    });
  });
}

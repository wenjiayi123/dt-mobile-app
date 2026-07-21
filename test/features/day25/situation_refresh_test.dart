import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dt_mobile_app/features/situation/application/situation_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SituationController refresh', () {
    test('refreshNow keeps a usable snapshot when next fetch fails', () async {
      SharedPreferences.setMockInitialValues({
        'cache.situation.latest.v1': '''
{
  "stabilityLevel": "stable",
  "systemScore": 78,
  "strategyPressure": 35,
  "constraintHeadroom": 31,
  "riskIntervalLow": 22,
  "riskIntervalHigh": 39,
  "trendPoints": [0.31, 0.34, 0.32, 0.37, 0.39, 0.41, 0.43],
  "summaryText": "cached public replay snapshot",
  "refreshAt": "2026-07-21T08:00:00.000"
}
''',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = await container.read(situationProvider.future);
      expect(first.dataSource, SituationDataSource.cache);

      final notifier = container.read(situationProvider.notifier);
      notifier.failNextFetchOnce();
      await notifier.refreshNow();

      final current = container.read(situationProvider);
      expect(current.hasValue, true);

      final after = current.requireValue;
      expect(after.summaryText.isNotEmpty, true);
      expect(after.trendPoints.isNotEmpty, true);
      expect(after.riskIntervalLow <= after.riskIntervalHigh, true);
    });

    test('first load with cache returns cache snapshot', () async {
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
      expect(snapshot.summaryText, 'cached snapshot');
      expect(snapshot.trendPoints.length, 7);
    });
  });
}

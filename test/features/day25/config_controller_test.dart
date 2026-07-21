import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dt_mobile_app/features/audit/application/audit_controller.dart';
import 'package:dt_mobile_app/features/situation/application/config_controller.dart';

class _FakeControlRepository implements ControlRepository {
  _FakeControlRepository({this.shouldThrow = false});

  final bool shouldThrow;
  ControlConfigPayload? lastPayload;
  int callCount = 0;

  @override
  Future<void> setConfig(ControlConfigPayload payload) async {
    callCount += 1;
    lastPayload = payload;
    if (shouldThrow) {
      throw Exception('mock setConfig failed');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigController', () {
    test('setRiskThreshold updates state and writes audit event', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeRepo = _FakeControlRepository();

      final container = ProviderContainer(
        overrides: [controlRepositoryProvider.overrideWith((ref) => fakeRepo)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(configControllerProvider.notifier);
      await notifier.setRiskThreshold(RiskThresholdPreset.high);

      final state = container.read(configControllerProvider);
      final auditTimeline = container.read(auditTimelineProvider);
      final latest = auditTimeline.latest;

      expect(state.riskThreshold, RiskThresholdPreset.high);
      expect(state.isSyncing, false);
      expect(state.lastAppliedAt, isNotNull);
      expect(state.syncMessage, '后端已记录客户端审阅参数 · 未生产下发');

      expect(fakeRepo.callCount, 1);
      expect(fakeRepo.lastPayload, isNotNull);
      expect(fakeRepo.lastPayload!.riskThreshold, RiskThresholdPreset.high);
      expect(fakeRepo.lastPayload!.toJson()['theta'], 80);

      expect(latest, isNotNull);
      expect(latest!.source, AuditEventSource.configChange);
      expect(latest.actionType, AuditActionType.override);
      expect(latest.payload['changedField'], 'risk_threshold_theta');
      expect(latest.payload['changedValueLabel'], '高 (80)');
      expect(latest.payload['source'], 'situation_control_panel');
      expect(latest.policySetSummary, contains('θ 高(80)'));
      expect(latest.humanChoiceSummary, contains('risk_threshold_theta'));
    });

    test(
      'setFutureWindowMinutes reverts state when repository fails',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fakeRepo = _FakeControlRepository(shouldThrow: true);

        final container = ProviderContainer(
          overrides: [
            controlRepositoryProvider.overrideWith((ref) => fakeRepo),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(configControllerProvider.notifier);
        final before = container.read(configControllerProvider);

        await notifier.setFutureWindowMinutes(45);

        final after = container.read(configControllerProvider);
        final latest = container.read(auditTimelineProvider).latest;

        expect(fakeRepo.callCount, 1);
        expect(after.runMode, before.runMode);
        expect(after.riskThreshold, before.riskThreshold);
        expect(after.futureWindowMinutes, before.futureWindowMinutes);
        expect(after.isSyncing, false);
        expect(after.syncMessage, '本次参数应用失败，已回退到上一版本');
        expect(after.lastAppliedAt, isNull);

        expect(latest, isNotNull);
        expect(latest!.source, AuditEventSource.configChange);
        expect(latest.payload['changedField'], 'future_window_tau');
        expect(latest.payload['changedValueLabel'], '45 min');
      },
    );
  });
}

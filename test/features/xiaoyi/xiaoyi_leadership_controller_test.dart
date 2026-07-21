import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dt_mobile_app/features/xiaoyi/application/xiaoyi_leadership_controller.dart';

void main() {
  group('XiaoyiLeadershipController', () {
    test('registers the full leadership command catalog', () {
      expect(xiaoyiLeadershipActions, hasLength(21));
      expect(
        xiaoyiLeadershipActions.map((action) => action.id).toSet(),
        hasLength(21),
      );

      expect(
        xiaoyiLeadershipActions.where(
          (action) =>
              action.category == XiaoyiLeadershipCategory.executivePanel,
        ),
        hasLength(8),
      );
      expect(
        xiaoyiLeadershipActions.where(
          (action) =>
              action.category == XiaoyiLeadershipCategory.executiveDecision,
        ),
        hasLength(8),
      );
      expect(
        xiaoyiLeadershipActions.where(
          (action) =>
              action.category == XiaoyiLeadershipCategory.commandLinkage,
        ),
        hasLength(5),
      );
    });

    test(
      'matches leadership language and keeps online checks confirm-only',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = container.read(
          xiaoyiLeadershipControllerProvider.notifier,
        );

        final judged = controller.judge(command: '小懿，验证这个策略能不能上线');
        expect(judged?.id, 'verify_policy_for_online');
        expect(judged?.requiresConfirmation, isTrue);

        var state = container.read(xiaoyiLeadershipControllerProvider);
        expect(state.packet, contains('"mode": "dry_run"'));
        expect(state.selectedActionId, 'verify_policy_for_online');

        final pending = controller.execute(
          actionId: 'verify_policy_for_online',
          confirmed: false,
        );
        expect(pending?.id, 'verify_policy_for_online');

        state = container.read(xiaoyiLeadershipControllerProvider);
        expect(state.answer, contains('需要确认'));
        expect(state.logs.first.kind, 'CONFIRM');
        expect(state.packet, contains('"mode": "dry_run"'));

        controller.execute(actionId: 'verify_policy_for_online');

        state = container.read(xiaoyiLeadershipControllerProvider);
        expect(state.packet, contains('"mode": "executed"'));
        expect(state.lastPanelLabel, '策略');
      },
    );

    test('updates executive preference without exposing frontline actions', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(
        xiaoyiLeadershipControllerProvider.notifier,
      );

      final action = controller.execute(command: '小懿，切到低碳优先');
      expect(action?.id, 'set_low_carbon_priority');

      final state = container.read(xiaoyiLeadershipControllerProvider);
      expect(state.executivePreference, closeTo(0.82, 0.001));
      expect(state.answer, contains('领导偏好'));
      expect(state.packet, contains('"action_id": "set_low_carbon_priority"'));
      expect(state.logs.first.kind, 'EXEC');
    });
  });
}

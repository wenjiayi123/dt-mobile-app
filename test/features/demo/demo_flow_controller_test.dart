import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dt_mobile_app/features/demo/application/demo_flow_controller.dart';

void main() {
  group('DemoFlowController', () {
    test('handoff waits for a matching return receipt before completion', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(demoFlowProvider.notifier);
      await controller.restorationComplete;
      controller.restart();
      controller.jumpToStep(portAiDemoSteps.indexWhere((s) => s.id == 'handoff'));
      controller.registerAction('open-strategy', () {});
      controller.registerAction('rl-open-handoff', controller.markExternalNavigationPending);
      await controller.triggerAction('rl-open-handoff');
      expect(container.read(demoFlowProvider).completedStepIds, isNot(contains('handoff')));
      expect(container.read(demoFlowProvider).stepStatus, DemoStepStatus.idle);
      controller.acceptExternalReceipt(traceId: 'unrelated');
      expect(container.read(demoFlowProvider).completedStepIds, isNot(contains('handoff')));
      controller.acceptExternalReceipt(traceId: container.read(demoFlowProvider).traceId);
      expect(container.read(demoFlowProvider).completedStepIds, contains('handoff'));
      expect(container.read(demoFlowProvider).stepStatus, DemoStepStatus.resultReady);
    });

    test(
      'keeps UI tour phases deterministic without changing business data',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = container.read(demoFlowProvider.notifier);
        expect(container.read(demoFlowProvider).stage, DemoFlowStage.ready);

        controller.setEnabled(true);
        controller.start();
        controller.advance();
        controller.advance();
        controller.advance();

        var state = container.read(demoFlowProvider);
        expect(state.stage, DemoFlowStage.strategy);
        expect(state.canAdvanceManually, isFalse);

        controller.advance();
        state = container.read(demoFlowProvider);
        expect(
          state.stage,
          DemoFlowStage.strategy,
          reason: '策略阶段必须等待真实人工确认，不能由导演自动越过',
        );
      },
    );

    test('explicit tour navigation can reach the audit page', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(demoFlowProvider.notifier);
      controller.setEnabled(true);
      controller.start();
      controller.setStage(DemoFlowStage.strategy);
      controller.markExecutionStarted();

      expect(container.read(demoFlowProvider).stage, DemoFlowStage.executing);

      controller.markAuditReady();
      final completed = container.read(demoFlowProvider);
      expect(completed.stage, DemoFlowStage.audit);
      expect(completed.isComplete, isTrue);
      expect(completed.logs.first.message, contains('审计'));
    });

    test('disabling UI tour resets its navigation state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(demoFlowProvider.notifier);
      controller.setEnabled(true);
      controller.start();
      controller.setEnabled(false);

      final state = container.read(demoFlowProvider);
      expect(state.enabled, isFalse);
      expect(state.stage, DemoFlowStage.ready);
      expect(state.isRunning, isFalse);
    });

    test('restoring defaults disables the optional UI tour', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(demoFlowProvider.notifier);
      controller.setEnabled(true);
      controller.start();
      controller.reset();

      final state = container.read(demoFlowProvider);
      expect(state.enabled, isFalse);
      expect(state.stage, DemoFlowStage.ready);
      expect(state.logs, isEmpty);
    });

    test(
      'route-opening actions complete when the native page is opened',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = container.read(demoFlowProvider.notifier);
        controller.restart();
        controller.jumpToStep(portAiDemoSteps.length - 1);
        final routeClosed = Completer<void>();
        controller.registerAction('open-settings', () => routeClosed.future);

        await controller.triggerAction('open-settings');

        expect(routeClosed.isCompleted, isFalse);
        expect(
          container.read(demoFlowProvider).stepStatus,
          DemoStepStatus.resultReady,
          reason: '打开路由即为可见结果，不应等到关闭页面。',
        );
      },
    );
  });
}

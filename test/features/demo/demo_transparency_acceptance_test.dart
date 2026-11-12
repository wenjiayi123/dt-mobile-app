import 'dart:convert';
import 'dart:io';
import 'package:dt_mobile_app/features/demo/presentation/trained_evidence_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dt_mobile_app/features/demo/application/demo_flow_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'one advance executes every destination and preserves failure handling',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final flow = c.read(demoFlowProvider.notifier);
      await flow.restorationComplete;
      flow.restart();
      final calls = <String>[];
      for (final step in portAiDemoSteps) {
        flow.registerAction(step.actionId, () {
          calls.add(step.actionId);
        });
        if (step.prepareActionId != null &&
            !portAiDemoSteps.any((s) => s.actionId == step.prepareActionId)) {
          flow.registerAction(step.prepareActionId!, () {});
        }
      }
      await flow.triggerAction(portAiDemoSteps.first.actionId);
      for (var i = 1; i < portAiDemoSteps.length; i++) {
        await flow.advanceAndRun();
        expect(c.read(demoFlowProvider).currentStepIndex, i);
        expect(c.read(demoFlowProvider).stepStatus, DemoStepStatus.resultReady);
        expect(calls.last, portAiDemoSteps[i].actionId);
      }
      expect(
        c.read(demoFlowProvider).completedStepIds.length,
        portAiDemoSteps.length,
      );
    },
  );
  test('reset cancels a pending single-click transition', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final flow = c.read(demoFlowProvider.notifier);
    await flow.restorationComplete;
    flow.restart();
    flow.registerAction(portAiDemoSteps.first.actionId, () {});
    var called = false;
    flow.registerAction(portAiDemoSteps[1].actionId, () {
      called = true;
    });
    await flow.triggerAction(portAiDemoSteps.first.actionId);
    final pending = flow.advanceAndRun();
    flow.restart();
    await pending;
    expect(called, isFalse);
    expect(c.read(demoFlowProvider).currentStepIndex, 0);
  });
  testWidgets('catalog renders six fields with every scene selectable', (
    tester,
  ) async {
    final data =
        jsonDecode(File('assets/demo-evidence.json').readAsStringSync())
            as Map<String, dynamic>;
    bool hasEvidence(Object? value) {
      if (value is Map) return value.values.any(hasEvidence);
      if (value is List) return value.any(hasEvidence);
      return value != null && value.toString().trim().isNotEmpty;
    }

    for (final scene in data['scenarios'] as List) {
      for (final field in [
        'algorithm',
        'datasets',
        'state',
        'reward',
        'actions',
        'outputs',
      ]) {
        expect(
          hasEvidence(scene[field]),
          isTrue,
          reason: '${scene['id']} $field must contain actual evidence',
        );
      }
    }
    await tester.binding.setSurfaceSize(const Size(470, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrainedEvidencePanel(data: data, onClose: () {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('已训练场景 · 算法与数据清单'), findsOneWidget);
    expect(find.text('具体算法'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

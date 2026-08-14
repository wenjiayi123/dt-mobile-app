import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dt_mobile_app/shared/ui/intelligent_action_button.dart';

void main() {
  testWidgets('exposes one actionable semantics node and runs its callback', (
    tester,
  ) async {
    var calls = 0;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntelligentActionButton(
            label: '进入 3D 孪生屏',
            icon: Icons.view_in_ar_rounded,
            onPressed: () => calls += 1,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('进入 3D 孪生屏'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('进入 3D 孪生屏'));
    await tester.pump();

    expect(calls, 1);
    semantics.dispose();
  });
}

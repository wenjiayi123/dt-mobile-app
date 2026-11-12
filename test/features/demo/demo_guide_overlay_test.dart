import 'package:dt_mobile_app/features/demo/application/demo_flow_controller.dart';
import 'package:dt_mobile_app/app.dart' as app;
import 'package:dt_mobile_app/features/demo/presentation/demo_guide_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guide controls work inside the real application navigator', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(470, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(
        child: app.DtMobileApp(
          home: Scaffold(body: Text('Home')),
          showDemoGuide: true,
        ),
      ),
    );
    final context = tester.element(find.byType(DemoGuideOverlay));
    ProviderScope.containerOf(
      context,
    ).read(demoFlowProvider.notifier).restart();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);

    final collapse = find.byTooltip('折叠');
    tester.state<TooltipState>(collapse).ensureTooltipVisible();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('折叠'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('更多演示控制'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('重置本步'), findsOneWidget);
    await tester.tap(find.text('重置本步'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('折叠'));
    await tester.pump();
    expect(find.byKey(const ValueKey('demo-guide-expand')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('demo-guide-expand')));
    await tester.pump();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('demo-guide-start')));
    await tester.pump();
    expect(find.byKey(const ValueKey('demo-guide-panel')), findsOneWidget);

    Navigator.of(tester.element(find.text('Home'))).pushNamed('/unknown');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('页面未找到'), findsOneWidget);
    expect(find.byKey(const ValueKey('demo-guide-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('mobile guide uses a stable opaque half-height surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(470, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Stack(children: [DemoGuideOverlay()])),
        ),
      ),
    );

    final overlayContext = tester.element(find.byType(DemoGuideOverlay));
    ProviderScope.containerOf(
      overlayContext,
    ).read(demoFlowProvider.notifier).restart();
    await tester.pump();

    final panelFinder = find.byKey(const ValueKey('demo-guide-panel'));
    expect(panelFinder, findsOneWidget);
    final logicalHeight = MediaQuery.sizeOf(overlayContext).height;
    expect(tester.getSize(panelFinder), Size(222, logicalHeight * 0.5));

    final panel = tester.widget<Container>(panelFinder);
    expect(panel.clipBehavior, Clip.none);
    expect(panel.child, isA<Column>());
    expect(
      find.descendant(
        of: panelFinder,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    final decoration = panel.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF0A1930));
    expect(decoration.color!.a, 1);
  });
}

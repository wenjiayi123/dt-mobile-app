import 'package:dt_mobile_app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('real application shell renders injected home and routes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const DtMobileApp(
        home: Scaffold(body: Center(child: Text('真实移动前台壳层'))),
      ),
    );

    // The real shell includes a continuously animated digital-twin backdrop,
    // so pumpAndSettle would correctly never settle. Pump explicit frames
    // instead and keep the test coupled to production composition.
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('真实移动前台壳层'), findsOneWidget);

    final context = tester.element(find.text('真实移动前台壳层'));
    Navigator.of(context).pushNamed('/route-that-does-not-exist');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('页面未找到'), findsOneWidget);
    expect(find.text('当前路由不存在'), findsOneWidget);
    expect(find.text('无法打开：/route-that-does-not-exist'), findsOneWidget);
  });
}

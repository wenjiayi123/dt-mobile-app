import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dt_mobile_app/core/network/dio_provider.dart';
import 'package:dt_mobile_app/features/home/presentation/demo_port_data_card.dart';

void main() {
  testWidgets('loads only on request, preserves zero, and removes old data after failure', (tester) async {
    final dio = Dio(); var requests = 0; var fail = false;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      if (fail) { handler.reject(DioException(requestOptions: options, message: 'source offline')); return; }
      expect(options.path, '/api/public-port-demo/workspace');
      handler.resolve(Response(requestOptions: options, data: {
        'schema': 'port-dt-demo-workspace.v1', 'production_authority': false,
        'snapshot': {'source_timestamp': '2025-12-15T12:00:00+08:00'},
        'source_mode': '公开参数标定演示', 'coverage': {'available': 1, 'total': 1},
        'metrics': [{'id': 'energy_kwh', 'name': '窗口用电', 'value': 0,
          'unit': 'kWh', 'evidence_class': 'engineering_derived', 'detail': '测试夹具', 'replacement': 'EMS'}],
        'site_pending': [],
      }));
    }));
    await tester.pumpWidget(ProviderScope(overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DemoPortDataCard())))));
    expect(requests, 0);
    await tester.tap(find.text('读取演示数据')); await tester.pumpAndSettle();
    expect(requests, 1); expect(find.text('0'), findsOneWidget); expect(find.text('kWh'), findsOneWidget);
    fail = true;
    await tester.tap(find.text('刷新演示数据')); await tester.pumpAndSettle();
    expect(requests, 2); expect(find.text('0'), findsNothing);
    expect(find.textContaining('本次演示源未取得'), findsOneWidget);
    expect(find.text('读取演示数据'), findsOneWidget);
  });
}

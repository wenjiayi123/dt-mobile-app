import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dt_mobile_app/features/xiaoyi/presentation/shanghai_lab_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrialAdapter implements HttpClientAdapter {
  bool loseFirstResponse = true;
  bool mismatch = false;
  final requests = <Map<String, dynamic>>[];
  final events = <Map<String, dynamic>>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final sha = 'a' * 64;
    dynamic data;
    if (options.method == 'POST') {
      final body = Map<String, dynamic>.from(options.data as Map);
      requests.add(body);
      if (events.isEmpty) {
        events.add({
          ...body,
          'sha256': 'receipt',
          'seq': 1,
          'actor_id': 'test',
          'created_at': '2026-10-31',
        });
      }
      if (loseFirstResponse) {
        loseFirstResponse = false;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      }
      data = events.first;
    } else if (options.path.endsWith('/briefing')) {
      data = {'result_sha256': mismatch ? 'b' * 64 : sha, 'text': '工程模拟；碳排增加。'};
    } else if (options.path.endsWith('/delivery')) {
      data = {
        'result_sha256': sha,
        'events': events,
        'status': 'waiting_reviews',
        'review_mode': 'same_actor_lab_review',
      };
    } else {
      data = {'result_sha256': sha};
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  testWidgets(
    'lost response persists request and retry reuses exact key, never claims ack',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final adapter = TrialAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
        ..httpClientAdapter = adapter;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ShanghaiLabPage(trialId: 'sjt-${'a' * 24}', transport: dio),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认作业复核'));
      await tester.pumpAndSettle();
      expect(find.text('重试并核对原回执'), findsOneWidget);
      expect(find.text('已签收：服务端回执已独立读回'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().length, 1);
      await tester.ensureVisible(find.text('重试并核对原回执'));
      await tester.tap(find.text('重试并核对原回执'));
      await tester.pumpAndSettle();
      expect(adapter.requests.length, 2);
      expect(adapter.requests[0], adapter.requests[1]);
      expect(adapter.events.length, 1);
      expect(prefs.getKeys(), isEmpty);
      expect(find.text('确认作业复核 · 已完成'), findsOneWidget);
    },
  );

  testWidgets('mismatched version cannot be reviewed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = TrialAdapter()..mismatch = true;
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ShanghaiLabPage(trialId: 'sjt-${'a' * 24}', transport: dio),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('结果版本不一致'), findsOneWidget);
    expect(find.text('确认作业复核'), findsNothing);
  });
}

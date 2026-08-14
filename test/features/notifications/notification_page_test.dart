import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dt_mobile_app/features/alerts/application/alerts_controller.dart';
import 'package:dt_mobile_app/features/home/application/home_tab_notifier.dart';
import 'package:dt_mobile_app/features/notifications/application/notification_controller.dart';
import 'package:dt_mobile_app/features/notifications/presentation/notification_page.dart';

void main() {
  testWidgets('focused notification next-step button opens its target tab', (
    tester,
  ) async {
    final feed = _SilentAlertsFeedService();
    addTearDown(feed.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [alertsFeedServiceProvider.overrideWithValue(feed)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationPage(),
                  ),
                ),
                child: const Text('打开通知'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开通知'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NotificationPage));
    final container = ProviderScope.containerOf(context);
    await container
        .read(notificationCenterProvider.notifier)
        .pushSystemNotice(title: '共享后端校验完成', body: 'Web 与移动端证据链已同步');
    await tester.pump(const Duration(milliseconds: 1100));

    await tester.tap(find.text('查看焦点通知'));
    await tester.pumpAndSettle();
    expect(find.text('下一步：查看焦点事件'), findsOneWidget);

    await tester.tap(find.text('下一步：查看焦点事件'));
    await tester.pumpAndSettle();

    expect(container.read(homeTabProvider), HomeTab.audit);
    expect(find.byType(NotificationPage), findsNothing);
  });
}

class _SilentAlertsFeedService implements AlertsFeedService {
  final StreamController<AlertsFeedEvent> _controller =
      StreamController<AlertsFeedEvent>.broadcast();

  @override
  Stream<AlertsFeedEvent> watchEvents() => _controller.stream;

  @override
  Future<void> reconnect() async {}

  @override
  void failNextReconnectOnce() {}

  @override
  void dispose() => _controller.close();
}

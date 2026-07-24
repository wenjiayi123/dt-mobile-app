import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dt_mobile_app/features/alerts/application/alerts_controller.dart';
import 'package:dt_mobile_app/features/audit/application/audit_controller.dart';
import 'package:dt_mobile_app/features/home/application/home_tab_notifier.dart';
import 'package:dt_mobile_app/features/strategy/application/strategy_controller.dart';
import 'package:dt_mobile_app/features/xiaoyi/presentation/xiaoyi_leadership_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the leadership linkage panel and command groups', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final openedTabs = <HomeTab>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          auditUploadEnabledProvider.overrideWithValue(false),
          alertsSnapshotProvider.overrideWith(_FakeAlertsSnapshotNotifier.new),
          strategyControllerProvider.overrideWith(_FakeStrategyController.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: XiaoyiLeadershipPanel(onOpenTab: openedTabs.add),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('小懿决策助手'), findsOneWidget);
    expect(find.text('生成简报'), findsOneWidget);
    expect(find.text('查看策略'), findsOneWidget);
    expect(find.text('小懿互动功能 / 指令清单'), findsNothing);

    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();

    expect(find.text('小懿互动功能 / 指令清单'), findsOneWidget);
    expect(find.text('AI决策面板'), findsOneWidget);
    expect(find.text('领导研判'), findsOneWidget);
    expect(find.text('指令联动'), findsOneWidget);
    expect(openedTabs, isEmpty);
  });

  testWidgets('executes a command row and records visible result', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final openedTabs = <HomeTab>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          auditUploadEnabledProvider.overrideWithValue(false),
          alertsSnapshotProvider.overrideWith(_FakeAlertsSnapshotNotifier.new),
          strategyControllerProvider.overrideWith(_FakeStrategyController.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: XiaoyiLeadershipPanel(onOpenTab: openedTabs.add),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('联动健康检查'),
      -360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final row = find
        .ancestor(
          of: find.text('联动健康检查'),
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_CommandActionRow',
          ),
        )
        .first;

    await tester.tap(
      find.descendant(
        of: row,
        matching: find.widgetWithText(FilledButton, '执行'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('执行结果 · 联动健康检查'), findsOneWidget);
    expect(find.textContaining('健康检查完成'), findsOneWidget);
    expect(find.text('审计留痕 1'), findsOneWidget);
  });
}

class _FakeAlertsSnapshotNotifier extends AlertsSnapshotNotifier {
  @override
  Future<AlertsSnapshot> build() async => AlertsSnapshot.empty;
}

class _FakeStrategyController extends StrategyController {
  @override
  StrategyControllerState build() => StrategyControllerState.initial();

  @override
  Future<void> refreshCandidates({bool silent = false}) async {}
}

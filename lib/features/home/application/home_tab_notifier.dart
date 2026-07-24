import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Home 的 4 个 Tab（应用层定义，供 UI/业务统一引用）
///
/// 说明：
/// - 这是“移动端主导航”的状态源，后续接入：
///   - 告警红点 badge（alerts tab）
///   - 审计/回放入口（audit tab）
///   - 深链/通知跳转到指定 tab
enum HomeTab { situation, strategy, alerts, audit }

extension HomeTabX on HomeTab {
  String get label => switch (this) {
    HomeTab.situation => '态势',
    HomeTab.strategy => '策略',
    HomeTab.alerts => '告警',
    HomeTab.audit => '审计',
  };

  IconData get icon => switch (this) {
    HomeTab.situation => Icons.radar,
    HomeTab.strategy => Icons.route,
    HomeTab.alerts => Icons.notifications_active,
    HomeTab.audit => Icons.fact_check,
  };
}

/// Riverpod 3.x Notifier：管理当前选中的 Tab
class HomeTabNotifier extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.situation;

  void select(HomeTab tab) => state = tab;

  /// 便于未来做“下一页/上一页”或手势切换
  void selectIndex(int index) {
    final safe = index.clamp(0, HomeTab.values.length - 1);
    state = HomeTab.values[safe];
  }
}

final homeTabProvider = NotifierProvider<HomeTabNotifier, HomeTab>(
  HomeTabNotifier.new,
);

/// 控制主导航是显示运营总览，还是某个业务页。
///
/// 独立成全局状态后，审计回放等子路由也可以一键回到总览，
/// 不需要用户先返回、再手动点底部“首页”。
class HomeDashboardNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void showDashboard() => state = true;

  void showBusinessTab() => state = false;
}

final homeDashboardProvider = NotifierProvider<HomeDashboardNotifier, bool>(
  HomeDashboardNotifier.new,
);

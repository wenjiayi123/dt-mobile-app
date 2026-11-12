import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alerts/application/alerts_controller.dart';
import '../../demo/application/demo_flow_controller.dart';
import '../application/home_tab_notifier.dart';

/// Outside the business Navigator so sheets and pushed pages cannot cover it.
class PrimaryNavigation extends ConsumerWidget {
  const PrimaryNavigation({super.key, required this.onNavigate});

  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(homeTabProvider);
    final dashboard = ref.watch(homeDashboardProvider);
    final unread = ref.watch(unreadAlertsCountProvider).asData?.value ?? 0;

    return NavigationBar(
      key: const ValueKey('persistent-primary-navigation'),
      selectedIndex: dashboard ? 0 : HomeTab.values.indexOf(tab) + 1,
      onDestinationSelected: (index) {
        onNavigate();
        final dashboardController = ref.read(homeDashboardProvider.notifier);
        final String actionId;
        if (index == 0) {
          dashboardController.showDashboard();
          actionId = 'open-dashboard';
        } else {
          final target = HomeTab.values[index - 1];
          dashboardController.showBusinessTab();
          ref.read(homeTabProvider.notifier).select(target);
          actionId = switch (target) {
            HomeTab.situation => 'open-situation',
            HomeTab.strategy => 'open-strategy',
            HomeTab.alerts => 'open-alerts',
            HomeTab.audit => 'open-audit',
          };
        }
        if (!ref.read(demoFlowProvider).isBusy) {
          unawaited(
            ref
                .read(demoFlowProvider.notifier)
                .triggerAction(actionId, origin: DemoActionOrigin.page),
          );
        }
      },
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.space_dashboard_outlined),
          selectedIcon: Icon(Icons.space_dashboard_rounded),
          label: '首页',
        ),
        for (final destination in HomeTab.values)
          NavigationDestination(
            icon: destination == HomeTab.alerts && unread > 0
                ? Badge(
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: Icon(destination.icon),
                  )
                : Icon(destination.icon),
            label: destination.label,
          ),
      ],
    );
  }
}

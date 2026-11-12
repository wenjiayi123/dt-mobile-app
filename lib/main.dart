// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart' as app;
import 'features/home/presentation/home_page.dart';
import 'features/xiaoyi/presentation/shanghai_lab_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep browser controls available to assistive tools for the app lifetime.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  runApp(const ProviderScope(child: DtMobileApp()));
}

/// 入口保持零参数：
/// - 便于测试里直接 pumpWidget(const ProviderScope(child: DtMobileApp()))
/// - 内部委托给 lib/app.dart 的壳子，并注入 HomeShellPage（来自 home_page.dart）
class DtMobileApp extends StatelessWidget {
  const DtMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    final trial = Uri.base.queryParameters['shanghai_trial'];
    if (trial != null && RegExp(r'^sjt-[a-f0-9]{24}$').hasMatch(trial)) {
      return MaterialApp(
        theme: ThemeData(useMaterial3: true, fontFamily: 'PortAISansSC'),
        home: ShanghaiLabPage(trialId: trial),
      );
    }
    return const app.DtMobileApp(
      home: HomeShellPage(showBottomNavigation: false),
      showDemoGuide: true,
      showPrimaryNavigation: true,
    );
  }
}

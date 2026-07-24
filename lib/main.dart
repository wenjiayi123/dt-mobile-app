// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart' as app;
import 'features/home/presentation/home_page.dart';

void main() {
  runApp(const ProviderScope(child: DtMobileApp()));
}

/// 入口保持零参数：
/// - 便于测试里直接 pumpWidget(const ProviderScope(child: DtMobileApp()))
/// - 内部委托给 lib/app.dart 的壳子，并注入 HomeShellPage（来自 home_page.dart）
class DtMobileApp extends StatelessWidget {
  const DtMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const app.DtMobileApp(home: HomeShellPage());
  }
}

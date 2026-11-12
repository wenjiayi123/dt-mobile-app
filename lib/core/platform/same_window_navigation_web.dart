// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

String? currentAppReturnUrl({Map<String, String> resumeParameters = const {}}) {
  final uri = Uri.tryParse(html.window.location.href);
  if (uri == null || uri.origin.isEmpty) return null;
  // Preserve native_build and deployment parameters across the round trip.
  // A consumed receipt must not be sent back as the next task's result.
  final parameters = Map<String, String>.from(uri.queryParameters)
    ..removeWhere((key, _) => _returnReceiptKeys.contains(key))
    ..addAll(resumeParameters);
  return uri.replace(queryParameters: parameters, fragment: '').toString();
}

bool navigateSameWindow(String url) {
  html.window.location.assign(url);
  return true;
}

Map<String, String> readCrossSystemReturnReceipt() {
  final uri = Uri.tryParse(html.window.location.href);
  if (uri == null || uri.queryParameters['xiaoyi_return'] != '1') {
    return const <String, String>{};
  }
  return Map<String, String>.unmodifiable(uri.queryParameters);
}

const _returnReceiptKeys = <String>{
  'xiaoyi_return',
  'task_goal',
  'target_system',
  'dataset_version',
  'algorithm',
  'parameters',
  'execution_status',
  'key_metrics',
  'validation_conclusion',
  'trace_id',
  'timestamp',
  'production_authority',
  'portai_demo_resume',
};

void clearCrossSystemReturnReceipt() {
  final uri = Uri.tryParse(html.window.location.href);
  if (uri == null) return;
  final parameters = Map<String, String>.from(uri.queryParameters)
    ..removeWhere((key, _) => _returnReceiptKeys.contains(key));
  html.window.history.replaceState(
    null,
    '',
    uri.replace(queryParameters: parameters).toString(),
  );
}

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import 'xiaoyi_leadership_controller.dart';

@immutable
class XiaoyiWebLinkageStatus {
  const XiaoyiWebLinkageStatus({
    required this.backendId,
    required this.sharedBackendVerified,
    required this.webFrontendRegistered,
    required this.mobileFrontendRegistered,
    required this.rlInterfaceOnline,
    required this.assistantGatewayAvailable,
    required this.xiaoyiOnline,
    required this.xiaoyiLabel,
    required this.auditChainValid,
    required this.checkedAt,
  });

  final String backendId;
  final bool sharedBackendVerified;
  final bool webFrontendRegistered;
  final bool mobileFrontendRegistered;
  final bool rlInterfaceOnline;
  final bool assistantGatewayAvailable;
  final bool xiaoyiOnline;
  final String xiaoyiLabel;
  final bool auditChainValid;
  final DateTime checkedAt;

  bool get webLinkageReady =>
      backendId == 'port-dt-multi' &&
      sharedBackendVerified &&
      webFrontendRegistered &&
      mobileFrontendRegistered &&
      rlInterfaceOnline &&
      assistantGatewayAvailable &&
      auditChainValid;

  String get summary {
    if (!webLinkageReady) return 'Web 共享链路未通过完整核验';
    if (xiaoyiOnline) return 'Web 共享后端、小懿服务与审计链均在线';
    return 'Web 共享后端与审计链在线；小懿服务离线，保留后端证据兜底';
  }

  factory XiaoyiWebLinkageStatus.fromResponses({
    required Map<String, dynamic> mobileStatus,
    required Map<String, dynamic> integrationHealth,
    required Map<String, dynamic> auditVerification,
  }) {
    final frontends = _stringSet(mobileStatus['frontends']);
    final systems = _map(integrationHealth['systems']);
    final rl = _map(systems['rl_interface']);
    final routes = _map(rl['routes']);
    final xiaoyi = _map(systems['xiaoyi_ai']);
    return XiaoyiWebLinkageStatus(
      backendId: mobileStatus['backend_id']?.toString() ?? 'unknown',
      sharedBackendVerified: mobileStatus['shared_backend_verified'] == true,
      webFrontendRegistered: frontends.contains('web'),
      mobileFrontendRegistered: frontends.contains('flutter_mobile'),
      rlInterfaceOnline: rl['online'] == true,
      assistantGatewayAvailable:
          routes['/api/assistant/actions/execute'] == true,
      xiaoyiOnline: xiaoyi['online'] == true && xiaoyi['chat_capable'] == true,
      xiaoyiLabel: xiaoyi['label']?.toString() ?? '小懿状态未知',
      auditChainValid: auditVerification['valid'] == true,
      checkedAt: DateTime.now(),
    );
  }
}

@immutable
class XiaoyiWebActionReceipt {
  const XiaoyiWebActionReceipt({
    required this.actionId,
    required this.actionLabel,
    required this.status,
    required this.openUrl,
    required this.updatedAt,
  });

  final String actionId;
  final String actionLabel;
  final String status;
  final String openUrl;
  final DateTime updatedAt;

  bool get actionReady =>
      status != 'failed' &&
      status != 'blocked' &&
      status != 'training_incomplete';

  String get summary => actionReady
      ? 'Web 网关已确认 $actionId · $status · production_dispatch=false'
      : 'Web 网关回执 $actionId · $status · action_ready=false · production_dispatch=false';

  factory XiaoyiWebActionReceipt.fromJson(
    Map<String, dynamic> json, {
    required String expectedActionId,
  }) {
    final action = _map(json['action']);
    final execution = _map(json['execution_result']);
    final willExecute = _map(json['will_execute']);
    final actionId = action['id']?.toString() ?? '';
    final openUrl = willExecute['open_url']?.toString() ?? '';
    if (json['gateway'] != 'xiaoyi_assistant_action_gateway' ||
        json['matched'] != true ||
        actionId != expectedActionId ||
        execution['mode'] != 'dry_run' ||
        execution['executed'] != false ||
        openUrl.isEmpty) {
      throw const FormatException('Web 小懿网关回执字段不完整或越过 dry-run 边界');
    }
    return XiaoyiWebActionReceipt(
      actionId: actionId,
      actionLabel: action['label']?.toString() ?? actionId,
      status: execution['status']?.toString() ?? 'dry_run',
      openUrl: openUrl,
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class XiaoyiWebLinkageRepository {
  XiaoyiWebLinkageRepository(this._dio);

  final Dio _dio;

  Future<XiaoyiWebLinkageStatus> checkStatus() async {
    final responses = await Future.wait<Response<Object>>([
      _dio.get<Object>('/api/mobile/status'),
      _dio.get<Object>('/api/rl/integration/health'),
      _dio.get<Object>('/api/mobile/audit/verify'),
    ]);
    return XiaoyiWebLinkageStatus.fromResponses(
      mobileStatus: _map(responses[0].data),
      integrationHealth: _map(responses[1].data),
      auditVerification: _map(responses[2].data),
    );
  }

  Future<XiaoyiWebActionReceipt> executeDryRun({
    required String webActionId,
    required String instruction,
    required bool confirmed,
  }) async {
    final response = await _dio.post<Object>(
      '/api/assistant/actions/execute',
      data: <String, Object>{
        'action_id': webActionId,
        'instruction': instruction,
        'source': 'dt_mobile_app',
        'dry_run': true,
        'confirm': confirmed,
        'production_dispatch': false,
      },
    );
    return XiaoyiWebActionReceipt.fromJson(
      _map(response.data),
      expectedActionId: webActionId,
    );
  }
}

final xiaoyiWebLinkageRepositoryProvider = Provider<XiaoyiWebLinkageRepository>(
  (ref) => XiaoyiWebLinkageRepository(ref.read(dioProvider)),
);

final xiaoyiWebLinkageStatusProvider = FutureProvider<XiaoyiWebLinkageStatus>(
  (ref) => ref.read(xiaoyiWebLinkageRepositoryProvider).checkStatus(),
);

String? webActionIdFor(XiaoyiLeadershipActionType type) {
  return switch (type) {
    XiaoyiLeadershipActionType.startXiaoyi => 'start_xiaoyi_ai',
    XiaoyiLeadershipActionType.askBrief ||
    XiaoyiLeadershipActionType.openSituation ||
    XiaoyiLeadershipActionType.refreshSituation =>
      'summarize_current_situation',
    XiaoyiLeadershipActionType.openStrategy ||
    XiaoyiLeadershipActionType.reviewStrategyPortfolio ||
    XiaoyiLeadershipActionType.setEfficiencyPriority ||
    XiaoyiLeadershipActionType.setBalancedDispatch ||
    XiaoyiLeadershipActionType.setLowCarbonPriority ||
    XiaoyiLeadershipActionType.setShorePowerPriority =>
      'explain_current_strategy',
    XiaoyiLeadershipActionType.openAlerts ||
    XiaoyiLeadershipActionType.requestRiskEscalation => 'triage_monitoring',
    XiaoyiLeadershipActionType.openAudit ||
    XiaoyiLeadershipActionType.openReplayBrief ||
    XiaoyiLeadershipActionType.generateMeetingBrief => 'prepare_shift_handoff',
    XiaoyiLeadershipActionType.runPolicyTest => 'run_policy_test',
    XiaoyiLeadershipActionType.verifyOnlineDryRun => 'verify_policy_for_online',
    XiaoyiLeadershipActionType.openSimulationDemo => 'review_twin_forecast',
    XiaoyiLeadershipActionType.refreshDashboard ||
    XiaoyiLeadershipActionType.linkageHealth ||
    XiaoyiLeadershipActionType.dataLinkCheck => null,
  };
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

Set<String> _stringSet(Object? raw) {
  if (raw is! List) return const <String>{};
  return raw.map((item) => item.toString()).toSet();
}

String xiaoyiWebLinkageErrorMessage(Object error) {
  if (error is DioException) return mapToAppNetworkException(error).message;
  if (error is FormatException) return error.message;
  return 'Web 共享链路未返回可验证回执';
}

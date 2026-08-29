import 'package:flutter_test/flutter_test.dart';

import 'package:dt_mobile_app/features/xiaoyi/application/xiaoyi_leadership_controller.dart';
import 'package:dt_mobile_app/features/xiaoyi/application/xiaoyi_web_linkage.dart';

void main() {
  test(
    'requires shared backend identity, both frontends and audit validity',
    () {
      final status = XiaoyiWebLinkageStatus.fromResponses(
        mobileStatus: <String, dynamic>{
          'backend_id': 'port-dt-multi',
          'shared_backend_verified': true,
          'frontends': <String>['web', 'flutter_mobile'],
        },
        integrationHealth: <String, dynamic>{
          'systems': <String, dynamic>{
            'rl_interface': <String, dynamic>{
              'online': true,
              'routes': <String, dynamic>{
                '/api/assistant/actions/execute': true,
              },
            },
            'xiaoyi_ai': <String, dynamic>{
              'online': false,
              'chat_capable': false,
              'label': '小懿未在线 · 后端证据兜底',
            },
          },
        },
        auditVerification: <String, dynamic>{'valid': true},
      );

      expect(status.webLinkageReady, isTrue);
      expect(status.xiaoyiOnline, isFalse);
      expect(status.summary, contains('后端证据兜底'));
    },
  );

  test('accepts only a matched non-executing dry-run gateway receipt', () {
    final receipt = XiaoyiWebActionReceipt.fromJson(<String, dynamic>{
      'gateway': 'xiaoyi_assistant_action_gateway',
      'matched': true,
      'updated_at': '2026-08-14T00:00:00Z',
      'action': <String, dynamic>{
        'id': 'run_policy_test',
        'label': '运行训练后策略测试',
      },
      'will_execute': <String, dynamic>{
        'open_url': 'http://127.0.0.1:8000/rl-panel?action=run_policy_test',
      },
      'execution_result': <String, dynamic>{
        'status': 'ready_to_execute',
        'mode': 'dry_run',
        'executed': false,
      },
    }, expectedActionId: 'run_policy_test');

    expect(receipt.actionId, 'run_policy_test');
    expect(receipt.actionReady, isTrue);
    expect(receipt.summary, contains('production_dispatch=false'));

    expect(
      () => XiaoyiWebActionReceipt.fromJson(<String, dynamic>{
        'gateway': 'xiaoyi_assistant_action_gateway',
        'matched': true,
        'action': <String, dynamic>{'id': 'run_policy_test'},
        'will_execute': <String, dynamic>{'open_url': 'http://localhost'},
        'execution_result': <String, dynamic>{
          'status': 'executed',
          'mode': 'executed',
          'executed': true,
        },
      }, expectedActionId: 'run_policy_test'),
      throwsFormatException,
    );
  });

  test('keeps a complete but failed Web gateway receipt fail-closed', () {
    final receipt = XiaoyiWebActionReceipt.fromJson(<String, dynamic>{
      'gateway': 'xiaoyi_assistant_action_gateway',
      'matched': true,
      'action': <String, dynamic>{'id': 'start_xiaoyi_ai'},
      'will_execute': <String, dynamic>{
        'open_url': 'http://127.0.0.1:8000/integration-hub',
      },
      'execution_result': <String, dynamic>{
        'status': 'failed',
        'mode': 'dry_run',
        'executed': false,
      },
    }, expectedActionId: 'start_xiaoyi_ai');

    expect(receipt.actionReady, isFalse);
    expect(receipt.summary, contains('action_ready=false'));
  });

  test('maps mobile Xiaoyi actions to the registered Web action gateway', () {
    expect(
      webActionIdFor(XiaoyiLeadershipActionType.runPolicyTest),
      'run_policy_test',
    );
    expect(
      webActionIdFor(XiaoyiLeadershipActionType.verifyOnlineDryRun),
      'verify_policy_for_online',
    );
    expect(
      webActionIdFor(XiaoyiLeadershipActionType.openSimulationDemo),
      'review_twin_forecast',
    );
    expect(webActionIdFor(XiaoyiLeadershipActionType.linkageHealth), isNull);
  });
}

import 'dart:async';
import 'account_history.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dt_mobile_app/core/network/dio_provider.dart';

/// Shares the server-side mission and the authenticated user's permissions.
class JointHarnessCard extends ConsumerStatefulWidget {
  const JointHarnessCard({super.key});
  @override
  ConsumerState<JointHarnessCard> createState() => _JointHarnessCardState();
}

class _JointHarnessCardState extends ConsumerState<JointHarnessCard> {
  static String get _base {
    const configured = String.fromEnvironment('XIAOYI_API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb && (Uri.base.scheme == 'http' || Uri.base.scheme == 'https')) {
      return Uri(scheme: Uri.base.scheme, host: Uri.base.host, port: 8010).origin;
    }
    return 'http://127.0.0.1:8010';
  }

  String? _handoffId;
  int _identityRevision = 0;
  final _dio = Dio(
    BaseOptions(
      baseUrl: _base,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
    ),
  );
  final _goal = TextEditingController(text: '联动五系统完成港航工程情景评估并回传移动端。');
  Map<String, dynamic>? _mission;
  String? _error, _createKey, _createSignature;
  String _mode = 'enterprise';
  String _workflow = 'assessment';
  bool _roleRehearsal = false;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(authTokenProvider, (previous, next) {
      if (!mounted || previous == next) return;
      ++_identityRevision;
      _timer?.cancel();
      setState(() { _mission = null; _error = null; });
      if (!_busy && _handoffId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _load());
      }
    });
    final id = Uri.base.queryParameters['joint_task'];
    if (id != null && RegExp(r'^jm-[a-f0-9]{32}$').hasMatch(id)) {
      _handoffId = id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(id: id));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _goal.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  Options get _options {
    final token = ref.read(authTokenProvider);
    return Options(
      headers: {
        if (token != null && token.trim().isNotEmpty)
          'Authorization': 'Bearer $token',
      },
    );
  }

  Map<String, dynamic> _map(dynamic value) =>
      Map<String, dynamic>.from(value as Map);

  Future<void> _load({String? id}) async {
    if (_busy || !mounted) return;
    await _run(() async {
      final selected = id ?? _handoffId ?? _mission?['id'];
      if (selected != null) {
        final response = await _dio.get<dynamic>(
          '/api/harness/joint/missions/$selected',
          options: _options,
        );
        if (mounted) _mission = _map(response.data);
      } else {
        final response = await _dio.get<dynamic>(
          '/api/harness/joint/missions',
          options: _options,
        );
        final items = _map(response.data)['items'] as List;
        if (items.isEmpty) {
          if (mounted) _mission = null;
        } else {
          final selectedId = _map(items.first)['id'];
          final detail = await _dio.get<dynamic>(
            '/api/harness/joint/missions/$selectedId',
            options: _options,
          );
          if (mounted) _mission = _map(detail.data);
        }
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!mounted || _busy) return;
    final revision = _identityRevision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _error = error is DioException
            ? '${error.response?.data ?? error.message}'
            : '$error';
      }
    } finally {
      if (mounted) {
        if (revision != _identityRevision) {
          _mission = null;
          _error = null;
          if (_handoffId != null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
        }
        setState(() => _busy = false);
        _timer?.cancel();
        if (_mission?['status'] == 'running') {
          _timer = Timer(const Duration(seconds: 3), () => _load());
        }
      }
    }
  }

  Future<void> _create() => _run(() async {
    final signature = '$_mode:$_workflow:$_roleRehearsal:${_goal.text.trim()}';
    if (_createSignature != signature) {
      _createKey = 'mobile-${DateTime.now().microsecondsSinceEpoch}';
      _createSignature = signature;
    }
    final response = await _dio.post<dynamic>(
      '/api/harness/joint/missions',
      options: _options,
      data: {
        'request_id': _createKey,
        'goal': _goal.text.trim(),
        'mode': _mode,
        'require_mobile': true,
        'mutate_sandbox': false,
        'workflow': _workflow,
        'max_seconds': _workflow == 'full_business' ? 3600 : 360,
        'business_approval': _roleRehearsal ? 'role_rehearsal' : 'human',
      },
    );
    if (mounted) {
      _mission = _map(response.data);
      _createKey = null;
      _createSignature = null;
    }
  });

  Future<void> _approve() => _run(() async {
    final m = _mission!;
    final response = await _dio.post<dynamic>(
      '/api/harness/joint/missions/${m['id']}/approval',
      options: _options,
      data: {'plan_sha256': m['plan_sha256'], 'approve': true},
    );
    if (mounted) _mission = _map(response.data);
  });

  Future<void> _approveBusiness(String slot) => _run(() async {
    final m = _mission!;
    final response = await _dio.post<dynamic>(
      '/api/harness/joint/missions/${m['id']}/business-approval',
      options: _options,
      data: {
        'bundle_sha256': m['business_approval_sha256'],
        'slot': slot,
        'approve': true,
      },
    );
    if (mounted) _mission = _map(response.data);
  });

  Future<void> _acknowledge() => _run(() async {
    final m = _mission!;
    final response = await _dio.post<dynamic>(
      '/api/harness/joint/missions/${m['id']}/mobile-ack',
      options: _options,
      data: {
        'receipt_sha256': m['delivery_sha256'],
        'client': kIsWeb
            ? 'flutter-web'
            : defaultTargetPlatform == TargetPlatform.macOS
            ? 'flutter-macos'
            : 'flutter-mobile',
      },
    );
    if (mounted) _mission = _map(response.data);
  });

  Future<void> _stop() async {
    final m = _mission;
    if (m == null) return;
    try {
      final response = await _dio.post<dynamic>(
        '/api/harness/joint/missions/${m['id']}/control/cancel',
        options: _options,
      );
      if (mounted) setState(() => _mission = _map(response.data));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _mission;
    final labels = {
      'waiting_approval': '等待计划审批',
      'waiting_business_approval': '等待实际工作单双岗位复核',
      'running': '执行中',
      'waiting_mobile': '等待本机签收',
      'completed': '六系统任务已完成',
      'blocked': '前置条件未通过',
      'needs_review': '需要核查',
      'cancelled': '已取消',
      'paused': '已暂停',
    };
    final results = m == null ? <String, dynamic>{} : _map(m['results']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '双模式港航联合任务',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('与舷鸥共享任务编号、计划和实际回执。'),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => AccountHistoryPage(baseUrl: _base),
              )),
              child: const Text('账号历史与工单 / My activity'),
            ),
            if (_handoffId != null) ...[
              SelectableText('交接工单 / Work order: $_handoffId'),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/auth'),
                child: const Text('登录或切换凭证 / Sign in'),
              ),
            ],
            ExpansionTile(
              title: const Text('提交新的联合任务'),
              tilePadding: EdgeInsets.zero,
              children: [
                TextField(
                  controller: _goal,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '任务目标'),
                ),
                DropdownButton<String>(
                  value: _mode,
                  items: const [
                    DropdownMenuItem(
                      value: 'enterprise',
                      child: Text('企业受控模式'),
                    ),
                    DropdownMenuItem(
                      value: 'research',
                      child: Text('RL策略研究模式'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _mode = value!),
                ),
                DropdownButton<String>(
                  value: _workflow,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: 'assessment',
                      child: Text('原有联合评估'),
                    ),
                    DropdownMenuItem(
                      value: 'full_business',
                      child: Text('完整航次与业务闭环仿真'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _workflow = value!),
                ),
                if (_workflow == 'full_business')
                  CheckboxListTile(
                    title: const Text('显式模拟岗位演练（不代表真实双人审批）'),
                    value: _roleRehearsal,
                    onChanged: _busy
                        ? null
                        : (value) =>
                              setState(() => _roleRehearsal = value ?? false),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: const Text('生成联合计划'),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _load(),
                  child: const Text('读取联合任务'),
                ),
                if (m?['status'] == 'waiting_approval')
                  FilledButton(
                    onPressed: _busy ? null : _approve,
                    child: const Text('批准此联合计划'),
                  ),
                if (m?['status'] == 'waiting_business_approval') ...[
                  if (m?['config']['business_approval'] == 'role_rehearsal')
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _approveBusiness('role_rehearsal'),
                      child: const Text('确认模拟两个岗位演练并执行业务'),
                    )
                  else ...[
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _approveBusiness('operator'),
                      child: const Text('当前认证身份操作复核'),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _approveBusiness('safety_officer'),
                      child: const Text('当前认证管理员安全复核'),
                    ),
                  ],
                ],
                if (m?['status'] == 'waiting_mobile')
                  FilledButton(
                    onPressed: _busy ? null : _acknowledge,
                    child: const Text('确认收到联合回执'),
                  ),
                if ([
                  'running',
                  'paused',
                  'waiting_mobile',
                  'waiting_business_approval',
                ].contains(m?['status']))
                  OutlinedButton(onPressed: _stop, child: const Text('停止联合任务')),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (m != null) ...[
              SelectableText(
                '${labels[m['status']] ?? m['status']}\n${m['id']}',
              ),
              Text('计划摘要：${m['plan_sha256']}'),
              for (final note in (m['business_approvals'] as List? ?? const []))
                if (note is Map)
                  Text("${note['slot']} · ${note['actor_id']}"
                       "${(note['opinion'] ?? '').toString().isEmpty ? '' : ' · ${note['opinion']}'}"),
              if (m['delivery_sha256'] != null)
                SelectableText("交接摘要 / Delivery: ${m['delivery_sha256']}"),
              if (m['business_approval_sha256'] != null)
                Text('工作单复核摘要：${m['business_approval_sha256']}'),
              if (m['voyage_progress'] != null)
                Text(
                  '原生航次进度：${m['voyage_progress']['simulation_seconds']} 模拟秒，航点 ${m['voyage_progress']['waypoint']}',
                ),
              for (final step in (m['plan']['steps'] as List))
                Text(
                  '${results.containsKey(step['id']) ? '✓' : '○'} ${step['label']}',
                ),
              if (m['error'] != null) Text('${m['error']}'),
              ExpansionTile(
                title: const Text('查看实际回执'),
                children: [
                  for (final entry in results.entries)
                    ListTile(
                      title: Text(entry.key),
                      subtitle: SelectableText('${entry.value}'),
                    ),
                ],
              ),
              Text('${m['notice']}'),
            ],
          ],
        ),
      ),
    );
  }
}

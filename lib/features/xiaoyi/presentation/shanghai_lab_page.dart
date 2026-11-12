import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/dio_provider.dart';

/// Optional deep link; the established demonstration screens remain unchanged.
class ShanghaiLabPage extends ConsumerStatefulWidget {
  const ShanghaiLabPage({super.key, required this.trialId, this.transport});
  final String trialId;
  final Dio? transport;

  @override
  ConsumerState<ShanghaiLabPage> createState() => _ShanghaiLabPageState();
}

class _ShanghaiLabPageState extends ConsumerState<ShanghaiLabPage> {
  late final Dio _dio =
      widget.transport ??
      Dio(
        BaseOptions(
          baseUrl: const String.fromEnvironment(
            'XIAOYI_API_BASE_URL',
            defaultValue: 'http://127.0.0.1:8010',
          ),
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
  Map<String, dynamic>? _result, _briefing, _delivery, _pending;
  String? _error;
  bool _busy = false;
  String get _path => '/api/harness/shanghai/trials/${widget.trialId}';
  String get _key => 'shanghai.pending.${widget.trialId}';
  Options get _options => Options(
    headers: {
      if (ref.read(authTokenProvider) case final String token)
        'Authorization': 'Bearer $token',
    },
  );
  Map<String, dynamic> _map(dynamic data) =>
      Map<String, dynamic>.from(data as Map);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run(_load));
  }

  @override
  void dispose() {
    if (widget.transport == null) _dio.close(force: true);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) {
        _error = e is DioException ? '${e.response?.data ?? e.message}' : '$e';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _pending = saved == null ? null : _map(jsonDecode(saved));
    final result = _map(
      (await _dio.get<dynamic>(_path, options: _options)).data,
    );
    final briefing = _map(
      (await _dio.get<dynamic>('$_path/briefing', options: _options)).data,
    );
    final delivery = _map(
      (await _dio.get<dynamic>('$_path/delivery', options: _options)).data,
    );
    if (result['result_sha256'] != briefing['result_sha256'] ||
        result['result_sha256'] != delivery['result_sha256']) {
      throw StateError('结果版本不一致，请重新读取；本机不确认成功。');
    }
    if (mounted) {
      _result = result;
      _briefing = briefing;
      _delivery = delivery;
    }
  }

  Future<void> _send(String action) async {
    final sha = _result!['result_sha256'] as String;
    final client = kIsWeb
        ? 'flutter-web'
        : defaultTargetPlatform == TargetPlatform.macOS
        ? 'flutter-macos'
        : 'flutter-mobile';
    _pending ??= {
      'request_id': 'mobile-${DateTime.now().microsecondsSinceEpoch}',
      'result_sha256': sha,
      'action': action,
      'client': client,
    };
    if (_pending!['result_sha256'] != sha) {
      throw StateError('待确认请求属于另一版本，请保留记录并核查。');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_pending));
    final receipt = _map(
      (await _dio.post<dynamic>(
        '$_path/delivery',
        data: _pending,
        options: _options,
      )).data,
    );
    final readback = _map(
      (await _dio.get<dynamic>('$_path/delivery', options: _options)).data,
    );
    final events = (readback['events'] as List).map(_map);
    if (readback['result_sha256'] != sha ||
        !events.any(
          (e) =>
              e['sha256'] == receipt['sha256'] &&
              e['request_id'] == _pending!['request_id'],
        )) {
      throw StateError('服务端回执尚未独立读回；保留原请求，可重试确认。');
    }
    await prefs.remove(_key);
    if (mounted) {
      _pending = null;
      _delivery = readback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = ((_delivery?['events'] as List?) ?? [])
        .map((e) => _map(e)['action'])
        .toSet();
    final acknowledged = _delivery?['status'] == 'acknowledged_lab';
    return Scaffold(
      appBar: AppBar(title: const Text('PortAI · 上海港联合试验')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                '公开数据校准 · 试验复核与签收',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText('任务：${widget.trialId}'),
              const Text('保留原有策略和训练证据。此页不执行现场设备控制。'),
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('读取或确认未完成：$_error'),
                  ),
                ),
              if (_briefing != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(_briefing!['text'] as String),
                  ),
                ),
              if (_result != null) ...[
                SelectableText('结果摘要：${_result!['result_sha256']}'),
                const SizedBox(height: 12),
                Text(
                  acknowledged ? '已签收：服务端回执已独立读回' : '待完成业务复核与签收',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (_delivery?['review_mode'] == 'same_actor_lab_review')
                  const Text('当前为同一身份的岗位试验复核，不代表两名独立现场人员审批。'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final pair in const [
                      ('operations_review', '确认作业复核'),
                      ('energy_review', '确认能碳复核'),
                      ('acknowledge', '签收试验结果'),
                    ])
                      FilledButton(
                        onPressed:
                            _busy ||
                                _pending != null ||
                                done.contains(pair.$1) ||
                                pair.$1 == 'acknowledge' &&
                                    !done.containsAll([
                                      'operations_review',
                                      'energy_review',
                                    ])
                            ? null
                            : () => _run(() => _send(pair.$1)),
                        child: Text(
                          done.contains(pair.$1) ? '${pair.$2} · 已完成' : pair.$2,
                        ),
                      ),
                  ],
                ),
                for (final raw in (_delivery?['events'] as List?) ?? [])
                  ListTile(
                    title: Text('${_map(raw)['seq']}. ${_map(raw)['action']}'),
                    subtitle: Text(
                      '${_map(raw)['actor_id']} · ${_map(raw)['created_at']}',
                    ),
                  ),
              ],
              if (_pending != null) ...[
                const Text('有一条尚未确认的请求。重试沿用原编号，不重复生成签收。'),
                OutlinedButton(
                  onPressed: _busy || _result == null
                      ? null
                      : () => _run(() => _send(_pending!['action'] as String)),
                  child: const Text('重试并核对原回执'),
                ),
              ],
              TextButton(
                onPressed: _busy ? null : () => _run(_load),
                child: const Text('重新读取服务端记录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

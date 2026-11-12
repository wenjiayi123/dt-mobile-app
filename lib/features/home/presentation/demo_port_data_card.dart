import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dt_mobile_app/core/network/dio_provider.dart';

/// Uses the Web system's presentation feed; no local KPI calculation or polling.
class DemoPortDataCard extends ConsumerStatefulWidget {
  const DemoPortDataCard({super.key});

  @override
  ConsumerState<DemoPortDataCard> createState() => _DemoPortDataCardState();
}

class _DemoPortDataCardState extends ConsumerState<DemoPortDataCard> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  int _request = 0;

  Future<void> _load() async {
    final token = ++_request;
    setState(() { _loading = true; _data = null; _error = null; });
    try {
      final response = await ref.read(dioProvider).get<Object>('/api/public-port-demo/workspace');
      final raw = response.data;
      if (raw is! Map || raw['schema'] != 'port-dt-demo-workspace.v1' ||
          raw['production_authority'] != false || raw['metrics'] is! List ||
          raw['snapshot'] is! Map || raw['coverage'] is! Map) {
        throw const FormatException('演示数据合同不匹配');
      }
      if (!mounted || token != _request) return;
      setState(() { _data = Map<String, dynamic>.from(raw); });
    } catch (error) {
      if (!mounted || token != _request) return;
      setState(() { _error = '本次演示源未取得：$error'; });
    } finally {
      if (mounted && token == _request) setState(() { _loading = false; });
    }
  }

  String _value(Object? value) {
    if (value is num && value.isFinite) {
      return value == value.truncateToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final metrics = (_data?['metrics'] as List? ?? const []).whereType<Map>().toList();
    final snapshot = _data?['snapshot'] as Map?;
    final coverage = _data?['coverage'] as Map?;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.dataset_outlined, size: 19),
            const SizedBox(width: 8),
            const Expanded(child: Text('双端共享 · 演示作业数据')),
            TextButton(onPressed: _loading ? null : _load,
              child: Text(_loading ? '读取中…' : _data == null ? '读取演示数据' : '刷新演示数据')),
          ]),
          const Text('使用 Web 相同快照与来源；公开参数标定演示，非现场实测。', style: TextStyle(fontSize: 11)),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11))),
          if (_data != null) ...[
            const SizedBox(height: 8),
            Text('${_data!['source_mode']} · ${snapshot?['source_timestamp']}\n'
              '展示字段 ${coverage?['available']} / ${coverage?['total']}；现场接入和审批独立核验。',
              style: const TextStyle(fontSize: 11)),
            Wrap(spacing: 10, runSpacing: 8, children: metrics
              .where((m) => ['berths_busy', 'qc_busy', 'mean_service_hours', 'energy_kwh', 'electricity_carbon_kg', 'energy_kwh_per_teu'].contains(m['id']))
              .map((m) => SizedBox(width: 175, child: DecoratedBox(
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8)),
                child: Padding(padding: const EdgeInsets.all(10), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${m['name']}', style: const TextStyle(fontSize: 11)),
                    Text(_value(m['value']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    Text('${m['unit']}', style: const TextStyle(fontSize: 10)),
                  ])),
              ))).toList()),
            ExpansionTile(title: const Text('完整字段、来源与现场缺项', style: TextStyle(fontSize: 12)),
              children: [
                for (final m in metrics) ListTile(dense: true, title: Text('${m['name']}  ${_value(m['value'])} ${m['unit']}'),
                  subtitle: Text('${m['evidence_class']} · ${m['detail']}\n替换：${m['replacement']}', style: const TextStyle(fontSize: 10))),
                for (final item in (_data?['site_pending'] as List? ?? const []).whereType<Map>())
                  ListTile(dense: true, title: Text('现场待接入 · ${item['name']}'), subtitle: Text('${item['reason']}')),
              ]),
          ],
        ]),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';

/// Same backend training evidence as the Web client, packaged for offline demos.
class TrainedEvidencePanel extends StatefulWidget {
  const TrainedEvidencePanel({
    super.key,
    required this.data,
    required this.onClose,
  });
  final Map<String, dynamic> data;
  final VoidCallback onClose;
  @override
  State<TrainedEvidencePanel> createState() => _TrainedEvidencePanelState();
}

class _TrainedEvidencePanelState extends State<TrainedEvidencePanel> {
  int selected = 0;
  String query = '';
  static const labels = <String, String>{
    'algorithm': '具体算法',
    'datasets': '数据集名称、数量与来源',
    'state': 'State 状态（模型看到什么）',
    'reward': 'Reward 奖励（怎样判断好坏）',
    'actions': 'Action 动作（模型能决定什么）',
    'outputs': '输出清单与验证结果',
    'training': '训练记录与复现参数',
    'sources': '证据文件与 SHA-256',
  };
  String format(Object? value) => value is String
      ? value
      : const JsonEncoder.withIndent('  ').convert(value);

  String? brief(String key, Object? value) {
    if (key == 'training' || key == 'sources') return null;
    if (value is List && key == 'algorithm') return value.join(' · ');
    if (value is Map) {
      if (key == 'algorithm') {
        return format(value['trained_rl'] ?? value['method'] ?? value);
      }
      if (key == 'state' || key == 'actions') {
        final fields = value['fields'];
        if (fields is List) {
          return '${value['dimensions'] ?? fields.length} 项：${fields.take(6).join(' · ')}${fields.length > 6 ? '；展开查看完整顺序与范围' : ''}';
        }
      }
      if (key == 'reward') {
        return format(
          value['formula'] ?? value['weights'] ?? value['terms'] ?? value,
        );
      }
      if (key == 'outputs' && value['fields'] is List) {
        return (value['fields'] as List).join(' · ');
      }
    }
    if (key == 'datasets') {
      final descriptions = <String>{};
      void collect(Object? item, int depth) {
        if (depth > 4 || item == null) return;
        if (item is List) {
          for (final child in item) {
            collect(child, depth + 1);
          }
        } else if (item is Map) {
          final name =
              item['label'] ??
              item['title'] ??
              item['name'] ??
              item['id'] ??
              item['dataset_id'];
          final count =
              item['rows'] ?? item['row_count'] ?? item['recordCount'];
          if (name != null || count != null) {
            descriptions.add(
              '${name ?? ''}${count == null ? '' : ' · $count 条记录'}',
            );
          }
          if (name == null || count == null) {
            for (final child in item.values) {
              collect(child, depth + 1);
            }
          }
        }
      }

      collect(value, 0);
      if (descriptions.isNotEmpty) return descriptions.take(3).join('\n');
    }
    final text = format(value);
    return text.length > 200 ? '${text.substring(0, 200)}…（展开完整清单）' : text;
  }

  Widget? summary(String key, Object? value) {
    final text = brief(key, value);
    return text == null
        ? null
        : Text(
            text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.5,
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final scenes = (widget.data['scenarios'] as List)
        .cast<Map<String, dynamic>>();
    final filtered = scenes
        .asMap()
        .entries
        .where(
          (e) =>
              jsonEncode(e.value).toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final effective = filtered.any((e) => e.key == selected)
        ? selected
        : filtered.firstOrNull?.key;
    final scene = effective == null ? null : scenes[effective];
    return Material(
      key: const ValueKey('trained-evidence-panel'),
      color: const Color(0xFF092239),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '已训练场景 · 算法与数据清单',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: '关闭场景清单',
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              key: const ValueKey('evidence-search'),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '搜索场景、算法或数据集',
                labelStyle: TextStyle(color: Colors.cyanAccent),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Text(
                  '${filtered.length}/${scenes.length} 场景',
                  style: const TextStyle(color: Colors.cyanAccent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('evidence-scenes-$effective'),
                    initialValue: effective,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF123651),
                    style: const TextStyle(color: Colors.white),
                    items: filtered
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              '${e.key + 1}. ${e.value['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => selected = value);
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: scene == null
                ? const Center(
                    child: Text(
                      '没有匹配的场景',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : ListView(
                    key: ValueKey('evidence-scene-${scene['id']}'),
                    padding: const EdgeInsets.all(12),
                    children: [
                      Text(
                        '${scene['name']}\n${scene['status']}',
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '证据快照：${widget.data['generated_at']}\n与港口 Web 共用后端训练证据；公开观测、工程派生、模拟交互分项标识。',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      ...labels.entries.map(
                        (field) => Card(
                          color: const Color(0xFF11334D),
                          child: ExpansionTile(
                            key: ValueKey('${scene['id']}-${field.key}'),
                            title: Text(
                              field.value,
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: summary(field.key, scene[field.key]),
                            initiallyExpanded: false,
                            childrenPadding: const EdgeInsets.all(10),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: SelectableText(
                                  format(scene[field.key]),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

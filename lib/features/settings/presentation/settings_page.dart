import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/app.dart';
import 'package:dt_mobile_app/core/config/app_config.dart';
import 'package:dt_mobile_app/core/debug/debug_config.dart';
import 'package:dt_mobile_app/features/auth/application/auth_controller.dart';
import 'package:dt_mobile_app/features/demo/application/demo_flow_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(authViewStateProvider);
    final debugConfig = ref.watch(debugConfigProvider);
    final debugController = ref.read(debugConfigProvider.notifier);
    final demoFlow = ref.watch(demoFlowProvider);

    final baseUrl = AppConfig.apiBaseUrl;
    final wsUrl = _deriveWsUrl(baseUrl);
    final environmentLabel = _inferEnvironmentLabel(baseUrl);
    final transportLabel = _inferTransportLabel(baseUrl, wsUrl);
    final sourceLabel = AppConfig.sourceHint;
    final maskedToken = viewState.isLoggedIn
        ? viewState.currentMaskedToken
        : '未配置';

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(
            title: '移动端设置',
            subtitle: viewState.isLoggedIn ? '访问凭证已配置（未验证）' : '未配置访问凭证',
            trailing: _TonePill(
              label: viewState.isLoggedIn ? '已配置' : '未配置',
              tone: viewState.isLoggedIn ? _Tone.success : _Tone.neutral,
            ),
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: '账号与安全',
            children: [
              _SettingsTile(
                leading: viewState.isLoggedIn
                    ? Icons.verified_user_outlined
                    : Icons.lock_outline,
                title: '访问凭证',
                subtitle: viewState.isLoggedIn ? '当前凭证：$maskedToken' : '配置访问凭证',
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pushNamed(routeAuth);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: '系统',
            children: [
              _StaticInfoTile(
                leading: Icons.cloud_done_outlined,
                title: '连接',
                subtitle: '$sourceLabel · 实际状态以接口响应为准',
              ),
              const Divider(height: 1),
              _StaticInfoTile(
                leading: Icons.dns_outlined,
                title: '环境',
                subtitle: '$environmentLabel · $transportLabel',
              ),
              const Divider(height: 1),
              const _StaticInfoTile(
                leading: Icons.security_outlined,
                title: '安全',
                subtitle: '凭证信息仅展示脱敏摘要',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DeveloperSection(
            debugConfig: debugConfig,
            debugController: debugController,
            baseUrl: baseUrl,
            wsUrl: wsUrl,
            environmentLabel: environmentLabel,
            transportLabel: transportLabel,
            sourceLabel: sourceLabel,
            maskedToken: debugConfig.showTokenStatus ? maskedToken : '已隐藏',
            tokenStatus: viewState.isLoggedIn ? '已配置' : '未配置',
            demoFlowEnabled: demoFlow.enabled,
            onDemoModeChanged: (value) {
              ref.read(demoFlowProvider.notifier).setEnabled(value);
            },
            onReset: () {
              debugController.reset();
              ref.read(demoFlowProvider.notifier).reset();
            },
          ),
        ],
      ),
    );
  }
}

class _DeveloperSection extends StatelessWidget {
  const _DeveloperSection({
    required this.debugConfig,
    required this.debugController,
    required this.baseUrl,
    required this.wsUrl,
    required this.environmentLabel,
    required this.transportLabel,
    required this.sourceLabel,
    required this.maskedToken,
    required this.tokenStatus,
    required this.demoFlowEnabled,
    required this.onDemoModeChanged,
    required this.onReset,
  });

  final DebugConfigState debugConfig;
  final DebugConfigNotifier debugController;
  final String baseUrl;
  final String wsUrl;
  final String environmentLabel;
  final String transportLabel;
  final String sourceLabel;
  final String maskedToken;
  final String tokenStatus;
  final bool demoFlowEnabled;
  final ValueChanged<bool> onDemoModeChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: const Icon(Icons.developer_mode_outlined),
        title: const Text('高级选项'),
        subtitle: const Text('开发与联调'),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.layers_outlined),
            title: const Text('界面讲解流程'),
            subtitle: Text(
              demoFlowEnabled ? '已启用 · 只改变导航提示，不生成业务数据' : '已关闭 · 不显示讲解步骤',
            ),
            value: demoFlowEnabled,
            onChanged: onDemoModeChanged,
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.receipt_long_outlined),
            title: const Text('网络摘要'),
            subtitle: Text(debugConfig.networkLogEnabled ? '已启用' : '已关闭'),
            value: debugConfig.networkLogEnabled,
            onChanged: debugController.setNetworkLogEnabled,
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.key_outlined),
            title: const Text('凭证摘要'),
            subtitle: const Text('仅展示脱敏摘要'),
            value: debugConfig.showTokenStatus,
            onChanged: debugController.setShowTokenStatus,
          ),
          const Divider(height: 1),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.speed_outlined),
            title: const Text('流量统计'),
            subtitle: Text(debugConfig.showStreamPerfStats ? '已启用' : '已关闭'),
            value: debugConfig.showStreamPerfStats,
            onChanged: debugController.setShowStreamPerfStats,
          ),
          const SizedBox(height: 12),
          _DeveloperInfoCard(
            environmentLabel: environmentLabel,
            transportLabel: transportLabel,
            sourceLabel: sourceLabel,
            baseUrl: baseUrl,
            wsUrl: wsUrl,
            tokenStatus: tokenStatus,
            maskedToken: maskedToken,
            networkLogEnabled: debugConfig.networkLogEnabled,
            showStreamPerfStats: debugConfig.showStreamPerfStats,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('恢复默认'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData leading;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(leading),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _StaticInfoTile extends StatelessWidget {
  const _StaticInfoTile({
    required this.leading,
    required this.title,
    required this.subtitle,
  });

  final IconData leading;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(leading),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10305A), Color(0xFF0A1D38), Color(0xFF071427)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x664DE4FF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2639DFFF),
            blurRadius: 24,
            spreadRadius: -8,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF1769DB), Color(0xFF1FD3D0)],
              ),
              border: Border.all(color: const Color(0xFF73EDFF)),
              boxShadow: const [
                BoxShadow(color: Color(0x664DE4FF), blurRadius: 16),
              ],
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFB8C8E5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

enum _Tone { success, neutral }

class _TonePill extends StatelessWidget {
  const _TonePill({required this.label, required this.tone});

  final String label;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final foreground = tone == _Tone.success
        ? const Color(0xFF76F7C5)
        : const Color(0xFFB8C8E5);
    final background = tone == _Tone.success
        ? const Color(0x2629DFA7)
        : const Color(0x66172B49);
    final border = tone == _Tone.success
        ? const Color(0x6629DFA7)
        : const Color(0x465D789F);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DeveloperInfoCard extends StatelessWidget {
  const _DeveloperInfoCard({
    required this.environmentLabel,
    required this.transportLabel,
    required this.sourceLabel,
    required this.baseUrl,
    required this.wsUrl,
    required this.tokenStatus,
    required this.maskedToken,
    required this.networkLogEnabled,
    required this.showStreamPerfStats,
  });

  final String environmentLabel;
  final String transportLabel;
  final String sourceLabel;
  final String baseUrl;
  final String wsUrl;
  final String tokenStatus;
  final String maskedToken;
  final bool networkLogEnabled;
  final bool showStreamPerfStats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x3D4DE4FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '连接详情',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _DebugLine(label: '环境', value: environmentLabel),
          const SizedBox(height: 6),
          _DebugLine(label: '协议', value: transportLabel),
          const SizedBox(height: 6),
          _DebugLine(label: '链路', value: sourceLabel),
          const SizedBox(height: 6),
          _DebugLine(label: 'API', value: baseUrl),
          const SizedBox(height: 6),
          _DebugLine(label: 'WS', value: wsUrl),
          const SizedBox(height: 6),
          _DebugLine(label: '凭证', value: '$tokenStatus · $maskedToken'),
          const SizedBox(height: 6),
          _DebugLine(label: '网络日志', value: networkLogEnabled ? '开启' : '关闭'),
          const SizedBox(height: 6),
          _DebugLine(label: '流统计', value: showStreamPerfStats ? '开启' : '关闭'),
        ],
      ),
    );
  }
}

class _DebugLine extends StatelessWidget {
  const _DebugLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: style?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: style)),
      ],
    );
  }
}

String _deriveWsUrl(String baseUrl) {
  final normalized = baseUrl.trim();
  if (normalized.isEmpty) return 'ws://10.0.2.2:8000/ws';

  if (normalized.startsWith('https://')) {
    return 'wss://${normalized.substring('https://'.length)}/ws';
  }

  if (normalized.startsWith('http://')) {
    return 'ws://${normalized.substring('http://'.length)}/ws';
  }

  return 'ws://$normalized/ws';
}

String _inferEnvironmentLabel(String baseUrl) {
  if (AppConfig.environmentLabel == 'REPLAY') return '公开历史回放环境';
  final value = baseUrl.trim().toLowerCase();

  if (value.contains('10.0.2.2') ||
      value.contains('127.0.0.1') ||
      value.contains('localhost')) {
    return '开发环境';
  }

  if (value.contains('demo') ||
      value.contains('staging') ||
      value.contains('test')) {
    return '演示环境';
  }

  return '生产环境';
}

String _inferTransportLabel(String baseUrl, String wsUrl) {
  final httpPart = baseUrl.trim().startsWith('https://') ? 'HTTPS' : 'HTTP';
  final wsPart = wsUrl.trim().startsWith('wss://') ? 'WSS' : 'WS';
  return '$httpPart / $wsPart';
}

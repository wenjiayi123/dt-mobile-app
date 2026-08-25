import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/features/auth/application/auth_controller.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  late final TextEditingController _tokenController;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(authDraftControllerProvider);
    _tokenController = TextEditingController(text: draft.inputToken);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthDraftState>(authDraftControllerProvider, (previous, next) {
      final oldText = previous?.inputToken ?? '';
      if (_tokenController.text != next.inputToken &&
          _tokenController.text != oldText) {
        _tokenController.value = TextEditingValue(
          text: next.inputToken,
          selection: TextSelection.collapsed(offset: next.inputToken.length),
        );
      }
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewState = ref.watch(authViewStateProvider);
    final draftState = ref.watch(authDraftControllerProvider);
    final helperText = ref.watch(authInputHelperTextProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('访问凭证')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('访问凭证', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '配置后即可连接受保护的业务数据。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 16),
          _KeyConclusionCard(
            headline: viewState.summaryHeadline,
            detail: viewState.summaryDetail,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '凭证配置',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusPill(
                        icon: viewState.isLoggedIn
                            ? Icons.verified_user
                            : Icons.lock_outline,
                        label: viewState.statusLabel,
                        background: viewState.isLoggedIn
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        foreground: viewState.isLoggedIn
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('当前凭证（已脱敏）', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(
                      viewState.currentMaskedToken,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '更新凭证',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(helperText, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    obscureText: _obscureToken,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLines: 1,
                    textInputAction: TextInputAction.done,
                    onChanged: (value) {
                      ref
                          .read(authDraftControllerProvider.notifier)
                          .onTokenChanged(value);
                    },
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '访问凭证',
                      hintText: '请输入 Bearer Token',
                      suffixIcon: IconButton(
                        tooltip: _obscureToken ? '显示凭证' : '隐藏凭证',
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                        icon: Icon(
                          _obscureToken
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: draftState.canSave
                              ? () => _handleSave(context)
                              : null,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('保存凭证'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: viewState.hasToken || draftState.hasDraft
                              ? _handleClear
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('清空凭证'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleSave(BuildContext context) {
    final result = ref.read(authDraftControllerProvider.notifier).saveToken();

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.savedMaskedToken == null
              ? result.message
              : '${result.message}：${result.savedMaskedToken}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认清空访问凭证'),
        content: const Text('清空后，受保护的业务接口将停止使用当前凭证；后续需要重新配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final result = ref.read(authDraftControllerProvider.notifier).clearToken();
    _tokenController.clear();

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _KeyConclusionCard extends StatelessWidget {
  const _KeyConclusionCard({required this.headline, required this.detail});

  final String headline;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              headline,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(detail),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

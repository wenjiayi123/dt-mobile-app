import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'trained_evidence_panel.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/demo_flow_controller.dart';

/// A root-level floating guide remains above business pages and modal barriers.
/// Its outer Overlay supplies tooltips and menus without requiring a page route.
class DemoGuideLayout extends ConsumerStatefulWidget {
  const DemoGuideLayout({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<DemoGuideLayout> createState() => _DemoGuideLayoutState();
}

class _DemoGuideLayoutState extends ConsumerState<DemoGuideLayout> {
  Map<String, dynamic>? evidence;
  late final DemoAction openEvidence;
  late final DemoFlowController controller;

  Future<String> loadEvidence() async {
    if (!kIsWeb) return rootBundle.loadString('assets/demo-evidence.json');
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      final url = Uri.base
          .resolve('assets/assets/demo-evidence.json')
          .replace(
            queryParameters: {
              'evidence': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          );
      final response = await client.get<String>(
        url.toString(),
        options: Options(responseType: ResponseType.plain),
      );
      return response.data ?? (throw StateError('场景证据响应为空'));
    } finally {
      client.close();
    }
  }

  @override
  void initState() {
    super.initState();
    controller = ref.read(demoFlowProvider.notifier);
    openEvidence = () async {
      final content = await loadEvidence();
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      if ((parsed['scenarios'] as List).isEmpty) throw StateError('未找到已训练场景证据');
      if (mounted) setState(() => evidence = parsed);
      await WidgetsBinding.instance.endOfFrame;
    };
    controller.registerAction('trained-evidence', openEvidence);
  }

  @override
  void dispose() {
    controller.unregisterAction('trained-evidence', openEvidence);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DemoFlowState>(demoFlowProvider, (previous, next) {
      if (previous?.currentStep.id == 'trained-evidence' &&
          next.currentStep.id != 'trained-evidence' &&
          evidence != null) {
        setState(() => evidence = null);
      }
    });
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (evidence != null)
          Positioned(
            left: 8,
            right: 8,
            top: MediaQuery.sizeOf(context).height * 0.52,
            bottom: 8,
            child: TrainedEvidencePanel(
              data: evidence!,
              onClose: () => setState(() => evidence = null),
            ),
          ),
        const DemoGuideOverlay(),
      ],
    );
  }
}

/// Close a step's result surface when the presenter advances, without popping
/// an unrelated route that may have been opened by a result action.
class DemoStepSurface extends ConsumerWidget {
  const DemoStepSurface({super.key, required this.stepId, required this.child});
  final String stepId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<DemoFlowState>(demoFlowProvider, (previous, next) {
      if (previous?.currentStep.id == stepId && next.currentStep.id != stepId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.of(context).pop();
          }
        });
      }
    });
    return child;
  }
}

class DemoGuideOverlay extends ConsumerWidget {
  const DemoGuideOverlay({super.key});

  static const double expandedWidth = 222;
  static const double collapsedWidth = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoFlowProvider);
    final controller = ref.read(demoFlowProvider.notifier);
    final viewport = MediaQuery.sizeOf(context);
    final viewportWidth = viewport.width;
    // PortAI remains a mobile surface when rehearsed in a wide web window.
    // Keep the guide compact everywhere so it never turns into a desktop rail.
    final compactMobile = viewportWidth.isFinite;
    final panelWidth = !compactMobile
        ? expandedWidth
        : (viewportWidth * 0.56).clamp(188.0, 222.0).toDouble();
    final panelHeight = compactMobile ? viewport.height * 0.5 : null;
    if (!state.isOpen) {
      return Positioned(
        right: 10,
        top: 12,
        child: SafeArea(
          child: FilledButton.icon(
            key: const ValueKey('demo-guide-start'),
            onPressed: controller.restart,
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text('演示开始'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1769E0),
              foregroundColor: Colors.white,
              elevation: 8,
            ),
          ),
        ),
      );
    }

    if (state.isCollapsed) {
      return Positioned(
        right: 8,
        top: 12,
        child: SafeArea(
          child: Material(
            elevation: 12,
            color: const Color(0xFF0B2440),
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: collapsedWidth,
              height: 148,
              child: TextButton(
                key: const ValueKey('demo-guide-expand'),
                onPressed: controller.toggleCollapsed,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Semantics(
                  label:
                      '展开演示引导 ${state.currentStepIndex + 1}/${portAiDemoSteps.length}',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.chevron_left_rounded,
                        color: Color(0xFF65F5FF),
                      ),
                      const SizedBox(height: 8),
                      RotatedBox(
                        quarterTurns: 1,
                        child: Text(
                          '${state.currentStepIndex + 1}/${portAiDemoSteps.length} 演示引导',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'PortAISansSC',
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final step = state.currentStep;
    final resultReady =
        state.stepStatus == DemoStepStatus.resultReady ||
        state.stepStatus == DemoStepStatus.skipped;
    final statusColor = switch (state.stepStatus) {
      DemoStepStatus.running => const Color(0xFF65F5FF),
      DemoStepStatus.resultReady => const Color(0xFF76F7C5),
      DemoStepStatus.failed => const Color(0xFFFF7B88),
      DemoStepStatus.skipped => const Color(0xFFFFC46B),
      DemoStepStatus.idle => const Color(0xFF9DC8F8),
    };

    return Positioned(
      right: 8,
      top: 8,
      bottom: compactMobile ? null : 8,
      height: panelHeight,
      width: panelWidth,
      child: Container(
        key: const ValueKey('demo-guide-panel'),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1930),
          border: Border.all(color: const Color(0x5565F5FF)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            _Header(
              state: state,
              compact: compactMobile,
              onCollapse: controller.toggleCollapsed,
              onClose: controller.closeGuide,
            ),
            LinearProgressIndicator(
              value: state.progress.clamp(0, 1),
              minHeight: 3,
              color: const Color(0xFF65F5FF),
              backgroundColor: const Color(0xFF122A4A),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compactMobile ? 9 : 12,
                  compactMobile ? 7 : 12,
                  compactMobile ? 9 : 12,
                  compactMobile ? 5 : 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compactMobile) ...[
                      _StepPicker(
                        state: state,
                        onSelected: controller.jumpToStep,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      compactMobile
                          ? '${step.section}  ·  ${step.title}'
                          : step.section,
                      style: const TextStyle(
                        color: Color(0xFF65F5FF),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'PortAISansSC',
                        letterSpacing: 1.2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (!compactMobile) ...[
                      const SizedBox(height: 4),
                      Text(
                        step.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'PortAISansSC',
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else
                      const SizedBox(height: 5),
                    _InfoBlock(
                      icon: Icons.record_voice_over_outlined,
                      label: '演说台词',
                      text: step.narration,
                      color: const Color(0xFF8EBBFF),
                      compact: compactMobile,
                    ),
                    SizedBox(height: compactMobile ? 5 : 9),
                    _InfoBlock(
                      icon: Icons.visibility_outlined,
                      label: '可见变化',
                      text: step.expectedChange,
                      color: const Color(0xFF76F7C5),
                      compact: compactMobile,
                    ),
                    SizedBox(height: compactMobile ? 5 : 10),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(compactMobile ? 6 : 9),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (state.isBusy)
                            SizedBox.square(
                              dimension: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: statusColor,
                              ),
                            )
                          else
                            Icon(
                              _statusIcon(state.stepStatus),
                              size: 16,
                              color: statusColor,
                            ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              state.statusMessage ?? '等待执行当前操作。',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: compactMobile ? 9.5 : 10.5,
                                height: 1.35,
                                fontFamily: 'PortAISansSC',
                                decoration: TextDecoration.none,
                              ),
                              maxLines: compactMobile ? 1 : null,
                              overflow: compactMobile
                                  ? TextOverflow.ellipsis
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!compactMobile) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        'Trace ID  ${state.traceId.isEmpty ? '启动后生成' : state.traceId}',
                        style: const TextStyle(
                          color: Color(0xFF7894BD),
                          fontSize: 9,
                          fontFamily: 'PortAISansSC',
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compactMobile ? 7 : 10,
                compactMobile ? 3 : 8,
                compactMobile ? 7 : 10,
                compactMobile ? 6 : 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: compactMobile ? 38 : null,
                      child: FilledButton.icon(
                        key: const ValueKey('demo-guide-primary'),
                        onPressed: state.isBusy
                            ? null
                            : resultReady
                            ? () => unawaited(controller.advanceAndRun())
                            : () => unawaited(
                                controller.triggerAction(step.actionId),
                              ),
                        icon: state.isBusy
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                resultReady
                                    ? state.isComplete
                                          ? Icons.flag_outlined
                                          : Icons.arrow_forward_rounded
                                    : Icons.touch_app_outlined,
                              ),
                        label: Text(
                          state.isBusy
                              ? '执行中…'
                              : resultReady
                              ? state.isComplete
                                    ? '演示已完成'
                                    : '下一步并演示'
                              : step.actionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: compactMobile
                            ? FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'PortAISansSC',
                                  decoration: TextDecoration.none,
                                ),
                                iconSize: 16,
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  _CompactMoreMenu(state: state, controller: controller),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.compact,
    required this.onCollapse,
    required this.onClose,
  });
  final DemoFlowState state;
  final bool compact;
  final VoidCallback onCollapse;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(compact ? 8 : 12, 4, 3, 3),
    child: Row(
      children: [
        Icon(
          Icons.movie_filter_outlined,
          color: const Color(0xFF76F7C5),
          size: compact ? 16 : 19,
        ),
        SizedBox(width: compact ? 4 : 7),
        Expanded(
          child: Text(
            compact
                ? '演示 ${state.currentStepIndex + 1}/${portAiDemoSteps.length}'
                : 'PortAI 演示控制台  ${state.currentStepIndex + 1}/${portAiDemoSteps.length}',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w900,
              fontFamily: 'PortAISansSC',
              decoration: TextDecoration.none,
            ),
          ),
        ),
        IconButton(
          tooltip: '折叠',
          onPressed: onCollapse,
          icon: const Icon(Icons.chevron_right_rounded),
          iconSize: compact ? 17 : 19,
          visualDensity: compact ? VisualDensity.compact : null,
        ),
        IconButton(
          tooltip: '关闭',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          iconSize: compact ? 16 : 18,
          visualDensity: compact ? VisualDensity.compact : null,
        ),
      ],
    ),
  );
}

class _StepPicker extends StatelessWidget {
  const _StepPicker({required this.state, required this.onSelected});
  final DemoFlowState state;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: portAiDemoSteps.length,
      separatorBuilder: (_, _) => const SizedBox(width: 4),
      itemBuilder: (context, index) {
        final selected = index == state.currentStepIndex;
        final done = state.completedStepIds.contains(portAiDemoSteps[index].id);
        return InkWell(
          key: ValueKey('demo-step-${portAiDemoSteps[index].id}'),
          borderRadius: BorderRadius.circular(99),
          onTap: state.isBusy ? null : () => onSelected(index),
          child: Container(
            width: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? const Color(0xFF1769E0)
                  : done
                  ? const Color(0xFF16765A)
                  : const Color(0xFF132B4B),
              border: Border.all(
                color: selected
                    ? const Color(0xFF65F5FF)
                    : const Color(0xFF28466D),
              ),
            ),
            child: done && !selected
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'PortAISansSC',
                      decoration: TextDecoration.none,
                    ),
                  ),
          ),
        );
      },
    ),
  );
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.label,
    required this.text,
    required this.color,
    this.compact = false,
  });
  final IconData icon;
  final String label;
  final String text;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(compact ? 6 : 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                fontFamily: 'PortAISansSC',
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 2 : 5),
        Text(
          text,
          style: TextStyle(
            color: const Color(0xFFD9E7F9),
            fontSize: compact ? 10 : 11,
            height: compact ? 1.3 : 1.45,
            fontFamily: 'PortAISansSC',
            decoration: TextDecoration.none,
          ),
          maxLines: compact ? (label == '演说台词' ? 3 : 1) : null,
          overflow: compact ? TextOverflow.ellipsis : null,
        ),
      ],
    ),
  );
}

class _CompactMoreMenu extends StatelessWidget {
  const _CompactMoreMenu({required this.state, required this.controller});

  final DemoFlowState state;
  final DemoFlowController controller;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 34,
    child: MenuAnchor(
      builder: (context, menu, child) => IconButton(
        tooltip: '更多演示控制',
        padding: EdgeInsets.zero,
        onPressed: state.isBusy
            ? null
            : () => menu.isOpen ? menu.close() : menu.open(),
        icon: const Icon(Icons.more_horiz_rounded, size: 18),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: controller.retryCurrentStep,
          child: const Text('重试本步'),
        ),
        MenuItemButton(
          onPressed: controller.resetCurrentStep,
          child: const Text('重置本步'),
        ),
        MenuItemButton(
          onPressed: controller.resetAllGuide,
          child: const Text('重置全部'),
        ),
        MenuItemButton(
          onPressed: controller.fallbackNext,
          child: const Text('保底下一步'),
        ),
      ],
    ),
  );
}

IconData _statusIcon(DemoStepStatus status) => switch (status) {
  DemoStepStatus.idle => Icons.radio_button_unchecked_rounded,
  DemoStepStatus.running => Icons.sync_rounded,
  DemoStepStatus.resultReady => Icons.check_circle_outline_rounded,
  DemoStepStatus.failed => Icons.error_outline_rounded,
  DemoStepStatus.skipped => Icons.skip_next_rounded,
};

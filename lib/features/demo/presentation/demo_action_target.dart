import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/demo_flow_controller.dart';

/// Registers one real page action with the demo controller. The page button and
/// the guide both execute the same callback, so there is no duplicate business
/// logic and direct page clicks can move the guide to the matching step.
class DemoActionTarget extends ConsumerStatefulWidget {
  const DemoActionTarget({
    super.key,
    required this.actionId,
    required this.onAction,
    required this.builder,
    this.highlightRadius = 16,
  });

  final String actionId;
  final FutureOr<void> Function() onAction;
  final Widget Function(BuildContext context, VoidCallback onPressed) builder;
  final double highlightRadius;

  @override
  ConsumerState<DemoActionTarget> createState() => _DemoActionTargetState();
}

class _DemoActionTargetState extends ConsumerState<DemoActionTarget> {
  late DemoAction _registeredAction;
  late DemoFlowController _demoController;

  @override
  void initState() {
    super.initState();
    _demoController = ref.read(demoFlowProvider.notifier);
    _registeredAction = widget.onAction;
    WidgetsBinding.instance.addPostFrameCallback((_) => _register());
  }

  @override
  void didUpdateWidget(covariant DemoActionTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionId != widget.actionId ||
        !identical(oldWidget.onAction, widget.onAction)) {
      _demoController.unregisterAction(oldWidget.actionId, _registeredAction);
      _registeredAction = widget.onAction;
      WidgetsBinding.instance.addPostFrameCallback((_) => _register());
    }
  }

  void _register() {
    if (!mounted) return;
    _demoController.registerAction(widget.actionId, _registeredAction);
  }

  @override
  void dispose() {
    _demoController.unregisterAction(widget.actionId, _registeredAction);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = ref.watch(
      demoFlowProvider.select(
        (state) =>
            state.isOpen &&
            !state.isCollapsed &&
            state.currentStep.actionId == widget.actionId,
      ),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: highlighted ? const EdgeInsets.all(3) : EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.highlightRadius),
        border: highlighted
            ? Border.all(color: const Color(0xFF65F5FF), width: 2)
            : null,
        boxShadow: highlighted
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x5565F5FF),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: widget.builder(
        context,
        () => unawaited(
          ref
              .read(demoFlowProvider.notifier)
              .triggerAction(widget.actionId, origin: DemoActionOrigin.page),
        ),
      ),
    );
  }
}

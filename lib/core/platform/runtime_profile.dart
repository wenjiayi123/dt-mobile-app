import 'package:flutter/foundation.dart';

/// Runtime hints for the macOS desktop wrapper.
///
/// Keep the desktop wrapper's idle screen static. Business/action animation
/// stays enabled while ambient effects no longer compete with startup and input.
abstract final class RuntimeProfile {
  static bool get isNativeDesktopShell =>
      kIsWeb && Uri.base.queryParameters.containsKey('native_build');

  static bool get reduceAmbientMotion => isNativeDesktopShell;
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dt_mobile_app/core/network/dio_provider.dart';

/// 运行期访问凭证门面。凭证只保存在内存并注入 HTTP 请求；是否有效只能由
/// 服务器响应证明，应用不把“已填写”冒充为“已认证”。

@immutable
class AuthDraftState {
  const AuthDraftState({
    required this.inputToken,
    required this.canSave,
    required this.hasDraft,
    required this.previewMaskedToken,
    required this.helperText,
    required this.statusLabel,
  });

  final String inputToken;
  final bool canSave;
  final bool hasDraft;
  final String previewMaskedToken;
  final String helperText;
  final String statusLabel;

  AuthDraftState copyWith({
    String? inputToken,
    bool? canSave,
    bool? hasDraft,
    String? previewMaskedToken,
    String? helperText,
    String? statusLabel,
  }) {
    return AuthDraftState(
      inputToken: inputToken ?? this.inputToken,
      canSave: canSave ?? this.canSave,
      hasDraft: hasDraft ?? this.hasDraft,
      previewMaskedToken: previewMaskedToken ?? this.previewMaskedToken,
      helperText: helperText ?? this.helperText,
      statusLabel: statusLabel ?? this.statusLabel,
    );
  }

  static AuthDraftState fromToken({
    required String rawInput,
    required bool isLoggedIn,
  }) {
    final normalized = rawInput.trim();
    final hasDraft = normalized.isNotEmpty;

    return AuthDraftState(
      inputToken: rawInput,
      canSave: hasDraft,
      hasDraft: hasDraft,
      previewMaskedToken: hasDraft ? maskSensitiveToken(normalized) : '暂无',
      helperText: hasDraft ? '保存后即可访问受保护的数据。' : '请输入访问凭证。凭证仅在本次运行中有效。',
      statusLabel: isLoggedIn ? '凭证已配置（未验证）' : '凭证未配置',
    );
  }
}

/// 页面可直接消费的只读视图模型。
@immutable
class AuthViewState {
  const AuthViewState({
    required this.isLoggedIn,
    required this.statusLabel,
    required this.currentMaskedToken,
    required this.hasToken,
    required this.summaryHeadline,
    required this.summaryDetail,
  });

  final bool isLoggedIn;
  final String statusLabel;
  final String currentMaskedToken;
  final bool hasToken;
  final String summaryHeadline;
  final String summaryDetail;

  factory AuthViewState.fromAuthState(AuthState authState) {
    final isLoggedIn = authState.isLoggedIn;
    final masked = authState.maskedToken ?? '暂无';

    return AuthViewState(
      isLoggedIn: isLoggedIn,
      statusLabel: authState.statusLabel,
      currentMaskedToken: masked,
      hasToken: authState.token != null && authState.token!.trim().isNotEmpty,
      summaryHeadline: isLoggedIn ? '访问凭证已配置' : '访问凭证未配置',
      summaryDetail: isLoggedIn
          ? '凭证会注入请求，但只有服务器成功响应才能证明其有效。'
          : '如后端启用鉴权，请输入短期访问凭证。',
    );
  }
}

/// 页面行为结果，避免 UI 到处硬编码提示文案。
@immutable
class AuthActionResult {
  const AuthActionResult({
    required this.success,
    required this.message,
    this.savedMaskedToken,
  });

  final bool success;
  final String message;
  final String? savedMaskedToken;
}

class AuthDraftController extends Notifier<AuthDraftState> {
  @override
  AuthDraftState build() {
    final authState = ref.watch(authStateProvider);
    return AuthDraftState.fromToken(
      rawInput: authState.token ?? '',
      isLoggedIn: authState.isLoggedIn,
    );
  }

  void onTokenChanged(String value) {
    final authState = ref.read(authStateProvider);
    state = AuthDraftState.fromToken(
      rawInput: value,
      isLoggedIn: authState.isLoggedIn,
    );
  }

  void syncFromCurrentAuth() {
    final authState = ref.read(authStateProvider);
    state = AuthDraftState.fromToken(
      rawInput: authState.token ?? '',
      isLoggedIn: authState.isLoggedIn,
    );
  }

  AuthActionResult saveToken() {
    final normalized = state.inputToken.trim();
    if (normalized.isEmpty) {
      return const AuthActionResult(success: false, message: '凭证为空，未保存。');
    }

    ref.read(authStateProvider.notifier).setToken(normalized);

    state = AuthDraftState.fromToken(rawInput: normalized, isLoggedIn: true);

    return AuthActionResult(
      success: true,
      message: '访问凭证已保存到本次运行（尚未由服务器验证）',
      savedMaskedToken: maskSensitiveToken(normalized),
    );
  }

  AuthActionResult clearToken() {
    ref.read(authStateProvider.notifier).clearToken();

    state = AuthDraftState.fromToken(rawInput: '', isLoggedIn: false);

    return const AuthActionResult(success: true, message: '访问凭证已清空。');
  }
}

/// 给鉴权页绑定输入草稿。
final authDraftControllerProvider =
    NotifierProvider<AuthDraftController, AuthDraftState>(
      AuthDraftController.new,
    );

/// 给 UI 读取当前凭证配置状态；它不代表服务器已验证登录。
final authViewStateProvider = Provider<AuthViewState>((ref) {
  final authState = ref.watch(authStateProvider);
  return AuthViewState.fromAuthState(authState);
});

/// 给 UI 一个统一的“当前输入建议文案”读取口。
final authInputHelperTextProvider = Provider<String>((ref) {
  return ref.watch(authDraftControllerProvider).helperText;
});

/// 给 UI 一个统一的“当前预览脱敏 token”读取口。
final authDraftMaskedTokenProvider = Provider<String>((ref) {
  return ref.watch(authDraftControllerProvider).previewMaskedToken;
});

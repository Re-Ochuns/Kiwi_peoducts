import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/common_state_view.dart';
import 'auth_controller.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({required this.authenticatedBuilder, super.key});

  final Widget Function(BuildContext context, VoidCallback? signOut)
  authenticatedBuilder;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AuthController>();

    return switch (controller.state) {
      AuthViewState.restoring || AuthViewState.signedOut => const Scaffold(
        body: CommonStateView.loading(title: 'アプリを準備しています'),
      ),
      AuthViewState.authenticating => const Scaffold(
        body: CommonStateView.loading(title: 'アプリを準備しています'),
      ),
      AuthViewState.checkingAccess => const Scaffold(
        body: CommonStateView.loading(title: '利用状況を確認しています'),
      ),
      AuthViewState.authenticated => authenticatedBuilder(context, null),
      AuthViewState.accessUnavailable => AccessUnavailablePage(
        onSignOut: controller.signOut,
      ),
      AuthViewState.error => Scaffold(
        body: CommonStateView.error(
          title: '認証状態を確認できません',
          message: controller.message ?? '時間をおいて再試行してください。',
          actionLabel: '再試行',
          onAction: controller.retry,
        ),
      ),
    };
  }
}

class AccessUnavailablePage extends StatelessWidget {
  const AccessUnavailablePage({required this.onSignOut, super.key});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CommonStateView.error(
        title: '利用承認を確認できません',
        message: '管理者にアカウントの利用状況を確認してください。',
        actionLabel: '利用セッションを更新',
        onAction: onSignOut,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/common_state_view.dart';
import 'auth_controller.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({required this.authenticatedBuilder, super.key});

  final Widget Function(BuildContext context, VoidCallback signOut)
  authenticatedBuilder;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AuthController>();

    return switch (controller.state) {
      AuthViewState.restoring => const Scaffold(
        body: CommonStateView.loading(title: 'ログイン状態を確認しています'),
      ),
      AuthViewState.signedOut => LoginPage(
        onSignIn: controller.signInWithGoogle,
      ),
      AuthViewState.authenticating => const Scaffold(
        body: CommonStateView.loading(title: 'Googleログインを開始しています'),
      ),
      AuthViewState.checkingAccess => const Scaffold(
        body: CommonStateView.loading(title: '利用状況を確認しています'),
      ),
      AuthViewState.authenticated => authenticatedBuilder(
        context,
        controller.signOut,
      ),
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

class LoginPage extends StatelessWidget {
  const LoginPage({required this.onSignIn, super.key});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'おおくま農園',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ログイン',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '登録済みのGoogleアカウントを使用してください。',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: onSignIn,
                    child: const Text('Googleでログイン'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
        actionLabel: 'ログイン画面に戻る',
        onAction: onSignOut,
      ),
    );
  }
}

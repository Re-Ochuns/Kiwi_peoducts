import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

enum AuthViewState {
  restoring,
  signedOut,
  authenticating,
  checkingAccess,
  authenticated,
  accessUnavailable,
  error,
}

enum _RetryAction { restore, signIn, signOut }

class AuthController extends ChangeNotifier {
  AuthController(this._repository) {
    _subscription = _repository.authStateChanges.listen(
      _handleAuthChange,
      onError: (Object error, StackTrace stackTrace) => _showError(),
    );
    restoreSession();
  }

  final AuthRepository _repository;
  late final StreamSubscription<AuthUser?> _subscription;
  AuthViewState _state = AuthViewState.restoring;
  String? _message;
  int _requestId = 0;
  _RetryAction _retryAction = _RetryAction.restore;

  AuthViewState get state => _state;
  String? get message => _message;

  Future<void> restoreSession() async {
    final user = _repository.currentUser;
    if (user == null) {
      _setState(AuthViewState.signedOut);
      return;
    }
    await _checkAccess(user);
  }

  Future<void> signInWithGoogle() async {
    _setState(AuthViewState.authenticating);
    try {
      await _repository.signInWithGoogle();
    } catch (_) {
      _retryAction = _RetryAction.signIn;
      _showError('Googleログインを開始できませんでした。通信状況を確認して再試行してください。');
    }
  }

  Future<void> retry() => switch (_retryAction) {
    _RetryAction.restore => restoreSession(),
    _RetryAction.signIn => signInWithGoogle(),
    _RetryAction.signOut => signOut(),
  };

  Future<void> signOut() async {
    final requestId = ++_requestId;
    _setState(AuthViewState.restoring);
    try {
      await _repository.signOut();
      if (requestId == _requestId) _setState(AuthViewState.signedOut);
    } catch (_) {
      if (requestId == _requestId) {
        _retryAction = _RetryAction.signOut;
        _showError('ログアウトできませんでした。通信状況を確認して再試行してください。');
      }
    }
  }

  void _handleAuthChange(AuthUser? user) {
    if (user == null) {
      _requestId++;
      _setState(AuthViewState.signedOut);
      return;
    }
    _checkAccess(user);
  }

  Future<void> _checkAccess(AuthUser user) async {
    final requestId = ++_requestId;
    _setState(AuthViewState.checkingAccess);
    try {
      final status = await _repository.loadAccessStatus(user.id);
      if (requestId != _requestId) return;
      _setState(
        status == UserAccessStatus.active
            ? AuthViewState.authenticated
            : AuthViewState.accessUnavailable,
      );
    } catch (_) {
      if (requestId == _requestId) {
        _retryAction = _RetryAction.restore;
        _showError('利用状況を確認できませんでした。通信状況を確認して再試行してください。');
      }
    }
  }

  void _showError([String? message]) {
    _setState(
      AuthViewState.error,
      message: message ?? '認証状態を確認できませんでした。再試行してください。',
    );
  }

  void _setState(AuthViewState next, {String? message}) {
    _state = next;
    _message = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

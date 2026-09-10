@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/auth/auth_repository.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/main.dart';

import 'support/golden_test_environment.dart';

void main() {
  final goldenDate = DateTime(2026, 9, 8);
  setUpAll(loadGoldenTestFont);

  testWidgets('390pxのログイン画面', (tester) async {
    configureGoldenView(tester, const Size(390, 844));
    await tester.pumpWidget(
      KiwiInventoryApp(
        authRepository: _SignedOutGoldenAuthRepository(),
        theme: buildAppTheme(fontFamily: goldenFontFamily),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KiwiInventoryApp),
      matchesGoldenFile('goldens/login_390.png'),
    );
  });

  testWidgets('390pxの作業者ホーム', (tester) async {
    configureGoldenView(tester, const Size(390, 844));
    await tester.pumpWidget(
      KiwiInventoryApp(
        authRepository: _GoldenAuthRepository(),
        currentDate: goldenDate,
        theme: buildAppTheme(fontFamily: goldenFontFamily),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KiwiInventoryApp),
      matchesGoldenFile('goldens/worker_home_390.png'),
    );
  });

  testWidgets('1280pxの管理ホーム', (tester) async {
    configureGoldenView(tester, const Size(1280, 900));
    await tester.pumpWidget(
      KiwiInventoryApp(
        authRepository: _GoldenAuthRepository(),
        currentDate: goldenDate,
        theme: buildAppTheme(fontFamily: goldenFontFamily),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KiwiInventoryApp),
      matchesGoldenFile('goldens/manager_home_1280.png'),
    );
  });
}

class _GoldenAuthRepository implements AuthRepository {
  static const _user = AuthUser(id: 'golden-user');
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<UserAccessStatus> loadAccessStatus(String userId) async =>
      UserAccessStatus.active;

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}
}

class _SignedOutGoldenAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<UserAccessStatus> loadAccessStatus(String userId) async =>
      UserAccessStatus.unavailable;

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}
}

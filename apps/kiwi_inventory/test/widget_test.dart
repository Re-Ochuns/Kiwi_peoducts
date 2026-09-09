import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/auth/auth_repository.dart';
import 'package:kiwi_inventory/main.dart';

void main() {
  group('レスポンシブ基盤', () {
    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('${width.toInt()}px幅で作業者ホームを表示する', (tester) async {
        await _setSurface(tester, Size(width, 900));
        await tester.pumpWidget(
          KiwiInventoryApp(authRepository: FakeAuthRepository.active()),
        );
        await tester.pumpAndSettle();

        expect(find.text('おおくま農園'), findsOneWidget);
        expect(find.text('ToDo'), findsOneWidget);
        expect(find.text('収穫・仕入れ登録'), findsOneWidget);
        expect(find.text('追熟計画作成'), findsOneWidget);
        expect(find.byType(BottomNavigationBar), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in [900.0, 1280.0]) {
      testWidgets('${width.toInt()}px幅で管理ホームを表示する', (tester) async {
        await _setSurface(tester, Size(width, 900));
        await tester.pumpWidget(
          KiwiInventoryApp(authRepository: FakeAuthRepository.active()),
        );
        await tester.pumpAndSettle();

        expect(find.text('ホーム'), findsAtLeastNWidgets(1));
        expect(find.text('受注'), findsOneWidget);
        expect(find.text('在庫管理'), findsOneWidget);
        expect(find.text('優先して確認'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('ToDoから詳細を開いて戻れる', (tester) async {
      await _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        KiwiInventoryApp(authRepository: FakeAuthRepository.active()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('LOT-2026-0142'));
      await tester.pumpAndSettle();
      expect(find.text('対象ID'), findsOneWidget);
      expect(find.text('← ToDoへ戻る'), findsOneWidget);

      await tester.tap(find.text('← ToDoへ戻る'));
      await tester.pumpAndSettle();
      expect(find.text('作業を始める'), findsOneWidget);
    });

    testWidgets('詳細への矢印操作に対象を含む読み上げ名がある', (tester) async {
      await _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        KiwiInventoryApp(authRepository: FakeAuthRepository.active()),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('LOT-2026-0142の詳細を見る'), findsOneWidget);
    });
  });

  group('認証後ルーティング', () {
    testWidgets('未認証ではログイン画面だけを表示する', (tester) async {
      final repository = FakeAuthRepository.signedOut();
      await tester.pumpWidget(KiwiInventoryApp(authRepository: repository));
      await tester.pump();

      expect(find.text('Googleでログイン'), findsOneWidget);
      expect(find.text('ToDo'), findsNothing);
    });

    testWidgets('キーボードでGoogleログインを開始できる', (tester) async {
      final repository = FakeAuthRepository.signedOut();
      await tester.pumpWidget(KiwiInventoryApp(authRepository: repository));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(repository.signInCalls, 1);
    });

    testWidgets('有効なセッションを復元してホームへ進む', (tester) async {
      await _setSurface(tester, const Size(390, 844));
      final repository = FakeAuthRepository.active();
      await tester.pumpWidget(KiwiInventoryApp(authRepository: repository));
      await tester.pumpAndSettle();

      expect(find.text('ToDo'), findsOneWidget);
      expect(repository.accessChecks, 1);
    });

    testWidgets('Googleログイン後に利用状況を確認してホームへ進む', (tester) async {
      await _setSurface(tester, const Size(390, 844));
      final repository = FakeAuthRepository.signedOut();
      await tester.pumpWidget(KiwiInventoryApp(authRepository: repository));
      await tester.pump();

      await tester.tap(find.text('Googleでログイン'));
      await tester.pumpAndSettle();

      expect(repository.signInCalls, 1);
      expect(find.text('ToDo'), findsOneWidget);
    });

    testWidgets('利用承認を確認できないユーザーをホームへ通さない', (tester) async {
      final repository = FakeAuthRepository.restricted();
      await tester.pumpWidget(KiwiInventoryApp(authRepository: repository));
      await tester.pumpAndSettle();

      expect(find.text('利用承認を確認できません'), findsOneWidget);
      expect(find.text('ToDo'), findsNothing);
      expect(find.text('ログイン画面に戻る'), findsOneWidget);
    });

    testWidgets('認証失敗を日本語で表示して再試行できる', (tester) async {
      final repository = FakeAuthRepository.signedOut(signInFails: true);
      await tester.pumpWidget(KiwiInventoryApp(authRepository: repository));
      await tester.pump();

      await tester.tap(find.text('Googleでログイン'));
      await tester.pumpAndSettle();

      expect(find.text('認証状態を確認できません'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
      expect(
        find.text('Googleログインを開始できませんでした。通信状況を確認して再試行してください。'),
        findsOneWidget,
      );

      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(repository.signInCalls, 2);
    });

    testWidgets('設定不足を画面上で説明する', (tester) async {
      await tester.pumpWidget(
        const KiwiInventoryApp(startupError: '接続設定がありません。'),
      );

      expect(find.text('アプリを開始できません'), findsOneWidget);
      expect(find.text('接続設定がありません。'), findsOneWidget);
    });
  });
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository._(
    this._user, {
    required this.accessStatus,
    this.signInFails = false,
  });

  factory FakeAuthRepository.active() => FakeAuthRepository._(
    const AuthUser(id: 'active-user', email: 'worker@example.com'),
    accessStatus: UserAccessStatus.active,
  );

  factory FakeAuthRepository.signedOut({bool signInFails = false}) =>
      FakeAuthRepository._(
        null,
        accessStatus: UserAccessStatus.active,
        signInFails: signInFails,
      );

  factory FakeAuthRepository.restricted() => FakeAuthRepository._(
    const AuthUser(id: 'restricted-user'),
    accessStatus: UserAccessStatus.unavailable,
  );

  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast(sync: true);
  AuthUser? _user;
  final UserAccessStatus accessStatus;
  final bool signInFails;
  int signInCalls = 0;
  int accessChecks = 0;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<UserAccessStatus> loadAccessStatus(String userId) async {
    accessChecks++;
    return accessStatus;
  }

  @override
  Future<void> signInWithGoogle() async {
    signInCalls++;
    if (signInFails) throw Exception('sign in failed');
    _user = const AuthUser(id: 'signed-in-user');
    _controller.add(_user);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }
}

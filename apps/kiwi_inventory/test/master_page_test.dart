import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/master/master_page.dart';
import 'package:kiwi_inventory/master/master_repository.dart';

import 'support/fake_master_repository.dart';

void main() {
  group('マスター一覧', () {
    testWidgets('管理ホームからマスターへ遷移する', (tester) async {
      final repository = FakeMasterRepository();
      await _setSurface(tester, const Size(1280, 900));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ManagerHomePage(masterRepository: repository),
        ),
      );

      await tester.tap(find.text('マスター'));
      await tester.pumpAndSettle();

      expect(find.byType(MasterPage), findsOneWidget);
      expect(find.text('hayward'), findsOneWidget);
      expect(repository.loadCalls, 1);
    });

    testWidgets('900px幅で表示し、種類と検索条件を変更できる', (tester) async {
      await _pumpMaster(
        tester,
        FakeMasterRepository(),
        size: const Size(900, 900),
      );

      await tester.tap(find.byKey(const Key('master-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作業者').last);
      await tester.pumpAndSettle();
      expect(find.text('worker-01'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('master-search')), '作業者A');
      await tester.pump();
      expect(find.text('worker-01'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('無効データは初期表示から除外する', (tester) async {
      await _pumpMaster(tester, FakeMasterRepository());

      expect(find.text('hayward'), findsOneWidget);
      expect(find.text('koryoku'), findsNothing);
      await tester.tap(find.byKey(const Key('master-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('すべて').last);
      await tester.pumpAndSettle();
      expect(find.text('koryoku'), findsOneWidget);
    });

    testWidgets('段階1の9種類を一覧できる', (tester) async {
      await _pumpMaster(tester, FakeMasterRepository());
      const cases = <MasterType, String>{
        MasterType.variety: 'hayward',
        MasterType.grade: 'L',
        MasterType.orchard: 'farm-01',
        MasterType.orchardPlot: 'plot-a',
        MasterType.tree: 'tree-01',
        MasterType.supplier: 'supplier-01',
        MasterType.worker: 'worker-01',
        MasterType.storageLocation: 'cold-01',
        MasterType.sortingDeadlineRule: '2026年9月',
      };

      for (final entry in cases.entries) {
        await tester.tap(find.byKey(const Key('master-type')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.key.label).last);
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets('閲覧権限だけの利用者に更新操作を表示しない', (tester) async {
      await _pumpMaster(tester, FakeMasterRepository(canManage: false));

      expect(find.text('新規登録'), findsNothing);
      await tester.tap(find.text('hayward'));
      await tester.pumpAndSettle();
      expect(find.text('編集'), findsNothing);
      expect(find.text('無効化'), findsNothing);
      expect(find.textContaining('閲覧のみ'), findsOneWidget);
    });

    testWidgets('選択欄に装飾矢印を表示しない', (tester) async {
      await _pumpMaster(tester, FakeMasterRepository());

      expect(find.text('↓'), findsNothing);
      expect(find.byType(Icon), findsNothing);
    });
  });

  group('マスター更新', () {
    testWidgets('品種を新規登録する', (tester) async {
      final repository = FakeMasterRepository();
      await _pumpMaster(tester, repository);

      await tester.tap(find.text('新規登録'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('master-field-code')),
        'rainbow-red',
      );
      await tester.enterText(
        find.byKey(const Key('master-field-name')),
        'レインボーレッド',
      );
      await tester.tap(find.byKey(const Key('master-submit')));
      await tester.pumpAndSettle();

      expect(repository.registerCalls, 1);
      expect(repository.lastType, MasterType.variety);
      expect(repository.lastValues?['code'], 'rainbow-red');
      expect(repository.lastIdempotencyKey, isNotEmpty);
    });

    testWidgets('変更理由を付けて品種を編集する', (tester) async {
      final repository = FakeMasterRepository();
      await _pumpMaster(tester, repository);
      await tester.tap(find.text('hayward'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('編集'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('master-field-name')),
        'ヘイワード改',
      );
      await tester.enterText(
        find.byKey(const Key('master-field-reason')),
        '表記を統一',
      );
      await tester.tap(find.byKey(const Key('master-submit')));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, 1);
      expect(repository.lastValues?['name'], 'ヘイワード改');
      expect(repository.lastReason, '表記を統一');
    });

    testWidgets('理由を必須にして無効化する', (tester) async {
      final repository = FakeMasterRepository();
      await _pumpMaster(tester, repository);
      await tester.tap(find.text('hayward'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('無効化'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('master-transition-submit')));
      await tester.pump();
      expect(find.text('理由を入力してください。'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('master-transition-reason')),
        '今季の使用終了',
      );
      await tester.tap(find.byKey(const Key('master-transition-submit')));
      await tester.pumpAndSettle();

      expect(repository.setActiveCalls, 1);
      expect(repository.lastActive, isFalse);
      expect(repository.lastReason, '今季の使用終了');
    });

    testWidgets('無効化済みマスターを再有効化する', (tester) async {
      final repository = FakeMasterRepository();
      await _pumpMaster(tester, repository);
      await tester.tap(find.byKey(const Key('master-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('無効').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('koryoku'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('再有効化'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('master-transition-reason')),
        '取扱い再開',
      );
      await tester.tap(find.byKey(const Key('master-transition-submit')));
      await tester.pumpAndSettle();

      expect(repository.setActiveCalls, 1);
      expect(repository.lastActive, isTrue);
      expect(repository.lastReason, '取扱い再開');
    });

    testWidgets('項目別の重複エラーをフォームに表示する', (tester) async {
      final repository = FakeMasterRepository(
        nextFailure: const MasterFailure(
          message: 'このコードは登録済みです。',
          code: 'MASTER_DUPLICATE',
          field: 'code',
          reason: 'duplicate',
        ),
      );
      await _pumpMaster(tester, repository);
      await tester.tap(find.text('新規登録'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('master-field-code')),
        'hayward',
      );
      await tester.enterText(find.byKey(const Key('master-field-name')), '別品種');
      await tester.tap(find.byKey(const Key('master-submit')));
      await tester.pumpAndSettle();

      expect(find.text('このコードは登録済みです。'), findsWidgets);
      expect(find.byType(MasterFormDialog), findsOneWidget);
    });

    testWidgets('等級は新規登録せず表示順だけ編集する', (tester) async {
      final repository = FakeMasterRepository();
      await _pumpMaster(tester, repository);
      await tester.tap(find.byKey(const Key('master-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('等級').last);
      await tester.pumpAndSettle();

      expect(find.text('新規登録'), findsNothing);
      await tester.tap(find.text('L'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('編集'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('master-field-display_order')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('master-field-code')), findsNothing);
    });
  });
}

Future<void> _pumpMaster(
  WidgetTester tester,
  FakeMasterRepository repository, {
  Size size = const Size(1280, 900),
}) async {
  await _setSurface(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: MasterPage(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

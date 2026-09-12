import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/ripening/ripening_plan_page.dart';
import 'package:kiwi_inventory/ripening/ripening_plan_repository.dart';

import 'support/fake_ripening_plan_repository.dart';

void main() {
  testWidgets('作業者ホームから追熟計画を開ける', (tester) async {
    final repository = FakeRipeningPlanRepository();
    await _setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: WorkerHomePage(
          ripeningPlanRepository: repository,
          currentDate: DateTime(2026, 9, 12, 9),
        ),
      ),
    );

    await tester.tap(find.text('追熟計画作成'));
    await tester.pumpAndSettle();

    expect(find.byType(RipeningPlanPage), findsOneWidget);
    expect(repository.loadCalls, 1);
  });

  testWidgets('管理者ナビから同じ追熟計画を開ける', (tester) async {
    final repository = FakeRipeningPlanRepository();
    await _setSurface(tester, const Size(1280, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ManagerHomePage(
          ripeningPlanRepository: repository,
          currentDate: DateTime(2026, 9, 12, 9),
        ),
      ),
    );

    await tester.tap(find.text('追熟計画'));
    await tester.pumpAndSettle();

    expect(find.byType(ManagerRipeningPlanPage), findsOneWidget);
    expect(find.byType(RipeningPlanPage), findsOneWidget);
    expect(repository.loadCalls, 1);
  });

  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('${width.toInt()}px幅で横方向に崩れずアイコンを表示しない', (tester) async {
      await _pumpPage(tester, size: Size(width, 900));
      await _completeMixedForm(tester);

      expect(find.text('追熟計画作成'), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('取得失敗から再試行できる', (tester) async {
    final repository = FakeRipeningPlanRepository(loadFailures: 1);
    await _pumpPage(tester, repository: repository);

    expect(find.text('追熟計画を開始できません'), findsOneWidget);
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();

    expect(find.text('追熟計画作成'), findsOneWidget);
    expect(repository.loadCalls, 2);
  });

  testWidgets('内訳合計が追熟重量と一致するまで確認できない', (tester) async {
    await _pumpPage(tester);
    await _selectValue(
      tester,
      const Key('ripening-inventory'),
      testRipeningOptions.inventories.single,
    );
    await tester.enterText(find.byKey(const Key('ripening-weight')), '10');
    await _selectValue(
      tester,
      const Key('ripening-allocation-order-0'),
      'order-1',
    );
    await tester.enterText(
      find.byKey(const Key('ripening-allocation-weight-0')),
      '6',
    );
    await tester.pump();

    expect(find.text('未割当　4.00 kg'), findsOneWidget);
    final review = tester.widget<FilledButton>(
      find.byKey(const Key('ripening-review')),
    );
    expect(review.onPressed, isNull);
  });

  testWidgets('受注と予備を合わせて下書き登録し確定する', (tester) async {
    final repository = FakeRipeningPlanRepository();
    await _pumpPage(tester, repository: repository);
    await _completeMixedForm(tester);

    await _tapVisible(tester, find.byKey(const Key('ripening-review')));
    await tester.pumpAndSettle();
    expect(find.text('入力内容の確認'), findsOneWidget);
    expect(find.text('受注 1件・予備 1件'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ripening-submit')));
    await tester.pumpAndSettle();

    expect(repository.registerCalls, 1);
    expect(repository.confirmCalls, 1);
    expect(repository.lastInput!.totalWeightHundredths, 1000);
    expect(repository.lastInput!.allocations.length, 2);
    expect(
      repository.lastInput!.allocations.last.type,
      RipeningAllocationType.reserve,
    );
    expect(
      repository.lastInput!.plannedCompletionAt.difference(
        repository.lastInput!.plannedEthyleneAt,
      ),
      const Duration(hours: 168),
    );
    expect(find.text('登録完了'), findsOneWidget);
    expect(find.text('追熟-2026-001'), findsOneWidget);
  });

  testWidgets('確定失敗後は下書きを再登録せず同じ確定キーで再送する', (tester) async {
    final repository = FakeRipeningPlanRepository(confirmFailures: 1);
    await _pumpPage(tester, repository: repository);
    await _completeMixedForm(tester);

    await _submitFromDialog(tester);
    expect(find.textContaining('通信状況を確認'), findsOneWidget);
    expect(find.text('下書きID: 追熟-2026-001'), findsOneWidget);
    final firstConfirmKey = repository.confirmKeys.single;

    await _submitFromDialog(tester);

    expect(repository.registerCalls, 1);
    expect(repository.confirmCalls, 2);
    expect(repository.confirmKeys.last, firstConfirmKey);
    expect(find.text('登録完了'), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  FakeRipeningPlanRepository? repository,
  Size size = const Size(390, 900),
}) async {
  await _setSurface(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: RipeningPlanPage(
        repository: repository ?? FakeRipeningPlanRepository(),
        currentDate: DateTime(2026, 9, 12, 9),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _completeMixedForm(WidgetTester tester) async {
  await _selectValue(
    tester,
    const Key('ripening-inventory'),
    testRipeningOptions.inventories.single,
  );
  await tester.enterText(find.byKey(const Key('ripening-weight')), '10');
  await _selectValue(
    tester,
    const Key('ripening-allocation-order-0'),
    'order-1',
  );
  await tester.enterText(
    find.byKey(const Key('ripening-allocation-weight-0')),
    '6',
  );
  await _pressButton<OutlinedButton>(
    tester,
    const Key('ripening-add-allocation'),
  );
  await _selectValue(
    tester,
    const Key('ripening-allocation-type-1'),
    RipeningAllocationType.reserve,
  );
  await tester.enterText(
    find.byKey(const Key('ripening-allocation-weight-1')),
    '4',
  );
  await _selectValue(tester, const Key('ripening-location'), 'location-1');
  await _selectValue(tester, const Key('ripening-worker'), 'worker-1');
  await tester.pump();

  expect(find.text('未割当　0.00 kg'), findsOneWidget);
  final review = tester.widget<FilledButton>(
    find.byKey(const Key('ripening-review')),
  );
  expect(review.onPressed, isNotNull);
}

Future<void> _submitFromDialog(WidgetTester tester) async {
  await _tapVisible(tester, find.byKey(const Key('ripening-review')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('ripening-submit')));
  await tester.pumpAndSettle();
}

Future<void> _selectValue(WidgetTester tester, Key key, Object value) async {
  final dynamic field = tester.widget(find.byKey(key));
  field.onChanged(value);
  await tester.pump();
}

Future<void> _pressButton<T extends ButtonStyleButton>(
  WidgetTester tester,
  Key key,
) async {
  final button = tester.widget<T>(find.byKey(key));
  button.onPressed!.call();
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

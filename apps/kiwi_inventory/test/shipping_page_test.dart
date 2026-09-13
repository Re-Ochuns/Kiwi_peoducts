import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/shipping/shipping_page.dart';

import 'support/fake_shipping_repository.dart';

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('${width.toInt()}pxで出荷対象と残量を表示できる', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(FakeShippingRepository()));
      await tester.pumpAndSettle();

      expect(find.text('受注-2026-001'), findsOneWidget);
      expect(find.text('出荷残量 7.50 kg'), findsOneWidget);
      expect(find.text('一部出荷'), findsOneWidget);
      expect(find.text('追熟-2026-001-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('部分出荷を確認して残量と複数実績を更新する', (tester) async {
    final repository = FakeShippingRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shipping-weight-container-1')),
      '3.00',
    );
    await tester.pump();
    await _tapConfirm(tester);

    expect(find.text('出荷内容の確認'), findsOneWidget);
    expect(find.text('受注-2026-001'), findsNWidgets(2));
    expect(find.text('3.00 kg'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('shipping-complete')));
    await tester.pumpAndSettle();

    expect(repository.lastInput?.expectedOrderVersion, 3);
    expect(repository.lastInput?.lines.single.weightHundredths, 300);
    expect(find.text('出荷を記録しました'), findsOneWidget);
    expect(find.text('4.50 kg'), findsOneWidget);
    await tester.tap(find.text('出荷内容へ戻る'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('出荷実績'));
    expect(find.text('出荷-2026-002'), findsOneWidget);
    expect(find.text('出荷-2026-001'), findsOneWidget);
  });

  testWidgets('使用可能残量を超える確定操作を無効にする', (tester) async {
    await tester.pumpWidget(_app(FakeShippingRepository()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shipping-weight-container-1')),
      '6.01',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('追熟-2026-001-1の使用可能残量を超えています'));

    expect(find.text('追熟-2026-001-1の使用可能残量を超えています'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('shipping-confirm-input')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('出荷取消は理由と確認を経て残量を復元する', (tester) async {
    final repository = FakeShippingRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('この出荷を取り消す'));
    await tester.tap(find.text('この出荷を取り消す'));
    await tester.pumpAndSettle();

    expect(find.text('出荷取消の確認'), findsOneWidget);
    expect(find.text('出荷-2026-001'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('shipping-cancel-complete')));
    await tester.pumpAndSettle();

    expect(repository.cancelCalls, 1);
    expect(repository.shippedWeightHundredths, 0);
    expect(find.text('取消済み'), findsOneWidget);
    expect(find.text('出荷を取り消しました'), findsOneWidget);
  });

  testWidgets('結果不明の再確認は同じ冪等性キーを使う', (tester) async {
    final repository = FakeShippingRepository(confirmFailures: 1);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('shipping-weight-container-1')),
      '1.00',
    );
    await tester.pump();
    await _tapConfirm(tester);
    await tester.tap(find.byKey(const Key('shipping-complete')));
    await tester.pumpAndSettle();

    expect(find.text('出荷結果を確認できませんでした。'), findsOneWidget);
    await _tapConfirm(tester);
    await tester.tap(find.byKey(const Key('shipping-complete')));
    await tester.pumpAndSettle();

    expect(repository.confirmKeys, hasLength(2));
    expect(repository.confirmKeys.first, repository.confirmKeys.last);
  });

  testWidgets('出荷予定一覧から対象受注を選択できる', (tester) async {
    final repository = FakeShippingRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ShippingPage(
          repository: repository,
          currentDate: DateTime(2026, 9, 13, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('出荷予定'), findsOneWidget);
    await tester.tap(find.text('受注-2026-001'));
    await tester.pumpAndSettle();

    expect(find.text('出荷内容'), findsOneWidget);
    expect(repository.loadOrderCalls, 1);
  });

  testWidgets('出荷予定の読込失敗から再試行できる', (tester) async {
    final repository = FakeShippingRepository(loadFailures: 1);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ShippingPage(
          repository: repository,
          currentDate: DateTime(2026, 9, 13, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('出荷予定を表示できません'), findsOneWidget);
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();

    expect(repository.loadOrdersCalls, 2);
    expect(find.text('出荷予定'), findsOneWidget);
  });

  testWidgets('900px・文字200%でも出荷対象と重量入力を確認できる', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ShippingPage(
            repository: FakeShippingRepository(),
            initialOrderId: 'order-1',
            currentDate: DateTime(2026, 9, 13, 10),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('受注-2026-001'), findsWidgets);
    expect(find.text('出荷残量 7.50 kg'), findsOneWidget);
    expect(
      find.byKey(const Key('shipping-weight-container-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('shipping-confirm-input')));
  await tester.tap(find.byKey(const Key('shipping-confirm-input')));
  await tester.pumpAndSettle();
}

Widget _app(FakeShippingRepository repository) => MaterialApp(
  theme: buildAppTheme(),
  home: ShippingPage(
    repository: repository,
    initialOrderId: 'order-1',
    currentDate: DateTime(2026, 9, 13, 10),
  ),
);

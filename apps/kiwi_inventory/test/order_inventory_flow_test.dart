import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/orders/order_management_page.dart';
import 'package:kiwi_inventory/orders/order_management_repository.dart';

import 'support/fake_order_inventory_repository.dart';

void main() {
  for (final width in [900.0, 1280.0]) {
    testWidgets('$width px: 在庫選択から受注確定まで予約対象を保持する', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 950);
      addTearDown(tester.view.reset);
      final repo = FakeOrderInventoryRepository();
      final data = await repo.load(filter: OrderListFilter.active);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: OrderFormDialog(repository: repo, data: data),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-customer')), findsNothing);
      expect(find.textContaining('利用可能 1.00 kg'), findsNWidgets(2));
      expect(repo.registerOrderCalls, 0);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-stock-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-customer')), findsOneWidget);
      expect(repo.registerOrderCalls, 0);
      for (final invalid in ['NaN', '1e308', '1.001', '-1']) {
        await tester.enterText(
          find.byKey(const Key('order-stock-stock-1')),
          invalid,
        );
        await tester.tap(find.byKey(const Key('order-confirm-input')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('order-save')), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(
        find.byKey(const Key('order-stock-stock-1')),
        '1.00',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('order-notes')));
      await tester.enterText(find.byKey(const Key('order-notes')), '入力を保持');
      await tester.ensureVisible(find.text('在庫を再選択'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在庫を再選択'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-stock-next')));
      await tester.pumpAndSettle();
      expect(find.text('入力を保持'), findsOneWidget);
      await tester.tap(find.byKey(const Key('order-confirm-input')));
      await tester.pumpAndSettle();
      expect(find.text('受注・在庫予約を確定'), findsOneWidget);
      expect(repo.registerOrderCalls, 0);
      await tester.tap(find.byKey(const Key('order-save')));
      await tester.pumpAndSettle();
      expect(repo.registerOrderCalls, 1);
      expect(repo.lastOrderInput!.reservations!.single.containerId, 'stock-1');
      expect(repo.lastOrderInput!.reservations!.single.weightHundredths, 100);
      expect(repo.lastOrderInput!.notes, '入力を保持');
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';

import 'inventory_page_test.dart' show FakeInventoryRepository;
import 'support/fake_master_repository.dart';
import 'support/fake_order_management_repository.dart';
import 'support/fake_process_board_repository.dart';
import 'support/fake_ripening_plan_repository.dart';
import 'support/fake_shipping_repository.dart';

void main() {
  testWidgets('全管理画面のメニュー間をホーム経由せず移動し、ホームへ戻れる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var signOuts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ManagerHomePage(
          inventoryRepository: FakeInventoryRepository(),
          masterRepository: FakeMasterRepository(),
          orderManagementRepository: FakeOrderManagementRepository(),
          processBoardRepository: FakeProcessBoardRepository(),
          ripeningPlanRepository: FakeRipeningPlanRepository(),
          shippingRepository: FakeShippingRepository(),
          onSignOut: () => signOuts++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> select(String item) async {
      await tester.tap(
        find.descendant(
          of: find.byType(ManagerNavigation),
          matching: find.text(item),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ManagerNavigation>(find.byType(ManagerNavigation))
            .selectedItem,
        item,
      );
      expect(tester.takeException(), isNull);
    }

    for (final source in ManagerNavigation.items.where(
      (item) => item != 'ホーム',
    )) {
      await select(source);
      for (final target in ManagerNavigation.items.where(
        (item) => item != 'ホーム',
      )) {
        await select(target);
        await select(source);
      }
      await select('ホーム');
    }
    await select('工程ボード');
    await tester.tap(find.text('ログアウト'));
    await tester.pumpAndSettle();
    expect(signOuts, 1);
    expect(find.byType(ManagerHomePage), findsOneWidget);
  });
}

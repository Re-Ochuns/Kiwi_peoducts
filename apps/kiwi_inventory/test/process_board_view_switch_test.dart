import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/process_board/process_board_repository.dart';
import 'package:kiwi_inventory/process_board/process_board_inventory.dart';
import 'package:kiwi_inventory/ripening/ripening_plan_page.dart';

import 'support/fake_process_board_repository.dart';
import 'support/fake_ripening_plan_repository.dart';

void main() {
  testWidgets('inventory tab must close the planning form', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final items = [testProcessBoardData.items.first];
    final inventory = buildProcessBoardInventory(
      items: items,
      reservations: [],
      allocations: [],
      orders: {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ManagerProcessBoardPage(
          repository: FakeProcessBoardRepository(
            data: ProcessBoardData(items: items, inventoryItems: inventory),
          ),
          ripeningPlanRepository: FakeRipeningPlanRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONT-2026-0101'));
    await tester.pumpAndSettle();
    final open = find.widgetWithText(FilledButton, '追熟計画を入力');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byType(RipeningPlanPage), findsOneWidget);
    await tester.tap(find.text('在庫'));
    await tester.pumpAndSettle();
    expect(find.byType(RipeningPlanPage), findsNothing);
    expect(find.text('CONT-2026-0101'), findsNWidgets(3));
    expect(find.widgetWithText(FilledButton, '追熟計画を入力'), findsNothing);
    await tester.tap(find.text('一覧'));
    await tester.pumpAndSettle();
    expect(find.byType(RipeningPlanPage), findsNothing);
    expect(find.text('CONT-2026-0101'), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, '追熟計画を入力'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

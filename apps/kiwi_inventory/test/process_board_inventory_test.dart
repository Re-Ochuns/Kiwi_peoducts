import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/process_board/process_board_page.dart';

import 'support/fake_process_board_repository.dart';

void main() {
  testWidgets('switch inventory from manager navigation and return to board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final board = FakeProcessBoardRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ManagerHomePage(processBoardRepository: board),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('工程ボード').first);
    await tester.pumpAndSettle();
    expect(find.byType(ProcessBoardPage), findsOneWidget);
    expect(find.text('CONT-2026-0101'), findsOneWidget);
    expect(find.text('CONT-2026-0102'), findsOneWidget);
    expect(find.text('CONT-2026-0103'), findsOneWidget);
    expect(find.text('CONT-2026-0104'), findsOneWidget);
    // Select an order container; inventory filtering must also hide its panel.
    await tester.tap(find.text('CONT-2026-0102'));
    await tester.pumpAndSettle();
    final boardState = tester.state(find.byType(ProcessBoardPage));
    await tester.tap(find.text('在庫').first);
    await tester.pumpAndSettle();
    expect(find.byType(ProcessBoardPage), findsOneWidget);
    expect(find.text('CONT-2026-0101'), findsOneWidget);
    expect(find.text('CONT-2026-0103'), findsOneWidget);
    expect(find.text('CONT-2026-0102'), findsNothing);
    expect(find.text('CONT-2026-0104'), findsNothing);
    expect(find.text('20.50 kg'), findsNothing);
    expect(find.text('15.75 kg'), findsNothing);
    expect(find.text('0.00 kg'), findsNWidgets(3));
    await tester.tap(find.text('一覧').first);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ProcessBoardPage)), same(boardState));
    expect(find.text('CONT-2026-0102'), findsOneWidget);
    expect(find.text('CONT-2026-0104'), findsOneWidget);
    expect(board.loadCalls, 1);
    await tester.tap(find.text('在庫').first);
    await tester.pumpAndSettle();
    expect(find.text('CONT-2026-0102'), findsNothing);
    expect(find.text('CONT-2026-0104'), findsNothing);
    expect(board.loadCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disable view switching during board submission', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ManagerProcessBoardPage(repository: FakeProcessBoardRepository()),
      ),
    );
    await tester.pumpAndSettle();
    final board = tester.widget<ProcessBoardPage>(
      find.byType(ProcessBoardPage),
    );
    board.onBusyChanged!(true);
    await tester.pump();
    expect(
      tester
          .widget<SegmentedButton<bool>>(
            find.byKey(const Key('process-board-view-switch')),
          )
          .onSelectionChanged,
      isNull,
    );
    board.onBusyChanged!(false);
    await tester.pump();
    expect(
      tester
          .widget<SegmentedButton<bool>>(
            find.byKey(const Key('process-board-view-switch')),
          )
          .onSelectionChanged,
      isNotNull,
    );
  });
}

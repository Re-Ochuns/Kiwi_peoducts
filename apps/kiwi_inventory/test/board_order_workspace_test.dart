import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/board_order/board_order_repository.dart';
import 'package:kiwi_inventory/board_order/board_order_workspace.dart';
import 'package:kiwi_inventory/process_board/process_board_repository.dart';

import 'support/fake_process_board_repository.dart';

const options = BoardOrderOptions(
  varieties: [BoardOrderOption('v', 'Hayward')],
  grades: [BoardOrderOption('g', 'M')],
  customers: [
    BoardOrderOption('c', 'Customer A'),
    BoardOrderOption('b', 'Customer B'),
  ],
  locations: [BoardOrderOption('loc', 'Room A')],
  workers: [BoardOrderOption('w', 'Worker A')],
);
final candidate = BoardOrderCandidate(
  id: 'stock',
  kind: 'container',
  displayId: 'CANDIDATE-1',
  stage: ProcessStage.sorted,
  availableHundredths: 1000,
  start: DateTime(2027, 5, 22, 9),
  completion: DateTime(2027, 6, 1, 9),
  version: 'version1',
  containerIds: 'CANDIDATE-1',
  locationId: 'loc',
);

class FakeBoardOrders implements BoardOrderRepository {
  final keys = <String>[];
  Map<String, Object?>? input;
  List<BoardOrderCandidate> rows = [candidate];
  BoardOrderFailure? failure;
  Completer<BoardOrderResult>? pending;
  int searches = 0;
  @override
  Future<BoardOrderOptions> loadOptions() async => options;
  @override
  Future<List<BoardOrderOption>> destinations(String id) async => [
    BoardOrderOption('$id-d', 'Destination $id'),
  ];
  @override
  Future<List<BoardOrderCandidate>> candidates(
    BoardOrderCriteria criteria,
  ) async {
    searches++;
    return rows;
  }

  @override
  Future<BoardOrderResult> confirm(
    Map<String, Object?> value,
    String key,
  ) async {
    keys.add(key);
    input = value;
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    return const BoardOrderResult('ORDER-118', 'PLAN-118', false);
  }
}

Future<void> select(WidgetTester tester, String label, String option) async {
  final field = find.ancestor(
    of: find.text(label).last,
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> pump(
  WidgetTester tester,
  FakeBoardOrders repo, {
  double width = 1280,
  ValueChanged<bool>? busy,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Row(
          children: [
            const SizedBox(width: 224),
            Expanded(
              child: BoardOrderWorkspace(
                repository: repo,
                boardRepository: FakeProcessBoardRepository(),
                inventoryOnly: true,
                onBusyChanged: busy ?? (_) {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('board-order-date')),
    '2027-06-01',
  );
  await select(tester, '品種', 'Hayward');
  await select(tester, '等級', 'M');
  await tester.enterText(find.byKey(const Key('board-order-weight')), '2.50');
  await tester.tap(find.text('候補を表示'));
  await tester.pumpAndSettle();
}

Future<void> review(WidgetTester tester) async {
  await search(tester);
  await tester.tap(find.text('CANDIDATE-1'));
  await tester.pumpAndSettle();
  await select(tester, '顧客', 'Customer A');
  await select(tester, '配送先', 'Destination c');
  await select(tester, '担当作業者', 'Worker A');
  await tester.tap(find.text('確認へ'));
  await tester.pumpAndSettle();
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final width in [900.0, 1280.0]) {
    testWidgets('complete order flow at width $width', (tester) async {
      final repo = FakeBoardOrders();
      await pump(tester, repo, width: width);
      await review(tester);
      expect(repo.keys, isEmpty);
      await tester.tap(find.text('受注・計画を確定'));
      await tester.pumpAndSettle();
      expect(repo.input!['ordered_weight_kg'], 2.5);
      expect(repo.input!['shipping_destination_id'], 'c-d');
      expect(repo.input!['candidate_id'], 'stock');
      expect(find.text('受注番号：ORDER-118'), findsOneWidget);
      await tester.tap(find.text('工程ボードへ戻る'));
      await tester.pumpAndSettle();
      expect(repo.searches, 2);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'condition change discards candidates and clear restores inventory',
    (tester) async {
      await pump(tester, FakeBoardOrders());
      await search(tester);
      expect(find.text('CANDIDATE-1'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('board-order-weight')), '4');
      await tester.pumpAndSettle();
      expect(find.text('CANDIDATE-1'), findsNothing);
      expect(find.text('CONT-2026-0101'), findsOneWidget);
    },
  );
  testWidgets('no candidates and validation do not create orders', (
    tester,
  ) async {
    final repo = FakeBoardOrders()..rows = [];
    await pump(tester, repo);
    await tester.tap(find.text('候補を表示'));
    await tester.pumpAndSettle();
    expect(repo.searches, 0);
    await search(tester);
    expect(find.textContaining('条件に合う在庫はありません'), findsOneWidget);
    expect(repo.keys, isEmpty);
  });
  testWidgets('changing customer clears the previous destination', (
    tester,
  ) async {
    await pump(tester, FakeBoardOrders());
    await search(tester);
    await tester.tap(find.text('CANDIDATE-1'));
    await tester.pumpAndSettle();
    await select(tester, '顧客', 'Customer A');
    await select(tester, '配送先', 'Destination c');
    await select(tester, '顧客', 'Customer B');
    expect(find.text('Destination c'), findsNothing);
  });
  testWidgets('uncertain result retries the same operation key and input', (
    tester,
  ) async {
    final repo = FakeBoardOrders()
      ..failure = const BoardOrderFailure('unknown', uncertain: true);
    await pump(tester, repo);
    await review(tester);
    await tester.tap(find.text('受注・計画を確定'));
    await tester.pumpAndSettle();
    expect(find.text('入力に戻る'), findsNothing);
    expect(find.text('閉じる'), findsNothing);
    repo.failure = null;
    await tester.tap(find.text('同じ内容で再試行'));
    await tester.pumpAndSettle();
    expect(repo.keys, hasLength(2));
    expect(repo.keys.first, repo.keys.last);
  });
  testWidgets('submission blocks closing and duplicate taps', (tester) async {
    final repo = FakeBoardOrders()..pending = Completer<BoardOrderResult>();
    final busy = <bool>[];
    await pump(tester, repo, busy: busy.add);
    await review(tester);
    await tester.tap(find.text('受注・計画を確定'));
    await tester.pump();
    expect(busy.last, true);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '閉じる'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '登録中…'))
          .onPressed,
      isNull,
    );
    repo.pending!.complete(const BoardOrderResult('ORDER', 'PLAN', false));
    await tester.pumpAndSettle();
    expect(busy.last, false);
  });
  testWidgets('conflict re-search preserves customer and destination', (
    tester,
  ) async {
    final repo = FakeBoardOrders()
      ..failure = const BoardOrderFailure(
        '在庫が変更されました',
        code: 'INVENTORY_UNAVAILABLE',
      );
    await pump(tester, repo);
    await review(tester);
    await tester.tap(find.text('受注・計画を確定'));
    await tester.pumpAndSettle();
    expect(find.text('候補を再検索'), findsOneWidget);
    await tester.tap(find.text('候補を再検索'));
    await tester.pumpAndSettle();
    expect(repo.searches, 2);
    await tester.tap(find.text('CANDIDATE-1'));
    await tester.pumpAndSettle();
    expect(find.text('Customer A'), findsOneWidget);
    expect(find.text('Destination c'), findsOneWidget);
    expect(find.text('Worker A'), findsOneWidget);
  });

  testWidgets('existing lot keeps its location and worker', (tester) async {
    final repo = FakeBoardOrders()
      ..rows = [
        BoardOrderCandidate(
          id: candidate.id,
          kind: 'lot',
          displayId: candidate.displayId,
          stage: ProcessStage.resting,
          availableHundredths: candidate.availableHundredths,
          start: candidate.start,
          completion: candidate.completion,
          version: candidate.version,
          containerIds: 'CONT-A、CONT-B',
        ),
      ];
    await pump(tester, repo);
    await search(tester);
    await tester.tap(find.text('CANDIDATE-1'));
    await tester.pumpAndSettle();
    await select(tester, '顧客', 'Customer A');
    await select(tester, '配送先', 'Destination c');
    expect(find.text('担当作業者'), findsNothing);
    expect(find.text('保管場所'), findsNothing);
    await tester.tap(find.text('確認へ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('受注・計画を確定'));
    await tester.pumpAndSettle();
    expect(repo.input!['candidate_kind'], 'lot');
    expect(repo.input!.containsKey('assigned_worker_id'), isFalse);
    expect(repo.input!.containsKey('storage_location_id'), isFalse);
  });
}

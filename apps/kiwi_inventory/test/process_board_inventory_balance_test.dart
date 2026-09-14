import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/process_board/process_board_inventory.dart';
import 'package:kiwi_inventory/process_board/process_board_repository.dart';

import 'support/fake_process_board_repository.dart';

ProcessBoardItem container(
  String id,
  int weight, {
  ProcessStage stage = ProcessStage.shippable,
}) => ProcessBoardItem(
  id: id,
  displayId: id,
  stage: stage,
  useType: ProcessUseType.mixed,
  variety: 'Kiwi',
  grade: 'M',
  weightHundredths: weight,
  status: stage == ProcessStage.sorted || stage == ProcessStage.waiting
      ? 'cold_storage'
      : 'shippable',
  location: 'A',
  needsReview: false,
  orderIds: const ['order'],
  orderNumbers: const ['ORDER-1'],
  ripeningLotId: 'lot',
  ripeningDisplayId: 'LOT-1',
);

List<ProcessBoardItem> inventory({
  List<ProcessBoardItem>? items,
  List<Map<String, dynamic>> reservations = const [],
  String orderStatus = 'partially_shipped',
  List<Map<String, dynamic>> shipments = const [],
  double allocated = 6,
}) => buildProcessBoardInventory(
  items: items ?? [container('CONT-1', 600), container('CONT-2', 400)],
  reservations: reservations,
  allocations: [
    {
      'ripening_lot_id': 'lot',
      'allocation_type': 'order',
      'order_id': 'order',
      'allocated_weight_kg': allocated,
    },
  ],
  orders: {
    'order': {'status': orderStatus, 'shipments': shipments},
  },
);

Map<String, dynamic> shipment(
  double weight, {
  String status = 'confirmed',
  String lot = 'lot',
}) => {
  'status': status,
  'shipment_lines': [
    {
      'shipped_weight_kg': weight,
      'container': {'ripening_lot_id': lot},
    },
  ],
};

void main() {
  test('mixed lot is shown once without assigning balance to containers', () {
    final rows = inventory();
    expect(rows, hasLength(1));
    expect(rows.single.displayId, 'LOT-1');
    expect(rows.single.weightHundredths, 400);
    expect(rows.single.inventoryBalance!.totalHundredths, 1000);
    expect(rows.single.inventoryBalance!.orderHundredths, 600);
    expect(rows.single.inventoryBalance!.containerDisplayIds, [
      'CONT-1',
      'CONT-2',
    ]);
  });

  test(
    'confirmed shipments reduce allocation; cancelled and other lots do not',
    () {
      final rows = inventory(
        items: [container('CONT-1', 400), container('CONT-2', 400)],
        shipments: [
          shipment(2),
          shipment(1, status: 'cancelled'),
          shipment(3, lot: 'other'),
        ],
      );
      expect(rows.single.weightHundredths, 400);
      expect(rows.single.inventoryBalance!.orderHundredths, 400);
    },
  );

  for (final status in ['cancelled', 'shipped']) {
    test('$status order does not reserve stock', () {
      expect(inventory(orderStatus: status).single.weightHundredths, 1000);
    });
  }

  test(
    'zero or insufficient remaining weight does not produce negative stock',
    () {
      expect(inventory(allocated: 10), isEmpty);
      expect(inventory(allocated: 12), isEmpty);
      expect(
        inventory(shipments: [shipment(20)]).single.weightHundredths,
        1000,
      );
    },
  );

  test(
    'cold source keeps unassigned remainder and aggregates planned lot once',
    () {
      final rows = inventory(
        items: [
          container('CONT-1', 1000, stage: ProcessStage.waiting),
          container('CONT-2', 1000, stage: ProcessStage.waiting),
        ],
        reservations: [
          {
            'container_id': 'CONT-1',
            'ripening_lot_id': 'lot',
            'reserved_weight_kg': 5,
          },
          {
            'container_id': 'CONT-2',
            'ripening_lot_id': 'lot',
            'reserved_weight_kg': 5,
          },
        ],
      );
      expect(rows, hasLength(3));
      expect(
        rows.where((item) => item.stage == ProcessStage.sorted),
        hasLength(2),
      );
      expect(
        rows.where((item) => item.stage == ProcessStage.waiting),
        hasLength(1),
      );
      expect(
        rows
            .where((item) => item.inventoryBalance!.isLot)
            .single
            .weightHundredths,
        400,
      );
      expect(
        rows.fold<int>(0, (sum, item) => sum + item.weightHundredths),
        1400,
      );
    },
  );

  test(
    'missing allocation weight never exposes the whole mixed lot as free',
    () {
      expect(
        buildProcessBoardInventory(
          items: [container('CONT-1', 1000)],
          reservations: const [],
          allocations: [
            {
              'ripening_lot_id': 'lot',
              'allocation_type': 'order',
              'order_id': 'order',
            },
          ],
          orders: {
            'order': {'status': 'confirmed'},
          },
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'inventory card, total and detail show lot balance and return to full list',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final items = [container('CONT-1', 600), container('CONT-2', 400)];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ManagerProcessBoardPage(
            repository: FakeProcessBoardRepository(
              data: ProcessBoardData(items: items, inventoryItems: inventory()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('在庫'));
      await tester.pumpAndSettle();
      expect(find.text('LOT-1'), findsOneWidget);
      expect(find.text('CONT-1'), findsNothing);
      expect(find.text('CONT-2'), findsNothing);
      expect(find.text('4.00 kg'), findsNWidgets(2));
      await tester.tap(find.text('LOT-1'));
      await tester.pumpAndSettle();
      expect(find.text('10.00 kg'), findsOneWidget);
      expect(find.text('6.00 kg'), findsOneWidget);
      expect(find.text('CONT-1、CONT-2'), findsOneWidget);
      expect(find.text('4.00 kg'), findsNWidgets(3));
      await tester.tap(find.text('一覧'));
      await tester.pumpAndSettle();
      expect(find.text('CONT-1'), findsOneWidget);
      expect(find.text('CONT-2'), findsOneWidget);
      expect(find.text('LOT-1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

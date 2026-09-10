import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/sorting/sorting_repository.dart';
import 'package:kiwi_inventory/sorting/supabase_sorting_repository.dart';

void main() {
  test('重量を0.01kg単位へ正確に変換する', () {
    expect(parseWeightHundredths('10'), 1000);
    expect(parseWeightHundredths('10.2'), 1020);
    expect(parseWeightHundredths('10.25'), 1025);
    expect(parseWeightHundredths('10.256'), isNull);
    expect(parseWeightHundredths('-1'), isNull);
    expect(parseWeightHundredths('abc'), isNull);
  });

  test('選果要求を契約どおりの入力へ変換する', () {
    const input = SortingInput(
      receivingLotId: 'lot-id',
      sortingDate: '2026-09-10',
      workerId: 'worker-id',
      expectedLotVersion: 3,
      containers: [
        SortingContainerInput(gradeId: 'grade-m', weightHundredths: 1025),
      ],
    );

    expect(input.toRpcInput(), {
      'receiving_lot_id': 'lot-id',
      'sorting_date': '2026-09-10',
      'worker_id': 'worker-id',
      'expected_lot_version': 3,
      'containers': [
        {'grade_id': 'grade-m', 'weight_kg': 10.25},
      ],
    });
  });

  test('冪等性キーはUUID v4とRFC 4122 variantを満たす', () {
    final key = createSortingIdempotencyKey();
    expect(
      key,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('選果対象はID・品種・産地で検索できる', () {
    final lot = testSortingLot;
    expect(lot.matches('受入-2026'), isTrue);
    expect(lot.matches('ヘイワード'), isTrue);
    expect(lot.matches('第一圃場'), isTrue);
    expect(lot.matches('香緑'), isFalse);
  });
}

final testSortingLot = SortingLot(
  id: 'lot-id',
  displayId: '受入-2026-001',
  sourceType: 'harvest',
  receivedOn: DateTime(2026, 9, 1),
  originName: '第一圃場 A区画',
  varietyName: 'ヘイワード',
  totalWeightHundredths: 1000,
  sortingDueOn: DateTime(2026, 9, 9),
  version: 2,
);

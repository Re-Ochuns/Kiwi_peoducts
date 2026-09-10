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
    expect(parseWeightHundredths('9999999999.99'), maxWeightHundredths);
    expect(parseWeightHundredths('10000000000'), isNull);
    expect(parseWeightHundredths('999999999999999999999999999999'), isNull);
  });

  test('PostgRESTの認証エラーを再送不可へ正規化する', () {
    for (final code in ['401', 'PGRST301', 'PGRST302', 'PGRST303']) {
      final failure = sortingFailureForPostgrestCode(code);
      expect(failure.code, 'AUTH_REQUIRED');
      expect(failure.retryable, isFalse);
    }

    for (final code in ['403', '42501']) {
      final failure = sortingFailureForPostgrestCode(code);
      expect(failure.code, 'AUTH_FORBIDDEN');
      expect(failure.retryable, isFalse);
    }
  });

  test('PostgRESTの契約・サーバーエラーを契約どおり正規化する', () {
    final contractFailure = sortingFailureForPostgrestCode('PGRST202');
    expect(contractFailure.code, 'CONTRACT_MISMATCH');
    expect(contractFailure.retryable, isFalse);

    final serverFailure = sortingFailureForPostgrestCode('503');
    expect(serverFailure.code, 'SERVER_UNAVAILABLE');
    expect(serverFailure.retryable, isTrue);
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

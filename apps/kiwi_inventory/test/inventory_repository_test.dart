import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/inventory/inventory_repository.dart';
import 'package:kiwi_inventory/inventory/supabase_inventory_repository.dart';

void main() {
  test('現在量から予約量を引いて利用可能量を求める', () {
    final item = InventoryItem(
      id: '1',
      displayId: '在庫-1',
      varietyName: 'ヘイワード',
      gradeCode: 'M',
      originalWeightHundredths: 1000,
      currentWeightHundredths: 925,
      reservedWeightHundredths: 200,
      status: InventoryStatus.coldStorage,
      locationCode: null,
      locationName: null,
      updatedAt: DateTime(2026),
    );

    expect(item.availableWeightHundredths, 725);
    expect(formatInventoryWeight(item.availableWeightHundredths), '7.25');
    expect(item.locationLabel, '未設定');
  });

  test('DBの状態値を日本語表示へ変換する', () {
    expect(
      InventoryStatus.fromValue('awaiting_ripeness_check').label,
      '追熟確認待ち',
    );
  });

  test('権限エラーは再試行不可として扱う', () {
    final failure = inventoryFailureForPostgrestCode('42501');

    expect(failure.code, 'AUTH_FORBIDDEN');
    expect(failure.retryable, isFalse);
    expect(failure.isPermissionDenied, isTrue);
  });
}

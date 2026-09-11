import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/master/master_repository.dart';
import 'package:kiwi_inventory/master/supabase_master_repository.dart';

void main() {
  test('段階1の9マスターをRPC値とテーブルに対応付ける', () {
    expect(MasterType.values, hasLength(9));
    expect(MasterType.variety.rpcValue, 'variety');
    expect(MasterType.orchardPlot.rpcValue, 'orchard_plot');
    expect(MasterType.storageLocation.tableName, 'storage_locations');
    expect(MasterType.sortingDeadlineRule.tableName, 'sorting_deadline_rules');
    expect(MasterType.grade.canRegister, isFalse);
  });

  test('冪等性キーはUUID v4とRFC 4122 variantを満たす', () {
    final key = createMasterIdempotencyKey();
    expect(
      key,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('親マスターの表示名を解決する', () {
    final variety = MasterRecord(
      type: MasterType.variety,
      id: 'variety-1',
      values: const {'code': 'hayward', 'name': 'ヘイワード'},
      isActive: true,
      version: 1,
      updatedAt: null,
    );
    final catalog = MasterCatalog(
      records: {
        MasterType.variety: [variety],
      },
      canManage: true,
    );

    expect(
      catalog.relatedLabel(MasterType.variety, 'variety-1'),
      'hayward　ヘイワード',
    );
  });
}

import 'package:kiwi_inventory/orders/order_management_repository.dart';

import 'fake_order_management_repository.dart';

class FakeOrderInventoryRepository extends FakeOrderManagementRepository
    implements OrderInventoryRepository {
  int inventoryCalls = 0;
  @override
  Future<List<OrderStock>> loadInventory({
    String search = '',
    String? varietyId,
    String? gradeId,
    int offset = 0,
    String? orderId,
  }) async {
    inventoryCalls++;
    return [
      for (final id in ['stock-1', 'stock-2'])
        OrderStock(
          id: id,
          displayId: id,
          varietyId: 'variety-1',
          gradeId: 'grade-1',
          varietyLabel: 'ヘイワード',
          gradeLabel: 'L',
          current: 200,
          reserved: 100,
          available: 100,
          origin: '農園',
          sortedOn: '2026-09-14',
          location: '冷蔵庫',
        ),
    ];
  }
}

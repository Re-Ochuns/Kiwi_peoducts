import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/receiving/receiving_repository.dart';
import 'package:kiwi_inventory/receiving/supabase_receiving_repository.dart';

void main() {
  test('操作キーはvariantを含むUUID v4で生成する', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    expect(pattern.hasMatch(createIdempotencyKey()), isTrue);
  });

  test('収穫要求に仕入れ固有項目を含めない', () {
    const input = ReceivingInput(
      sourceType: ReceivingSourceType.harvest,
      receivedDate: '2028-05-01',
      orchardId: 'orchard-1',
      plotId: 'plot-1',
      treeId: 'tree-1',
      originName: '第一農園 A区画',
      varietyId: 'variety-1',
      totalWeightKg: 25.5,
      containerCount: 2,
      workerId: 'worker-1',
    );

    final request = input.toRpcInput();
    expect(request['source_type'], 'harvest');
    expect(request['tree_id'], 'tree-1');
    expect(request.containsKey('supplier_id'), isFalse);
    expect(request.containsKey('supplier_reference'), isFalse);
  });

  test('仕入れ要求に収穫固有項目を含めない', () {
    const input = ReceivingInput(
      sourceType: ReceivingSourceType.purchase,
      receivedDate: '2028-05-01',
      supplierId: 'supplier-1',
      supplierReference: ' PO-001 ',
      originName: ' 香川県 ',
      varietyId: 'variety-1',
      totalWeightKg: 18.4,
      containerCount: 1,
      workerId: 'worker-1',
    );

    final request = input.toRpcInput();
    expect(request['source_type'], 'purchase');
    expect(request['supplier_reference'], 'PO-001');
    expect(request['origin_name'], '香川県');
    expect(request.containsKey('orchard_id'), isFalse);
    expect(request.containsKey('plot_id'), isFalse);
    expect(request.containsKey('tree_id'), isFalse);
  });
}

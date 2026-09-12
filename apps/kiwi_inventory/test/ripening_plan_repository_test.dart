import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/ripening/ripening_plan_repository.dart';
import 'package:kiwi_inventory/ripening/supabase_ripening_plan_repository.dart';

void main() {
  test('追熟計画をRPC契約どおりの入力へ変換する', () {
    final input = _input();

    expect(input.toRpcInput(), {
      'variety_id': 'variety-1',
      'grade_id': 'grade-m',
      'total_weight_kg': 10.0,
      'storage_location_id': 'location-1',
      'planned_ethylene_at': '2026-09-12T01:00:00.000Z',
      'planned_completion_at': '2026-09-19T01:00:00.000Z',
      'assigned_worker_id': 'worker-1',
      'notes': null,
      'allocations': [
        {
          'allocation_type': 'order',
          'order_id': 'order-1',
          'allocated_weight_kg': 6.0,
        },
        {
          'allocation_type': 'reserve',
          'order_id': null,
          'allocated_weight_kg': 4.0,
        },
      ],
      'reservations': [
        {'container_id': 'container-1', 'reserved_weight_kg': 10.0},
      ],
    });
  });

  test('同じ入力の署名は安定し、冪等性キーはUUID v4である', () {
    expect(_input().signature, _input().signature);
    expect(
      createRipeningIdempotencyKey(),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
}

RipeningPlanInput _input() => RipeningPlanInput(
  inventory: const RipeningInventoryOption(
    id: 'container-1',
    displayId: '在庫-1',
    varietyId: 'variety-1',
    varietyLabel: 'ヘイワード',
    gradeId: 'grade-m',
    gradeLabel: 'M',
    availableWeightHundredths: 1000,
  ),
  totalWeightHundredths: 1000,
  locationId: 'location-1',
  plannedEthyleneAt: DateTime.utc(2026, 9, 12, 1),
  plannedCompletionAt: DateTime.utc(2026, 9, 19, 1),
  workerId: 'worker-1',
  allocations: const [
    RipeningAllocationInput(
      type: RipeningAllocationType.order,
      orderId: 'order-1',
      weightHundredths: 600,
    ),
    RipeningAllocationInput(
      type: RipeningAllocationType.reserve,
      weightHundredths: 400,
    ),
  ],
);

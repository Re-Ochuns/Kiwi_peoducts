import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_inventory/process_board/process_board_repository.dart';
import 'package:kiwi_inventory/process_board/supabase_process_board_repository.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('コンテナ・追熟計画・割当・ToDoを4工程の表示項目へ統合する', () async {
    final client = _client((request) {
      final path = request.url.path;
      if (path.endsWith('/containers')) {
        return _json([
          _container(
            id: 'container-cold',
            displayId: 'CONT-1',
            status: 'cold_storage',
            weight: 8.25,
            ripeningLotId: null,
          ),
          _container(
            id: 'container-ripening',
            displayId: 'CONT-2',
            status: 'ethylene_processing',
            weight: 6.5,
            ripeningLotId: 'lot-2',
          ),
          _container(
            id: 'container-resting',
            displayId: 'CONT-3',
            status: 'awaiting_ripeness_check',
            weight: 5,
            ripeningLotId: 'lot-3',
          ),
          _container(
            id: 'container-shippable',
            displayId: 'CONT-4',
            status: 'shippable',
            weight: 4.75,
            ripeningLotId: 'lot-4',
          ),
        ], request);
      }
      if (path.endsWith('/rpc/shipment_inventory_list')) {
        return _json([
          {'id': 'container-shippable', 'remaining_use_type': 'mixed'},
        ], request);
      }
      if (path.endsWith('/rpc/shipment_container_list')) {
        return _json([
          {'id': 'container-shippable', 'available_weight_kg': 4.75},
        ], request);
      }
      if (path.endsWith('/inventory_reservations')) {
        return _json(const [], request);
      }
      if (path.endsWith('/ripening_lots')) {
        return _json([
          {
            'id': 'lot-2',
            'display_id': 'RIP-2',
            'use_type': 'order',
            'planned_completion_at': '2026-09-18T01:00:00Z',
            'calculated_removal_at': '2026-09-17T01:00:00Z',
            'calculated_rest_end_at': null,
          },
          {
            'id': 'lot-3',
            'display_id': 'RIP-3',
            'use_type': 'reserve',
            'planned_completion_at': '2026-09-19T01:00:00Z',
            'calculated_removal_at': '2026-09-18T01:00:00Z',
            'calculated_rest_end_at': '2026-09-19T01:00:00Z',
          },
          {
            'id': 'lot-4',
            'display_id': 'RIP-4',
            'use_type': 'order',
            'planned_completion_at': '2026-09-20T01:00:00Z',
            'calculated_removal_at': '2026-09-19T01:00:00Z',
            'calculated_rest_end_at': '2026-09-20T01:00:00Z',
          },
        ], request);
      }
      if (path.endsWith('/ripening_allocations')) {
        return _json([
          {
            'ripening_lot_id': 'lot-2',
            'allocation_type': 'order',
            'order_id': 'order-1',
          },
          {
            'ripening_lot_id': 'lot-4',
            'allocation_type': 'order',
            'order_id': 'order-2',
          },
        ], request);
      }
      if (path.endsWith('/work_tasks')) {
        return _json([
          {
            'id': 'task-2',
            'task_type': 'ethylene_removal_check',
            'ripening_lot_id': 'lot-2',
            'scheduled_at': '2026-09-17T01:00:00Z',
            'due_at': '2026-09-17T02:00:00Z',
            'status': 'pending',
            'target_url': '/work-tasks/task-2',
            'assigned_worker_id': null,
            'schedule_warning': null,
            'calendar_sync_status': 'synced',
            'calendar_sync_error': null,
          },
        ], request);
      }
      if (path.endsWith('/orders')) {
        return _json([
          {
            'id': 'order-1',
            'order_number': 'ORD-1',
            'scheduled_ship_on': '2026-09-21',
            'status': 'confirmed',
          },
          {
            'id': 'order-2',
            'order_number': 'ORD-2',
            'scheduled_ship_on': '2026-09-20',
            'status': 'confirmed',
          },
        ], request);
      }
      throw StateError('unexpected request: $path');
    });

    final data = await SupabaseProcessBoardRepository(client).load();

    expect(data.itemsFor(ProcessStage.sorted).single.displayId, 'CONT-1');
    expect(
      data.itemsFor(ProcessStage.sorted).single.date,
      DateTime(2026, 10, 14),
    );
    expect(data.weightFor(ProcessStage.ripening), 650);
    expect(
      data.itemsFor(ProcessStage.ripening).single.nextTask?.type,
      WorkTaskType.ethyleneRemovalCheck,
    );
    expect(
      data.itemsFor(ProcessStage.resting).single.useType,
      ProcessUseType.reserve,
    );
    final shippable = data.itemsFor(ProcessStage.shippable).single;
    expect(shippable.useType, ProcessUseType.mixed);
    expect(shippable.orderNumbers, ['ORD-2']);
    expect(shippable.date, DateTime(2026, 9, 20));
    await client.dispose();
  });

  test('同じ冷蔵コンテナの複数予約を保持し件数と重量を重複させない', () async {
    final client = _scenarioClient(
      status: 'cold_storage',
      reservations: [
        {'container_id': 'container', 'ripening_lot_id': 'lot-2'},
        {'container_id': 'container', 'ripening_lot_id': 'lot-1'},
      ],
      lots: [
        {'id': 'lot-1', 'display_id': 'RIP-1', 'use_type': 'reserve'},
        {'id': 'lot-2', 'display_id': 'RIP-2', 'use_type': 'order'},
      ],
      allocations: [
        {
          'ripening_lot_id': 'lot-2',
          'allocation_type': 'order',
          'order_id': 'order-1',
        },
      ],
      orders: [
        {
          'id': 'order-1',
          'order_number': 'ORD-1',
          'status': 'confirmed',
          'scheduled_ship_on': '2026-09-20',
        },
      ],
      tasks: [
        for (final id in ['lot-1', 'lot-2'])
          {
            'id': 'task-$id',
            'task_type': 'ethylene_injection',
            'ripening_lot_id': id,
            'scheduled_at': '2026-09-17T01:00:00Z',
            'due_at': '2026-09-17T02:00:00Z',
            'status': 'pending',
            'target_url': '/work-tasks/task-$id',
          },
      ],
    );
    addTearDown(client.dispose);
    final data = await SupabaseProcessBoardRepository(client).load();
    final item = data.items.single;
    expect(data.weightFor(ProcessStage.sorted), 1000);
    expect(item.useType, ProcessUseType.mixed);
    expect(item.plans.map((plan) => plan.id), ['lot-1', 'lot-2']);
    expect(item.orderNumbers, ['ORD-1']);
    expect(item.forPlan('lot-1').useType, ProcessUseType.reserve);
    expect(item.forPlan('lot-2').nextTask?.targetId, 'lot-2');
    expect(item.forPlan('lot-1').nextTask?.targetId, 'lot-1');
  });

  test('出荷済み受注と割当残量ゼロを除き出荷可能受注の日付を表示する', () async {
    final requested = <String>[];
    final client = _scenarioClient(
      status: 'shippable',
      lots: [
        {'id': 'lot-1', 'display_id': 'RIP-1', 'use_type': 'mixed'},
      ],
      allocations: [
        for (final id in ['done', 'cancelled', 'exhausted', 'active'])
          {
            'ripening_lot_id': 'lot-1',
            'allocation_type': 'order',
            'order_id': id,
          },
      ],
      orders: [
        for (final entry in {
          'done': 'shipped',
          'cancelled': 'cancelled',
          'exhausted': 'partially_shipped',
          'active': 'in_progress',
        }.entries)
          {
            'id': entry.key,
            'order_number': entry.key,
            'status': entry.value,
            'scheduled_ship_on': entry.key == 'active'
                ? '2026-09-23'
                : '2026-09-20',
          },
      ],
      candidates: (id) {
        requested.add(id);
        return [
          {'id': 'container', 'available_weight_kg': id == 'active' ? 2 : 0},
        ];
      },
    );
    addTearDown(client.dispose);
    final item = (await SupabaseProcessBoardRepository(
      client,
    ).load()).items.single;
    expect(requested, unorderedEquals(['exhausted', 'active']));
    expect(item.orderIds, ['active']);
    expect(item.date, DateTime(2026, 9, 23));
  });

  test('出荷候補がなくなった予備在庫は受注を持たず期限を表示する', () async {
    final client = _scenarioClient(
      status: 'shippable',
      lots: [
        {'id': 'lot-1', 'display_id': 'RIP-1', 'use_type': 'mixed'},
      ],
      allocations: [
        {
          'ripening_lot_id': 'lot-1',
          'allocation_type': 'order',
          'order_id': 'done',
        },
      ],
      orders: [
        {
          'id': 'done',
          'order_number': 'ORD-done',
          'status': 'shipped',
          'scheduled_ship_on': '2026-09-20',
        },
      ],
    );
    addTearDown(client.dispose);
    final item = (await SupabaseProcessBoardRepository(
      client,
    ).load()).items.single;
    expect(item.orderIds, isEmpty);
    expect(item.date, DateTime(2026, 9, 25));
  });

  test('権限エラーを再試行なしの画面用エラーへ変換する', () async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode({
          'code': '42501',
          'message': 'permission denied',
          'details': null,
          'hint': null,
        }),
        403,
        request: request,
        headers: {'content-type': 'application/json'},
      ),
    );

    await expectLater(
      SupabaseProcessBoardRepository(client).load(),
      throwsA(
        isA<ProcessBoardFailure>()
            .having((failure) => failure.code, 'code', 'AUTH_FORBIDDEN')
            .having((failure) => failure.retryable, 'retryable', isFalse),
      ),
    );
    await client.dispose();
  });
}

Map<String, Object?> _container({
  required String id,
  required String displayId,
  required String status,
  required double weight,
  required String? ripeningLotId,
}) => {
  'id': id,
  'display_id': displayId,
  'current_weight_kg': weight,
  'status': status,
  'needs_review': false,
  'ripening_lot_id': ripeningLotId,
  'shippable_from': '2026-09-20',
  'shippable_until': '2026-09-25',
  'sorting_result': {'sorted_on': '2026-09-14'},
  'variety': {'name': 'ヘイワード'},
  'grade': {'code': 'M'},
  'location': {'code': 'cold-01', 'name': '第一冷蔵庫'},
};

SupabaseClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => SupabaseClient(
  'https://example.test',
  'test',
  httpClient: MockClient(handler),
);

Future<http.Response> _json(Object body, http.Request request) async =>
    http.Response(
      jsonEncode(body),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );

SupabaseClient _scenarioClient({
  required String status,
  List<Map<String, Object?>> reservations = const [],
  List<Map<String, Object?>> lots = const [],
  List<Map<String, Object?>> allocations = const [],
  List<Map<String, Object?>> orders = const [],
  List<Map<String, Object?>> tasks = const [],
  List<Map<String, Object?>> Function(String)? candidates,
}) => _client((request) {
  final path = request.url.path;
  if (path.endsWith('/containers')) {
    return _json([
      _container(
        id: 'container',
        displayId: 'CONT-1',
        status: status,
        weight: 10,
        ripeningLotId: status == 'cold_storage' ? null : 'lot-1',
      ),
    ], request);
  }
  if (path.endsWith('/rpc/shipment_inventory_list')) {
    return _json([
      {'id': 'container', 'remaining_use_type': 'reserve'},
    ], request);
  }
  if (path.endsWith('/rpc/shipment_container_list')) {
    final id = (jsonDecode(request.body) as Map)['order_id_value'] as String;
    return _json(candidates?.call(id) ?? [], request);
  }
  if (path.endsWith('/inventory_reservations')) {
    return _json(reservations, request);
  }
  if (path.endsWith('/ripening_lots')) {
    // Model PostgREST's IN filter so a dropped reservation also drops its lot.
    final filter = request.url.queryParameters['id'] ?? '';
    return _json(
      lots.where((lot) => filter.contains(lot['id'] as String)).toList(),
      request,
    );
  }
  if (path.endsWith('/ripening_allocations')) {
    return _json(allocations, request);
  }
  if (path.endsWith('/orders')) return _json(orders, request);
  if (path.endsWith('/work_tasks')) return _json(tasks, request);
  throw StateError('unexpected request: $path');
});

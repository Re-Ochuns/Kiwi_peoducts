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

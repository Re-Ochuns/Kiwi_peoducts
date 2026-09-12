import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_inventory/ripening/ripening_plan_repository.dart';
import 'package:kiwi_inventory/ripening/supabase_ripening_plan_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('冷蔵在庫・未割当受注・有効マスターを選択肢へ変換する', () async {
    final client = _client((request) {
      final path = request.url.path;
      if (path.endsWith('/rpc/ripening_inventory_available')) {
        return _json([
          {
            'container_id': 'container-1',
            'display_id': '在庫-1',
            'variety_id': 'variety-1',
            'grade_id': 'grade-m',
            'available_weight_kg': 8.25,
          },
          {
            'container_id': 'container-empty',
            'display_id': '在庫-2',
            'variety_id': 'variety-1',
            'grade_id': 'grade-m',
            'available_weight_kg': 0,
          },
        ], request);
      }
      if (path.endsWith('/rpc/order_list')) {
        return _json([
          {
            'order_id': 'order-1',
            'order_number': 'ORD-1',
            'customer_name': '青果店A',
            'customer_nickname': '',
            'variety_id': 'variety-1',
            'grade_id': 'grade-m',
            'shortage_weight_kg': 6.5,
            'status': 'confirmed',
            'scheduled_ship_on': '2026-09-20',
          },
          {
            'order_id': 'order-draft',
            'order_number': 'ORD-2',
            'customer_name': '青果店B',
            'customer_nickname': null,
            'variety_id': 'variety-1',
            'grade_id': 'grade-m',
            'shortage_weight_kg': 5,
            'status': 'draft',
            'scheduled_ship_on': '2026-09-21',
          },
        ], request);
      }
      if (path.endsWith('/varieties')) {
        return _json([
          {'id': 'variety-1', 'code': 'hayward', 'name': 'ヘイワード'},
        ], request);
      }
      if (path.endsWith('/grades')) {
        return _json([
          {'id': 'grade-m', 'code': 'M'},
        ], request);
      }
      if (path.endsWith('/storage_locations')) {
        return _json([
          {'id': 'location-1', 'code': 'ripening-01', 'name': '第1追熟庫'},
        ], request);
      }
      if (path.endsWith('/workers')) {
        return _json([
          {'id': 'worker-1', 'code': 'W01', 'display_name': '岡本'},
        ], request);
      }
      throw StateError('unexpected request: $path');
    });

    final options = await SupabaseRipeningPlanRepository(client).loadOptions();

    expect(options.inventories, hasLength(1));
    expect(options.inventories.single.availableWeightHundredths, 825);
    expect(options.inventories.single.varietyLabel, 'hayward　ヘイワード');
    expect(options.orders, hasLength(1));
    expect(options.orders.single.availableWeightHundredths, 650);
    expect(options.locations.single.label, 'ripening-01　第1追熟庫');
    expect(options.workers.single.label, 'W01　岡本');
    await client.dispose();
  });

  test('登録要求を共通封筒で送り成功応答を変換する', () async {
    Map<String, dynamic>? requestBody;
    final client = _client((request) {
      expect(request.url.path, endsWith('/rpc/ripening_plan_register'));
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'ok': true,
        'correlation_id': 'correlation-1',
        'idempotent_replay': false,
        'data': {
          'id': 'ripening-lot-1',
          'display_id': '追熟-2026-001',
          'status': 'draft',
          'version': 1,
          'planned_ethylene_at': '2026-09-12T01:00:00Z',
          'planned_completion_at': '2026-09-19T01:00:00Z',
        },
      }, request);
    });

    final result = await SupabaseRipeningPlanRepository(client).register(
      input: _input(),
      idempotencyKey: '00000000-0000-4000-8000-000000000001',
    );

    final request = requestBody!['req'] as Map<String, dynamic>;
    final meta = request['meta'] as Map<String, dynamic>;
    expect(meta['idempotency_key'], '00000000-0000-4000-8000-000000000001');
    expect(meta['correlation_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect((request['input'] as Map<String, dynamic>)['total_weight_kg'], 10);
    expect(result.displayId, '追熟-2026-001');
    expect(result.version, 1);
    await client.dispose();
  });

  test('業務エラーの詳細と問い合わせ番号を画面用エラーへ保持する', () async {
    final client = _client(
      (request) => _json({
        'ok': false,
        'correlation_id': 'correlation-1',
        'error': {
          'code': 'INVENTORY_UNAVAILABLE',
          'message': '在庫を再確認してください。',
          'retryable': false,
          'details': {'field': 'reservations', 'reason': 'overbooked'},
        },
      }, request),
    );

    await expectLater(
      SupabaseRipeningPlanRepository(client).register(
        input: _input(),
        idempotencyKey: '00000000-0000-4000-8000-000000000001',
      ),
      throwsA(
        isA<RipeningPlanFailure>()
            .having((value) => value.code, 'code', 'INVENTORY_UNAVAILABLE')
            .having((value) => value.field, 'field', 'reservations')
            .having((value) => value.reason, 'reason', 'overbooked')
            .having(
              (value) => value.correlationId,
              'correlationId',
              'correlation-1',
            ),
      ),
    );
    await client.dispose();
  });
}

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
      type: RipeningAllocationType.reserve,
      weightHundredths: 1000,
    ),
  ],
);

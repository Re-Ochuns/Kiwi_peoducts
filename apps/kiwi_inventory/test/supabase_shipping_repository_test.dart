import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_inventory/shipping/shipping_repository.dart';
import 'package:kiwi_inventory/shipping/supabase_shipping_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('未出荷受注を出荷日順の一覧へ変換する', () async {
    final client = _client((request) {
      final path = request.url.path;
      if (path.endsWith('/rpc/order_list')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final status = body['status_value'];
        return _json(
          status == 'confirmed' || status == 'shipped'
              ? [
                  {
                    'order_id': 'order-1',
                    'order_number': '受注-2026-001',
                    'customer_id': 'customer-1',
                    'customer_name': '青果店A',
                    'customer_nickname': 'A店',
                    'ordered_on': '2026-09-10',
                    'scheduled_ship_on': '2026-09-13',
                    'variety_id': 'variety-1',
                    'grade_id': 'grade-1',
                    'ordered_weight_kg': 10,
                    'allocated_weight_kg': 10,
                    'shortage_weight_kg': 0,
                    'status': status,
                    'version': 3,
                  },
                ]
              : [],
          request,
        );
      }
      if (path.endsWith('/varieties')) {
        return _json([
          {'id': 'variety-1', 'code': 'hayward', 'name': 'ヘイワード'},
        ], request);
      }
      if (path.endsWith('/grades')) {
        return _json([
          {'id': 'grade-1', 'code': 'M'},
        ], request);
      }
      throw StateError('unexpected request: $path');
    });

    final orders = await SupabaseShippingRepository(client).loadOrders();

    expect(orders, hasLength(2));
    expect(orders.map((order) => order.status), contains('shipped'));
    expect(orders.first.number, '受注-2026-001');
    expect(orders.first.customer, 'A店');
    expect(orders.first.variety, 'ヘイワード');
    expect(orders.first.grade, 'M');
    expect(orders.first.orderedWeightHundredths, 1000);
    await client.dispose();
  });

  test('受注・使用可能コンテナ・複数出荷実績を詳細へ変換する', () async {
    final client = _client((request) {
      final path = request.url.path;
      if (path.endsWith('/rpc/order_get')) {
        return _json(_orderDetail(), request);
      }
      if (path.endsWith('/rpc/shipment_container_list')) {
        return _json([
          {
            'id': 'container-1',
            'display_id': '追熟-2026-001-1',
            'ripening_lot_id': 'lot-1',
            'version': 2,
            'current_weight_kg': 6,
            'available_weight_kg': 5,
            'remaining_use_type': 'mixed',
            'shippable_until': '2026-09-14T03:00:00Z',
            'best_before_at': '2026-09-15T03:00:00Z',
          },
        ], request);
      }
      if (path.endsWith('/rpc/shipment_list')) {
        return _json([
          {
            'id': 'shipment-1',
            'status': 'confirmed',
            'shipped_at': '2026-09-13T00:00:00Z',
          },
        ], request);
      }
      if (path.endsWith('/rpc/shipment_get')) {
        return _json(_shipment(), request);
      }
      if (path.endsWith('/containers')) {
        return _json([
          {'id': 'container-1', 'ripening_lot_id': 'lot-1'},
        ], request);
      }
      if (path.endsWith('/workers')) {
        return _json([
          {'id': 'worker-1', 'code': 'W01', 'display_name': '岡本'},
        ], request);
      }
      if (path.endsWith('/varieties')) {
        return _json([
          {'id': 'variety-1', 'code': 'hayward', 'name': 'ヘイワード'},
        ], request);
      }
      if (path.endsWith('/grades')) {
        return _json([
          {'id': 'grade-1', 'code': 'M'},
        ], request);
      }
      throw StateError('unexpected request: $path');
    });

    final detail = await SupabaseShippingRepository(client)
        .loadOrder('order-1');

    expect(detail.order.shippedWeightHundredths, 250);
    expect(detail.remainingAllocationHundredths['lot-1'], 750);
    expect(detail.order.remainingWeightHundredths, 750);
    expect(detail.destination, contains('愛媛県松山市'));
    expect(detail.containers.single.availableWeightHundredths, 500);
    expect(detail.containers.single.useLabel, '受注分・予備');
    expect(detail.shipments.single.totalWeightHundredths, 250);
    expect(detail.workers.single.label, 'W01　岡本');
    await client.dispose();
  });

  test('部分出荷を共通封筒で送り成功応答を変換する', () async {
    Map<String, dynamic>? requestBody;
    final client = _client((request) {
      expect(request.url.path, endsWith('/rpc/shipment_confirm'));
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'ok': true,
        'correlation_id': 'correlation-1',
        'idempotent_replay': false,
        'data': _shipment(),
      }, request);
    });

    final result = await SupabaseShippingRepository(client).confirm(
      input: _input(),
      idempotencyKey: '00000000-0000-4000-8000-000000000001',
    );

    final request = requestBody!['req'] as Map<String, dynamic>;
    final meta = request['meta'] as Map<String, dynamic>;
    final input = request['input'] as Map<String, dynamic>;
    expect(meta['idempotency_key'], '00000000-0000-4000-8000-000000000001');
    expect(meta['correlation_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(input['checked'], isTrue);
    expect(input['expected_order_version'], 3);
    expect((input['lines'] as List).single, {
      'container_id': 'container-1',
      'expected_version': 2,
      'shipped_weight_kg': 2.5,
    });
    expect(result.shipment.displayId, '出荷-2026-001');
    await client.dispose();
  });

  test('出荷取消を版番号・理由とともに共通封筒で送る', () async {
    Map<String, dynamic>? requestBody;
    final client = _client((request) {
      expect(request.url.path, endsWith('/rpc/shipment_cancel'));
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'ok': true,
        'correlation_id': 'correlation-2',
        'idempotent_replay': true,
        'data': {..._shipment(), 'status': 'cancelled'},
      }, request);
    });

    final result = await SupabaseShippingRepository(client).cancel(
      shipmentId: 'shipment-1',
      expectedVersion: 4,
      reason: ' 入力内容の訂正 ',
      idempotencyKey: '00000000-0000-4000-8000-000000000002',
    );

    final request = requestBody!['req'] as Map<String, dynamic>;
    expect(
      request['meta'],
      containsPair('idempotency_key', '00000000-0000-4000-8000-000000000002'),
    );
    expect(request['input'], {
      'shipment_id': 'shipment-1',
      'expected_version': 4,
      'reason': '入力内容の訂正',
    });
    expect(result.idempotentReplay, isTrue);
    expect(result.shipment.status, 'cancelled');
    await client.dispose();
  });

  test('競合エラーを再送不可として保持する', () async {
    final client = _client(
      (request) => _json({
        'ok': false,
        'correlation_id': 'correlation-1',
        'error': {
          'code': 'CONFLICT_STALE',
          'message': '受注が更新されています。',
          'retryable': false,
          'details': {'field': 'expected_order_version'},
        },
      }, request),
    );

    await expectLater(
      SupabaseShippingRepository(client).confirm(
        input: _input(),
        idempotencyKey: '00000000-0000-4000-8000-000000000001',
      ),
      throwsA(
        isA<ShippingFailure>()
            .having((error) => error.code, 'code', 'CONFLICT_STALE')
            .having((error) => error.isConflict, 'isConflict', isTrue)
            .having(
              (error) => error.correlationId,
              'correlationId',
              'correlation-1',
            ),
      ),
    );
    await client.dispose();
  });

  test('権限エラーを再試行不可として返す', () async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode({'code': '42501', 'message': 'permission denied'}),
        403,
        request: request,
        headers: {'content-type': 'application/json'},
      ),
    );

    await expectLater(
      SupabaseShippingRepository(client).loadOrders(),
      throwsA(
        isA<ShippingFailure>()
            .having((error) => error.code, 'code', 'AUTH_FORBIDDEN')
            .having((error) => error.retryable, 'retryable', isFalse),
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

Future<http.Response> _json(Object? body, http.Request request) async =>
    http.Response(
      jsonEncode(body),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );

Map<String, Object?> _orderDetail() => {
  'id': 'order-1',
  'order_number': '受注-2026-001',
  'scheduled_ship_on': '2026-09-13',
  'variety_id': 'variety-1',
  'grade_id': 'grade-1',
  'ordered_weight_kg': 10,
  'status': 'partially_shipped',
  'version': 3,
  'customer': {'name': '青果店A', 'nickname': 'A店'},
  'ripening_allocations': [
    {'ripening_lot_id': 'lot-1', 'allocated_weight_kg': 10},
  ],
  'shipping_destination_snapshot': {
    'destination_name': '本店',
    'recipient_name': '青果店A 御中',
    'postal_code': '790-0001',
    'address': '愛媛県松山市一番町1-1',
  },
};

Map<String, Object?> _shipment() => {
  'id': 'shipment-1',
  'display_id': '出荷-2026-001',
  'version': 1,
  'status': 'confirmed',
  'shipped_at': '2026-09-13T00:00:00Z',
  'total_weight_kg': 2.5,
  'lines': [
    {'container_id': 'container-1', 'shipped_weight_kg': 2.5},
  ],
};

ShippingConfirmInput _input() => ShippingConfirmInput(
  orderId: 'order-1',
  expectedOrderVersion: 3,
  shippedAt: DateTime.utc(2026, 9, 13),
  workerId: 'worker-1',
  reason: '出荷内容確認済み',
  lines: const [
    ShippingLineInput(
      containerId: 'container-1',
      expectedVersion: 2,
      weightHundredths: 250,
    ),
  ],
);

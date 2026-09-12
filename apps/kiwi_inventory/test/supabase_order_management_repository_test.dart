import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_inventory/orders/order_management_repository.dart';
import 'package:kiwi_inventory/orders/supabase_order_management_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('未出荷の4状態を読み込み不足量と管理権限を変換する', () async {
    final requests = <http.Request>[];
    final client = _client((request) {
      requests.add(request);
      if (request.url.path.endsWith('/profiles')) {
        return {'access_status': 'active'};
      }
      if (request.url.path.endsWith('/user_roles')) {
        return [
          {'role': 'administrator'},
        ];
      }
      if (request.url.path.endsWith('/customer_list')) {
        return (jsonDecode(request.body) as Map)['search_value'] == null
            ? [_customerRow]
            : <Object>[];
      }
      if (request.url.path.endsWith('/varieties')) {
        return [
          {'id': _varietyId, 'code': 'hayward', 'name': 'ヘイワード'},
        ];
      }
      if (request.url.path.endsWith('/grades')) {
        return [
          {'id': _gradeId, 'code': 'L'},
        ];
      }
      if (request.url.path.endsWith('/order_list')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return body['status_value'] == 'draft' ? [_orderRow] : <Object>[];
      }
      return <Object>[];
    });
    final repository = SupabaseOrderManagementRepository(
      client,
      currentUserId: _userId,
    );

    final data = await repository.load(
      filter: OrderListFilter.active,
      customerSearch: '別顧客',
    );

    expect(data.canManage, isTrue);
    expect(data.customers, isEmpty);
    expect(data.customerOptions.single.id, _customerId);
    expect(data.orders, hasLength(1));
    expect(data.orders.single.number, '受注-2026-001');
    expect(data.orders.single.shortageWeight, 7.5);
    final orderRequests = requests.where(
      (request) => request.url.path.endsWith('/order_list'),
    );
    expect(orderRequests, hasLength(4));
    expect(
      orderRequests
          .map(
            (request) =>
                (jsonDecode(request.body)
                    as Map<String, dynamic>)['status_value'],
          )
          .toSet(),
      {'draft', 'confirmed', 'in_progress', 'partially_shipped'},
    );
    await client.dispose();
  });

  test('受注登録RPCへ共通封筒を送り発行済み受注を返す', () async {
    late Map<String, dynamic> registerBody;
    final client = _client((request) {
      if (request.url.path.endsWith('/order_register')) {
        registerBody = jsonDecode(request.body) as Map<String, dynamic>;
        return {
          'ok': true,
          'correlation_id': '69000000-0000-4000-8000-000000000001',
          'idempotent_replay': false,
          'data': _orderDetailRow,
        };
      }
      if (request.url.path.endsWith('/order_get')) return _orderDetailRow;
      return <Object>[];
    });
    final repository = SupabaseOrderManagementRepository(client);

    final result = await repository.registerOrder(
      OrderInput(
        customerId: _customerId,
        destinationId: _destinationId,
        orderedOn: DateTime(2026, 9, 12),
        scheduledShipOn: DateTime(2026, 9, 15),
        varietyId: _varietyId,
        gradeId: _gradeId,
        orderedWeight: 20,
        notes: '午前着',
      ),
      idempotencyKey: '6c000000-0000-4000-8000-000000000001',
    );

    final req = registerBody['req'] as Map<String, dynamic>;
    final meta = req['meta'] as Map<String, dynamic>;
    final input = req['input'] as Map<String, dynamic>;
    expect(meta['idempotency_key'], '6c000000-0000-4000-8000-000000000001');
    expect(meta['correlation_id'], matches(_uuidV4Pattern));
    expect(input['ordered_date'], '2026-09-12');
    expect(input['scheduled_ship_date'], '2026-09-15');
    expect(input['ordered_weight_kg'], 20);
    expect(result.number, '受注-2026-001');
    await client.dispose();
  });

  test('業務エラーの項目と相関IDを画面用失敗へ変換する', () async {
    final client = _client(
      (request) => {
        'ok': false,
        'correlation_id': '69000000-0000-4000-8000-000000000002',
        'error': {
          'code': 'CUSTOMER_DUPLICATE',
          'message': '同じ顧客コードが登録されています。',
          'retryable': false,
          'details': {'field': 'customer_code', 'reason': 'duplicate'},
        },
      },
    );
    final repository = SupabaseOrderManagementRepository(client);

    await expectLater(
      repository.registerCustomer(
        const CustomerInput(
          code: 'C-001',
          name: '別の顧客',
          nickname: '',
          postalCode: '100-0001',
          address: '東京都',
        ),
        idempotencyKey: '6c000000-0000-4000-8000-000000000002',
      ),
      throwsA(
        isA<OrderManagementFailure>()
            .having((error) => error.code, 'code', 'CUSTOMER_DUPLICATE')
            .having((error) => error.field, 'field', 'customer_code')
            .having(
              (error) => error.correlationId,
              'correlationId',
              '69000000-0000-4000-8000-000000000002',
            ),
      ),
    );
    await client.dispose();
  });
}

SupabaseClient _client(Object Function(http.Request request) response) =>
    SupabaseClient(
      'https://example.test',
      'test',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(response(request)),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

const _userId = '60000000-0000-4000-8000-000000000003';
const _customerId = '60000000-0000-4000-8000-000000000004';
const _destinationId = '60000000-0000-4000-8000-000000000005';
const _varietyId = '60000000-0000-4000-8000-000000000006';
const _gradeId = '60000000-0000-4000-8000-000000000007';
const _orderId = '60000000-0000-4000-8000-000000000008';

const _customerRow = {
  'customer_id': _customerId,
  'customer_code': 'C-001',
  'name': '青果店株式会社',
  'nickname': '青果店',
  'postal_code': '100-0001',
  'address': '東京都',
  'is_active': true,
  'version': 1,
  'destination_count': 1,
};

const _orderRow = {
  'order_id': _orderId,
  'order_number': '受注-2026-001',
  'customer_id': _customerId,
  'customer_name': '青果店株式会社',
  'customer_nickname': '青果店',
  'ordered_on': '2026-09-12',
  'scheduled_ship_on': '2026-09-15',
  'variety_id': _varietyId,
  'grade_id': _gradeId,
  'ordered_weight_kg': 20,
  'allocated_weight_kg': 12.5,
  'shortage_weight_kg': 7.5,
  'status': 'draft',
  'version': 1,
};

const _orderDetailRow = {
  'id': _orderId,
  'order_number': '受注-2026-001',
  'customer_id': _customerId,
  'shipping_destination_id': _destinationId,
  'ordered_on': '2026-09-12',
  'scheduled_ship_on': '2026-09-15',
  'variety_id': _varietyId,
  'grade_id': _gradeId,
  'ordered_weight_kg': 20,
  'allocated_weight_kg': 0,
  'shortage_weight_kg': 20,
  'status': 'draft',
  'version': 1,
  'notes': '午前着',
  'customer': {'customer_code': 'C-001', 'name': '青果店株式会社', 'nickname': '青果店'},
  'shipping_destination_snapshot': {
    'destination_name': '本店',
    'recipient_name': '受取担当者',
    'postal_code': '100-0001',
    'address': '東京都',
  },
  'ripening_allocations': <Object>[],
};

final _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

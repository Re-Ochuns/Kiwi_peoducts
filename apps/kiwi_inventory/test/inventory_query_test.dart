import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kiwi_inventory/inventory/inventory_repository.dart';
import 'package:kiwi_inventory/inventory/supabase_inventory_repository.dart';

void main() {
  for (final sort in InventorySort.values) {
    test('在庫取得・件数・検索・状態・ページ指定: ${sort.name}', () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode([
              {
                'id': 'container-1',
                'display_id': 'CONT-1',
                'original_weight_kg': 10,
                'current_weight_kg': 9.25,
                'reserved_weight_kg': 2,
                'status': 'cold_storage',
                'updated_at': '2026-09-14T00:00:00Z',
                'variety': {'name': 'ヘイワード'},
                'grade': {'code': 'M'},
                'location': null,
              },
            ]),
            200,
            request: request,
            headers: {
              'content-type': 'application/json',
              'content-range': '20-20/21',
            },
          );
        }),
      );
      final result = await SupabaseInventoryRepository(client).loadPage(
        InventoryQuery(
          search: ' CONT ',
          status: InventoryStatus.coldStorage,
          sort: sort,
          page: 1,
        ),
      );
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.url.queryParameters['display_id'], 'ilike.%CONT%');
      expect(request.url.queryParameters['status'], 'eq.cold_storage');
      expect(request.url.queryParameters['offset'], '20');
      expect(request.url.queryParameters['limit'], '20');
      expect(
        request.url.queryParameters['order'],
        contains(switch (sort) {
          InventorySort.updatedDescending => 'updated_at.desc',
          InventorySort.displayIdAscending => 'display_id.',
          InventorySort.currentWeightDescending => 'current_weight_kg.desc',
        }),
      );
      expect(request.headers['Prefer'], contains('count=exact'));
      expect(result.totalCount, 21);
      expect(result.items.single.availableWeightHundredths, 725);
      expect(result.hasPrevious, isTrue);
      expect(result.hasNext, isFalse);
      await client.dispose();
    });
  }
  test('初期クエリで空の一覧と0件を取得できる', () async {
    final client = SupabaseClient(
      'https://example.invalid',
      'test-key',
      httpClient: MockClient((request) async {
        expect(request.url.queryParameters.containsKey('status'), isFalse);
        expect(request.url.queryParameters.containsKey('display_id'), isFalse);
        return http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json', 'content-range': '*/0'},
        );
      }),
    );
    final result = await SupabaseInventoryRepository(client)
        .loadPage(const InventoryQuery());
    expect(result.totalCount, 0);
    expect(result.items, isEmpty);
    await client.dispose();
  });
}

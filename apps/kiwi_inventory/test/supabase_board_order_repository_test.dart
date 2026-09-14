import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kiwi_inventory/board_order/board_order_repository.dart';
import 'package:kiwi_inventory/board_order/supabase_board_order_repository.dart';
import 'package:kiwi_inventory/process_board/process_board_repository.dart';

void main() {
  test(
    'search sends criteria and parses lot balances without apportionment',
    () async {
      final client = SupabaseClient(
        'https://example.test',
        'key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/board_order_candidates');
          expect(
            jsonDecode(request.body)['input_value']['ordered_weight_kg'],
            2.25,
          );
          return http.Response(
            jsonEncode([
              {
                'id': 'lot',
                'kind': 'lot',
                'display_id': 'LOT-1',
                'stage': 'resting',
                'available_weight_kg': 7.75,
                'planned_ethylene_at': '2027-05-20T00:00:00Z',
                'planned_completion_at': '2027-05-30T00:00:00Z',
                'version': 'v1',
                'container_ids': 'C1、C2',
                'location_id': null,
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final repo = SupabaseBoardOrderRepository(client);
      final rows = await repo.candidates(
        const BoardOrderCriteria(
          shipDate: '2027-06-01',
          varietyId: 'v',
          gradeId: 'g',
          weightHundredths: 225,
        ),
      );
      expect(rows.single.availableHundredths, 775);
      expect(rows.single.stage, ProcessStage.resting);
      expect(rows.single.containerIds, 'C1、C2');
      await client.dispose();
    },
  );
  test(
    'confirmation passes operation key and surfaces business conflict',
    () async {
      final client = SupabaseClient(
        'https://example.test',
        'key',
        httpClient: MockClient((request) async {
          expect(
            jsonDecode(request.body)['req']['meta']['idempotency_key'],
            'retry-key',
          );
          return http.Response(
            jsonEncode({
              'ok': false,
              'error': {
                'code': 'INVENTORY_UNAVAILABLE',
                'message': 'retry search',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      await expectLater(
        SupabaseBoardOrderRepository(client).confirm({}, 'retry-key'),
        throwsA(
          isA<BoardOrderFailure>()
              .having((e) => e.code, 'code', 'INVENTORY_UNAVAILABLE')
              .having((e) => e.uncertain, 'uncertain', false),
        ),
      );
      await client.dispose();
    },
  );
  test(
    'transport error preserves uncertain outcome for idempotent retry',
    () async {
      final client = SupabaseClient(
        'https://example.test',
        'key',
        httpClient: MockClient((_) async {
          throw http.ClientException('network lost');
        }),
      );
      await expectLater(
        SupabaseBoardOrderRepository(client).confirm({}, 'key'),
        throwsA(
          isA<BoardOrderFailure>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      await client.dispose();
    },
  );
  test('successful confirmation returns existing plan identity', () async {
    final client = SupabaseClient(
      'https://example.test',
      'key',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'order_number': 'ORDER-1',
              'ripening_display_id': 'LOT-1',
              'existing_plan': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    final result = await SupabaseBoardOrderRepository(client)
        .confirm({}, 'key');
    expect(result.existingPlan, true);
    expect(result.planNumber, 'LOT-1');
    await client.dispose();
  });
}

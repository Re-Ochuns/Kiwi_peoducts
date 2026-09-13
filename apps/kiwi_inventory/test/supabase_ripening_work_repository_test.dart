import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_inventory/ripening_work/ripening_work_repository.dart';
import 'package:kiwi_inventory/ripening_work/supabase_ripening_work_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('追熟計画・場所・担当者を作業詳細へ変換する', () async {
    final requestedPaths = <String>[];
    final client = _client((request) {
      requestedPaths.add(request.url.path);
      final path = request.url.path;
      if (path.endsWith('/rpc/ripening_work_get')) {
        return _json({
          'id': 'ripening-1',
          'display_id': '追熟-2026-001',
          'status': 'in_progress',
          'version': 3,
          'total_weight_kg': 20.5,
          'storage_location_id': 'location-1',
          'assigned_worker_id': 'worker-1',
          'planned_ethylene_at': '2026-09-12T00:00:00Z',
          'planned_completion_at': '2026-09-19T00:00:00Z',
          'tasks': [
            {
              'managed_by_planning': true,
              'task_type': 'ethylene_removal_check',
              'scheduled_at': '2026-09-15T03:00:00Z',
              'due_at': '2026-09-15T04:00:00Z',
              'task_details': {'variety': '新しい品種', 'grade': 'L'},
            },
          ],
          'results': [
            {
              'work_type': 'ethylene_injection',
              'actual_at': '2026-09-12T01:00:00Z',
              'rest_started_at': null,
            },
          ],
        }, request);
      }
      if (path.endsWith('/storage_locations')) {
        return _json([
          {'id': 'location-1', 'code': 'R01', 'name': '第1追熟庫'},
        ], request);
      }
      if (path.endsWith('/workers')) {
        return _json([
          {'id': 'worker-1', 'code': 'W01', 'display_name': '岡本'},
        ], request);
      }
      throw StateError('unexpected request: $path');
    });

    final details = await SupabaseRipeningWorkRepository(client)
        .load('ripening-1');

    expect(requestedPaths, contains(endsWith('/rpc/ripening_work_get')));
    expect(details.displayId, '追熟-2026-001');
    expect(details.weightHundredths, 2050);
    expect(details.version, 3);
    expect(details.tasks.single.productLabel, '新しい品種・L');
    expect(details.tasks.single.type, 'ethylene_removal_check');
    expect(
      details.tasks.single.scheduledAt,
      DateTime.utc(2026, 9, 15, 3).toLocal(),
    );
    expect(details.tasks.single.dueAt, DateTime.utc(2026, 9, 15, 4).toLocal());
    expect(details.results.single.type, 'ethylene_injection');
    expect(details.locations.single.label, 'R01　第1追熟庫');
    expect(details.workers.single.label, 'W01　岡本');
    await client.dispose();
  });

  for (final scenario in <(List<Map<String, String>>, String?)>[
    ([], 'location-1'),
    (
      [
        {'location_id': 'location-2'},
      ],
      'location-2',
    ),
    (
      [
        {'location_id': 'location-2'},
        {'location_id': 'location-2'},
      ],
      'location-2',
    ),
    (
      [
        {'location_id': 'location-1'},
        {'location_id': 'location-2'},
      ],
      null,
    ),
  ]) {
    test('現物場所を初期選択し複数場所は明示選択する: ${scenario.$1}', () async {
      final client = _client((request) {
        if (request.url.path.endsWith('/rpc/ripening_work_get')) {
          return _json({
            'id': 'ripening-1',
            'display_id': '追熟-2026-001',
            'status': 'in_progress',
            'version': 3,
            'total_weight_kg': 20.5,
            'storage_location_id': 'location-1',
            'assigned_worker_id': 'worker-1',
            'planned_ethylene_at': '2026-09-12T00:00:00Z',
            'planned_completion_at': '2026-09-19T00:00:00Z',
            'containers': scenario.$1,
            'results': [],
          }, request);
        }
        return _json([], request);
      });
      final details = await SupabaseRipeningWorkRepository(client)
          .load('ripening-1');
      expect(details.locationId, scenario.$2);
      await client.dispose();
    });
  }

  test('抜き確認を共通封筒で送り成功応答を変換する', () async {
    Map<String, dynamic>? requestBody;
    final client = _client((request) {
      expect(
        request.url.path,
        endsWith('/rpc/ripening_ethylene_removal_complete'),
      );
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'ok': true,
        'correlation_id': 'correlation-1',
        'idempotent_replay': false,
        'data': {
          'display_id': '追熟-2026-001',
          'version': 4,
          'status': 'resting',
          'results': [
            {
              'work_type': 'ethylene_injection',
              'actual_at': '2026-09-12T01:00:00Z',
            },
            {
              'work_type': 'ethylene_removal_check',
              'actual_at': '2026-09-13T01:00:00Z',
            },
          ],
        },
      }, request);
    });

    final result = await SupabaseRipeningWorkRepository(client).complete(
      type: RipeningWorkType.ethyleneRemoval,
      input: _input(),
      idempotencyKey: '00000000-0000-4000-8000-000000000001',
    );

    final request = requestBody!['req'] as Map<String, dynamic>;
    final meta = request['meta'] as Map<String, dynamic>;
    final input = request['input'] as Map<String, dynamic>;
    expect(meta['idempotency_key'], '00000000-0000-4000-8000-000000000001');
    expect(meta['correlation_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(input['checked'], isTrue);
    expect(input['expected_version'], 3);
    expect(input['rest_temperature'], 16.5);
    expect(result.displayId, '追熟-2026-001');
    expect(result.version, 4);
    await client.dispose();
  });

  test('競合エラーの詳細と問い合わせ番号を画面用エラーへ保持する', () async {
    final client = _client(
      (request) => _json({
        'ok': false,
        'correlation_id': 'correlation-1',
        'error': {
          'code': 'CONFLICT_STALE',
          'message': '別の端末で更新されています。',
          'retryable': false,
          'details': {'field': 'expected_version'},
        },
      }, request),
    );

    await expectLater(
      SupabaseRipeningWorkRepository(client).complete(
        type: RipeningWorkType.ethyleneInjection,
        input: _input(),
        idempotencyKey: '00000000-0000-4000-8000-000000000001',
      ),
      throwsA(
        isA<RipeningWorkFailure>()
            .having((value) => value.code, 'code', 'CONFLICT_STALE')
            .having((value) => value.field, 'field', 'expected_version')
            .having(
              (value) => value.correlationId,
              'correlationId',
              'correlation-1',
            )
            .having((value) => value.isConflict, 'isConflict', isTrue),
      ),
    );
    await client.dispose();
  });

  test('権限エラーを再試行不可として画面へ返す', () async {
    final client = _client(
      (request) async => http.Response(
        jsonEncode({'code': '42501', 'message': 'permission denied'}),
        403,
        request: request,
        headers: {'content-type': 'application/json'},
      ),
    );

    await expectLater(
      SupabaseRipeningWorkRepository(client).load('ripening-1'),
      throwsA(
        isA<RipeningWorkFailure>()
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

Future<http.Response> _json(Object body, http.Request request) async =>
    http.Response(
      jsonEncode(body),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );

RipeningWorkInput _input() => RipeningWorkInput(
  ripeningLotId: 'ripening-1',
  expectedVersion: 3,
  actualAt: DateTime.utc(2026, 9, 13, 1),
  actualTemperature: 18,
  locationId: 'location-1',
  workerId: 'worker-1',
  restStartedAt: DateTime.utc(2026, 9, 13, 2),
  restTemperature: 16.5,
  notes: '確認済み',
);

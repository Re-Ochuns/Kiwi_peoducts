import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_inventory/work_tasks/supabase_work_task_repository.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('作業一覧と対象表示IDをToDoへ変換する', () async {
    final client = _client((request) {
      if (request.url.path.endsWith('/rpc/work_task_list')) {
        return _json([
          {
            'id': 'task-1',
            'task_type': 'ethylene_injection',
            'receiving_lot_id': null,
            'label_job_id': null,
            'ripening_lot_id': 'ripening-1',
            'order_id': null,
            'scheduled_at': '2026-09-12T01:00:00Z',
            'due_at': '2026-09-12T02:00:00Z',
            'status': 'pending',
            'assigned_worker_id': 'worker-1',
            'target_url': '/work-tasks/task-1',
            'task_details': {
              'variety': 'ヘイワード',
              'grade': 'M',
              'weight_kg': 20.5,
              'location': '第1追熟庫',
            },
            'schedule_warning': null,
          },
        ], request);
      }
      if (request.url.path.endsWith('/ripening_lots')) {
        return _json([
          {'id': 'ripening-1', 'display_id': '追熟-2026-001'},
        ], request);
      }
      throw StateError('unexpected request: ${request.url}');
    });

    final tasks = await SupabaseWorkTaskRepository(client).loadTasks();

    expect(tasks, hasLength(1));
    expect(tasks.single.targetDisplayId, '追熟-2026-001');
    expect(tasks.single.type, WorkTaskType.ethyleneInjection);
    expect(tasks.single.weightHundredths, 2050);
    expect(tasks.single.location, '第1追熟庫');
    await client.dispose();
  });

  test('対象がない作業詳細はnullを返す', () async {
    final client = _client((request) => _json(null, request));

    final task = await SupabaseWorkTaskRepository(client).loadTask('missing');

    expect(task, isNull);
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
      SupabaseWorkTaskRepository(client).loadTasks(),
      throwsA(
        isA<WorkTaskFailure>()
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

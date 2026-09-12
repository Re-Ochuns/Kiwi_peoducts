import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_inventory/work_tasks/supabase_work_task_repository.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'pending tasks beyond the API row cap are paged and labels are bounded',
    () async {
      final offsets = <int>[];
      var targetRequests = 0;
      final client = _client((request) {
        final query = request.url.queryParameters;
        if (request.url.path.endsWith('/rpc/work_task_list')) {
          expect(query['status'], 'eq.pending');
          expect(query['order'], 'due_at.asc.nullslast,id.asc.nullslast');
          final offset = int.parse(query['offset']!);
          final limit = int.parse(query['limit']!);
          expect(limit, 200);
          offsets.add(offset);
          final count = offset + limit <= 1005 ? limit : 1005 - offset;
          return _json(
            List.generate(
              count,
              (i) => {
                'id': 'task-${offset + i}',
                'task_type': 'ethylene_injection',
                'ripening_lot_id': 'ripening-${offset + i}',
                'scheduled_at': '2026-09-12T01:00:00Z',
                'due_at': '2026-09-12T02:00:00Z',
                'status': 'pending',
                'target_url': '/work-tasks/task-${offset + i}',
              },
            ),
            request,
          );
        }
        if (request.url.path.endsWith('/ripening_lots')) {
          targetRequests++;
          final ids = query['id']!
              .substring(4, query['id']!.length - 1)
              .split(',');
          expect(ids.length, lessThanOrEqualTo(200));
          return _json([
            for (final id in ids) {'id': id, 'display_id': id},
          ], request);
        }
        throw StateError('unexpected request: ${request.url}');
      });
      final tasks = await SupabaseWorkTaskRepository(client).loadTasks();
      expect(tasks.length, 1005);
      expect(tasks.last.id, 'task-1004');
      expect(offsets, [0, 200, 400, 600, 800, 1000]);
      expect(targetRequests, 6);
      await client.dispose();
    },
  );
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
            'calendar_sync_status': 'failed',
            'calendar_sync_error': 'GOOGLE_TEMPORARY',
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
    expect(tasks.single.calendarSyncStatus, 'failed');
    expect(tasks.single.calendarSyncError, 'GOOGLE_TEMPORARY');
    await client.dispose();
  });

  test('管理ホームでは中止済みを含む同期失敗を取得する', () async {
    final client = _client((request) {
      expect(request.url.path, endsWith('/rpc/work_task_list'));
      expect(request.url.queryParameters.containsKey('status'), isFalse);
      expect(
        request.url.queryParameters['or'],
        '(status.eq.pending,calendar_sync_status.eq.failed)',
      );
      return _json([
        {
          'id': 'task-cancelled',
          'task_type': 'shipping',
          'scheduled_at': '2026-09-12T01:00:00Z',
          'due_at': '2026-09-12T02:00:00Z',
          'status': 'cancelled',
          'target_url': '/work-tasks/task-cancelled',
          'calendar_sync_status': 'failed',
          'calendar_sync_error': 'GOOGLE_TEMPORARY',
        },
      ], request);
    });

    final tasks = await SupabaseWorkTaskRepository(client).loadDashboardTasks();

    expect(tasks.single.status, 'cancelled');
    expect(tasks.single.calendarSyncStatus, 'failed');
    await client.dispose();
  });

  test('同期警告の件数を変換する', () async {
    final client = _client((request) {
      expect(request.url.path, endsWith('/rpc/work_task_sync_warnings'));
      return _json({
        'failed_count': 2,
        'pending_count': 3,
        'overdue_sync_count': 1,
        'schedule_warning_count': 4,
      }, request);
    });

    final warnings = await SupabaseWorkTaskRepository(client)
        .loadSyncWarnings();

    expect(warnings.failedCount, 2);
    expect(warnings.pendingCount, 3);
    expect(warnings.overdueSyncCount, 1);
    expect(warnings.scheduleWarningCount, 4);
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

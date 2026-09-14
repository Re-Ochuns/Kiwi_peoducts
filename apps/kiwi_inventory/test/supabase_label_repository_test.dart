import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kiwi_inventory/label/supabase_label_repository.dart';

void main() {
  for (final completed in [false, true]) {
    for (final mixed in [false, true]) {
      test('追熟対象を取得: 完了=$completed 混在=$mixed', () async {
        final row = _row(2, completed ? 'printed' : 'not_printed');
        final container = row['container'] as Map<String, Object>;
        container.remove('sorting_result');
        container['ripening_lot_id'] = _id(90);
        final client = _client([
          row,
          if (mixed) _row(1, completed ? 'handwritten' : 'partially_printed'),
        ]);
        final repository = SupabaseLabelRepository(
          client,
          supabaseUrl: 'https://example.test',
          supabaseKey: 'test',
        );
        final result = await repository.load(completed: completed);
        expect(result.jobs.length, mixed ? 2 : 1);
        final job = result.jobs.first;
        expect(job.id, _id(2));
        expect(job.containerId, _id(2));
        expect(job.isRipening, isTrue);
        expect(job.sortedOn, isNull);
        expect(job.originName, '農園A・農園B');
        expect(job.ripeningFields!['割当'], '予備 8.50 kg');
        expect(job.ripeningFields!['注入日時'], isNot('未設定'));
        if (mixed) {
          expect(result.jobs.last.isRipening, isFalse);
          expect(result.jobs.last.workerName, '担当者');
        }
        await client.dispose();
      });
    }
  }

  test('対応済み1000件の後にある未対応も状態別に取得する', () async {
    final all = [
      for (var i = 1100; i > 100; i--) _row(i, 'printed'),
      _row(1, 'not_printed'),
    ];
    final client = _client(all);
    final repository = SupabaseLabelRepository(
      client,
      supabaseUrl: 'https://example.test',
      supabaseKey: 'test',
    );
    final page = await repository.load();
    expect(page.jobs.map((job) => job.id), [_id(1)]);
    expect(page.nextCursor, isNull);
    await client.dispose();
  });

  test('同じ作成日時でもIDカーソルで重複なく全ページを取得する', () async {
    final all = [for (var i = 55; i > 0; i--) _row(i, 'not_printed')];
    final client = _client(all);
    final repository = SupabaseLabelRepository(
      client,
      supabaseUrl: 'https://example.test',
      supabaseKey: 'test',
    );
    final first = await repository.load();
    expect(first.jobs.length, 50);
    expect(first.nextCursor!.id, _id(6));
    final second = await repository.load(after: first.nextCursor);
    expect(second.jobs.length, 5);
    expect(second.nextCursor, isNull);
    expect(
      [...first.jobs, ...second.jobs].map((job) => job.id).toSet().length,
      55,
    );
    final completed = await repository.load(completed: true);
    expect(completed.jobs, isEmpty);
    await client.dispose();
  });
}

SupabaseClient _client(List<Map<String, Object>> rows) {
  return SupabaseClient(
    'https://example.test',
    'test',
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/rpc/ripening_label_get')) {
        final id = jsonDecode(request.body)['container_id_value'];
        return http.Response(
          jsonEncode({
            'container_id': id,
            'orchard_names': '農園A・農園B',
            'location_name': '追熟室',
            'injection_at': '2026-09-14T00:00:00Z',
            'planned_removal_at': '2026-09-15T00:00:00Z',
            'planned_completion_at': '2026-09-20T00:00:00Z',
            'allocations': [
              {'allocation_type': 'reserve', 'allocated_weight_kg': 8.5},
            ],
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      if (!request.url.path.endsWith('/label_jobs')) {
        return http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      final params = request.url.queryParameters;
      expect(params['order'], 'created_at.desc.nullslast,id.desc.nullslast');
      expect(params['limit'], '51');
      final status = params['status']?.replaceAll('"', '');
      expect(
        status,
        isIn([
          'in.(not_printed,partially_printed)',
          'in.(printed,handwritten)',
        ]),
      );
      var selected = rows.where(
        (row) => status == 'in.(printed,handwritten)'
            ? ['printed', 'handwritten'].contains(row['status'])
            : ['not_printed', 'partially_printed'].contains(row['status']),
      );
      final cursor = params['or'];
      if (cursor != null) {
        expect(cursor, contains('created_at.lt.2026-09-10T00:00:00+00:00'));
        expect(cursor, contains('created_at.eq.2026-09-10T00:00:00+00:00'));
        final id = RegExp(r'id.lt.([0-9a-f-]+)').firstMatch(cursor)!.group(1)!;
        selected = selected.where(
          (row) => (row['id']! as String).compareTo(id) < 0,
        );
      }
      return http.Response(
        jsonEncode(selected.take(51).toList()),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

String _id(int i) => '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';

Map<String, Object> _row(int i, String status) => {
  'id': _id(i),
  'created_at': '2026-09-10T00:00:00+00:00',
  'status': status,
  'required_copies': 1,
  'printed_copies': status == 'printed' ? 1 : 0,
  'reprint_count': 0,
  'container': {
    'id': _id(i),
    'display_id': 'コンテナ-$i',
    'original_weight_kg': 8.5,
    'grade': {'code': 'M'},
    'variety': {'name': 'ヘイワード'},
    'sorting_result': {
      'sorted_on': '2026-09-10',
      'worker': {'display_name': '担当者'},
      'receiving_lot': {'origin_name': '農園'},
    },
  },
};

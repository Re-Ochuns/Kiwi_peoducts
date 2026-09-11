import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_inventory/csv_export/csv_export_repository.dart';
import 'package:kiwi_inventory/csv_export/supabase_csv_export_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('CSV RPCへ相関IDと条件を送り成功応答を変換する', () async {
    late Map<String, dynamic> requestBody;
    final client = SupabaseClient(
      'https://example.test',
      'test',
      httpClient: MockClient((request) async {
        expect(request.url.path, endsWith('/rpc/csv_export'));
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'ok': true,
            'correlation_id': '49000000-0000-4000-8000-000000000001',
            'data': {
              'export_id': '49000000-0000-0000-0000-000000000001',
              'filename': 'inventory_20260912T010203_49000000.csv',
              'row_count': 1,
              'csv': '\uFEFF"在庫内部ID"\r\n"32000000"\r\n',
              'generated_at': '2026-09-12T01:02:03.000Z',
            },
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final repository = SupabaseCsvExportRepository(client);

    final result = await repository.export(
      CsvExportRequest.inventory(
        search: '選果-2026',
        status: null,
        sort: 'display_id_asc',
      ),
    );

    final req = requestBody['req'] as Map<String, dynamic>;
    expect(
      (req['meta'] as Map<String, dynamic>)['correlation_id'],
      matches(_uuidV4Pattern),
    );
    expect(req['input'], {
      'dataset': 'inventory',
      'filters': {'search': '選果-2026', 'sort': 'display_id_asc'},
    });
    expect(result.rowCount, 1);
    expect(result.filename, 'inventory_20260912T010203_49000000.csv');
    await client.dispose();
  });

  test('業務エラーは自動再送せず相関IDを保持する', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://example.test',
      'test',
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'ok': false,
            'correlation_id': '49000000-0000-4000-8000-000000000002',
            'error': {
              'code': 'EXPORT_LIMIT_EXCEEDED',
              'message': '出力件数が上限を超えています。',
              'retryable': false,
            },
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final repository = SupabaseCsvExportRepository(client);

    await expectLater(
      repository.export(
        CsvExportRequest.masters(
          masterType: 'variety',
          search: '',
          active: 'all',
        ),
      ),
      throwsA(
        isA<CsvExportFailure>()
            .having((error) => error.code, 'code', 'EXPORT_LIMIT_EXCEEDED')
            .having(
              (error) => error.correlationId,
              'correlationId',
              '49000000-0000-4000-8000-000000000002',
            ),
      ),
    );
    expect(calls, 1);
    await client.dispose();
  });

  test('BOM不正な成功応答を画面用失敗へ変換する', () async {
    final client = SupabaseClient(
      'https://example.test',
      'test',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'export_id': '49000000-0000-0000-0000-000000000003',
              'filename': 'inventory_20260912T010203_49000000.csv',
              'row_count': 0,
              'csv': '"在庫内部ID"\r\n',
              'generated_at': '2026-09-12T01:02:03.000Z',
            },
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await expectLater(
      SupabaseCsvExportRepository(client)
          .export(CsvExportRequest.inventory(search: '', sort: 'updated_desc')),
      throwsA(
        isA<CsvExportFailure>().having(
          (error) => error.code,
          'code',
          'UNEXPECTED',
        ),
      ),
    );
    await client.dispose();
  });
}

final _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

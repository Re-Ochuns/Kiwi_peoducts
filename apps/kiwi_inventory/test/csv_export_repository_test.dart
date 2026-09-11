import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/csv_export/csv_export_repository.dart';

void main() {
  test('在庫要求は適用済み条件だけをRPC入力へ変換する', () {
    final request = CsvExportRequest.inventory(
      search: '  選果-2026  ',
      status: 'cold_storage',
      sort: 'updated_desc',
    );

    expect(request.input, {
      'dataset': 'inventory',
      'filters': {
        'search': '選果-2026',
        'status': 'cold_storage',
        'sort': 'updated_desc',
      },
    });
  });

  test('変更履歴要求は日付をYYYY-MM-DDに固定する', () {
    final request = CsvExportRequest.history(
      entityType: 'container',
      entityId: '32000000-0000-0000-0000-000000000001',
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 12),
    );

    expect(request.filters, {
      'entity_type': 'container',
      'entity_id': '32000000-0000-0000-0000-000000000001',
      'from_date': '2026-09-01',
      'to_date': '2026-09-12',
    });
  });

  test('CSV結果はU+FEFFを最終UTF-8バイト列EF BB BFとして保持する', () {
    final result = CsvExportResult(
      exportId: '49000000-0000-0000-0000-000000000001',
      filename: 'inventory_20260912T010203_49000000.csv',
      rowCount: 0,
      csv: '\uFEFF"在庫内部ID","在庫ID"\r\n',
      generatedAt: DateTime.utc(2026, 9, 12, 1, 2, 3),
    );

    expect(result.bytes.take(3), utf8.encode('\uFEFF'));
    expect(utf8.decode(result.bytes.sublist(3)), '"在庫内部ID","在庫ID"\r\n');
  });

  test('BOMなし・二重BOM・危険なファイル名の応答を拒否する', () {
    CsvExportResult create(String csv, String filename) => CsvExportResult(
      exportId: '49000000-0000-0000-0000-000000000001',
      filename: filename,
      rowCount: 0,
      csv: csv,
      generatedAt: DateTime.utc(2026, 9, 12),
    );

    expect(() => create('"見出し"\r\n', 'inventory.csv'), throwsFormatException);
    expect(
      () => create('\uFEFF\uFEFF"見出し"\r\n', 'inventory.csv'),
      throwsFormatException,
    );
    expect(
      () => create('\uFEFF"見出し"\r\n', '../inventory.csv'),
      throwsFormatException,
    );
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/csv_export/csv_export_dialog.dart';
import 'package:kiwi_inventory/csv_export/csv_export_repository.dart';

void main() {
  testWidgets('在庫の適用済み条件を初期表示して1回だけ出力する', (tester) async {
    final repository = _FakeCsvExportRepository();
    var downloadCalls = 0;
    Uint8List? downloadedBytes;
    await tester.pumpWidget(
      _host(
        CsvExportDialog(
          repository: repository,
          initialRequest: CsvExportRequest.inventory(
            search: '選果-2026',
            status: 'cold_storage',
            sort: 'display_id_asc',
          ),
          availableDatasets: const {CsvDataset.inventory, CsvDataset.masters},
          downloader: (bytes, filename) async {
            downloadCalls++;
            downloadedBytes = bytes;
            expect(filename, 'inventory_20260912T010203_49000000.csv');
            return true;
          },
        ),
      ),
    );

    expect(find.text('CSV出力'), findsOneWidget);
    expect(find.widgetWithText(TextField, '選果-2026'), findsOneWidget);
    expect(find.text('冷蔵保管'), findsOneWidget);
    expect(find.text('在庫ID順'), findsOneWidget);

    await tester.tap(find.byKey(const Key('csv-submit')));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.lastRequest!.input, {
      'dataset': 'inventory',
      'filters': {
        'search': '選果-2026',
        'status': 'cold_storage',
        'sort': 'display_id_asc',
      },
    });
    expect(downloadCalls, 1);
    expect(downloadedBytes!.take(3), [0xEF, 0xBB, 0xBF]);
  });

  testWidgets('処理中は条件変更と二重確定を無効にする', (tester) async {
    final completer = Completer<CsvExportResult>();
    final repository = _FakeCsvExportRepository(completer: completer);
    await tester.pumpWidget(
      _host(
        CsvExportDialog(
          repository: repository,
          initialRequest: CsvExportRequest.inventory(
            search: '',
            sort: 'updated_desc',
          ),
          availableDatasets: const {CsvDataset.inventory},
          downloader: (_, _) async => true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('csv-submit')));
    await tester.pump();

    expect(repository.calls, 1);
    expect(find.text('CSVを作成しています'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('csv-submit')),
    );
    expect(button.onPressed, isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('csv-inventory-search')))
          .enabled,
      isFalse,
    );

    completer.complete(_result);
    await tester.pumpAndSettle();
  });

  testWidgets('変更履歴の不正な日付はRPCを呼ばず日本語で示す', (tester) async {
    final repository = _FakeCsvExportRepository();
    await tester.pumpWidget(
      _host(
        CsvExportDialog(
          repository: repository,
          initialRequest: CsvExportRequest.history(),
          availableDatasets: const {CsvDataset.history},
          downloader: (_, _) async => true,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('csv-history-from')),
      '2026-02-30',
    );
    await tester.tap(find.byKey(const Key('csv-submit')));
    await tester.pump();

    expect(repository.calls, 0);
    expect(find.text('開始日に存在する日付を入力してください。'), findsOneWidget);
  });

  testWidgets('管理者以外には変更履歴の選択肢を表示しない', (tester) async {
    await tester.pumpWidget(
      _host(
        CsvExportDialog(
          repository: _FakeCsvExportRepository(),
          initialRequest: CsvExportRequest.inventory(
            search: '',
            sort: 'updated_desc',
          ),
          availableDatasets: const {CsvDataset.inventory, CsvDataset.masters},
          downloader: (_, _) async => true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('csv-dataset')));
    await tester.pumpAndSettle();

    expect(find.text('在庫'), findsWidgets);
    expect(find.text('マスター'), findsOneWidget);
    expect(find.text('変更履歴'), findsNothing);
  });

  testWidgets('対象画面幅で横方向にあふれない', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;

    for (final width in [360.0, 390.0, 430.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        _host(
          CsvExportDialog(
            repository: _FakeCsvExportRepository(),
            initialRequest: CsvExportRequest.history(),
            availableDatasets: const {CsvDataset.history},
            downloader: (_, _) async => true,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '${width.toInt()}px');
      expect(find.byKey(const Key('csv-submit')), findsOneWidget);
    }
  });
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

final _result = CsvExportResult(
  exportId: '49000000-0000-0000-0000-000000000001',
  filename: 'inventory_20260912T010203_49000000.csv',
  rowCount: 1,
  csv: '\uFEFF"在庫内部ID"\r\n"32000000"\r\n',
  generatedAt: DateTime.utc(2026, 9, 12, 1, 2, 3),
);

class _FakeCsvExportRepository implements CsvExportRepository {
  _FakeCsvExportRepository({this.completer});

  final Completer<CsvExportResult>? completer;
  int calls = 0;
  CsvExportRequest? lastRequest;

  @override
  Future<CsvExportResult> export(CsvExportRequest request) {
    calls++;
    lastRequest = request;
    return completer?.future ?? Future.value(_result);
  }
}

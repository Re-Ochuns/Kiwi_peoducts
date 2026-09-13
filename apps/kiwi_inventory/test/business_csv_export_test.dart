import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/csv_export/business_csv_button.dart';
import 'package:kiwi_inventory/csv_export/csv_export_dialog.dart';
import 'package:kiwi_inventory/csv_export/csv_export_repository.dart';
import 'package:kiwi_inventory/orders/order_management_page.dart';
import 'package:kiwi_inventory/ripening/ripening_plan_page.dart';
import 'package:kiwi_inventory/shipping/shipping_page.dart';

import 'support/fake_csv_export_repository.dart';
import 'support/fake_order_management_repository.dart';
import 'support/fake_ripening_plan_repository.dart';
import 'support/fake_shipping_repository.dart';

void main() {
  for (final dataset in [
    CsvDataset.orders,
    CsvDataset.ripening,
    CsvDataset.shipments,
  ]) {
    for (final width in [360.0, 390.0, 430.0, 1280.0]) {
      testWidgets(
        '${dataset.value} CSV at $width passes filters and downloads BOM bytes',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.reset);
          final repository = FakeCsvExportRepository();
          var downloads = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: BusinessCsvButton(
                  repository: repository,
                  request: CsvExportRequest.business(
                    dataset: dataset,
                    search: '適用済み',
                    status: dataset == CsvDataset.orders ? 'active' : 'all',
                    orderId: dataset == CsvDataset.shipments ? 'order-1' : null,
                  ),
                  downloader: (bytes, filename) async {
                    downloads++;
                    expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
                    expect(bytes[3], 34);
                    expect(filename, startsWith(dataset.value));
                    return true;
                  },
                ),
              ),
            ),
          );
          await tester.tap(find.text('CSV出力'));
          await tester.pumpAndSettle();
          expect(find.widgetWithText(TextField, '適用済み'), findsOneWidget);
          await tester.enterText(
            find.byKey(const Key('csv-business-from')),
            '2026-09-13',
          );
          await tester.enterText(
            find.byKey(const Key('csv-business-to')),
            '2026-09-14',
          );
          await tester.tap(find.byKey(const Key('csv-submit')));
          await tester.pumpAndSettle();
          expect(repository.lastRequest!.filters, {
            'search': '適用済み',
            'status': dataset == CsvDataset.orders ? 'active' : 'all',
            if (dataset == CsvDataset.shipments) 'order_id': 'order-1',
            'from_date': '2026-09-13',
            'to_date': '2026-09-14',
          });
          expect(downloads, 1);
          expect(find.text('1件のCSVの保存を開始しました。'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'order export excludes unapplied search and inherits submitted search',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderManagementPage(
              repository: FakeOrderManagementRepository(),
              csvExportRepository: FakeCsvExportRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('order-search')), '未適用');
      expect(
        tester
            .widget<BusinessCsvButton>(find.byType(BusinessCsvButton))
            .request
            .filters,
        {'status': 'active'},
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BusinessCsvButton>(find.byType(BusinessCsvButton))
            .request
            .filters,
        {'status': 'active', 'search': '未適用'},
      );
    },
  );
  testWidgets('ripening screen exposes plan and actual CSV', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RipeningPlanPage(
          repository: FakeRipeningPlanRepository(),
          csvExportRepository: FakeCsvExportRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BusinessCsvButton>(find.byType(BusinessCsvButton))
          .request
          .dataset,
      CsvDataset.ripening,
    );
  });
  testWidgets('shipping list and selected history keep distinct scopes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ShippingPage(
          repository: FakeShippingRepository(),
          initialOrderId: 'order-1',
          csvExportRepository: FakeCsvExportRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final buttons = tester
        .widgetList<BusinessCsvButton>(find.byType(BusinessCsvButton))
        .toList();
    expect(buttons.length, 2);
    expect(buttons[0].request.filters, {'status': 'all'});
    expect(buttons[1].request.filters, {
      'status': 'all',
      'order_id': 'order-1',
    });
  });
  testWidgets('business CSV failure is retryable only by explicit action', (
    tester,
  ) async {
    final repository = FakeCsvExportRepository()
      ..nextFailure = const CsvExportFailure(
        message: '上限を超えています',
        code: 'EXPORT_LIMIT_EXCEEDED',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CsvExportDialog(
            repository: repository,
            initialRequest: CsvExportRequest.business(
              dataset: CsvDataset.orders,
            ),
            availableDatasets: const {CsvDataset.orders},
            downloader: (_, _) async => true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('csv-submit')));
    await tester.pumpAndSettle();
    expect(find.text('上限を超えています'), findsOneWidget);
    expect(repository.calls, 1);
  });
  testWidgets('business CSV cannot submit twice while pending', (tester) async {
    final repository = _PendingRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CsvExportDialog(
            repository: repository,
            initialRequest: CsvExportRequest.business(
              dataset: CsvDataset.ripening,
            ),
            availableDatasets: const {CsvDataset.ripening},
            downloader: (_, _) async => true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('csv-submit')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('csv-submit')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('csv-business-search')))
          .enabled,
      false,
    );
    expect(repository.calls, 1);
    repository.pending.completeError(const CsvExportFailure(message: '通信エラー'));
    await tester.pumpAndSettle();
  });
}

class _PendingRepository implements CsvExportRepository {
  final pending = Completer<CsvExportResult>();
  int calls = 0;
  @override
  Future<CsvExportResult> export(CsvExportRequest request) {
    calls++;
    return pending.future;
  }
}

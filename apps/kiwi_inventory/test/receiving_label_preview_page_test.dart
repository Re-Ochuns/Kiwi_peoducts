import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/label/label_repository.dart';
import 'package:kiwi_inventory/label/receiving_label_preview_page.dart';
import 'package:kiwi_inventory/receiving/receiving_repository.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('白黒のA5プレビューでコンテナを目視判別できる', (tester) async {
    final repository = _ReceivingLabelRepository();
    await _pump(tester, repository);

    expect(find.text('仮ラベル確認'), findsOneWidget);
    expect(find.text('ヘイワード'), findsOneWidget);
    expect(find.text('第一農園 A区画'), findsOneWidget);
    expect(find.text('受入-2028-001'), findsOneWidget);
    expect(find.textContaining('25.50 kg'), findsOneWidget);
    expect(find.text('1 / 2'), findsNWidgets(3));
    final preview = tester.widget<Container>(
      find.byKey(const Key('receiving-label-preview')),
    );
    final decoration = preview.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.border!.top.color, Colors.black);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(repository.fetchCalls, 1);
  });

  testWidgets('前後のラベルを文字ボタンで確認できる', (tester) async {
    await _pump(tester, _ReceivingLabelRepository());

    await tester.tap(find.byKey(const Key('next-receiving-label')));
    await tester.pump();
    expect(find.text('2 / 2'), findsNWidgets(3));
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('next-receiving-label')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('結合PDFを一度だけ開き、受入登録を再実行しない', (tester) async {
    final repository = _ReceivingLabelRepository();
    var openCalls = 0;
    await _pump(
      tester,
      repository,
      opener: (_, filename) async {
        openCalls++;
        expect(filename, '受入-2028-001-receiving-labels.pdf');
        return true;
      },
    );

    await _tapVisible(
      tester,
      find.byKey(const Key('open-receiving-label-pdf')),
    );
    expect(openCalls, 1);
    expect(repository.fetchCalls, 1);
    expect(find.text('仮ラベル確認'), findsOneWidget);
  });

  testWidgets('PDF取得失敗後に同じ登録結果から再取得できる', (tester) async {
    final repository = _ReceivingLabelRepository(failures: 1);
    await _pump(tester, repository);

    expect(find.text('PDFを再取得'), findsOneWidget);
    await _tapVisible(
      tester,
      find.byKey(const Key('open-receiving-label-pdf')),
    );
    expect(repository.fetchCalls, 2);
    expect(find.text('2枚を表示して印刷'), findsOneWidget);
  });

  for (final width in [360.0, 390.0, 430.0, 1280.0]) {
    testWidgets('${width.toInt()}px幅でプレビューが崩れない', (tester) async {
      await _pump(tester, _ReceivingLabelRepository(), size: Size(width, 900));
      expect(find.byKey(const Key('receiving-label-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  _ReceivingLabelRepository repository, {
  Future<bool> Function(Uint8List, String)? opener,
  Size size = const Size(390, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: ReceivingLabelPreviewPage(
        repository: repository,
        result: _result,
        input: _input,
        varietyName: 'ヘイワード',
        sortingUrl: _sortingUrl,
        pdfOpener: opener,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

const _sortingUrl =
    'https://kiwi.example.test/sorting/e6000000-0000-4000-8000-000000000001';

const _result = ReceivingResult(
  receivingLotId: 'e6000000-0000-4000-8000-000000000001',
  displayId: '受入-2028-001',
  receivedDate: '2028-05-01',
  sortingDueDate: '2028-05-31',
  version: 1,
  idempotentReplay: false,
);

const _input = ReceivingInput(
  sourceType: ReceivingSourceType.harvest,
  receivedDate: '2028-05-01',
  orchardId: 'orchard-1',
  plotId: 'plot-1',
  treeId: 'tree-1',
  originName: '第一農園 A区画',
  varietyId: 'variety-1',
  totalWeightKg: 25.5,
  containerCount: 2,
  workerId: 'worker-1',
);

class _ReceivingLabelRepository implements LabelRepository {
  _ReceivingLabelRepository({this.failures = 0});

  int failures;
  int fetchCalls = 0;

  @override
  Future<LabelPdf> fetchReceivingBatchPdf({
    required String receivingLotId,
    required int expectedPageCount,
  }) async {
    fetchCalls++;
    expect(receivingLotId, _result.receivingLotId);
    expect(expectedPageCount, 2);
    if (failures > 0) {
      failures--;
      throw const LabelFailure(message: 'PDFを取得できませんでした。');
    }
    return LabelPdf(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'receiving-labels.pdf',
    );
  }

  @override
  Future<LabelPdf> fetchSortingBatchPdf({
    required String sortingResultId,
    required int expectedPageCount,
  }) => throw UnimplementedError();

  @override
  Future<LabelLoadData> load({bool completed = false, LabelCursor? after}) =>
      throw UnimplementedError();

  @override
  Future<LabelPdf> fetchPdf({required String containerId}) =>
      throw UnimplementedError();

  @override
  Future<LabelActionResult> markPrinted({
    required String labelJobId,
    required String workerId,
    required int copies,
    required String idempotencyKey,
    String? locationId,
  }) => throw UnimplementedError();

  @override
  Future<LabelActionResult> markHandwritten({
    required String labelJobId,
    required String workerId,
    required String idempotencyKey,
    String? notes,
    String? locationId,
  }) => throw UnimplementedError();

  @override
  Future<LabelActionResult> reprint({
    required String labelJobId,
    required String workerId,
    required String reason,
    required int copies,
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<LabelBatchActionResult> markSortingBatchPrinted({
    required String sortingResultId,
    required String workerId,
    required String idempotencyKey,
    String? locationId,
  }) => throw UnimplementedError();
}

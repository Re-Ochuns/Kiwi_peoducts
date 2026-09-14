import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/label/label_repository.dart';
import 'package:kiwi_inventory/label/sorting_label_batch_page.dart';
import 'package:kiwi_inventory/sorting/sorting_repository.dart';

void main() {
  testWidgets('白黒のA5プレビューで対象を目視判別できる', (tester) async {
    final repository = _BatchLabelRepository();
    await _pump(tester, repository);

    expect(find.text('ラベル一括確認'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('ヘイワード'), findsOneWidget);
    expect(find.text('8.50 kg'), findsOneWidget);
    expect(find.text('選果-2026-001-1'), findsOneWidget);
    expect(find.text('第一圃場 A区画'), findsOneWidget);

    final preview = tester.widget<Container>(
      find.byKey(const Key('sorting-label-preview')),
    );
    final decoration = preview.decoration! as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.border!.top.color, Colors.black);
    expect(repository.fetchCalls, 1);
  });

  testWidgets('等級順で並べて前後のラベルを文字ボタンで確認できる', (tester) async {
    await _pump(tester, _BatchLabelRepository());

    expect(find.text('1 / 2'), findsNWidgets(2));
    expect(find.text('選果-2026-001-1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('next-label')));
    await tester.pump();

    expect(find.text('L'), findsOneWidget);
    expect(find.text('選果-2026-001-2'), findsOneWidget);
    expect(find.text('2 / 2'), findsNWidgets(2));
  });

  testWidgets('PDFを一度開き、確認後に全件を一括記録する', (tester) async {
    final repository = _BatchLabelRepository();
    var openCalls = 0;
    await _pump(
      tester,
      repository,
      opener: (_, _) async {
        openCalls++;
        return true;
      },
    );

    await _tapVisible(tester, find.byKey(const Key('open-sorting-batch-pdf')));
    expect(openCalls, 1);
    expect(find.text('印刷結果を確認'), findsOneWidget);
    expect(repository.markCalls, 0);

    await tester.tap(find.byKey(const Key('confirm-sorting-batch-printed')));
    await tester.pumpAndSettle();

    expect(repository.markCalls, 1);
    expect(repository.lastSortingResultId, 'sorting-1');
    expect(repository.lastWorkerId, 'worker-1');
    expect(find.text('一括印刷を記録しました'), findsOneWidget);
    expect(find.text('2枚すべてを印刷済みにしました。'), findsOneWidget);
  });

  testWidgets('印刷できなかった場合は状態を更新しない', (tester) async {
    final repository = _BatchLabelRepository();
    await _pump(tester, repository, opener: (_, _) async => true);

    await _tapVisible(tester, find.byKey(const Key('open-sorting-batch-pdf')));
    await tester.tap(find.text('印刷できなかった'));
    await tester.pumpAndSettle();

    expect(repository.markCalls, 0);
    expect(find.text('ラベル一括確認'), findsOneWidget);
  });

  for (final width in [360.0, 390.0, 430.0, 1280.0]) {
    testWidgets('${width.toInt()}px幅でプレビューが崩れない', (tester) async {
      await _pump(tester, _BatchLabelRepository(), size: Size(width, 844));

      expect(find.byKey(const Key('sorting-label-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  _BatchLabelRepository repository, {
  Future<bool> Function(Uint8List, String)? opener,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: SortingLabelBatchPage(
        repository: repository,
        result: _result,
        lot: _lot,
        grades: _grades,
        workerId: 'worker-1',
        workerName: '岡本',
        sortedOn: DateTime(2026, 9, 15),
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

const _grades = [
  SortingGrade(id: 'grade-m', code: 'M', displayOrder: 1),
  SortingGrade(id: 'grade-l', code: 'L', displayOrder: 2),
];

final _lot = SortingLot(
  id: 'lot-1',
  displayId: '受入-2026-001',
  sourceType: 'harvest',
  receivedOn: DateTime(2026, 9, 14),
  originName: '第一圃場 A区画',
  varietyName: 'ヘイワード',
  totalWeightHundredths: 1800,
  sortingDueOn: DateTime(2026, 9, 20),
  version: 1,
);

const _result = SortingResult(
  sortingResultId: 'sorting-1',
  displayId: '選果-2026-001',
  inputWeightHundredths: 1800,
  outputWeightHundredths: 1800,
  lossWeightHundredths: 0,
  containers: [
    SortingResultContainer(
      containerId: 'container-2',
      displayId: '選果-2026-001-2',
      gradeId: 'grade-l',
      weightHundredths: 950,
    ),
    SortingResultContainer(
      containerId: 'container-1',
      displayId: '選果-2026-001-1',
      gradeId: 'grade-m',
      weightHundredths: 850,
    ),
  ],
  idempotentReplay: false,
);

class _BatchLabelRepository implements LabelRepository {
  int fetchCalls = 0;
  int markCalls = 0;
  String? lastSortingResultId;
  String? lastWorkerId;

  @override
  Future<LabelPdf> fetchSortingBatchPdf({
    required String sortingResultId,
    required int expectedPageCount,
  }) async {
    fetchCalls++;
    expect(expectedPageCount, 2);
    return LabelPdf(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: '$sortingResultId-labels.pdf',
    );
  }

  @override
  Future<LabelBatchActionResult> markSortingBatchPrinted({
    required String sortingResultId,
    required String workerId,
    required String idempotencyKey,
    String? locationId,
  }) async {
    markCalls++;
    lastSortingResultId = sortingResultId;
    lastWorkerId = workerId;
    return LabelBatchActionResult(
      sortingResultId: sortingResultId,
      completedCount: 2,
      idempotentReplay: false,
    );
  }

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
}

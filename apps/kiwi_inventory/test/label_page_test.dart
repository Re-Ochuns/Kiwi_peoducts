import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/label/label_page.dart';
import 'package:kiwi_inventory/label/label_repository.dart';
import 'package:kiwi_inventory/main.dart';

void main() {
  testWidgets('追熟ラベルは追熟情報を表示し手書き確認にも引き継ぐ', (tester) async {
    final job = LabelJob(
      id: 'ripening-job',
      containerId: 'ripening-container',
      containerDisplayId: '追熟-001',
      status: LabelJobStatus.notPrinted,
      requiredCopies: 1,
      printedCopies: 0,
      reprintCount: 0,
      originName: '農園A・農園B',
      varietyName: 'ヘイワード',
      gradeCode: 'M',
      weightHundredths: 850,
      sortedOn: null,
      workerName: '',
      ripeningFields: const {
        'ラベル種別': '追熟',
        '追熟場所': '追熟室',
        '注入日時': '2026/09/14 09:00',
        '抜き予定': '2026/09/15 09:00',
        '追熟完了予定': '2026/09/20 09:00',
        '割当': '予備 8.50 kg',
      },
    );
    final repository = FakeLabelRepository();
    await _pumpDetail(tester, repository, job);
    expect(find.text('選果日'), findsNothing);
    expect(find.text('注入日時'), findsOneWidget);
    expect(find.text('予備 8.50 kg'), findsOneWidget);
    await _selectWorker(tester);
    await tester.ensureVisible(find.byKey(const Key('handwritten-label')));
    await tester.tap(find.byKey(const Key('handwritten-label')));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('追熟-001')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('予備 8.50 kg')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('選果担当者')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  group('ラベル対象', () {
    testWidgets('続きを追加し表示切替でカーソルをリセットする', (tester) async {
      final repository = PagedLabelRepository();
      await _pumpTargets(tester, repository);
      expect(find.text(testPendingJob.containerDisplayId), findsOneWidget);
      await tester.tap(find.text('さらに読み込む'));
      await tester.pumpAndSettle();
      expect(find.text('選果-2026-099-1'), findsOneWidget);
      expect(find.text(testPendingJob.containerDisplayId), findsOneWidget);
      expect(find.text('さらに読み込む'), findsNothing);
      expect(repository.cursors.last, isNotNull);
      await tester.tap(find.byKey(const Key('label-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('対応済み').last);
      await tester.pumpAndSettle();
      expect(repository.cursors.last, isNull);
      expect(repository.filters.last, isTrue);
      expect(find.text(testPrintedJob.containerDisplayId), findsOneWidget);
      expect(find.text(testPendingJob.containerDisplayId), findsNothing);
    });

    testWidgets('作業者ホームから開ける', (tester) async {
      final repository = FakeLabelRepository();
      await _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: WorkerHomePage(labelRepository: repository),
        ),
      );

      await tester.tap(find.text('ラベル発行'));
      await tester.pumpAndSettle();

      expect(find.text('ラベル発行'), findsOneWidget);
      expect(find.text(testPendingJob.containerDisplayId), findsOneWidget);
      expect(repository.loadCalls, 1);
    });

    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('${width.toInt()}px幅で横方向に崩れない', (tester) async {
        await _setSurface(tester, Size(width, 844));
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: LabelTargetPage(repository: FakeLabelRepository()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(testPendingJob.containerDisplayId), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('一覧と確認画面の選択欄に装飾矢印を表示しない', (tester) async {
      await _pumpTargets(tester, FakeLabelRepository());

      expect(find.text('↓'), findsNothing);
      await tester.tap(find.text('詳細を見る →'));
      await tester.pumpAndSettle();
      expect(find.text('↓'), findsNothing);
    });

    testWidgets('一部印刷の枚数と状態を表示する', (tester) async {
      final partial = _job(
        status: LabelJobStatus.partiallyPrinted,
        printedCopies: 1,
        requiredCopies: 2,
      );
      await _pumpTargets(
        tester,
        FakeLabelRepository(data: _loadData(jobs: [partial])),
      );

      expect(find.text('一部印刷'), findsOneWidget);
      await tester.tap(find.text('詳細を見る →'));
      await tester.pumpAndSettle();
      expect(find.text('印刷 1/2枚'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('label-copies')))
            .controller!
            .text,
        '1',
      );
    });

    testWidgets('対応済みへ切り替えて再印刷対象を表示する', (tester) async {
      await _pumpTargets(
        tester,
        FakeLabelRepository(
          data: _loadData(jobs: [testPendingJob, testPrintedJob]),
        ),
      );

      await tester.tap(find.byKey(const Key('label-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('対応済み').last);
      await tester.pumpAndSettle();

      expect(find.text(testPrintedJob.containerDisplayId), findsOneWidget);
      expect(find.text(testPendingJob.containerDisplayId), findsNothing);
      expect(find.text('印刷済み'), findsOneWidget);
    });

    testWidgets('手書き対応済みは完了状態として操作を表示しない', (tester) async {
      final handwritten = _job(
        status: LabelJobStatus.handwritten,
        displayId: '選果-2026-003-1',
      );
      await _pumpTargets(
        tester,
        FakeLabelRepository(data: _loadData(jobs: [handwritten])),
      );
      await tester.tap(find.byKey(const Key('label-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('対応済み').last);
      await tester.pumpAndSettle();

      expect(find.text('手書き対応済み'), findsOneWidget);
      await tester.tap(find.text('詳細を見る →'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-label-pdf')), findsNothing);
      expect(find.byKey(const Key('handwritten-label')), findsNothing);
    });

    testWidgets('読み込み失敗から再試行できる', (tester) async {
      final repository = FakeLabelRepository(loadFailures: 1);
      await _pumpTargets(tester, repository);

      expect(find.text('ラベル対象を読み込めませんでした'), findsOneWidget);
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      expect(find.text(testPendingJob.containerDisplayId), findsOneWidget);
      expect(repository.loadCalls, 2);
    });
  });

  group('ラベル対応', () {
    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('${width.toInt()}px幅で確認画面が横方向に崩れない', (tester) async {
        await _pumpDetail(
          tester,
          FakeLabelRepository(),
          testPendingJob,
          size: Size(width, 900),
        );

        expect(find.text('ラベル確認'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('ラベル記載内容を確認できる', (tester) async {
      await _pumpDetail(tester, FakeLabelRepository(), testPendingJob);

      expect(find.text('ラベル記載内容'), findsOneWidget);
      expect(find.text('第一圃場 A区画'), findsOneWidget);
      expect(find.text('ヘイワード'), findsOneWidget);
      expect(find.text('M'), findsOneWidget);
      expect(find.text('8.50 kg'), findsOneWidget);
      expect(find.text('2026-09-10'), findsOneWidget);
      expect(find.text('作業者A'), findsOneWidget);
    });

    testWidgets('PDF取得失敗では状態を更新せず再試行できる', (tester) async {
      final repository = FakeLabelRepository(pdfFailures: 1);
      await _pumpDetail(
        tester,
        repository,
        testPendingJob,
        pdfOpener: (_, _) async => true,
      );
      expect(find.textContaining('PDFを取得できませんでした'), findsOneWidget);
      expect(repository.markPrintedCalls, 0);
      await _selectWorker(tester);

      await tester.tap(find.byKey(const Key('open-label-pdf')));
      await tester.pumpAndSettle();
      expect(find.text('PDFを表示して印刷'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-label-pdf')));
      await tester.pumpAndSettle();
      expect(find.text('印刷結果を確認'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-label-printed')));
      await tester.pumpAndSettle();
      expect(repository.markPrintedCalls, 1);
      expect(repository.pdfCalls, 2);
    });

    testWidgets('印刷中断時は印刷済みを記録しない', (tester) async {
      final repository = FakeLabelRepository();
      await _pumpDetail(
        tester,
        repository,
        testPendingJob,
        pdfOpener: (_, _) async => false,
      );
      await _selectWorker(tester);

      await tester.tap(find.byKey(const Key('open-label-pdf')));
      await tester.pumpAndSettle();

      expect(find.textContaining('PDFを開けませんでした'), findsOneWidget);
      expect(repository.markPrintedCalls, 0);
    });

    testWidgets('印刷できた確認後だけ印刷枚数を記録する', (tester) async {
      final repository = FakeLabelRepository();
      await _pumpDetail(
        tester,
        repository,
        testPendingJob,
        pdfOpener: (_, _) async => true,
      );
      await _selectWorker(tester);

      await tester.tap(find.byKey(const Key('open-label-pdf')));
      await tester.pumpAndSettle();
      expect(repository.markPrintedCalls, 0);
      await tester.tap(find.byKey(const Key('confirm-label-printed')));
      await tester.pumpAndSettle();

      expect(repository.markPrintedCalls, 1);
      expect(repository.printedCopies.single, 1);
      expect(find.text('印刷済みを記録しました'), findsOneWidget);
    });

    testWidgets('再印刷理由を必須にして履歴用の値を送る', (tester) async {
      final repository = FakeLabelRepository();
      await _pumpDetail(
        tester,
        repository,
        testPrintedJob,
        pdfOpener: (_, _) async => true,
      );
      await _selectWorker(tester);

      await tester.tap(find.byKey(const Key('open-label-pdf')));
      await tester.pump();
      expect(find.text('再印刷理由を入力してください。'), findsOneWidget);
      expect(repository.pdfCalls, 1);

      await tester.enterText(
        find.byKey(const Key('reprint-reason')),
        'ラベル汚損のため',
      );
      await tester.tap(find.byKey(const Key('open-label-pdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-label-printed')));
      await tester.pumpAndSettle();

      expect(repository.reprintCalls, 1);
      expect(repository.reprintReasons.single, 'ラベル汚損のため');
      expect(find.text('再印刷を記録しました'), findsOneWidget);
    });

    testWidgets('応答消失後はPDFを開かず同じキーで記録だけ再確認する', (tester) async {
      final repository = FakeLabelRepository(loseReprintResponse: true);
      var opened = 0;
      await _pumpDetail(
        tester,
        repository,
        testPrintedJob,
        pdfOpener: (_, _) async {
          opened++;
          return true;
        },
      );
      await _selectWorker(tester);
      await tester.enterText(find.byKey(const Key('reprint-reason')), '汚損');
      await tester.ensureVisible(find.byKey(const Key('open-label-pdf')));
      await tester.tap(find.byKey(const Key('open-label-pdf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-label-printed')));
      await tester.pumpAndSettle();
      expect(find.text('記録結果が未確認です'), findsOneWidget);
      expect(find.byKey(const Key('label-copies')), findsNothing);
      expect(find.byKey(const Key('open-label-pdf')), findsNothing);
      final context = tester.element(find.byType(LabelDetailPage));
      await Navigator.of(context).maybePop();
      await tester.pumpAndSettle();
      expect(find.text('記録結果が未確認です'), findsOneWidget);
      await tester.tap(find.text('記録結果を再確認'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(repository.reprintCalls, 2);
      expect(repository.reprintKeys.toSet().length, 1);
      expect(repository.reprintWrites, 1);
      expect(find.text('再印刷を記録しました'), findsOneWidget);
    });

    testWidgets('手書き必須項目を確認して対応を記録する', (tester) async {
      final repository = FakeLabelRepository();
      await _pumpDetail(tester, repository, testPendingJob);
      await _selectWorker(tester);

      await tester.ensureVisible(find.byKey(const Key('handwritten-label')));
      await tester.tap(find.byKey(const Key('handwritten-label')));
      await tester.pumpAndSettle();

      expect(find.text('手書き内容を確認'), findsOneWidget);
      expect(find.text(testPendingJob.containerDisplayId), findsWidgets);
      expect(find.text('産地・区画'), findsWidgets);
      expect(find.text('正味重量'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-handwritten-label')));
      await tester.pumpAndSettle();

      expect(repository.handwrittenCalls, 1);
      expect(find.text('手書き対応を記録しました'), findsOneWidget);
    });
  });
}

Future<void> _pumpTargets(
  WidgetTester tester,
  LabelRepository repository,
) async {
  await _setSurface(tester, const Size(390, 844));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: LabelTargetPage(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetail(
  WidgetTester tester,
  LabelRepository repository,
  LabelJob job, {
  Future<bool> Function(Uint8List, String)? pdfOpener,
  Size size = const Size(390, 900),
}) async {
  await _setSurface(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: LabelDetailPage(
        repository: repository,
        job: job,
        workers: testLoadData.workers,
        locations: testLoadData.locations,
        pdfOpener: pdfOpener,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectWorker(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('label-worker')));
  await tester.tap(find.byKey(const Key('label-worker')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('worker-01　作業者A').last);
  await tester.pumpAndSettle();
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

LabelJob _job({
  LabelJobStatus status = LabelJobStatus.notPrinted,
  int printedCopies = 0,
  int requiredCopies = 1,
  String displayId = '選果-2026-001-1',
}) => LabelJob(
  id: 'label-job-$displayId',
  containerId: 'container-$displayId',
  containerDisplayId: displayId,
  status: status,
  requiredCopies: requiredCopies,
  printedCopies: printedCopies,
  reprintCount: status == LabelJobStatus.printed ? 1 : 0,
  originName: '第一圃場 A区画',
  varietyName: 'ヘイワード',
  gradeCode: 'M',
  weightHundredths: 850,
  sortedOn: DateTime(2026, 9, 10),
  workerName: '作業者A',
);

final testPendingJob = _job();
final testPrintedJob = _job(
  status: LabelJobStatus.printed,
  printedCopies: 1,
  displayId: '選果-2026-002-1',
);

LabelLoadData _loadData({List<LabelJob>? jobs}) => LabelLoadData(
  jobs: jobs ?? [testPendingJob],
  workers: const [LabelOption(id: 'worker-1', label: 'worker-01　作業者A')],
  locations: const [LabelOption(id: 'location-1', label: 'cold-01　第一冷蔵庫')],
);

final testLoadData = _loadData();

class FakeLabelRepository implements LabelRepository {
  FakeLabelRepository({
    LabelLoadData? data,
    this.loadFailures = 0,
    this.pdfFailures = 0,
    this.actionFailure,
    this.loseReprintResponse = false,
  }) : data = data ?? testLoadData;

  final LabelLoadData data;
  int loadFailures;
  int pdfFailures;
  final LabelFailure? actionFailure;
  final bool loseReprintResponse;
  final List<String> reprintKeys = [];
  int reprintWrites = 0;
  int loadCalls = 0;
  int pdfCalls = 0;
  int markPrintedCalls = 0;
  int handwrittenCalls = 0;
  int reprintCalls = 0;
  final List<int> printedCopies = [];
  final List<String> reprintReasons = [];

  @override
  Future<LabelLoadData> load({
    bool completed = false,
    LabelCursor? after,
  }) async {
    loadCalls++;
    if (loadFailures > 0) {
      loadFailures--;
      throw const LabelFailure(message: '通信に失敗しました。', retryable: true);
    }
    return data;
  }

  @override
  Future<LabelPdf> fetchPdf({required String containerId}) async {
    pdfCalls++;
    if (pdfFailures > 0) {
      pdfFailures--;
      throw const LabelFailure(message: 'PDFを取得できませんでした。', retryable: true);
    }
    return LabelPdf(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'label.pdf',
    );
  }

  @override
  Future<LabelPdf> fetchSortingBatchPdf({
    required String sortingResultId,
    required int expectedPageCount,
  }) => fetchPdf(containerId: sortingResultId);

  @override
  Future<LabelActionResult> markPrinted({
    required String labelJobId,
    required String workerId,
    required int copies,
    required String idempotencyKey,
    String? locationId,
  }) async {
    markPrintedCalls++;
    printedCopies.add(copies);
    if (actionFailure != null) throw actionFailure!;
    return LabelActionResult(
      labelJobId: labelJobId,
      status: LabelJobStatus.printed,
      printedCopies: copies,
      requiredCopies: copies,
      reprintCount: 0,
    );
  }

  @override
  Future<LabelActionResult> markHandwritten({
    required String labelJobId,
    required String workerId,
    required String idempotencyKey,
    String? notes,
    String? locationId,
  }) async {
    handwrittenCalls++;
    if (actionFailure != null) throw actionFailure!;
    return LabelActionResult(
      labelJobId: labelJobId,
      status: LabelJobStatus.handwritten,
      printedCopies: 0,
      requiredCopies: 1,
      reprintCount: 0,
    );
  }

  @override
  Future<LabelActionResult> reprint({
    required String labelJobId,
    required String workerId,
    required String reason,
    required int copies,
    required String idempotencyKey,
  }) async {
    reprintCalls++;
    if (!reprintKeys.contains(idempotencyKey)) reprintWrites++;
    reprintKeys.add(idempotencyKey);
    if (loseReprintResponse && reprintCalls == 1) {
      throw const LabelFailure(message: '応答消失', retryable: true);
    }
    reprintReasons.add(reason);
    if (actionFailure != null) throw actionFailure!;
    return LabelActionResult(
      labelJobId: labelJobId,
      status: LabelJobStatus.printed,
      printedCopies: 1 + copies,
      requiredCopies: 1,
      reprintCount: 2,
    );
  }

  @override
  Future<LabelBatchActionResult> markSortingBatchPrinted({
    required String sortingResultId,
    required String workerId,
    required String idempotencyKey,
    String? locationId,
  }) async => LabelBatchActionResult(
    sortingResultId: sortingResultId,
    completedCount: data.jobs.length,
    idempotentReplay: false,
  );
}

class PagedLabelRepository extends FakeLabelRepository {
  final List<LabelCursor?> cursors = [];
  final List<bool> filters = [];

  @override
  Future<LabelLoadData> load({
    bool completed = false,
    LabelCursor? after,
  }) async {
    cursors.add(after);
    filters.add(completed);
    return LabelLoadData(
      jobs: completed
          ? [testPrintedJob]
          : after == null
          ? [testPendingJob]
          : [_job(displayId: '選果-2026-099-1')],
      workers: testLoadData.workers,
      locations: testLoadData.locations,
      nextCursor: !completed && after == null
          ? const LabelCursor(createdAt: '2026-09-10T00:00:00Z', id: 'first')
          : null,
    );
  }
}

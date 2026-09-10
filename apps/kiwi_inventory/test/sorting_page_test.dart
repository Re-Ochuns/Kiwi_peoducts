import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/sorting/sorting_page.dart';
import 'package:kiwi_inventory/sorting/sorting_repository.dart';

void main() {
  group('選果対象', () {
    testWidgets('作業者ホームの選果登録から開ける', (tester) async {
      final repository = FakeSortingRepository();
      await _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: WorkerHomePage(
            sortingRepository: repository,
            currentDate: DateTime(2026, 9, 10),
          ),
        ),
      );

      await tester.tap(find.text('選果登録').first);
      await tester.pumpAndSettle();

      expect(find.text('選果対象'), findsOneWidget);
      expect(repository.loadCalls, 1);
    });

    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('${width.toInt()}px幅で横方向に崩れない', (tester) async {
        await _pumpTargets(
          tester,
          FakeSortingRepository(),
          size: Size(width, 844),
        );

        expect(find.text('選果対象'), findsOneWidget);
        expect(find.text('受入-2026-001'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('ID・品種・産地で絞り込み、対象を読み上げられる', (tester) async {
      final repository = FakeSortingRepository(
        data: testLoadData(
          lots: [
            testLot,
            SortingLot(
              id: 'lot-2',
              displayId: '受入-2026-002',
              sourceType: 'purchase',
              receivedOn: DateTime(2026, 9, 2),
              originName: '熊本県',
              varietyName: '香緑',
              totalWeightHundredths: 850,
              sortingDueOn: DateTime(2026, 9, 20),
              version: 1,
            ),
          ],
        ),
      );
      await _pumpTargets(tester, repository);

      expect(find.bySemanticsLabel('受入-2026-001の選果入力へ進む'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '香緑');
      await tester.pump();

      expect(find.text('受入-2026-001'), findsNothing);
      expect(find.text('受入-2026-002'), findsOneWidget);
    });

    testWidgets('空状態を表示する', (tester) async {
      await _pumpTargets(
        tester,
        FakeSortingRepository(data: testLoadData(lots: const [])),
      );

      expect(find.text('選果対象はありません'), findsOneWidget);
    });

    testWidgets('取得失敗から再試行できる', (tester) async {
      final repository = FakeSortingRepository(loadFailures: 1);
      await _pumpTargets(tester, repository);

      expect(find.text('選果対象を読み込めませんでした'), findsOneWidget);
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      expect(find.text('受入-2026-001'), findsOneWidget);
      expect(repository.loadCalls, 2);
    });
  });

  group('選果入力', () {
    testWidgets('等級ごとの入力と合計・ロスを同時に確認できる', (tester) async {
      await _setSurface(tester, const Size(390, 900));
      await _openInput(tester, FakeSortingRepository());

      await _selectWorker(tester);
      await _tapVisible(tester, find.byKey(const Key('add-container')));
      await tester.ensureVisible(find.byKey(const Key('weight-1')));
      await tester.enterText(find.byKey(const Key('weight-1')), '8.50');
      await tester.pump();

      expect(find.text('8.50 kg'), findsOneWidget);
      expect(find.text('1個・8.50 kg'), findsOneWidget);
      expect(find.text('1.50 kg'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('confirm-sorting')),
      );
      expect(button.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('選択中の等級に属するコンテナだけを表示する', (tester) async {
      await _openInput(tester, FakeSortingRepository());
      await _tapVisible(tester, find.byKey(const Key('add-container')));
      expect(find.byKey(const Key('weight-1')), findsOneWidget);

      await _tapVisible(tester, find.text('L').first);
      expect(find.text('Lのコンテナ'), findsOneWidget);
      expect(find.byKey(const Key('weight-1')), findsNothing);
    });

    testWidgets('元重量を超えると理由を表示して確認を禁止する', (tester) async {
      await _openInput(tester, FakeSortingRepository());
      await _selectWorker(tester);
      await _tapVisible(tester, find.byKey(const Key('add-container')));
      await tester.ensureVisible(find.byKey(const Key('weight-1')));
      await tester.enterText(find.byKey(const Key('weight-1')), '10.01');
      await tester.pump();

      expect(find.text('選果後重量が元重量を0.01 kg超えています。'), findsOneWidget);
      expect(find.text('元重量から超過'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('confirm-sorting')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('確認後に確定し、生成結果を表示する', (tester) async {
      final repository = FakeSortingRepository();
      await _openInput(tester, repository);
      await _completeForm(tester);

      await tester.tap(find.byKey(const Key('confirm-sorting')));
      await tester.pumpAndSettle();
      expect(find.text('選果内容を確認'), findsOneWidget);
      expect(find.text('選果を確定'), findsOneWidget);

      await tester.tap(find.byKey(const Key('submit-sorting')));
      await tester.pumpAndSettle();

      expect(repository.confirmCalls, 1);
      expect(find.text('選果を確定しました'), findsOneWidget);
      expect(find.textContaining('選果-2026-001-1'), findsOneWidget);
      expect(repository.lastInput!.containers.single.weightHundredths, 850);
    });

    testWidgets('送信中は二重操作を受け付けない', (tester) async {
      final completer = Completer<SortingResult>();
      final repository = FakeSortingRepository(confirmCompleter: completer);
      await _openInput(tester, repository);
      await _completeForm(tester);
      await tester.tap(find.byKey(const Key('confirm-sorting')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit-sorting')));
      await tester.pump();

      expect(find.text('確定しています'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('confirm-sorting')),
      );
      expect(button.onPressed, isNull);
      expect(repository.confirmCalls, 1);

      completer.complete(testResult);
      await tester.pumpAndSettle();
    });

    testWidgets('競合時は最新の対象一覧を再読込する', (tester) async {
      final repository = FakeSortingRepository(
        confirmFailure: const SortingFailure(
          message: 'このロットはすでに選果が確定されています。',
          code: 'CONFLICT_STALE',
        ),
      );
      await _openInput(tester, repository);
      await _completeForm(tester);
      await tester.tap(find.byKey(const Key('confirm-sorting')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit-sorting')));
      await tester.pumpAndSettle();

      expect(find.text('最新の状態を確認してください'), findsOneWidget);
      await tester.tap(find.text('選果対象を再読込'));
      await tester.pumpAndSettle();

      expect(find.text('選果対象'), findsOneWidget);
      expect(repository.loadCalls, 2);
    });

    testWidgets('失敗後の再送では同じ冪等性キーを使う', (tester) async {
      final repository = FakeSortingRepository(confirmFailures: 1);
      await _openInput(tester, repository);
      await _completeForm(tester);

      await _submitFromDialog(tester);
      expect(find.textContaining('通信状況を確認'), findsOneWidget);
      final firstKey = repository.idempotencyKeys.single;

      await _submitFromDialog(tester);
      expect(repository.confirmCalls, 2);
      expect(repository.idempotencyKeys.last, firstKey);
    });
  });
}

Future<void> _pumpTargets(
  WidgetTester tester,
  FakeSortingRepository repository, {
  Size size = const Size(390, 844),
}) async {
  await _setSurface(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: SortingTargetPage(
        repository: repository,
        currentDate: DateTime(2026, 9, 10),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openInput(
  WidgetTester tester,
  FakeSortingRepository repository,
) async {
  await _pumpTargets(tester, repository);
  await tester.tap(find.text('受入-2026-001'));
  await tester.pumpAndSettle();
  expect(find.text('選果入力'), findsOneWidget);
}

Future<void> _selectWorker(WidgetTester tester) async {
  await _tapVisible(tester, find.byKey(const Key('sorting-worker')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('W01　岡本').last);
  await tester.pumpAndSettle();
}

Future<void> _completeForm(WidgetTester tester) async {
  await _selectWorker(tester);
  await _tapVisible(tester, find.byKey(const Key('add-container')));
  await tester.ensureVisible(find.byKey(const Key('weight-1')));
  await tester.enterText(find.byKey(const Key('weight-1')), '8.50');
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _submitFromDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('confirm-sorting')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('submit-sorting')));
  await tester.pumpAndSettle();
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

SortingLoadData testLoadData({List<SortingLot>? lots}) => SortingLoadData(
  lots: lots ?? [testLot],
  grades: const [
    SortingGrade(id: 'grade-m', code: 'M', displayOrder: 1),
    SortingGrade(id: 'grade-l', code: 'L', displayOrder: 2),
  ],
  workers: const [
    SortingWorker(id: 'worker-1', code: 'W01', displayName: '岡本'),
  ],
);

final testLot = SortingLot(
  id: 'lot-1',
  displayId: '受入-2026-001',
  sourceType: 'harvest',
  receivedOn: DateTime(2026, 9, 1),
  originName: '第一圃場 A区画',
  varietyName: 'ヘイワード',
  totalWeightHundredths: 1000,
  sortingDueOn: DateTime(2026, 9, 9),
  version: 2,
);

const testResult = SortingResult(
  sortingResultId: 'sorting-1',
  displayId: '選果-2026-001',
  inputWeightHundredths: 1000,
  outputWeightHundredths: 850,
  lossWeightHundredths: 150,
  containers: [
    SortingResultContainer(
      containerId: 'container-1',
      displayId: '選果-2026-001-1',
      gradeId: 'grade-m',
      weightHundredths: 850,
    ),
  ],
  idempotentReplay: false,
);

class FakeSortingRepository implements SortingRepository {
  FakeSortingRepository({
    SortingLoadData? data,
    this.loadFailures = 0,
    this.confirmFailure,
    this.confirmFailures = 0,
    this.confirmCompleter,
  }) : data = data ?? testLoadData();

  final SortingLoadData data;
  int loadFailures;
  final SortingFailure? confirmFailure;
  int confirmFailures;
  final Completer<SortingResult>? confirmCompleter;
  int loadCalls = 0;
  int confirmCalls = 0;
  SortingInput? lastInput;
  final List<String> idempotencyKeys = [];

  @override
  Future<SortingLoadData> load() async {
    loadCalls++;
    if (loadFailures > 0) {
      loadFailures--;
      throw const SortingFailure(message: '通信状況を確認してください。');
    }
    return data;
  }

  @override
  Future<SortingResult> confirm({
    required SortingInput input,
    required String idempotencyKey,
  }) async {
    confirmCalls++;
    lastInput = input;
    idempotencyKeys.add(idempotencyKey);
    if (confirmFailures > 0) {
      confirmFailures--;
      throw const SortingFailure(message: '通信状況を確認して再試行してください。');
    }
    if (confirmFailure != null) throw confirmFailure!;
    if (confirmCompleter != null) return confirmCompleter!.future;
    return testResult;
  }
}

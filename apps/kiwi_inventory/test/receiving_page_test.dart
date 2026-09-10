import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/receiving/receiving_page.dart';
import 'package:kiwi_inventory/receiving/receiving_repository.dart';

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('${width.toInt()}px幅で横方向にあふれない', (tester) async {
      await _pumpPage(tester, FakeReceivingRepository(), width: width);
      expect(find.text('収穫・仕入れ登録'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('収穫と仕入れで必要な入力項目を切り替える', (tester) async {
    await _pumpPage(tester, FakeReceivingRepository());

    expect(find.text('農園'), findsOneWidget);
    expect(find.text('樹体'), findsOneWidget);
    expect(find.text('仕入先管理ID'), findsNothing);

    await tester.tap(find.text('仕入れ'));
    await tester.pump();

    expect(find.text('農園'), findsNothing);
    expect(find.text('仕入先'), findsOneWidget);
    expect(find.text('仕入先管理ID'), findsOneWidget);
    expect(find.text('産地・区画'), findsOneWidget);
  });

  testWidgets('未入力の項目を確定前に表示する', (tester) async {
    await _pumpPage(tester, FakeReceivingRepository());

    await tester.ensureVisible(find.text('入力内容を確認'));
    await tester.tap(find.text('入力内容を確認'));
    await tester.pump();

    expect(find.text('入力してください。'), findsNWidgets(2));
    expect(find.text('選択してください。'), findsOneWidget);
    expect(find.text('登録内容を確認'), findsNothing);
  });

  testWidgets('収穫を確認して登録結果を表示する', (tester) async {
    final repository = FakeReceivingRepository();
    await _pumpPage(tester, repository);
    await _completeHarvestForm(tester);

    await tester.tap(find.text('入力内容を確認'));
    await tester.pumpAndSettle();
    expect(find.text('登録内容を確認'), findsOneWidget);
    expect(find.text('25.50 kg'), findsOneWidget);

    await tester.tap(find.text('登録を確定'));
    await tester.pumpAndSettle();

    expect(repository.registerCalls, 1);
    expect(find.text('登録が完了しました'), findsOneWidget);
    expect(find.text('受入-2028-001'), findsOneWidget);
    expect(find.text('2028-05-31'), findsOneWidget);
    expect(repository.inputs.single.sourceType, ReceivingSourceType.harvest);
    expect(repository.inputs.single.originName, '第一農園 A区画');
  });

  testWidgets('登録結果から理由付き修正へ進める', (tester) async {
    final repository = FakeReceivingRepository();
    await _pumpPage(tester, repository);
    await _completeHarvestForm(tester);
    await _confirmAndRegister(tester);

    await tester.tap(find.text('登録内容を修正'));
    await tester.pumpAndSettle();
    expect(find.text('受入-2028-001を修正'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('field-total_weight_kg')),
      '24.80',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('field-reason')));
    await tester.enterText(
      find.byKey(const ValueKey('field-reason')),
      '計量結果を訂正',
    );
    await tester.ensureVisible(find.text('修正内容を確認'));
    await tester.tap(find.text('修正内容を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修正を確定'));
    await tester.pumpAndSettle();

    expect(repository.correctCalls, 1);
    expect(repository.correctionReasons.single, '計量結果を訂正');
    expect(find.text('修正が完了しました'), findsOneWidget);
  });

  testWidgets('仕入れの必須項目を入力して登録できる', (tester) async {
    final repository = FakeReceivingRepository();
    await _pumpPage(tester, repository);

    await tester.tap(find.text('仕入れ'));
    await tester.pump();
    await _choose(tester, 'supplier_id', 'supplier-01　仕入先A');
    await tester.enterText(
      find.byKey(const ValueKey('field-supplier_reference')),
      'PO-2028-001',
    );
    await tester.enterText(
      find.byKey(const ValueKey('field-origin_name')),
      '香川県 高松市',
    );
    await _choose(tester, 'variety_id', 'hayward　ヘイワード');
    await tester.enterText(
      find.byKey(const ValueKey('field-total_weight_kg')),
      '18.40',
    );
    await tester.enterText(
      find.byKey(const ValueKey('field-container_count')),
      '1',
    );
    await _choose(tester, 'worker_id', 'worker-01　作業者A');
    await _confirmAndRegister(tester);

    final input = repository.inputs.single;
    expect(input.sourceType, ReceivingSourceType.purchase);
    expect(input.supplierReference, 'PO-2028-001');
    expect(input.orchardId, isNull);
  });

  testWidgets('業務エラーを対象入力欄の近くへ表示する', (tester) async {
    final repository = FakeReceivingRepository(
      failures: const [
        ReceivingFailure(
          message: '総重量は0.01kg単位で指定してください。',
          field: 'total_weight_kg',
          reason: 'invalid_precision',
        ),
      ],
    );
    await _pumpPage(tester, repository);
    await _completeHarvestForm(tester);
    await _confirmAndRegister(tester);

    expect(find.text('入力内容を確認してください。'), findsOneWidget);
    expect(find.text('総重量は0.01kg単位で指定してください。'), findsOneWidget);
  });

  testWidgets('通信失敗後の手動再送で同じ操作キーを使う', (tester) async {
    final repository = FakeReceivingRepository(
      failures: const [
        ReceivingFailure(
          message: '通信に失敗しました。',
          correlationId: 'test-correlation-id',
          retryable: true,
        ),
      ],
    );
    await _pumpPage(tester, repository);
    await _completeHarvestForm(tester);
    await _confirmAndRegister(tester);

    expect(find.textContaining('問い合わせID: test-correlation-id'), findsOneWidget);
    await _confirmAndRegister(tester);

    expect(repository.registerCalls, 2);
    expect(repository.keys[0], repository.keys[1]);
    expect(find.text('登録が完了しました'), findsOneWidget);
  });

  testWidgets('送信中は標準の戻る操作を無効にする', (tester) async {
    final completer = Completer<ReceivingResult>();
    final repository = FakeReceivingRepository(registerCompleter: completer);
    await _pumpPage(tester, repository);
    await _completeHarvestForm(tester);

    await tester.ensureVisible(find.text('入力内容を確認'));
    await tester.tap(find.text('入力内容を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('登録を確定'));
    await tester.pump();

    final pagePopScope = tester.widget<PopScope<void>>(
      find.byWidgetPredicate(
        (widget) => widget is PopScope<void> && !widget.canPop,
      ),
    );
    expect(pagePopScope.canPop, isFalse);

    completer.complete(FakeReceivingRepository.registerResult);
    await tester.pumpAndSettle();
  });

  testWidgets('入力欄のない業務エラーは画面上に詳細を表示する', (tester) async {
    final repository = FakeReceivingRepository(
      failures: const [
        ReceivingFailure(
          message: '対象の受入ロットが見つかりません。',
          field: 'receiving_lot_id',
          reason: 'not_found',
        ),
      ],
    );
    await _pumpPage(tester, repository);
    await _completeHarvestForm(tester);
    await _confirmAndRegister(tester);

    expect(find.text('対象の受入ロットが見つかりません。'), findsOneWidget);
    expect(find.text('入力内容を確認してください。'), findsNothing);
  });

  testWidgets('確認と完了のダイアログを縦スクロール可能にする', (tester) async {
    await _pumpPage(tester, FakeReceivingRepository());
    await _completeHarvestForm(tester);

    await tester.ensureVisible(find.text('入力内容を確認'));
    await tester.tap(find.text('入力内容を確認'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
      isTrue,
    );

    await tester.tap(find.text('登録を確定'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
      isTrue,
    );
  });

  testWidgets('選択肢の読み込み失敗から再試行できる', (tester) async {
    final repository = FakeReceivingRepository(loadFails: true);
    await _pumpPage(tester, repository);

    expect(find.text('入力項目を読み込めません'), findsOneWidget);
    repository.loadFails = false;
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();

    expect(find.text('収穫・仕入れ登録'), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  ReceivingRepository repository, {
  double width = 390,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ReceivingPage(
        repository: repository,
        currentDate: DateTime(2028, 5, 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _completeHarvestForm(WidgetTester tester) async {
  await _choose(tester, 'orchard_id', '農園01　第一農園');
  await _choose(tester, 'plot_id', 'plot-a　A区画');
  await _choose(tester, 'tree_id', 'tree-01　樹体1号');
  await tester.enterText(
    find.byKey(const ValueKey('field-total_weight_kg')),
    '25.50',
  );
  await tester.enterText(
    find.byKey(const ValueKey('field-container_count')),
    '2',
  );
  await _choose(tester, 'worker_id', 'worker-01　作業者A');
}

Future<void> _choose(WidgetTester tester, String field, String option) async {
  await tester.ensureVisible(find.byKey(ValueKey('master-$field')));
  await tester.tap(find.byKey(ValueKey('master-$field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option));
  await tester.pumpAndSettle();
}

Future<void> _confirmAndRegister(WidgetTester tester) async {
  await tester.ensureVisible(find.text('入力内容を確認'));
  await tester.tap(find.text('入力内容を確認'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('登録を確定'));
  await tester.pumpAndSettle();
}

class FakeReceivingRepository implements ReceivingRepository {
  FakeReceivingRepository({
    this.loadFails = false,
    List<ReceivingFailure> failures = const [],
    this.registerCompleter,
  }) : _failures = [...failures];

  bool loadFails;
  final Completer<ReceivingResult>? registerCompleter;
  final List<ReceivingFailure> _failures;
  int registerCalls = 0;
  int correctCalls = 0;
  final List<String> keys = [];
  final List<ReceivingInput> inputs = [];
  final List<String> correctionReasons = [];

  static const registerResult = ReceivingResult(
    receivingLotId: 'lot-1',
    displayId: '受入-2028-001',
    receivedDate: '2028-05-01',
    sortingDueDate: '2028-05-31',
    version: 1,
    idempotentReplay: false,
  );

  static const masters = ReceivingMasters(
    orchards: [
      MasterOption(id: 'orchard-1', label: '農園01　第一農園', businessName: '第一農園'),
    ],
    plots: [
      MasterOption(
        id: 'plot-1',
        label: 'plot-a　A区画',
        businessName: 'A区画',
        parentId: 'orchard-1',
      ),
    ],
    trees: [
      MasterOption(
        id: 'tree-1',
        label: 'tree-01　樹体1号',
        parentId: 'plot-1',
        varietyId: 'variety-1',
      ),
    ],
    suppliers: [MasterOption(id: 'supplier-1', label: 'supplier-01　仕入先A')],
    varieties: [MasterOption(id: 'variety-1', label: 'hayward　ヘイワード')],
    workers: [MasterOption(id: 'worker-1', label: 'worker-01　作業者A')],
  );

  @override
  Future<ReceivingMasters> loadMasters() async {
    if (loadFails) {
      throw const ReceivingFailure(message: '通信状況を確認してください。');
    }
    return masters;
  }

  @override
  Future<ReceivingResult> register({
    required ReceivingInput input,
    required String idempotencyKey,
  }) async {
    registerCalls++;
    keys.add(idempotencyKey);
    inputs.add(input);
    if (_failures.isNotEmpty) throw _failures.removeAt(0);
    if (registerCompleter != null) return registerCompleter!.future;
    return registerResult;
  }

  @override
  Future<ReceivingResult> correct({
    required ReceivingInput input,
    required String receivingLotId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) async {
    correctCalls++;
    keys.add(idempotencyKey);
    inputs.add(input);
    correctionReasons.add(reason);
    return const ReceivingResult(
      receivingLotId: 'lot-1',
      displayId: '受入-2028-001',
      receivedDate: '2028-05-01',
      sortingDueDate: '2028-05-31',
      version: 2,
      idempotentReplay: false,
    );
  }
}

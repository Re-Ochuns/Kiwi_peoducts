@Tags(['golden'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/auth/auth_repository.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/csv_export/csv_export_dialog.dart';
import 'package:kiwi_inventory/csv_export/csv_export_repository.dart';
import 'package:kiwi_inventory/inventory/inventory_page.dart';
import 'package:kiwi_inventory/inventory/inventory_repository.dart';
import 'package:kiwi_inventory/label/label_page.dart';
import 'package:kiwi_inventory/label/label_repository.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/receiving/receiving_page.dart';
import 'package:kiwi_inventory/receiving/receiving_repository.dart';
import 'package:kiwi_inventory/ripening/ripening_plan_page.dart';

import 'support/golden_test_environment.dart';
import 'support/fake_csv_export_repository.dart';
import 'support/fake_master_repository.dart';
import 'support/fake_ripening_plan_repository.dart';
import 'support/fake_work_task_repository.dart';
import 'support/fake_order_management_repository.dart';

void main() {
  final goldenDate = DateTime(2026, 9, 8);
  setUpAll(loadGoldenTestFont);

  testWidgets('390pxのログイン画面', (tester) async {
    configureGoldenView(tester, const Size(390, 844));
    await tester.pumpWidget(
      KiwiInventoryApp(
        authRepository: _SignedOutGoldenAuthRepository(),
        theme: buildAppTheme(fontFamily: goldenFontFamily),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KiwiInventoryApp),
      matchesGoldenFile('goldens/login_390.png'),
    );
  });

  testWidgets('390pxの作業者ホーム', (tester) async {
    configureGoldenView(tester, const Size(390, 844));
    await tester.pumpWidget(
      KiwiInventoryApp(
        authRepository: _GoldenAuthRepository(),
        currentDate: DateTime(2026, 9, 12, 12),
        workTaskRepository: FakeWorkTaskRepository(),
        theme: buildAppTheme(fontFamily: goldenFontFamily),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KiwiInventoryApp),
      matchesGoldenFile('goldens/worker_home_390.png'),
    );
  });

  testWidgets('1280pxの管理ホーム', (tester) async {
    configureGoldenView(tester, const Size(1280, 900));
    await tester.pumpWidget(
      KiwiInventoryApp(
        authRepository: _GoldenAuthRepository(),
        currentDate: goldenDate,
        workTaskRepository: FakeWorkTaskRepository(),
        orderManagementRepository: FakeOrderManagementRepository(),
        theme: buildAppTheme(fontFamily: goldenFontFamily),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KiwiInventoryApp),
      matchesGoldenFile('goldens/manager_home_1280.png'),
    );
  });

  testWidgets('390pxの収穫受入登録画面', (tester) async {
    configureGoldenView(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fontFamily: goldenFontFamily),
        home: ReceivingPage(
          repository: _GoldenReceivingRepository(),
          currentDate: DateTime(2028, 5, 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ReceivingPage),
      matchesGoldenFile('goldens/receiving_harvest_390.png'),
    );
  });

  testWidgets('390pxの追熟計画作成画面', (tester) async {
    configureGoldenView(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fontFamily: goldenFontFamily),
        home: RipeningPlanPage(
          repository: FakeRipeningPlanRepository(),
          currentDate: DateTime(2026, 9, 12, 9),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RipeningPlanPage),
      matchesGoldenFile('goldens/ripening_plan_390.png'),
    );
  });

  testWidgets('1280pxの管理追熟計画作成画面', (tester) async {
    configureGoldenView(tester, const Size(1280, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fontFamily: goldenFontFamily),
        home: ManagerRipeningPlanPage(
          repository: FakeRipeningPlanRepository(),
          currentDate: DateTime(2026, 9, 12, 9),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ManagerRipeningPlanPage),
      matchesGoldenFile('goldens/manager_ripening_plan_1280.png'),
    );
  });

  testWidgets('390pxのラベル対象画面', (tester) async {
    configureGoldenView(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fontFamily: goldenFontFamily),
        home: LabelTargetPage(repository: _GoldenLabelRepository()),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(LabelTargetPage),
      matchesGoldenFile('goldens/label_targets_390.png'),
    );
  });

  testWidgets('390pxのラベル確認画面', (tester) async {
    configureGoldenView(tester, const Size(390, 900));
    final repository = _GoldenLabelRepository();
    final data = await repository.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fontFamily: goldenFontFamily),
        home: LabelDetailPage(
          repository: repository,
          job: data.jobs.first,
          workers: data.workers,
          locations: data.locations,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(LabelDetailPage),
      matchesGoldenFile('goldens/label_detail_390.png'),
    );
  });
  testWidgets('390pxの在庫一覧', (tester) async {
    configureGoldenView(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fontFamily: goldenFontFamily),
        home: InventoryPage(
          repository: _GoldenInventoryRepository(),
          csvExportRepository: FakeCsvExportRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(InventoryPage),
      matchesGoldenFile('goldens/inventory_list_390.png'),
    );
  });

  testWidgets('1280pxの管理在庫画面', (tester) async {
    configureGoldenView(tester, const Size(1280, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fontFamily: goldenFontFamily),
        home: ManagerInventoryPage(
          repository: _GoldenInventoryRepository(canViewHistory: true),
          csvExportRepository: FakeCsvExportRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('在庫-2026-001'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ManagerInventoryPage),
      matchesGoldenFile('goldens/manager_inventory_1280.png'),
    );
  });

  testWidgets('1280pxのマスター管理画面', (tester) async {
    configureGoldenView(tester, const Size(1280, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fontFamily: goldenFontFamily),
        home: ManagerMasterPage(
          repository: FakeMasterRepository(),
          csvExportRepository: FakeCsvExportRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('hayward'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ManagerMasterPage),
      matchesGoldenFile('goldens/manager_master_1280.png'),
    );
  });

  testWidgets('1280pxの受注管理画面', (tester) async {
    configureGoldenView(tester, const Size(1280, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fontFamily: goldenFontFamily),
        home: ManagerOrderPage(repository: FakeOrderManagementRepository()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('受注-2026-001'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ManagerOrderPage),
      matchesGoldenFile('goldens/manager_orders_1280.png'),
    );
  });

  testWidgets('390pxのCSV出力画面', (tester) async {
    configureGoldenView(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fontFamily: goldenFontFamily),
        home: Scaffold(
          body: CsvExportDialog(
            repository: FakeCsvExportRepository(),
            initialRequest: CsvExportRequest.history(
              entityType: 'container',
              entityId: '32000000-0000-0000-0000-000000000001',
            ),
            availableDatasets: const {
              CsvDataset.inventory,
              CsvDataset.masters,
              CsvDataset.history,
            },
            downloader: (_, _) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(CsvExportDialog),
      matchesGoldenFile('goldens/csv_export_dialog_390.png'),
    );
  });
}

class _GoldenInventoryRepository implements InventoryRepository {
  _GoldenInventoryRepository({this.canViewHistory = false});

  final bool canViewHistory;

  static final _item = InventoryItem(
    id: 'container-1',
    displayId: '在庫-2026-001',
    varietyName: 'ヘイワード',
    gradeCode: 'M',
    originalWeightHundredths: 1000,
    currentWeightHundredths: 925,
    reservedWeightHundredths: 200,
    status: InventoryStatus.coldStorage,
    locationCode: 'cold-01',
    locationName: '第一冷蔵庫',
    updatedAt: DateTime(2026, 9, 8, 9),
  );

  @override
  Future<InventoryPageData> loadPage(InventoryQuery query) async =>
      InventoryPageData(
        items: [
          _item,
          InventoryItem(
            id: 'container-2',
            displayId: '在庫-2026-002',
            varietyName: '香緑',
            gradeCode: 'L',
            originalWeightHundredths: 820,
            currentWeightHundredths: 820,
            reservedWeightHundredths: 0,
            status: InventoryStatus.shippable,
            locationCode: 'cold-02',
            locationName: '第二冷蔵庫',
            updatedAt: DateTime(2026, 9, 8, 8),
          ),
        ],
        totalCount: 2,
        page: query.page,
        pageSize: query.pageSize,
      );

  @override
  Future<InventoryDetailData> loadDetail(String containerId) async =>
      InventoryDetailData(
        item: _item,
        source: InventorySource(
          sortingDisplayId: '選果-2026-001',
          sortedOn: DateTime(2026, 9, 2),
          sortingWorkerName: '作業者A',
          receivingDisplayId: '受入-2026-001',
          receivedOn: DateTime(2026, 9, 1),
          sourceType: 'harvest',
          originName: '第一圃場 A区画',
        ),
        history: canViewHistory
            ? [
                InventoryHistoryEntry(
                  operation: 'create',
                  reason: '選果確定により作成',
                  changedAt: DateTime.utc(2026, 9, 2, 5, 30),
                  changedBy: '管理者A',
                ),
              ]
            : const [],
        canViewHistory: canViewHistory,
      );
}

class _GoldenLabelRepository implements LabelRepository {
  @override
  Future<LabelLoadData> load({
    bool completed = false,
    LabelCursor? after,
  }) async => LabelLoadData(
    jobs: [
      LabelJob(
        id: 'label-1',
        containerId: 'container-1',
        containerDisplayId: '選果-2026-0148-1',
        status: LabelJobStatus.notPrinted,
        requiredCopies: 1,
        printedCopies: 0,
        reprintCount: 0,
        originName: '第二農園 B区画',
        varietyName: '香緑',
        gradeCode: 'M',
        weightHundredths: 1840,
        sortedOn: DateTime(2026, 9, 8),
        workerName: '作業者A',
      ),
      LabelJob(
        id: 'label-2',
        containerId: 'container-2',
        containerDisplayId: '選果-2026-0147-2',
        status: LabelJobStatus.partiallyPrinted,
        requiredCopies: 2,
        printedCopies: 1,
        reprintCount: 0,
        originName: '第一農園 A区画',
        varietyName: 'ヘイワード',
        gradeCode: 'L',
        weightHundredths: 2050,
        sortedOn: DateTime(2026, 9, 8),
        workerName: '作業者B',
      ),
    ],
    workers: const [LabelOption(id: 'worker-1', label: 'worker-01　作業者A')],
    locations: const [LabelOption(id: 'location-1', label: 'cold-01　第一冷蔵庫')],
  );

  @override
  Future<LabelPdf> fetchPdf({required String containerId}) async => LabelPdf(
    bytes: Uint8List.fromList([1, 2, 3]),
    filename: '$containerId.pdf',
  );

  @override
  Future<LabelActionResult> markHandwritten({
    required String labelJobId,
    required String workerId,
    required String idempotencyKey,
    String? notes,
    String? locationId,
  }) => throw UnimplementedError();

  @override
  Future<LabelActionResult> markPrinted({
    required String labelJobId,
    required String workerId,
    required int copies,
    required String idempotencyKey,
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

class _GoldenReceivingRepository implements ReceivingRepository {
  static const _masters = ReceivingMasters(
    orchards: [MasterOption(id: 'orchard-1', label: '農園01　第一農園')],
    plots: [
      MasterOption(id: 'plot-1', label: 'plot-a　A区画', parentId: 'orchard-1'),
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
  Future<ReceivingMasters> loadMasters() async => _masters;

  @override
  Future<ReceivingResult> register({
    required ReceivingInput input,
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<ReceivingResult> correct({
    required ReceivingInput input,
    required String receivingLotId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

class _GoldenAuthRepository implements AuthRepository {
  static const _user = AuthUser(id: 'golden-user');
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<UserAccessStatus> loadAccessStatus(String userId) async =>
      UserAccessStatus.active;

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}
}

class _SignedOutGoldenAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<UserAccessStatus> loadAccessStatus(String userId) async =>
      UserAccessStatus.unavailable;

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}
}

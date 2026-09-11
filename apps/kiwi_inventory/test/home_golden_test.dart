@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/auth/auth_repository.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/inventory/inventory_page.dart';
import 'package:kiwi_inventory/inventory/inventory_repository.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/receiving/receiving_page.dart';
import 'package:kiwi_inventory/receiving/receiving_repository.dart';

import 'support/golden_test_environment.dart';

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
        currentDate: goldenDate,
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

  testWidgets('390pxの在庫一覧', (tester) async {
    configureGoldenView(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fontFamily: goldenFontFamily),
        home: InventoryPage(repository: _GoldenInventoryRepository()),
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
                  changedAt: DateTime(2026, 9, 2, 14, 30),
                  changedBy: '管理者A',
                ),
              ]
            : const [],
        canViewHistory: canViewHistory,
      );
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

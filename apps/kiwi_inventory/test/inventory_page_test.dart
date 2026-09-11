import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/inventory/inventory_page.dart';
import 'package:kiwi_inventory/inventory/inventory_repository.dart';
import 'package:kiwi_inventory/main.dart';

void main() {
  group('在庫一覧', () {
    testWidgets('作業者ホームから在庫参照を開ける', (tester) async {
      final repository = FakeInventoryRepository();
      await _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: WorkerHomePage(inventoryRepository: repository),
        ),
      );

      await tester.tap(find.text('在庫参照'));
      await tester.pumpAndSettle();

      expect(find.text('在庫参照'), findsOneWidget);
      expect(find.text(testItem.displayId), findsOneWidget);
      expect(repository.loadPageCalls, 1);
    });

    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('${width.toInt()}px幅で横方向に崩れない', (tester) async {
        await _pumpInventory(
          tester,
          FakeInventoryRepository(),
          size: Size(width, 844),
        );

        expect(find.text(testItem.displayId), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('不要な説明と選択欄の装飾矢印を表示しない', (tester) async {
      await _pumpInventory(tester, FakeInventoryRepository());

      expect(find.text('在庫ID、数量、状態、保管場所を確認できます。'), findsNothing);
      expect(find.text('↓'), findsNothing);
      final status = tester.widget<Text>(find.text('冷蔵保管'));
      expect(status.style?.fontSize, 14);
    });

    testWidgets('在庫ID・状態・並び順を指定して再取得する', (tester) async {
      final repository = FakeInventoryRepository();
      await _pumpInventory(tester, repository);

      await tester.enterText(
        find.byKey(const Key('inventory-search')),
        '在庫-002',
      );
      await tester.tap(find.byKey(const Key('inventory-search-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inventory-status-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('出荷可能').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inventory-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在庫ID順').last);
      await tester.pumpAndSettle();

      expect(repository.lastQuery!.search, '在庫-002');
      expect(repository.lastQuery!.status, InventoryStatus.shippable);
      expect(repository.lastQuery!.sort, InventorySort.displayIdAscending);
      expect(repository.lastQuery!.page, 0);
    });

    testWidgets('空状態を表示する', (tester) async {
      await _pumpInventory(
        tester,
        FakeInventoryRepository(items: const [], totalCount: 0),
      );

      expect(find.text('条件に合う在庫はありません'), findsOneWidget);
    });

    testWidgets('取得失敗から再試行できる', (tester) async {
      final repository = FakeInventoryRepository(pageFailures: 1);
      await _pumpInventory(tester, repository);

      expect(find.text('在庫一覧を読み込めませんでした'), findsOneWidget);
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      expect(find.text(testItem.displayId), findsOneWidget);
      expect(repository.loadPageCalls, 2);
    });

    testWidgets('権限エラーでは再試行を表示しない', (tester) async {
      await _pumpInventory(
        tester,
        FakeInventoryRepository(
          pageFailures: 1,
          pageFailure: const InventoryFailure(
            message: '在庫情報を確認する権限がありません。',
            code: 'AUTH_FORBIDDEN',
          ),
        ),
      );

      expect(find.text('在庫を表示できません'), findsOneWidget);
      expect(find.text('再試行'), findsNothing);
    });

    testWidgets('次ページを取得できる', (tester) async {
      final repository = FakeInventoryRepository(totalCount: 21);
      await _pumpInventory(tester, repository);

      await tester.tap(find.byKey(const Key('inventory-next-page')));
      await tester.pumpAndSettle();

      expect(repository.lastQuery!.page, 1);
      expect(find.text('2ページ'), findsOneWidget);
    });
  });

  group('在庫詳細', () {
    testWidgets('数量・発生元・一般作業者向け権限制御を表示する', (tester) async {
      await _pumpInventory(tester, FakeInventoryRepository());

      await tester.tap(find.text(testItem.displayId));
      await tester.pumpAndSettle();

      expect(find.text('元重量'), findsOneWidget);
      expect(find.text('9.25 kg'), findsWidgets);
      expect(find.text('2.00 kg'), findsWidgets);
      expect(find.text('7.25 kg'), findsOneWidget);
      expect(find.textContaining('受入情報を見る'), findsOneWidget);
      expect(find.textContaining('選果情報を見る'), findsOneWidget);
      expect(find.text('変更履歴は管理者のみ確認できます。'), findsOneWidget);
    });

    testWidgets('管理者には変更履歴を表示する', (tester) async {
      final repository = FakeInventoryRepository(canViewHistory: true);
      await _setSurface(tester, const Size(1280, 900));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ManagerHomePage(inventoryRepository: repository),
        ),
      );

      await tester.tap(find.text('在庫管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(testItem.displayId));
      await tester.pumpAndSettle();

      expect(find.text('棚卸しにより数量を訂正'), findsOneWidget);
      expect(find.textContaining('担当 管理者A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpInventory(
  WidgetTester tester,
  FakeInventoryRepository repository, {
  Size size = const Size(390, 844),
}) async {
  await _setSurface(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: InventoryPage(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

final testItem = InventoryItem(
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
  updatedAt: DateTime(2026, 9, 10, 9),
);

final testSource = InventorySource(
  sortingDisplayId: '選果-2026-001',
  sortedOn: DateTime(2026, 9, 2),
  sortingWorkerName: '作業者A',
  receivingDisplayId: '受入-2026-001',
  receivedOn: DateTime(2026, 9, 1),
  sourceType: 'harvest',
  originName: '第一圃場 A区画',
);

class FakeInventoryRepository implements InventoryRepository {
  FakeInventoryRepository({
    this.items,
    this.totalCount = 1,
    this.pageFailures = 0,
    this.pageFailure = const InventoryFailure(
      message: '在庫一覧を読み込めませんでした。通信状況を確認してください。',
      retryable: true,
    ),
    this.canViewHistory = false,
  });

  final List<InventoryItem>? items;
  final int totalCount;
  int pageFailures;
  final InventoryFailure pageFailure;
  final bool canViewHistory;
  int loadPageCalls = 0;
  InventoryQuery? lastQuery;

  @override
  Future<InventoryPageData> loadPage(InventoryQuery query) async {
    loadPageCalls++;
    lastQuery = query;
    if (pageFailures > 0) {
      pageFailures--;
      throw pageFailure;
    }
    return InventoryPageData(
      items: items ?? [testItem],
      totalCount: totalCount,
      page: query.page,
      pageSize: query.pageSize,
    );
  }

  @override
  Future<InventoryDetailData> loadDetail(String containerId) async =>
      InventoryDetailData(
        item: testItem,
        source: testSource,
        history: canViewHistory
            ? [
                InventoryHistoryEntry(
                  operation: 'correct',
                  reason: '棚卸しにより数量を訂正',
                  changedAt: DateTime(2026, 9, 10, 9, 30),
                  changedBy: '管理者A',
                ),
              ]
            : const [],
        canViewHistory: canViewHistory,
      );
}

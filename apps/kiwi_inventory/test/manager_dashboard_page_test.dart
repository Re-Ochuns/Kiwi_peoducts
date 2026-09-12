import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/manager_dashboard/manager_dashboard_page.dart';
import 'package:kiwi_inventory/manager_dashboard/manager_dashboard_repository.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/orders/order_management_repository.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';

import 'support/fake_order_management_repository.dart';
import 'support/fake_work_task_repository.dart';

void main() {
  testWidgets('900pxの管理ホームで横方向にあふれない', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ManagerHomePage(
          currentDate: DateTime(2026, 9, 12, 12),
          workTaskRepository: FakeWorkTaskRepository(),
          orderManagementRepository: FakeOrderManagementRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ホーム'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('900px以上で優先項目と予定を実データから表示する', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final orders = FakeOrderManagementRepository();
    final failedTask = WorkTaskItem(
      id: 'sync-failed',
      type: WorkTaskType.shipping,
      targetId: 'order-2',
      targetDisplayId: '受注-2026-002',
      scheduledAt: DateTime(2026, 9, 14, 10),
      dueAt: DateTime(2026, 9, 14, 12),
      status: 'pending',
      targetUrl: '/work-tasks/sync-failed',
      calendarSyncStatus: 'failed',
      calendarSyncError: 'GOOGLE_TEMPORARY',
    );
    WorkTaskItem? openedTask;
    OrderItem? openedOrder;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManagerDashboardPage(
            repository: _Repository(
              ManagerDashboardData(
                tasks: [...testWorkTasks, failedTask],
                orders: await orders.load(filter: OrderListFilter.active),
                syncWarnings: const WorkTaskSyncWarnings(
                  failedCount: 1,
                  pendingCount: 0,
                  overdueSyncCount: 0,
                  scheduleWarningCount: 0,
                ),
              ),
            ),
            currentDate: DateTime(2026, 9, 12, 12),
            onOpenTask: (task) => openedTask = task,
            onOpenOrder: (order) => openedOrder = order,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('優先して確認'), findsOneWidget);
    expect(find.text('予約量が不足しています'), findsOneWidget);
    expect(find.text('Googleカレンダーへ予定を同期できませんでした'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('受注-2026-001').first);
    expect(openedOrder?.id, 'order-1');
    await tester.tap(find.text('受注-2026-002').first);
    expect(openedTask?.id, 'sync-failed');
  });

  testWidgets('読み込み失敗時に再試行できる', (tester) async {
    final repository = _RetryRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManagerDashboardPage(
            repository: repository,
            currentDate: DateTime(2026, 9, 12),
            onOpenTask: (_) {},
            onOpenOrder: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('再試行'), findsOneWidget);

    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(find.text('確認が必要な項目はありません'), findsOneWidget);
  });
}

class _Repository implements ManagerDashboardRepository {
  const _Repository(this.data);
  final ManagerDashboardData data;

  @override
  Future<ManagerDashboardData> load() async => data;
}

class _RetryRepository implements ManagerDashboardRepository {
  int calls = 0;

  @override
  Future<ManagerDashboardData> load() async {
    calls++;
    if (calls == 1) {
      throw const ManagerDashboardFailure(
        message: '通信状況を確認してください。',
        retryable: true,
      );
    }
    return const ManagerDashboardData(
      tasks: [],
      orders: OrderManagementData(
        orders: [],
        customers: [],
        varieties: [],
        grades: [],
        canManage: false,
      ),
      syncWarnings: WorkTaskSyncWarnings.empty(),
    );
  }
}

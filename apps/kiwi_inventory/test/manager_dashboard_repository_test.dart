import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/manager_dashboard/manager_dashboard_repository.dart';
import 'package:kiwi_inventory/orders/order_management_repository.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';

import 'support/fake_order_management_repository.dart';
import 'support/fake_work_task_repository.dart';

void main() {
  test('予定・期限超過・予約不足・同期警告を分類する', () async {
    final tasks = [
      ...testWorkTasks,
      WorkTaskItem(
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
      ),
    ];
    final repository = DefaultManagerDashboardRepository(
      workTaskRepository: FakeWorkTaskRepository(
        tasks: tasks,
        syncWarnings: const WorkTaskSyncWarnings(
          failedCount: 1,
          pendingCount: 2,
          overdueSyncCount: 1,
          scheduleWarningCount: 0,
        ),
      ),
      orderManagementRepository: FakeOrderManagementRepository(),
    );

    final data = await repository.load();
    final now = DateTime(2026, 9, 12, 12);

    expect(data.overdueTasks(now).map((task) => task.id), ['task-overdue']);
    expect(data.todayTasks(now).map((task) => task.id), [
      'task-overdue',
      'task-today',
    ]);
    expect(data.upcomingTasks(now).map((task) => task.id), [
      'task-upcoming',
      'sync-failed',
    ]);
    expect(data.shortageOrders.single.number, '受注-2026-001');
    expect(data.syncFailedTasks.single.id, 'sync-failed');
    expect(data.attentionCount(now), 4);
  });

  test('受注読み込み失敗をホーム用エラーへ変換する', () async {
    final orders = FakeOrderManagementRepository()
      ..nextFailure = const OrderManagementFailure(
        message: '受注を読み込めませんでした。',
        code: 'NETWORK_FAILED',
        retryable: true,
      );
    final repository = DefaultManagerDashboardRepository(
      workTaskRepository: FakeWorkTaskRepository(),
      orderManagementRepository: orders,
    );

    await expectLater(
      repository.load(),
      throwsA(
        isA<ManagerDashboardFailure>()
            .having((error) => error.retryable, 'retryable', isTrue)
            .having((error) => error.message, 'message', '受注を読み込めませんでした。'),
      ),
    );
  });
}

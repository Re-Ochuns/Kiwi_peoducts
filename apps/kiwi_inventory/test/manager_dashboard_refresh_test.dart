import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';

import 'support/fake_work_task_repository.dart';
import 'support/fake_order_management_repository.dart';

class SnapshotTasks extends FakeWorkTaskRepository {
  bool resolved = false;
  @override
  Future<List<WorkTaskItem>> loadDashboardTasks() async {
    loadCalls++;
    return resolved ? [] : [testWorkTasks.first];
  }
}

void main() {
  testWidgets('refresh evaluates overdue status using current time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final task = WorkTaskItem(
      id: 'boundary',
      type: WorkTaskType.shipping,
      targetId: 'order-1',
      targetDisplayId: '時刻境界の受注',
      scheduledAt: now,
      dueAt: now.add(const Duration(seconds: 2)),
      status: 'pending',
      targetUrl: '/work-tasks/boundary',
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [managerDashboardRouteObserver],
        home: ManagerHomePage(
          workTaskRepository: FakeWorkTaskRepository(tasks: [task]),
          orderManagementRepository: FakeOrderManagementRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('出荷確認の期限を超過しています'), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('出荷確認の期限を超過しています'), findsOneWidget);
  });
  testWidgets('dashboard reloads resolved warnings on return from detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tasks = SnapshotTasks();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [managerDashboardRouteObserver],
        home: ManagerHomePage(
          currentDate: DateTime(2026, 9, 12, 12),
          workTaskRepository: tasks,
          orderManagementRepository: FakeOrderManagementRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('追熟-2026-001').first);
    await tester.pumpAndSettle();
    tasks.resolved = true;
    await tester.tap(find.text('← ホームへ戻る'));
    await tester.pumpAndSettle();
    expect(tasks.loadCalls, greaterThan(1));
    expect(find.text('エチレン注入の期限を超過しています'), findsNothing);
  });
}

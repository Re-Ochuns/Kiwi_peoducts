import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';

import 'manager_dashboard_refresh_test.dart' show SnapshotTasks;
import 'support/fake_order_management_repository.dart';
import 'support/fake_ripening_plan_repository.dart';

void main() {
  testWidgets('refresh after replacing the child route and returning home', (
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
          ripeningPlanRepository: FakeRipeningPlanRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('受注').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('追熟計画').first);
    await tester.pumpAndSettle();
    expect(
      tasks.loadCalls,
      1,
      reason: "Do not refresh while the home is hidden",
    );
    final readsBeforeReturn = tasks.loadCalls;
    tasks.resolved = true;
    await tester.tap(find.text('ホーム').first);
    await tester.pumpAndSettle();
    expect(tasks.loadCalls, greaterThan(readsBeforeReturn));
    expect(find.text('エチレン注入の期限を超過しています'), findsNothing);
  });
}

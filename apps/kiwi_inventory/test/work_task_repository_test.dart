import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';

import 'support/fake_work_task_repository.dart';

void main() {
  test('期限超過・ToDo・今後を優先順に分け、完了済みを除外する', () {
    final groups = WorkTaskGroups.fromTasks([
      ...testWorkTasks,
      WorkTaskItem(
        id: 'completed',
        type: WorkTaskType.shipping,
        targetId: 'order-1',
        targetDisplayId: 'ORD-2026-001',
        scheduledAt: DateTime(2026, 9, 12, 8),
        dueAt: DateTime(2026, 9, 12, 9),
        status: 'completed',
        targetUrl: '/work-tasks/completed',
      ),
    ], now: DateTime(2026, 9, 12, 12));

    expect(groups.overdue.map((task) => task.id), ['task-overdue']);
    expect(groups.today.map((task) => task.id), ['task-today']);
    expect(groups.upcoming.map((task) => task.id), ['task-upcoming']);
  });

  test('DBの作業種別を日本語の操作名へ変換する', () {
    expect(WorkTaskType.fromValue('ethylene_removal_check').label, 'エチレン抜き確認');
    expect(WorkTaskType.fromValue('unknown').label, '作業確認');
  });

  test('重量を小数点以下2桁で表示する', () {
    expect(formatWorkTaskWeight(825), '8.25 kg');
  });
}

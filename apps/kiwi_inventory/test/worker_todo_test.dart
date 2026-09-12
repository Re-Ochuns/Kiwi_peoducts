import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';
import 'package:kiwi_inventory/work_tasks/worker_todo.dart';

import 'support/fake_work_task_repository.dart';

void main() {
  group('スマホToDo', () {
    testWidgets('期限超過・ToDo・今後を表示して対象を開く', (tester) async {
      WorkTaskItem? selected;
      await _pump(
        tester,
        repository: FakeWorkTaskRepository(),
        onOpenTask: (task) => selected = task,
      );

      expect(find.text('期限超過'), findsNWidgets(2));
      expect(find.text('本日の予定'), findsOneWidget);
      expect(find.text('今後の作業'), findsOneWidget);
      expect(find.text('20.50 kg'), findsOneWidget);
      expect(find.text('場所 第1追熟庫'), findsOneWidget);
      expect(find.bySemanticsLabel('追熟-2026-001のエチレン注入を確認する'), findsOneWidget);

      await tester.tap(find.text('追熟-2026-002'));
      expect(selected?.id, 'task-upcoming');
    });

    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('${width.toInt()}pxで横方向の表示崩れがない', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pump(tester, repository: FakeWorkTaskRepository());

        expect(find.text('追熟-2026-001'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('通信エラーを表示して再試行できる', (tester) async {
      final repository = FakeWorkTaskRepository(loadFailures: 1);
      await _pump(tester, repository: repository);

      expect(find.byKey(const Key('todo-error')), findsOneWidget);
      expect(find.text('ToDoを読み込めませんでした。'), findsOneWidget);
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      expect(repository.loadCalls, 2);
      expect(find.text('追熟-2026-001'), findsOneWidget);
    });

    testWidgets('空状態を表示する', (tester) async {
      await _pump(tester, repository: FakeWorkTaskRepository(tasks: const []));

      expect(find.byKey(const Key('todo-empty')), findsOneWidget);
      expect(find.text('予定されている作業はありません'), findsOneWidget);
    });

    testWidgets('タスクURLから作業確認を直接開く', (tester) async {
      final repository = FakeWorkTaskRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: WorkTaskRoutePage(
            repository: repository,
            taskId: 'task-today',
            targetPageBuilder: (_) => const Scaffold(body: Text('ラベル対象')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('作業確認'), findsOneWidget);
      expect(find.text('選果-2026-0148-1'), findsOneWidget);
      expect(find.text('ラベル対応へ進む'), findsOneWidget);
      expect(repository.loadTaskCalls, 1);
    });

    test('作業タスクURLからIDを取り出す', () {
      expect(workTaskIdFromRoute('/work-tasks/task-1'), 'task-1');
      expect(workTaskIdFromRoute('/orders/task-1'), isNull);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeWorkTaskRepository repository,
  ValueChanged<WorkTaskItem>? onOpenTask,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: WorkerTodoSections(
            repository: repository,
            currentDate: DateTime(2026, 9, 12, 12),
            onOpenTask: onOpenTask ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

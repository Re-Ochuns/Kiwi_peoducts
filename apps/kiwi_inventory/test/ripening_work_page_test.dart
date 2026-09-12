import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/ripening/ripening_work_page.dart';
import 'package:kiwi_inventory/ripening/ripening_work_repository.dart';
import 'package:kiwi_inventory/work_tasks/worker_todo.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';

import 'support/fake_ripening_work_repository.dart';
import 'support/fake_work_task_repository.dart';

void main() {
  final now = DateTime(2026, 9, 13, 12, 34);
  Future<void> open(
    WidgetTester tester,
    FakeRipeningWorkRepository repo,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RipeningWorkPage(
          repository: repo,
          taskId: 'task-1',
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.ensureVisible(find.text('完了内容を確認'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('完了内容を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完了内容を確認'));
    await tester.pumpAndSettle();
  }

  for (final type in [
    WorkTaskType.ethyleneInjection,
    WorkTaskType.ethyleneRemovalCheck,
    WorkTaskType.ripenessCheck,
  ]) {
    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('${type.name} ${width}px 入力・確認・完了', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final repo = FakeRipeningWorkRepository(type: type);
        await open(tester, repo);
        expect(find.text('25.00 kg'), findsOneWidget);
        await confirm(tester);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('RIP-2026-0001'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('完了する'));
        await tester.pumpAndSettle();
        expect(find.text('完了しました'), findsOneWidget);
        expect(repo.calls, 1);
        expect(repo.inputs.single.actualAt, now);
        expect(repo.inputs.single.temperature, 20);
        expect(repo.inputs.single.checked, true);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('保存中の連打は一度だけ送信する', (tester) async {
    final completer = Completer<void>();
    final repo = FakeRipeningWorkRepository()..pendingSave = completer.future;
    await open(tester, repo);
    await confirm(tester);
    await tester.tap(find.text('完了する'));
    await tester.pump();
    await tester.tap(find.text('保存中…'));
    await tester.pump();
    expect(repo.calls, 1);
    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('完了しました'), findsOneWidget);
  });
  testWidgets('チェックなし・温度不正では送信しない', (tester) async {
    final repo = FakeRipeningWorkRepository();
    await open(tester, repo);
    await tester.ensureVisible(find.text('完了内容を確認'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('完了内容を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完了内容を確認'));
    await tester.pumpAndSettle();
    expect(find.text('作業の実施確認にチェックしてください。'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('work-temperature')), 'NaN');
    await tester.ensureVisible(find.text('完了内容を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完了内容を確認'));
    await tester.pumpAndSettle();
    expect(find.text('温度を数値で入力してください'), findsOneWidget);
    expect(repo.calls, 0);
  });
  testWidgets('通信失敗後は同じキーと実績を再送する', (tester) async {
    final repo = FakeRipeningWorkRepository()
      ..failure = const RipeningWorkFailure('通信失敗', retryable: true);
    await open(tester, repo);
    await confirm(tester);
    await tester.tap(find.text('完了する'));
    await tester.pumpAndSettle();
    repo.failure = null;
    await tester.tap(find.text('同じ内容で再試行'));
    await tester.pumpAndSettle();
    expect(repo.calls, 2);
    expect(repo.keys[0], repo.keys[1]);
    expect(identical(repo.inputs[0], repo.inputs[1]), true);
  });
  testWidgets('競合後は編集・再送を止め最新状態の確認を求める', (tester) async {
    final repo = FakeRipeningWorkRepository()
      ..failure = const RipeningWorkFailure('別の担当者が更新しました。');
    await open(tester, repo);
    await confirm(tester);
    await tester.tap(find.text('完了する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('最新の状態で開き直してください'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '完了内容を確認'))
          .onPressed,
      isNull,
    );
  });
  testWidgets('閲覧権限・完了済みの作業は送信不可', (tester) async {
    await open(tester, FakeRipeningWorkRepository(canComplete: false));
    expect(find.text('この作業を完了する権限がありません'), findsOneWidget);
    expect(find.text('完了内容を確認'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await open(tester, FakeRipeningWorkRepository(status: 'completed'));
    expect(find.text('この作業は完了または中止されています'), findsOneWidget);
  });
  testWidgets('読み込みエラーを再試行できる', (tester) async {
    final repo = FakeRipeningWorkRepository()
      ..loadFailure = const RipeningWorkFailure('読み込み失敗');
    await open(tester, repo);
    expect(find.text('読み込み失敗'), findsOneWidget);
    repo.loadFailure = null;
    await tester.tap(find.text('再読込'));
    await tester.pumpAndSettle();
    expect(find.text('25.00 kg'), findsOneWidget);
  });
  testWidgets('ToDoから追熟作業を直接表示する', (tester) async {
    final repo = FakeRipeningWorkRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: WorkerHomePage(
          currentDate: now,
          workTaskRepository: FakeWorkTaskRepository(tasks: [repo.task]),
          ripeningWorkRepository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('RIP-2026-0001'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RIP-2026-0001'));
    await tester.pumpAndSettle();
    expect(find.byType(RipeningWorkPage), findsOneWidget);
    expect(find.byType(WorkTaskDetailPage), findsNothing);
  });
  testWidgets('直接リンクの作業IDから追熟作業を表示する', (tester) async {
    final repo = FakeRipeningWorkRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: WorkTaskRoutePage(
          repository: FakeWorkTaskRepository(tasks: [repo.task]),
          taskId: 'task-1',
          targetPageBuilder: (task) =>
              RipeningWorkPage(repository: repo, taskId: task.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RipeningWorkPage), findsOneWidget);
    expect(find.text('RIP-2026-0001'), findsOneWidget);
  });
}

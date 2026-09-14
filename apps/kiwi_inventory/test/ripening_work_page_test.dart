import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/ripening_work/ripening_work_page.dart';
import 'package:kiwi_inventory/ripening_work/ripening_work_repository.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';

import 'support/fake_ripening_work_repository.dart';

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('${width.toInt()}pxで追熟作業の対象情報を表示できる', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_app(repository: FakeRipeningWorkRepository()));
      await tester.pumpAndSettle();

      expect(find.text('追熟-2026-001'), findsOneWidget);
      expect(find.text('20.50 kg'), findsOneWidget);
      expect(find.text('ヘイワード・M'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('360px・文字200%でも横方向に崩れない', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_app(repository: FakeRipeningWorkRepository()));
    await tester.pumpAndSettle();

    expect(find.text('追熟-2026-001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('注入内容を確認して完了しToDoへ戻る', (tester) async {
    final repository = FakeRipeningWorkRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => RipeningWorkPage(
                      repository: repository,
                      task: _task(WorkTaskType.ethyleneInjection),
                      currentDate: DateTime(2026, 9, 12, 10),
                    ),
                  ),
                ),
                child: const Text('作業を開く'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('作業を開く'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ripening-work-temperature')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const Key('ripening-work-confirm-input')),
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('ripening-work-actual-at')),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      '2026/09/12 10:00',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.descendant(
              of: find.byKey(const Key('ripening-work-location')),
              matching: find.byType(DropdownButtonFormField<String>),
            ),
          )
          .initialValue,
      'location-1',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.descendant(
              of: find.byKey(const Key('ripening-work-worker')),
              matching: find.byType(DropdownButtonFormField<String>),
            ),
          )
          .initialValue,
      'worker-1',
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('ripening-work-confirm-input')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('ripening-work-confirm-input')));
    await tester.pumpAndSettle();

    expect(find.text('エチレン注入の確認'), findsOneWidget);
    expect(find.text('追熟-2026-001'), findsNWidgets(2));
    expect(find.text('20.50 kg'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('ripening-work-complete')));
    await tester.pumpAndSettle();

    expect(repository.lastType, RipeningWorkType.ethyleneInjection);
    expect(repository.lastInput?.expectedVersion, 2);
    expect(find.text('完了を記録しました'), findsOneWidget);
    await tester.tap(find.text('ToDoへ戻る'));
    await tester.pumpAndSettle();
    expect(find.text('作業を開く'), findsOneWidget);
  });

  testWidgets('抜き確認では寝かせ開始と温度を必須入力にする', (tester) async {
    final repository = FakeRipeningWorkRepository();
    await tester.pumpWidget(
      _app(
        repository: repository,
        type: WorkTaskType.ethyleneRemovalCheck,
        date: DateTime(2026, 9, 13, 11),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('寝かせ開始日時（YYYY/MM/DD HH:mm）'), findsOneWidget);
    expect(find.text('寝かせ温度（℃）'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('ripening-work-rest-temperature')),
      '17',
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('ripening-work-confirm-input')),
    );
    await tester.tap(find.byKey(const Key('ripening-work-confirm-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ripening-work-complete')));
    await tester.pumpAndSettle();

    expect(repository.lastType, RipeningWorkType.ethyleneRemoval);
    expect(repository.lastInput?.restTemperature, 17);
    expect(repository.lastInput?.restStartedAt, DateTime(2026, 9, 13, 11));
  });

  testWidgets('結果不明の再確認は同じ冪等性キーを使う', (tester) async {
    final repository = FakeRipeningWorkRepository(completeFailures: 1);
    await tester.pumpWidget(_app(repository: repository));
    await tester.pumpAndSettle();
    await _confirm(tester);

    expect(find.text('完了結果を確認できませんでした。'), findsOneWidget);
    expect(find.text('問い合わせ番号 correlation-1'), findsOneWidget);
    await _confirm(tester);

    expect(repository.completionKeys, hasLength(2));
    expect(repository.completionKeys.first, repository.completionKeys.last);
  });

  testWidgets('競合後の再読込失敗を表示し古い詳細では送信させない', (tester) async {
    final repository = FakeRipeningWorkRepository(conflict: true);
    await tester.pumpWidget(_app(repository: repository));
    await tester.pumpAndSettle();
    await _confirm(tester);
    repository.loadFailures = 1;
    await tester.ensureVisible(find.text('最新状態を読み込む'));
    await tester.tap(find.text('最新状態を読み込む'));
    await tester.pumpAndSettle();
    expect(find.text('追熟作業を読み込めませんでした。'), findsOneWidget);
    expect(find.byKey(const Key('ripening-work-confirm-input')), findsNothing);
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();
    expect(find.text('最新情報を読み直してください。'), findsNothing);
    expect(repository.loadCalls, 3);
    expect(find.byKey(const Key('ripening-work-temperature')), findsNothing);
  });

  testWidgets('競合後は対象情報と送信versionを同じ最新詳細へ更新する', (tester) async {
    final repository = FakeRipeningWorkRepository(conflict: true);
    await tester.pumpWidget(_app(repository: repository));
    await tester.pumpAndSettle();
    await _confirm(tester);
    final old = repository.details;
    repository.details = RipeningWorkDetails(
      id: old.id,
      displayId: old.displayId,
      version: 9,
      status: old.status,
      weightHundredths: 3000,
      locationId: old.locationId,
      workerId: old.workerId,
      plannedEthyleneAt: DateTime(2026, 9, 15, 12),
      plannedCompletionAt: old.plannedCompletionAt,
      results: old.results,
      locations: old.locations,
      workers: old.workers,
      tasks: [
        RipeningWorkTask(
          type: 'ethylene_injection',
          productLabel: '新しい品種・L',
          scheduledAt: DateTime(2026, 9, 15, 12),
          dueAt: DateTime(2026, 9, 15, 13),
        ),
      ],
    );
    await tester.ensureVisible(find.text('最新状態を読み込む'));
    await tester.tap(find.text('最新状態を読み込む'));
    await tester.pumpAndSettle();
    expect(find.text('新しい品種・L'), findsOneWidget);
    expect(find.text('ヘイワード・M'), findsNothing);
    expect(find.text('30.00 kg'), findsOneWidget);
    expect(find.text('2026年9月15日 12:00'), findsOneWidget);
    expect(find.text('2026年9月15日 13:00'), findsOneWidget);
    repository.conflict = false;
    await _confirm(tester);
    expect(repository.lastInput!.expectedVersion, 9);
  });

  testWidgets('読込失敗から再試行できる', (tester) async {
    final repository = FakeRipeningWorkRepository(loadFailures: 1);
    await tester.pumpWidget(_app(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('追熟作業を読み込めませんでした。'), findsOneWidget);
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();

    expect(repository.loadCalls, 2);
    expect(find.text('追熟-2026-001'), findsOneWidget);
  });
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const Key('ripening-work-confirm-input')),
  );
  await tester.tap(find.byKey(const Key('ripening-work-confirm-input')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('ripening-work-complete')));
  await tester.pumpAndSettle();
}

Widget _app({
  required FakeRipeningWorkRepository repository,
  WorkTaskType type = WorkTaskType.ethyleneInjection,
  DateTime? date,
}) => MaterialApp(
  theme: buildAppTheme(),
  home: RipeningWorkPage(
    repository: repository,
    task: _task(type),
    currentDate: date ?? DateTime(2026, 9, 12, 10),
  ),
);

WorkTaskItem _task(WorkTaskType type) => WorkTaskItem(
  id: 'task-1',
  type: type,
  targetId: 'ripening-1',
  targetDisplayId: '追熟-2026-001',
  scheduledAt: DateTime(2026, 9, 12, 9),
  dueAt: DateTime(2026, 9, 12, 10),
  status: 'pending',
  targetUrl: '/work-tasks/task-1',
  variety: 'ヘイワード',
  grade: 'M',
  weightHundredths: 2050,
  location: '第1追熟庫',
);

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/process_board/process_board_page.dart';

import 'package:kiwi_inventory/process_board/process_board_repository.dart';
import 'package:kiwi_inventory/ripening_work/ripening_work_page.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';

import 'support/fake_ripening_work_repository.dart';
import 'support/fake_process_board_repository.dart';
import 'support/fake_ripening_plan_repository.dart';

void main() {
  group('工程ボード', () {
    testWidgets('4工程の件数・重量とコンテナ情報を一覧表示する', (tester) async {
      await _pumpBoard(tester, FakeProcessBoardRepository());

      for (final stage in ['選果済み', '追熟', '寝かせ', '出荷可能']) {
        expect(find.text(stage), findsOneWidget);
      }
      for (final summary in ['1コンテナ']) {
        expect(find.text(summary), findsNWidgets(4));
      }
      for (final weight in ['18.25 kg', '20.50 kg', '12.40 kg', '15.75 kg']) {
        expect(find.text(weight), findsWidgets);
      }
      expect(find.text('CONT-2026-0101'), findsOneWidget);
      expect(find.text('ヘイワード'), findsWidgets);
      expect(find.text('M'), findsWidgets);
      expect(find.text('保管期限'), findsOneWidget);
      expect(find.text('未設定'), findsOneWidget);
      expect(find.text('9/18 10:00'), findsOneWidget);
      expect(find.text('9/19 14:00'), findsOneWidget);
      expect(find.text('用途未確定'), findsNothing);
      expect(find.text('予備'), findsOneWidget);
      expect(find.text('受注'), findsOneWidget);
      expect(find.text('複合'), findsOneWidget);
      expect(find.text('詳細を見る →'), findsNothing);
    });

    testWidgets('選択した位置を保ったまま右側に詳細と次工程操作を開く', (tester) async {
      await _pumpBoard(
        tester,
        FakeProcessBoardRepository(),
        ripeningPlanRepository: FakeRipeningPlanRepository(),
      );

      await tester.tap(find.text('CONT-2026-0101'));
      await tester.pumpAndSettle();

      expect(find.text('コンテナ詳細'), findsOneWidget);
      expect(find.text('追熟計画を入力'), findsOneWidget);
      expect(find.text('CONT-2026-0101'), findsNWidgets(2));
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Draggable || widget is DragTarget,
        ),
        findsNothing,
      );
    });

    testWidgets('工程と用途を統合したアイコンに読み上げ名称がある', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpBoard(tester, FakeProcessBoardRepository());

      final node = tester.getSemantics(
        find.byKey(const Key('process-icon-container-ripening')),
      );
      expect(node.label, contains('追熟・受注・CONT-2026-0102'));
      semantics.dispose();
    });

    testWidgets('900px幅かつ文字200%でも主要操作と値が欠けない', (tester) async {
      await _pumpBoard(
        tester,
        FakeProcessBoardRepository(),
        size: const Size(900, 900),
        textScaler: const TextScaler.linear(2),
      );

      expect(find.text('工程ボード'), findsOneWidget);
      expect(find.text('最新状態を読み込む'), findsOneWidget);
      expect(find.text('18.25 kg'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('900px未満ではPC利用案内を表示する', (tester) async {
      await _pumpBoard(
        tester,
        FakeProcessBoardRepository(),
        size: const Size(899, 800),
      );

      expect(find.text('工程ボードはPCで使用してください'), findsOneWidget);
      expect(find.text('選果済み'), findsNothing);
    });

    testWidgets('一時的な読込失敗を再試行できる', (tester) async {
      final repository = FakeProcessBoardRepository(loadFailures: 1);
      await _pumpBoard(tester, repository);

      expect(find.text('工程ボードを表示できません'), findsOneWidget);
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      expect(find.text('選果済み'), findsOneWidget);
      expect(repository.loadCalls, 2);
    });

    testWidgets('複数予約の計画を切り替えて対応する注入作業を開く', (tester) async {
      final repository = FakeProcessBoardRepository(
        data: ProcessBoardData(
          items: [
            _boardItem(
              stage: ProcessStage.sorted,
              plans: [
                for (final id in ['plan-1', 'plan-2'])
                  ProcessBoardPlan(
                    id: id,
                    displayId: id,
                    useType: id == 'plan-1'
                        ? ProcessUseType.reserve
                        : ProcessUseType.order,
                    orderIds: const [],
                    orderNumbers: const [],
                    nextTask: _task(id, WorkTaskType.ethyleneInjection),
                  ),
              ],
            ),
          ],
        ),
      );
      await _pumpBoard(
        tester,
        repository,
        ripeningWorkRepository: FakeRipeningWorkRepository(),
      );
      await tester.tap(find.text('TEST-CONT'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('plan-2・受注').last);
      await tester.pumpAndSettle();
      // Locate the action by widget type to avoid depending on task label wording.
      final workButton = find.descendant(
        of: find.byType(SingleChildScrollView).last,
        matching: find.byType(FilledButton),
      );
      expect(workButton, findsOneWidget);
      await tester.ensureVisible(workButton);
      await tester.tap(workButton);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RipeningWorkPage>(find.byType(RipeningWorkPage))
            .task
            .targetId,
        'plan-2',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('熟度確認中に別端末で完了しても更新後は詳細へ戻る', (tester) async {
      final repository = FakeProcessBoardRepository(
        data: ProcessBoardData(
          items: [
            _boardItem(
              stage: ProcessStage.resting,
              task: _task('plan-1', WorkTaskType.ripenessCheck),
            ),
          ],
        ),
      );
      await _pumpBoard(
        tester,
        repository,
        ripeningWorkRepository: FakeRipeningWorkRepository(),
      );
      await tester.tap(find.text('TEST-CONT'));
      await tester.pumpAndSettle();
      final button = find.byType(FilledButton).last;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(RipeningWorkPage), findsOneWidget);

      repository.data = ProcessBoardData(
        items: [_boardItem(stage: ProcessStage.shippable)],
      );
      await tester.tap(find.text('最新状態を読み込む'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(RipeningWorkPage), findsNothing);
      expect(find.text('コンテナ詳細'), findsOneWidget);
      expect(find.text('出荷可能な割当受注はありません。'), findsOneWidget);
    });

    testWidgets('更新後に無効な受注選択を残さない', (tester) async {
      final repository = FakeProcessBoardRepository(
        data: ProcessBoardData(
          items: [
            _boardItem(stage: ProcessStage.shippable, orders: ['old', 'keep']),
          ],
        ),
      );
      await _pumpBoard(tester, repository);
      await tester.tap(find.text('TEST-CONT'));
      await tester.pumpAndSettle();
      repository.data = ProcessBoardData(
        items: [
          _boardItem(stage: ProcessStage.shippable, orders: ['keep', 'new']),
        ],
      );
      await tester.tap(find.text('最新状態を読み込む'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        'keep',
      );
    });

    testWidgets('更新失敗時は前回の表示と通知を残し、再試行成功で解消する', (tester) async {
      final repository = FakeProcessBoardRepository();
      await _pumpBoard(
        tester,
        repository,
        size: const Size(900, 900),
        textScaler: const TextScaler.linear(2),
      );
      repository.loadFailures = 1;
      await tester.tap(find.text('最新状態を読み込む'));
      await tester.pumpAndSettle();
      expect(repository.loadCalls, 2);
      expect(find.text('CONT-2026-0101'), findsOneWidget);
      expect(find.textContaining('表示中の情報は前回取得した内容です。'), findsOneWidget);
      expect(find.textContaining('工程ボードを読み込めませんでした。'), findsOneWidget);
      expect(tester.takeException(), isNull);

      repository.data = const ProcessBoardData(items: []);
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(repository.loadCalls, 3);
      expect(find.text('CONT-2026-0101'), findsNothing);
      expect(find.textContaining('更新に失敗しました。'), findsNothing);
      expect(find.text('再試行'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('管理者ホームの主要メニューから開ける', (tester) async {
      final repository = FakeProcessBoardRepository();
      await _setSurface(tester, const Size(1280, 900));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ManagerHomePage(processBoardRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('工程ボード'));
      await tester.pumpAndSettle();

      expect(find.byType(ProcessBoardPage), findsOneWidget);
      expect(repository.loadCalls, 1);
    });

    testWidgets('管理者ナビを含む画面幅900pxで利用できる', (tester) async {
      final repository = FakeProcessBoardRepository();
      await _setSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(900, 900)),
            child: ManagerProcessBoardPage(repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('選果済み'), findsOneWidget);
      expect(find.text('工程ボードはPCで使用してください'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpBoard(
  WidgetTester tester,
  FakeProcessBoardRepository repository, {
  Size size = const Size(1280, 900),
  TextScaler textScaler = TextScaler.noScaling,
  FakeRipeningPlanRepository? ripeningPlanRepository,
  FakeRipeningWorkRepository? ripeningWorkRepository,
}) async {
  await _setSurface(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
        child: ProcessBoardPage(
          repository: repository,
          ripeningPlanRepository: ripeningPlanRepository,
          ripeningWorkRepository: ripeningWorkRepository,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

WorkTaskItem _task(String plan, WorkTaskType type) => WorkTaskItem(
  id: 'task-$plan',
  type: type,
  targetId: plan,
  targetDisplayId: plan,
  scheduledAt: DateTime(2026, 9, 18),
  dueAt: DateTime(2026, 9, 19),
  status: 'pending',
  targetUrl: '/work-tasks/task-$plan',
);

ProcessBoardItem _boardItem({
  required ProcessStage stage,
  WorkTaskItem? task,
  List<ProcessBoardPlan> plans = const [],
  List<String> orders = const [],
}) => ProcessBoardItem(
  id: 'test-container',
  displayId: 'TEST-CONT',
  stage: stage,
  useType: ProcessUseType.mixed,
  variety: 'ヘイワード',
  grade: 'M',
  weightHundredths: 1000,
  status: stage.name,
  location: '冷蔵庫',
  needsReview: false,
  orderIds: orders,
  orderNumbers: orders,
  ripeningLotId: task?.targetId,
  nextTask: task,
  plans: plans,
);

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/process_board/process_board_page.dart';

import 'support/fake_process_board_repository.dart';
import 'support/fake_ripening_plan_repository.dart';

void main() {
  group('工程ボード', () {
    testWidgets('4工程の件数・重量とコンテナ情報を一覧表示する', (tester) async {
      await _pumpBoard(tester, FakeProcessBoardRepository());

      for (final stage in ['選果済み', '追熟', '寝かせ', '出荷可能']) {
        expect(find.text(stage), findsOneWidget);
      }
      for (final summary in [
        '1件　18.25 kg',
        '1件　20.50 kg',
        '1件　12.40 kg',
        '1件　15.75 kg',
      ]) {
        expect(find.text(summary), findsOneWidget);
      }
      expect(find.text('CONT-2026-0101'), findsOneWidget);
      expect(find.text('ヘイワード'), findsWidgets);
      expect(find.text('M'), findsWidgets);
      expect(find.text('保管期限 未設定'), findsOneWidget);
      expect(find.text('用途未確定'), findsOneWidget);
      expect(find.text('○ 予備'), findsOneWidget);
      expect(find.text('● 受注'), findsOneWidget);
      expect(find.text('⊙ 複合'), findsOneWidget);
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
      expect(find.text('18.25 kg'), findsOneWidget);
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

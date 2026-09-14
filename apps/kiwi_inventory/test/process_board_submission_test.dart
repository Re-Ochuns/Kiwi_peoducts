import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/ripening/ripening_plan_page.dart';
import 'package:kiwi_inventory/ripening/ripening_plan_repository.dart';

import 'support/fake_ripening_plan_repository.dart';

import 'dart:async';

import 'package:kiwi_inventory/process_board/process_board_page.dart';

import 'support/fake_process_board_repository.dart';

void main() {
  testWidgets('管理者の追熟計画は登録完了後にホームへ戻る', (tester) async {
    final repository = FakeRipeningPlanRepository();
    await _setSurface(tester, const Size(1280, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ManagerHomePage(
          ripeningPlanRepository: repository,
          currentDate: DateTime(2026, 9, 12, 9),
        ),
      ),
    );
    await tester.tap(find.text('追熟計画'));
    await tester.pumpAndSettle();
    await _completeMixedForm(tester);
    await _submitFromDialog(tester);
    await tester.tap(find.byKey(const Key('ripening-complete-close')));
    await tester.pumpAndSettle();
    expect(repository.confirmCalls, 1);
    expect(
      find.byType(RipeningPlanPage),
      findsNothing,
      reason: 'The existing manager flow must leave the completed form.',
    );
  });
  for (final fail in [false, true]) {
    testWidgets('送信中の離脱を防ぎ、確定の成功・失敗後に操作を戻す ($fail)', (tester) async {
      final repository = _DelayedRepository(confirmFailures: fail ? 1 : 0);
      await _setSurface(tester, const Size(1280, 900));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ManagerProcessBoardPage(
            repository: FakeProcessBoardRepository(),
            ripeningPlanRepository: repository,
            currentDate: DateTime(2026, 9, 12, 9),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONT-2026-0101'));
      await tester.pumpAndSettle();
      final open = find.widgetWithText(FilledButton, '追熟計画を入力');
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      await _completeMixedForm(tester);
      await _tapVisible(tester, find.byKey(const Key('ripening-review')));
      await tester.tap(find.byKey(const Key('ripening-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.registerCalls, 1);

      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '閉じる'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '← 詳細へ戻る'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ManagerNavigation>(find.byType(ManagerNavigation))
            .onSelected,
        isNull,
      );
      final refresh = find.widgetWithText(OutlinedButton, '最新状態を読み込む');
      expect(tester.widget<OutlinedButton>(refresh).onPressed, isNull);
      // Clicking another card cannot dispose the in-flight form.
      await tester.tap(find.text('CONT-2026-0102'));
      await tester.pump();
      expect(find.byType(RipeningPlanPage), findsOneWidget);
      final pop = tester.widget<PopScope>(
        find
            .descendant(
              of: find.byType(ProcessBoardPage),
              matching: find.byType(PopScope),
            )
            .first,
      );
      expect(pop.canPop, isFalse);
      tester.view.physicalSize = const Size(899, 900);
      await tester.pump();
      expect(find.byType(RipeningPlanPage), findsOneWidget);
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, '閉じる'));
      await tester.pump();
      repository.gate.complete();
      await tester.pumpAndSettle();
      expect(
        repository.confirmCalls,
        1,
        reason: 'A persisted draft must not be abandoned by closing the panel mid-request.',
      );
      if (!fail) {
        await tester.tap(find.byKey(const Key('ripening-complete-close')));
        await tester.pumpAndSettle();
        expect(find.byType(RipeningPlanPage), findsNothing);
      } else {
        expect(find.textContaining('通信状況を確認'), findsOneWidget);
        expect(find.byType(RipeningPlanPage), findsOneWidget);
      }
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '閉じる'))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<ManagerNavigation>(find.byType(ManagerNavigation))
            .onSelected,
        isNotNull,
      );
      expect(tester.widget<OutlinedButton>(refresh).onPressed, isNotNull);
    });
  }
}

class _DelayedRepository extends FakeRipeningPlanRepository {
  _DelayedRepository({super.confirmFailures});
  final gate = Completer<void>();
  @override
  Future<RipeningPlanResult> register({
    required RipeningPlanInput input,
    required String idempotencyKey,
  }) async {
    final result = await super.register(
      input: input,
      idempotencyKey: idempotencyKey,
    );
    await gate.future;
    return result;
  }
}

Future<void> _completeMixedForm(WidgetTester tester) async {
  await _selectValue(
    tester,
    const Key('ripening-inventory'),
    testRipeningOptions.inventories.single,
  );
  await tester.enterText(
    find.byKey(const Key('ripening-harvest-year')),
    '2026',
  );
  await tester.enterText(find.byKey(const Key('ripening-harvest-month')), '9');
  await tester.enterText(find.byKey(const Key('ripening-weight')), '10');
  await _selectValue(
    tester,
    const Key('ripening-allocation-order-0'),
    'order-1',
  );
  await tester.enterText(
    find.byKey(const Key('ripening-allocation-weight-0')),
    '6',
  );
  await _pressButton<OutlinedButton>(
    tester,
    const Key('ripening-add-allocation'),
  );
  await _selectValue(
    tester,
    const Key('ripening-allocation-type-1'),
    RipeningAllocationType.reserve,
  );
  await tester.enterText(
    find.byKey(const Key('ripening-allocation-weight-1')),
    '4',
  );
  await _selectValue(tester, const Key('ripening-location'), 'location-1');
  await _selectValue(tester, const Key('ripening-worker'), 'worker-1');
  await tester.pump();

  expect(find.text('未割当　0.00 kg'), findsOneWidget);
  final review = tester.widget<FilledButton>(
    find.byKey(const Key('ripening-review')),
  );
  expect(review.onPressed, isNotNull);
}

Future<void> _submitFromDialog(WidgetTester tester) async {
  await _tapVisible(tester, find.byKey(const Key('ripening-review')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('ripening-submit')));
  await tester.pumpAndSettle();
}

Future<void> _selectValue(WidgetTester tester, Key key, Object value) async {
  final dynamic field = tester.widget(find.byKey(key));
  field.onChanged(value);
  await tester.pump();
}

Future<void> _pressButton<T extends ButtonStyleButton>(
  WidgetTester tester,
  Key key,
) async {
  final button = tester.widget<T>(find.byKey(key));
  button.onPressed!.call();
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

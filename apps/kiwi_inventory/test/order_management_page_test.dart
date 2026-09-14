import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/app_theme.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/orders/order_management_page.dart';
import 'package:kiwi_inventory/orders/order_management_repository.dart';

import 'support/fake_order_management_repository.dart';
import 'support/fake_ripening_plan_repository.dart';

void main() {
  testWidgets('ホームから追熟計画を経由して受注管理へ遷移する', (tester) async {
    final repository = FakeOrderManagementRepository();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ManagerHomePage(
          orderManagementRepository: repository,
          ripeningPlanRepository: FakeRipeningPlanRepository(),
        ),
      ),
    );
    await tester.tap(find.text('追熟計画').first);
    await tester.pumpAndSettle();
    expect(find.byType(ManagerRipeningPlanPage), findsOneWidget);
    await tester.tap(find.text('受注').first);
    await tester.pumpAndSettle();
    expect(find.byType(OrderManagementPage), findsOneWidget);
    expect(repository.loadCalls, 1);
  });

  for (final value in ['0.07', '1.10', '2.01', '4.10']) {
    testWidgets('注文量$value kgを保存できる', (tester) async {
      final repository = FakeOrderManagementRepository();
      await _pump(tester, repository);
      await tester.tap(find.byKey(const Key('order-register')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('order-weight')), value);
      await tester.tap(find.byKey(const Key('order-confirm-input')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('order-save')));
      await tester.pumpAndSettle();
      expect(repository.lastOrderInput?.orderedWeight, double.parse(value));
    });
  }

  testWidgets('0.01kg未満の桁と非有限値を拒否する', (tester) async {
    final repository = FakeOrderManagementRepository();
    await _pump(tester, repository);
    await tester.tap(find.byKey(const Key('order-register')));
    await tester.pumpAndSettle();
    for (final value in ['1.001', 'NaN', 'Infinity', '0', '-1']) {
      await tester.enterText(find.byKey(const Key('order-weight')), value);
      await tester.tap(find.byKey(const Key('order-confirm-input')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-save')), findsNothing);
    }
    expect(repository.registerOrderCalls, 0);
  });

  testWidgets('顧客一覧の検索結果にない顧客の受注も編集できる', (tester) async {
    final repository = FakeOrderManagementRepository();
    final data = await repository.load(filter: OrderListFilter.active);
    final detail = await repository.loadOrder(repository.order.id);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: OrderFormDialog(
            repository: repository,
            existing: detail,
            data: OrderManagementData(
              orders: data.orders,
              customers: const [],
              orderCustomers: data.customers,
              varieties: data.varieties,
              grades: data.grades,
              canManage: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byKey(const Key('order-reason')), '数量変更');
    await tester.tap(find.byKey(const Key('order-confirm-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('order-save')));
    await tester.pumpAndSettle();
    expect(repository.lastOrderInput?.customerId, repository.customer.id);
  });

  testWidgets('管理ホームから受注管理へ遷移する', (tester) async {
    final repository = FakeOrderManagementRepository();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ManagerHomePage(orderManagementRepository: repository),
      ),
    );

    await tester.tap(find.text('受注'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderManagementPage), findsOneWidget);
    expect(repository.loadCalls, 1);
  });

  testWidgets('900px管理画面では表を維持して詳細をダイアログ表示する', (tester) async {
    final repository = FakeOrderManagementRepository();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ManagerOrderPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未計画 7.50 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('受注-2026-001'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('受注詳細'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('900px・文字200%でも受注の絞り込みと重量を確認できる', (tester) async {
    final repository = FakeOrderManagementRepository();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ManagerOrderPage(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('20.00 kg'), findsOneWidget);
    expect(find.text('未計画 7.50 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('order-status-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル').last);
    await tester.pumpAndSettle();

    expect(repository.lastFilter, OrderListFilter.cancelled);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未出荷受注を初期表示し未計画量を文字で識別できる', (tester) async {
    final repository = FakeOrderManagementRepository();
    await _pump(tester, repository);

    expect(repository.lastFilter, OrderListFilter.active);
    expect(find.text('受注-2026-001'), findsOneWidget);
    expect(find.text('未計画 7.50 kg'), findsOneWidget);
    expect(find.textContaining('ヘイワード・L'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('受注詳細を選択した時だけ配送先住所を表示する', (tester) async {
    final repository = FakeOrderManagementRepository();
    await _pump(tester, repository);

    expect(find.textContaining('東京都千代田区1-1'), findsNothing);
    await tester.tap(find.text('受注-2026-001'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-detail')), findsOneWidget);
    expect(find.textContaining('東京都千代田区1-1'), findsOneWidget);
    expect(find.text('追熟割当'), findsOneWidget);
  });

  testWidgets('受注を入力確認後に登録する', (tester) async {
    final repository = FakeOrderManagementRepository();
    await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('order-register')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('order-weight')), '20.00');
    await tester.tap(find.byKey(const Key('order-confirm-input')));
    await tester.pumpAndSettle();
    expect(find.text('この内容で保存'), findsOneWidget);
    expect(repository.registerOrderCalls, 0);

    await tester.tap(find.byKey(const Key('order-save')));
    await tester.pumpAndSettle();
    expect(repository.registerOrderCalls, 1);
    expect(repository.lastOrderInput?.orderedWeight, 20);
    expect(find.text('登録完了'), findsOneWidget);
  });

  testWidgets('理由を確認して下書き受注を確定する', (tester) async {
    final repository = FakeOrderManagementRepository();
    await _pump(tester, repository);
    await tester.tap(find.text('受注-2026-001'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('受注を確定'));
    await tester.tap(find.text('受注を確定'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('order-transition-save')));
    await tester.pump();
    expect(find.text('理由を入力してください。'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('order-transition-reason')),
      '内容確認済み',
    );
    await tester.tap(find.byKey(const Key('order-transition-save')));
    await tester.pumpAndSettle();

    expect(repository.confirmCalls, 1);
    expect(find.text('更新完了'), findsOneWidget);
  });

  testWidgets('顧客一覧と複数配送先の管理入口を表示する', (tester) async {
    final repository = FakeOrderManagementRepository();
    await _pump(tester, repository);
    await tester.tap(find.text('顧客・配送先'));
    await tester.pumpAndSettle();

    expect(find.text('C-001'), findsOneWidget);
    expect(find.text('1件'), findsOneWidget);
    await tester.tap(find.text('C-001'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer-detail')), findsOneWidget);
    expect(find.text('配送先を追加'), findsOneWidget);
    expect(find.text('本店\n受取担当者\n〒100-0001 東京都千代田区1-1'), findsOneWidget);
  });

  testWidgets('閲覧利用者には更新操作を表示しない', (tester) async {
    await _pump(tester, FakeOrderManagementRepository(canManage: false));
    expect(find.byKey(const Key('order-register')), findsNothing);
    await tester.tap(find.text('受注-2026-001'));
    await tester.pumpAndSettle();
    expect(find.text('受注を編集'), findsNothing);
    expect(find.text('受注を確定'), findsNothing);
    expect(find.text('受注をキャンセル'), findsNothing);
  });

  testWidgets('再読込失敗時は古い一覧を残さずエラーを表示する', (tester) async {
    final repository = FakeOrderManagementRepository();
    await _pump(tester, repository);
    repository.nextFailure = const OrderManagementFailure(
      message: '再読込に失敗しました。',
      retryable: true,
    );
    await tester.enterText(find.byKey(const Key('order-search')), '青果店');
    await tester.tap(find.text('検索'));
    await tester.pumpAndSettle();

    expect(find.text('受注と顧客を読み込めませんでした'), findsOneWidget);
    expect(find.text('再読込に失敗しました。'), findsOneWidget);
    expect(find.text('受注-2026-001'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeOrderManagementRepository repository,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: OrderManagementPage(repository: repository)),
    ),
  );
  await tester.pumpAndSettle();
}

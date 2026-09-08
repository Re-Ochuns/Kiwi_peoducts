import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';

void main() {
  testWidgets('スマートフォン幅で作業者ホームを表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KiwiInventoryApp());

    expect(find.text('おおくま農園'), findsOneWidget);
    expect(find.text('ToDo'), findsOneWidget);
    expect(find.text('収穫・仕入れ登録'), findsOneWidget);
    expect(find.text('追熟計画作成'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('PC幅で管理ホームを表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KiwiInventoryApp());

    expect(find.text('ホーム'), findsAtLeastNWidgets(1));
    expect(find.text('受注'), findsOneWidget);
    expect(find.text('在庫管理'), findsOneWidget);
    expect(find.text('優先して確認'), findsOneWidget);
  });

  testWidgets('ToDoから詳細を開いて戻れる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KiwiInventoryApp());

    await tester.tap(find.text('LOT-2026-0142'));
    await tester.pumpAndSettle();
    expect(find.text('対象ID'), findsOneWidget);
    expect(find.text('← ToDoへ戻る'), findsOneWidget);

    await tester.tap(find.text('← ToDoへ戻る'));
    await tester.pumpAndSettle();
    expect(find.text('作業を始める'), findsOneWidget);
  });
}

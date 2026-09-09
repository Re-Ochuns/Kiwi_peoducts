import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';

void main() {
  group('レスポンシブ基盤', () {
    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('${width.toInt()}px幅で作業者ホームを表示する', (tester) async {
        await _setSurface(tester, Size(width, 900));
        await tester.pumpWidget(const KiwiInventoryApp());

        expect(find.text('おおくま農園'), findsOneWidget);
        expect(find.text('ToDo'), findsOneWidget);
        expect(find.text('収穫・仕入れ登録'), findsOneWidget);
        expect(find.text('追熟計画作成'), findsOneWidget);
        expect(find.byType(BottomNavigationBar), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in [900.0, 1280.0]) {
      testWidgets('${width.toInt()}px幅で管理ホームを表示する', (tester) async {
        await _setSurface(tester, Size(width, 900));
        await tester.pumpWidget(const KiwiInventoryApp());

        expect(find.text('ホーム'), findsAtLeastNWidgets(1));
        expect(find.text('受注'), findsOneWidget);
        expect(find.text('在庫管理'), findsOneWidget);
        expect(find.text('優先して確認'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('ToDoから詳細を開いて戻れる', (tester) async {
      await _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(const KiwiInventoryApp());

      await tester.tap(find.text('LOT-2026-0142'));
      await tester.pumpAndSettle();
      expect(find.text('対象ID'), findsOneWidget);
      expect(find.text('← ToDoへ戻る'), findsOneWidget);

      await tester.tap(find.text('← ToDoへ戻る'));
      await tester.pumpAndSettle();
      expect(find.text('作業を始める'), findsOneWidget);
    });

    testWidgets('詳細への矢印操作に対象を含む読み上げ名がある', (tester) async {
      await _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(const KiwiInventoryApp());

      expect(find.bySemanticsLabel('LOT-2026-0142の詳細を見る'), findsOneWidget);
    });
  });
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

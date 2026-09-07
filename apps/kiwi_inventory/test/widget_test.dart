import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';

void main() {
  testWidgets('アプリ名を表示する', (WidgetTester tester) async {
    await tester.pumpWidget(const KiwiInventoryApp());

    expect(find.text('キウイ在庫管理'), findsOneWidget);
  });
}

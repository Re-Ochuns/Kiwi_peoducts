import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';

void main() {
  final goldenDate = DateTime(2026, 9, 8);

  testWidgets('390pxの作業者ホーム', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(KiwiInventoryApp(currentDate: goldenDate));

    await expectLater(
      find.byType(KiwiInventoryApp),
      matchesGoldenFile('goldens/worker_home_390.png'),
    );
  });

  testWidgets('1280pxの管理ホーム', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(KiwiInventoryApp(currentDate: goldenDate));

    await expectLater(
      find.byType(KiwiInventoryApp),
      matchesGoldenFile('goldens/manager_home_1280.png'),
    );
  });
}

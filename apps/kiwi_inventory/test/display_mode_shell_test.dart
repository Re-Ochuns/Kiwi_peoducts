import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/core/display_mode_shell.dart';

import 'widget_test.dart' show FakeAuthRepository;

void main() {
  Future<void> start(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      KiwiInventoryApp(authRepository: FakeAuthRepository.active()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'phone can select PC and switch back at the same header position',
    (tester) async {
      await start(tester, 390);
      final button = find.byKey(const ValueKey('display-mode-toggle'));
      final position = tester.getTopLeft(button);
      expect(find.text('PC画面へ'), findsOneWidget);
      expect(find.byType(WorkerHomePage), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(ManagerHomePage), findsOneWidget);
      expect(tester.getTopLeft(button), position);
      expect(find.text('スマホ画面へ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('display-mode-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkerHomePage), findsOneWidget);
      expect(tester.getTopLeft(button), position);
    },
  );

  testWidgets('desktop can switch to phone and back', (tester) async {
    await start(tester, 1280);
    await tester.tap(find.byKey(const ValueKey('display-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(WorkerHomePage), findsOneWidget);
    expect(tester.getSize(find.byType(WorkerHomePage)).width, 430);
    expect(find.text('PC画面へ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('display-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(ManagerHomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header survives navigation and mode change returns home', (
    tester,
  ) async {
    await start(tester, 390);
    await tester.tap(find.text('LOT-2026-0142'));
    await tester.pumpAndSettle();
    expect(find.text('対象ID'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('display-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(ManagerHomePage), findsOneWidget);
    expect(find.text('対象ID'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked navigation does not discard page or change display', (
    tester,
  ) async {
    await tester.pumpWidget(
      DisplayModeShell(
        appBuilder: (navigator, frame) => MaterialApp(
          navigatorKey: navigator,
          builder: frame,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PopScope(
                      canPop: false,
                      child: Scaffold(body: Text('unsaved')),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('display-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('unsaved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

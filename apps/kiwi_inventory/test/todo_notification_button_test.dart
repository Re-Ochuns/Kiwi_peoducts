import 'dart:async';

import 'package:kiwi_inventory/main.dart';

import 'widget_test.dart' show FakeAuthRepository;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:kiwi_inventory/notifications/todo_notification_button.dart';
import 'package:kiwi_inventory/notifications/todo_notification_repository.dart';

class FakeNotifications implements TodoNotificationRepository {
  bool allowed = true;
  int calls = 0;
  String result = 'sent';
  Completer<String>? pending;
  @override
  Future<bool> canNotify() async => allowed;
  @override
  Future<String> notify(String requestId) async {
    calls++;
    return pending?.future ?? result;
  }
}

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('notification is present on home at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        KiwiInventoryApp(
          authRepository: FakeAuthRepository.active(),
          todoNotificationRepository: FakeNotifications(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Discordに通知'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  Future<void> start(WidgetTester tester, FakeNotifications repo) async {
    await tester.pumpWidget(
      Provider<TodoNotificationRepository?>.value(
        value: repo,
        child: const MaterialApp(
          home: Scaffold(body: TodoNotificationButton()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('only confirmed administrators see the notification button', (
    tester,
  ) async {
    await start(tester, FakeNotifications()..allowed = false);
    expect(find.text('Discordに通知'), findsNothing);
  });
  testWidgets('button prevents double send and reports success', (
    tester,
  ) async {
    final repo = FakeNotifications()..pending = Completer<String>();
    await start(tester, repo);
    await tester.tap(find.text('Discordに通知'));
    await tester.pump();
    await tester.tap(find.text('通知中…'));
    expect(repo.calls, 1);
    repo.pending!.complete('sent');
    await tester.pumpAndSettle();
    expect(find.text('本日のToDoをDiscordに通知しました。'), findsOneWidget);
  });
  testWidgets('missing config never displays success', (tester) async {
    await start(tester, FakeNotifications()..result = 'not_configured');
    await tester.tap(find.text('Discordに通知'));
    await tester.pumpAndSettle();
    expect(find.textContaining('通知先が未設定'), findsOneWidget);
    expect(find.text('本日のToDoをDiscordに通知しました。'), findsNothing);
  });
}

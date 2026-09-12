import 'dart:async';

import 'package:kiwi_inventory/auth/supabase_auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/main.dart';
import 'package:kiwi_inventory/auth/auth_repository.dart';
import 'package:kiwi_inventory/work_tasks/work_task_repository.dart';

import 'support/fake_work_task_repository.dart';

class SignedOutAuth implements AuthRepository {
  AuthUser? user;
  final changes = StreamController<AuthUser?>.broadcast();
  @override
  AuthUser? get currentUser => user;
  @override
  Stream<AuthUser?> get authStateChanges => changes.stream;
  @override
  Future<void> signInWithGoogle() async {
    user = const AuthUser(id: 'user-1');
    changes.add(user);
  }

  @override
  Future<void> signOut() async {}
  @override
  Future<UserAccessStatus> loadAccessStatus(String id) async =>
      UserAccessStatus.active;
}

class Tasks implements WorkTaskRepository {
  List<WorkTaskItem> values = [testWorkTasks.first];
  int reads = 0;
  int detailReads = 0;

  @override
  Future<List<WorkTaskItem>> loadTasks() async {
    reads++;
    return List.of(values);
  }

  @override
  Future<WorkTaskItem?> loadTask(String id) async {
    detailReads++;

    return values.first;
  }
}

void main() {
  testWidgets('pull to refresh loads newly created tasks from an empty list', (
    tester,
  ) async {
    final tasks = Tasks()..values = [];
    await tester.pumpWidget(
      MaterialApp(home: WorkerHomePage(workTaskRepository: tasks)),
    );
    await tester.pumpAndSettle();
    expect(find.text('予定されている作業はありません'), findsOneWidget);
    tasks.values = [testWorkTasks.first];
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(tasks.reads, 2);
    expect(find.text('追熟-2026-001'), findsOneWidget);
  });
  test('OAuth return retains task route for hash and path URLs', () {
    expect(
      authRedirectTo(Uri.parse('https://example.test/#/work-tasks/task-1')),
      'https://example.test/#/work-tasks/task-1',
    );
    expect(
      authRedirectTo(Uri.parse('https://example.test/work-tasks/task-1')),
      'https://example.test/#/work-tasks/task-1',
    );
    expect(
      authRedirectTo(Uri.parse('https://example.test/?code=secret')),
      'https://example.test',
    );
  });
  testWidgets('signed-out deep link should expose login', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/work-tasks/task-overdue';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final auth = SignedOutAuth();
    addTearDown(auth.changes.close);
    final tasks = Tasks();
    await tester.pumpWidget(
      KiwiInventoryApp(authRepository: auth, workTaskRepository: tasks),
    );
    await tester.pumpAndSettle();
    expect(find.text('Googleでログイン'), findsOneWidget);
    expect(tasks.detailReads, 0);
    await tester.tap(find.text('Googleでログイン'));
    await tester.pumpAndSettle();
    expect(find.text('作業確認'), findsOneWidget);
    expect(tasks.detailReads, 1);
  });
  testWidgets('returning to ToDo should refresh completed tasks', (
    tester,
  ) async {
    final tasks = Tasks();
    await tester.pumpWidget(
      MaterialApp(
        home: WorkerHomePage(
          workTaskRepository: tasks,
          currentDate: DateTime(2026, 9, 12, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('追熟-2026-001'));
    await tester.tap(find.text('追熟-2026-001'));
    await tester.pumpAndSettle();
    tasks.values = [];
    await tester.tap(find.text('← ToDoへ戻る'));
    await tester.pumpAndSettle();
    expect(find.text('追熟-2026-001'), findsNothing);
    expect(tasks.reads, greaterThan(1));
  });
}

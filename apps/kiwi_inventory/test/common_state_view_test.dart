import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_inventory/core/common_state_view.dart';

void main() {
  testWidgets('空状態を説明する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CommonStateView.empty(
            title: '対象の作業はありません',
            message: '条件を変更して確認してください。',
          ),
        ),
      ),
    );

    expect(find.text('対象の作業はありません'), findsOneWidget);
    expect(find.text('条件を変更して確認してください。'), findsOneWidget);
  });

  testWidgets('エラー状態から再試行できる', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommonStateView.error(
            title: '読み込めませんでした',
            message: '通信状況を確認してください。',
            actionLabel: '再試行',
            onAction: () => retried = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('再試行'));
    expect(retried, isTrue);
  });
}

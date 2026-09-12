# Issue #61: 追熟作業フロントの先行実装

対象: develop 73c7e6a を起点とする codex/61-worker-ripening。
検証日: 2026-09-13。確認者: Codex。
環境: WSL Ubuntu / Flutter 3.47.2 / Dart 3.13.2。

## 実装
- 注入、抜き確認と寝かせ開始、追熟確認を工程別に表示。
- 対象ID・重量・品種等級・場所・予定日時温度を表示。
- 実績日時は確認時の現在日時。日付・時刻を手動変更可能。
- 温度・担当者・備考・工程別実施確認を入力し、対象IDと重量を再確認して保存。
- 保存中の二重送信防止。通信結果不明時は同じ入力とUUIDで再送。
- 非再送可能エラー時は操作を止め、最新状態の再取得を要求。
- Repositoryを注入したToDoおよび認証後の /work-tasks/:id から直接表示。

## ローカル検証
実行ディレクトリ: apps/kiwi_inventory
- flutter analyze
- flutter test --exclude-tags golden
- flutter test test/ripening_work_page_test.dart
- flutter test test/home_golden_test.dart
- flutter build web --release

Widget: 3工程 × 360/390/430px の入力・確認・完了、必須確認、
不正温度、閲覧権限、完了済み、読み込み失敗、再送、競合、
連打、ToDo・直接リンクをFake Repositoryで検証。
Golden: 各工程・各幅の入力画面と確認モーダル18画像を追加。
DBリセットや既存サービスの変更は行っていない。

## #62 待ち（未完了）
更新RPCの個別契約・実装が未提供のため、Supabaseアダプターは未実装。
本番起動時にFake Repositoryを注入しない。既存の本番画面は従来の
作業詳細表示を維持し、今回の保存操作はまだ利用できない。

RipeningWorkRepositoryはフロント内部の境界でありRPC契約ではない。
#62 の契約確定後に以下を実装・確認する:
- taskIdから最新工程、計画温度、担当候補、更新可否、versionを取得。
- completeで入力と同一idempotencyKeyを承認済みRPCに渡す。
- バックエンドの権限・状態・必須確認・実績日時温度制約を反映。
- 抜き確認と寝かせ開始の原子更新、出荷可能遷移、履歴、
  確定済み受注・予備内訳の維持を実DBで検証。
- 認証済みブラウザでGoogleカレンダーリンクから保存・ToDo再取得を確認。
- 実機、現場担当レビュー、CI結果のIssueへの記録。

現時点のFakeによる自動テストを実DBのローカル受入確認とみなさない。
Issue #61をCloseせず、Draft PRとして依存解消を待つ。

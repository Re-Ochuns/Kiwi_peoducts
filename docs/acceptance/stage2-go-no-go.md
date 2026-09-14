# S2 ローカル統合受入・Go/No-Go記録（#59）

## 判定

**ローカル技術検証: Pass。現場・運用開始: No-Go（確認待ち）。**

2026-09-13、Codexがユーザーの依頼で実施。ユーザーから「実機・現場リハーサルは未実施、ローカル検証を先行」と回答を得た。現場確認・業務責任者レビューを自動検証で代替しない。今回の変更は受入テストと記録のみで、業務コードを変更しない。

- 業務コードの対象: `73c7e6a1ef584debdfffd4a2ecedf2bfb0fe724c`（develop、#84マージ後）
- 受入テスト: 本PRの `stage2_live_acceptance_test.dart`
- 作業場所: `kiwi-verification/issue59`。既存の未追跡ファイルと検証ブランチを維持
- 専用環境: `kiwi_s2_acceptance`、API `127.0.0.1:58321`、DB `58322`
- Flutter 3.47.2 / Dart 3.13.2 / Supabase CLI 2.117.0 / PostgreSQL 17.6 / PostgREST v16.2
- 本コミットの全migrationと架空seedを新規環境へ適用。既存kiwi_productsへ書き込み・resetなし

## 検証結果

| 対象 | 期待結果 | 実測 |
| --- | --- | --- |
| Flutter format / analyze | エラーなし | Pass |
| Flutter自動テスト | 既存機能の回帰なし | 197件成功 |
| Linux Golden | 画面画像の回帰なし | 13件成功 |
| Web release build | ビルド成功 | Pass |
| DB lint | schemaエラーなし | Pass |
| 全pgTAP | 権限・業務制約・同時処理の整合性 | 16ファイル670項目成功 |
| Edge Functions | 同期、再送、中止、認証、PDFの回帰なし | 34件成功、型検査成功 |
| 実Repository統合 | 実Auth/PostgREST/DBで業務フローが成立 | 2シナリオ成功（詳細は次節） |

DBの並行テストは検証コピー中の接続先 `supabase_db_kiwi_products` を専用コンテナ名へ置換した。テストのassertion・業務SQLは変更していない。

対象developのCI:
- [Flutter CI（quality / golden / web-build）](https://github.com/Re-Ochuns/Kiwi_peoducts/actions/runs/34720261263)
- [Database CI](https://github.com/Re-Ochuns/Kiwi_peoducts/actions/runs/34720261220)

## 実APIの縦断確認

`SupabaseOrderManagementRepository`、`SupabaseRipeningPlanRepository`、`SupabaseWorkTaskRepository`、`DefaultManagerDashboardRepository`を実HTTPへ接続した。Authで発行したJWTを使用し、業務操作の応答をFakeへ置き換えていない。

1. 管理者が顧客・2配送先を登録・更新し、詳細とversionを確認。
2. 未認証の一覧拒否、member/pendingの顧客更新拒否、pendingの一覧非表示、管理者の管理権限を確認。
3. 1.10kg受注登録、2.01kg更新、0kg拒否、古いversionの競合拒否を確認。
4. 実DBコミット後にHTTP応答のみ破棄。Repositoryの自動再送で同じ受注IDへ回復。同一キーの再送・同時2要求でも同一ID。
5. 2件の4kg受注を確定。作業者が各受注2kg＋予備2kgの6kg複合計画を作成し、10kgコンテナから6kgを部分予約。
6. 同一キー同時作成は1計画に収束し、使用可能量は4kg。さらに6kgを予約する要求はINVENTORY_UNAVAILABLE。
7. 計画確定後に3作業タスクを取得。表示ID・重量・詳細取得を確認。注入から抜き確認までは168時間。
8. PC予定用Repositoryでも同じ3タスクと、各受注2kgの不足を取得。顧客一覧を検索しても受注編集候補は欠落しない。
9. 受注キャンセルで計画がdraft・needs_reviewへ戻り、旧タスクはToDoから外れる。計画中止後は全3タスクがcancelled、在庫使用可能量は10kgへ復元。

SQLを使用したのは架空ユーザー・10kg在庫の準備と、読み取りの整合性確認。実端末2台の代わりに複数HTTP要求を用いており、実端末試験とは区別する。実Google OAuthログインは今回検証していない。

## カレンダーの扱い

#79はユーザー判断でクローズされているが、全条件の確認完了を意味しない。[確認記録](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/79#issuecomment-5645873758)にある実Googleの作成・日付更新・再送の重複防止・中止表示・DB紐付けを既存証跡として参照する。今回、実Googleへ予定を追加・変更していない。

同期・再試行・中止のDB/Edge自動テストはPass。デプロイ先のSecrets/Vault、定期実行、実Googleの手動変更上書き、権限拒否からの復旧、ログインを含む予定リンク遷移は、対象環境での確認が残る。

## 残課題・受入条件

| 項目 | 状態 | 担当領域 |
| --- | --- | --- |
| 自動テスト、実API縦断、内訳・予約・使用可能量 | Pass | 開発 |
| P0/P1の未解決不具合 | 今回の検証範囲で未検出。全運用範囲の保証ではない | 開発・レビュー担当 |
| 実ブラウザでのログインから業務完了までのE2E | 未実施（Widget/Repository試験と区別） | 開発・確認者 |
| 実機・現場リハーサル、複数端末の現場操作 | 未実施 | 現場責任者・作業者 |
| 実環境カレンダー残項目 | 未実施、#79コメントから継続追跡 | 運用・カレンダー管理者 |
| 業務責任者・担当領域レビューと運用開始判断 | 未実施 | 各担当者 |

上記が完了するまで#59はOpenを維持する。このPRのマージだけで#59を自動Closeしない。
現場ではPC900px以上とスマホ360/390/430pxで同じ受注・計画・ToDoを確認し、通信断・再送・競合・中止の結果を記録する。確認者、日時、端末、対象コミット、期待結果と実測、残課題を追記して最終判定を更新する。

## 証跡と後片付け

ローカルログは `kiwi-verification/issue59-runtime/` の `flutter.log`、`golden.log`、`db-lint.log`、`db-test.log`、`live.log`。認証情報はコミットせず、検証終了時に削除する。専用環境は停止し、架空データのみ専用Docker volumeに保持する。再実行手順は[stage2-local-verification.md](stage2-local-verification.md)。

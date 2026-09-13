# Issue #63 ローカル検証

- 検証日: 2026-09-13
- 検証者: Codex
- 初回検証の対象実装コミット: `8d3370e02686c50e39b74ebb6bb59aa6d944ddd0`
- ブランチ: `codex/63-ripening-deadlines`
- 初回検証ではdevelop `43175b2`（追熟ラベル #92）を取り込んで検証。
- 作業場所: `/home/kugis/products/hackathon/kiwi-verification/issue63`
- DB設定: `/home/kugis/products/hackathon/kiwi-verification/issue63-runtime/supabase/config.toml`
- 専用プロジェクト: `kiwi_issue63`、DB: `supabase_db_kiwi_issue63`、DBポート56622。
- API: 専用PostgREST `kiwi_issue63_api`、`127.0.0.1:56621`。既存プロジェクトのDB・サービスを変更していない。
- Supabase CLI 2.117.0 / PostgreSQL 17.6 / PostgREST 16.2 / Flutter 3.47.2。

## 再現手順と結果

runtimeには専用project_idとポートを設定し、migrations/tests/seed.sqlを検証worktreeへリンクした。
`supabase db reset --local` は必ずこのruntime内で実行する。リポジトリ既定のkiwi_productsへ実行しない。
既存のdblink競合テストは固定名 `supabase_db_kiwi_products` を使うため、専用DBコンテナ内の `/etc/hosts` だけでその名前を自身のIPへ解決させた。

| 検証 | 結果 |
|---|---|
| 専用DBを全migration・seedから再構築 | 成功 |
| `supabase db lint --local --fail-on warning` | エラー・警告なし（pgTAP実行前） |
| `supabase test db` | 23ファイル・976項目 PASS |
| `python3 scripts/verify_issue63_local_api.py` | PASS |
| `dart format --output=none --set-exit-if-changed lib test` | 変更なし |
| `flutter analyze` | 指摘なし |
| `flutter test --exclude-tags golden` | 216項目 PASS |
| `flutter build web --release` | 成功 |
| `git diff --check` | 成功 |

APIスクリプトは専用DB・固定ローカルURLを検査し、合成データのみを投入する。
PostgRESTは同じ専用Dockerネットワークで起動し、DB接続は専用コンテナのauthenticatorロール、
公開スキーマpublic、匿名ロールanonを使用。JWT署名鍵はスクリプト内の合成テスト専用文字列で、本番資格情報ではない。
再実行前は専用DBだけを再構築する。API検証後は合成データが残る。

## 業務フローの受入

- 管理者だけが追熟マスターを作成・更新できる。memberの更新、直接DML、匿名・pendingの参照を拒否。
- 前年度の収穫年度・月を明示した計画が、その年度のマスターをコピーする。マスター変更後も計画の値を維持。
- 一致するマスターがない場合、登録の予約・割当を含めてロールバック。
- 注入実績に基づく予定・期限と現物重量を確認。ラベル手書き完了後に抜き確認・追熟確認へ進める。
- 出荷可能期間内に部分出荷、取消で重量が復元される。
- 期限到来で出荷不可・要再確認になっても現物重量が残り、廃棄イベントを作らない。
- 過去の注入実績で既に賞味期限を過ぎる場合、注入操作内で直ちにexpiredになる。
- 同じ注入操作の同時再送は一回分だけ反映。同時・反復の期限処理で履歴を重複させない。
- pgTAPで期限1マイクロ秒前・ちょうどの判定、未確認工程の期限切れ、出荷期間開始前の一覧除外・出荷拒否、旧計画の安全な移行を確認。

## 未検証・別途必要な事項

- 収穫年度・月入力と追熟マスター管理のフロント画面連携。本IssueのBackend契約は実装済みだが、旧画面は両項目を送らないため、そのままでは注入を開始できない。
- 既に開始済みでマスター・期限のない旧計画の個別データ移行。実際の収穫情報から確認が必要なため推測による自動補完は行わない。
- 本番環境のマスター実値、既存データ移行、cron稼働・監視、Googleカレンダー実接続・現場確認。
- Backend・DB/CI・契約の担当者レビュー。ローカル成功を本番反映の承認とはしない。

CI結果は関連PRのChecksに記録する。Issueはレビュー・CI完了までOpenを維持する。

## レビュー指摘の修正検証

- 修正コミット: `2f245e89a7421554b8c880223df34d5e7a1a61c8`
- 修正migration: `20260913000600_fix_deadline_csv_exports.sql`
- 自動更新履歴のCSV欠落をLEFT JOINで修正。変更者名は「システム（自動更新）」とし、手動実行者と区別。
- 追熟マスターのCSVヘッダー・全計算条件・検索・収穫年度順の並びを追加。
- 専用DBを全migrationから再構築し、SQL lintは指摘なし、pgTAPは24ファイル・996項目PASS。
- 追加20項目で履歴の欠落、マスターの列と並び順、検索・有効状態フィルター、権限、出力監査件数を検証。
- `scripts/verify_issue63_local_api.py` もPASS。実際の期限更新履歴の保存件数とCSV件数が一致し、追熟マスターCSVをAPI経由で取得できることを確認。
- 今回の修正ではFlutterコードを変更していない。CI結果はPRの最新Checksを参照。

# S2 ローカル実API受入の再実行

このテストは業務データを書き込む。専用 `kiwi_s2_acceptance` プロジェクトだけを対象とし、共用DBでは実行しない。実在する顧客やGoogleの認証鍵は不要。

## 準備

1. 対象コミットと作業ツリーの状態を記録する。`kiwi-verification`配下の専用worktreeを利用する。
2. worktree外の専用runtimeディレクトリに `supabase/config.toml`、`migrations/`、`tests/`、`seed.sql`をコピーする。既存runtimeを上書きしない。
3. コピーの `project_id` を `kiwi_s2_acceptance` にする。ポートの接頭辞553を583へ変更し、API58321、DB58322、shadow58320に分離する。Google OAuthを無効化し、テスト用に`auth.email.enable_signup=true`にする。label-pdfの関数設定は専用コピーから外す（今回はEdge実行を起動しない）。
4. 並行pgTAP用に、コピーしたSQLのDBホスト`supabase_db_kiwi_products`を`supabase_db_kiwi_s2_acceptance`へ置換する。
5. 同名プロジェクトのコンテナ・volumeが既にある場合は対象コミットと使用者を確認する。無条件にresetしない。新規環境ではstart時にmigrationとseedが適用される。

Supabase CLI 2.117.0、Flutter 3.47.2、Python 3.11以上を使用。以下の変数はそれぞれ実行ファイルのパスと専用runtimeの絶対パスを指定する。

```bash
export SUPABASE_CMD=/path/to/supabase
export FLUTTER_CMD=/path/to/flutter
export RUNTIME=/home/kugis/products/hackathon/kiwi-verification/issue59-runtime
"$SUPABASE_CMD" start --workdir "$RUNTIME"   -x studio,imgproxy,storage-api,realtime,logflare,vector,edge-runtime,supavisor,postgres-meta
"$SUPABASE_CMD" db lint --local --fail-on warning --workdir "$RUNTIME"
"$SUPABASE_CMD" test db --workdir "$RUNTIME"
python3 scripts/prepare_stage2_live.py "$RUNTIME"
cd apps/kiwi_inventory
"$FLUTTER_CMD" test   --dart-define=STAGE2_AUTH_FILE="$RUNTIME/credentials.json"   test/stage2_live_acceptance_test.dart
```

`prepare_stage2_live.py`はプロジェクトIDとポートを検査し、架空のadministrator/member/pendingを作成する。Authが発行したJWTを0600の認証ファイルに保存する。Google-profile fixtureのテスト専用パスワードを使用するため、実Google OAuthのテストではない。実行ログへ認証ファイルやCLIの秘密値を転記しない。

在庫fixtureは既存pgTAPから10kgの1コンテナを用意する。既存fixtureに予約が残る場合は停止する。成功した縦断シナリオは予約を解放するが、架空受注・顧客・履歴は専用DBに残る。

認証ファイルを指定しない通常の`flutter test`では、この実APIスイートは**Skip**になる。CIでの通常テスト成功を実API検証成功として数えない。実行結果が`2 tests passed`であることを個別に確認する。

## 全体回帰

通常のformat、analyze、`flutter test --exclude-tags golden`、Ubuntu Golden、Web buildに加え、`supabase/functions`で`deno check label-pdf/index.ts calendar-sync/index.ts`と`deno test --allow-read tests/`を実行する。Google応答を模擬するEdgeテストと実カレンダー確認は別に記録する。

## 終了

認証ファイルを削除し、専用configの`auth.email.enable_signup=false`へ戻してから、`supabase stop --workdir "$RUNTIME"`で専用環境だけを停止する。既存業務環境を停止しない。start出力に含まれるローカル秘密値も公開しない。最終結果・未確認事項を[受入判定表](stage2-go-no-go.md)と#59へ記録する。

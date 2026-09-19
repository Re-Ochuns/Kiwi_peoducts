# Googleカレンダー同期（Issue #57・#79）

## 決定事項

2026-09-12: サービスアカウント方式を採用。農園共通カレンダーの所有者とカレンダーIDは環境ごとに設定する。
エチレン注入から抜き確認までは既定1週間（168時間）。確定時の値を計画へコピーする。
品種・年度別マスターによる自動計算の拡張は #63。既定値だけを変える場合も既存スナップショットは維持する。

2026-09-12: 農園共通Googleカレンダーを確定した（Issue #79）。  
カレンダーID: `1b834061eb714a7a290928cc82bf64cbdb8ff588f1c268d1c0ec85329d4171b0@group.calendar.google.com`  
サービスアカウントのclient_emailへ「予定の変更」権限を付与してから接続を有効にする。

アプリ→Googleの一方向同期。中止イベントは削除せず【中止】を表示する。
顧客名・住所は送らず、作業種別・品種・等級・重量・場所・アプリリンクだけを送信する。
作業画面 /work-tasks/{task_id} は #56 で実装する契約であり、本変更にフロント画面は含まない。

## 設定とデプロイ

1. Google CloudでCalendar APIを有効化し、専用サービスアカウントを作る。
2. 農園共通カレンダー（ID は上記「決定事項」に記載）を、そのclient_emailへ
   「予定の変更」権限で共有する。個人のprimaryカレンダーを指定しない。
   出席者を登録しないため、ドメイン全体の代理権限は使用しない。
3. リポジトリ外の保護されたenvファイルへ秘密情報を保存し、Supabase Secretsへ登録する。
   設定ファイルをコミットしない。秘密情報をPR・Issue・ログへ貼らない。

| Edge Function環境変数 | 内容 | 備考 |
|---|---|---|
| GOOGLE_CALENDAR_SERVICE_ACCOUNT | client_email/private_keyを含むサービスアカウントJSON（1行） | 秘密情報 |
| GOOGLE_CALENDAR_ID | 農園共通カレンダーID | 「決定事項」に記載 |
| APP_BASE_URL | HTTPSのアプリURL | 例: `https://kiwi-staging.web.app` |
| CALENDAR_SYNC_TOKEN | サーバー間共有トークン（Vault の値と同一） | 秘密情報 |
| SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY | Supabaseが自動提供 | 設定不要 |

envファイルの例（`/secure/calendar-sync-staging.env` 等、リポジトリ外に保存）:

```ini
GOOGLE_CALENDAR_SERVICE_ACCOUNT={"client_email":"kiwi-calendar@<project>.iam.gserviceaccount.com","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"}
GOOGLE_CALENDAR_ID=1b834061eb714a7a290928cc82bf64cbdb8ff588f1c268d1c0ec85329d4171b0@group.calendar.google.com
APP_BASE_URL=https://<アプリのHTTPS URL>
CALENDAR_SYNC_TOKEN=<十分に長いランダム文字列>
```

```bash
mise x -- npx -y supabase@2.117.0 secrets set --env-file /secure/calendar-sync-staging.env --project-ref <project-ref>
mise x -- npx -y supabase@2.117.0 functions deploy calendar-sync --project-ref <project-ref>
```

4. Supabase VaultへSQL Editorで次の値を登録する。実際の値をSQL Editorの履歴・クリップボードから
   共有しない。`supabase/snippets/calendar-sync-vault-setup.sql` を参照。

   | Vault名 | 値 |
   |---|---|
   | `calendar_sync_url` | `https://<project-ref>.supabase.co/functions/v1/calendar-sync` |
   | `calendar_sync_token` | `CALENDAR_SYNC_TOKEN` と同じ値 |

5. DBマイグレーションで作成されるcalendar-sync-dispatchが毎分ワーカーを呼ぶ。
   Vault未設定時は外部接続を行わず、計画確定と送信待ちデータだけを保持する。
6. 管理者としてwork_tasks_reconcileへ共通封筒とinput.reasonを渡し、
   この変更より前の確定済み計画・受注をタスクへ取り込む。
7. 専用の検証カレンダーで正常送信、手動編集の上書き、中止、権限削除時の失敗と復旧を確認する（Issue #79）。

## 処理と運用

DB確定→work_tasksと送信キュー保存→cron→Edge Function→Google→結果保存。
Googleとの通信に失敗しても確定済み計画を戻さない。
イベントIDはタスクUUIDと世代から決定する。応答が失われた再送でも二重作成しない。
Googleの変更内容は取り込まず、成功後も15分後から定期的に再送対象にする。
未送信・失敗を定期再送より優先し、1回5件を処理する。大量の過去タスクがある環境では待ち時間を監視する。

work_task_sync_warningsが返す件数を管理画面で表示する。
calendar_sync_errorはCONFIG_INVALID / CONFIG_MISSING / GOOGLE_AUTH_FAILED /
GOOGLE_ACCESS_DENIED / GOOGLE_RATE_LIMIT / GOOGLE_UNAVAILABLE / GOOGLE_EVENT_GONE /
TASK_INVALID / SYNC_UNAVAILABLEの安全なコードのみ。
private.calendar_sync_logで試行結果を確認できる。失敗本文やGoogleトークンはログへ保存しない。
CONFIG_*なら環境変数とVault、ACCESS_DENIEDなら共有権限とAPI有効化を確認する。
認証情報やカレンダーIDを修正した後は自動再試行で復旧する。
カレンダーIDを別カレンダーへ変更する場合は、旧カレンダーのイベント整理を含む移行作業として扱う。

## 検証

```bash
supabase db reset
supabase db lint --local --fail-on warning
supabase test db
cd supabase/functions
deno check label-pdf/index.ts calendar-sync/index.ts
deno test --allow-read tests/
```

単体テストではGoogle HTTP応答を注入し、OAuth署名、作成・更新・再送、変更の上書き、
中止の保持、429/403/500、削除済みイベント、認証拒否を確認する。
pgTAPではタスク生成、168時間、スナップショット、警告、リース・再試行、
古い結果の拒否、移行用再構成と権限を確認する。競合テストは実際の別DBセッションを使う。
実カレンダーの認証・共有権限は秘密情報と対象カレンダーを設定してから別途確認する。

## 一次資料

- [Google: サービスアカウントのOAuth](https://developers.google.com/identity/protocols/oauth2/service-account)
- [Google: イベント作成とIDの制約](https://developers.google.com/workspace/calendar/api/v3/reference/events/insert)
- [Google: イベント全体の更新](https://developers.google.com/workspace/calendar/api/v3/reference/events/update)

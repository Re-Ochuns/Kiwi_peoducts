# 当日ToDoのDiscord通知

Google Chatから、個人アカウントで実証可能なDiscord Incoming Webhookへ変更した。
BotアカウントやBotトークンは不要。

## 動作

- PC・スマホのホームToDoに「Discordに通知」ボタンを表示。activeなadministratorのみ実行可能。
- 毎朝08:00 Asia/Tokyo（UTC前日23:00）にも同じ送信処理を呼ぶ。
- 送信時点で予定時刻が当日00:00以上・翌日00:00未満のpendingタスクを集計。
  完了・中止・前日以前の期限超過タスクは含めない。画面端末のタイムゾーンに関係なく日本時間。
- 件数と予定順の先頭最大10件を表示。Discordの2000文字制限に合わせてさらに省略する場合がある。
  省略件数と全件を確認するホームのリンクを付ける。0件の日もその旨を通知する。
- 作業種別・予定時刻・タスクURLのみを送る。顧客名、住所、品種などの自由入力、メモは送らない。
- allowed_mentions.parse=[]。URLの埋め込みプレビューを抑止する。
- 認可はサーバー側でJWTを検証し、active・administratorを確認。画面の表示モードとは無関係。

## 設定（環境ごと）

Discordの通常のテキストチャンネルでIncoming Webhookを作成する。
フォーラム・メディアチャンネルのスレッド指定には今回対応しない。
Webhookは https://discord.com/api/webhooks/<ID>/<TOKEN> 形式。値はチャット・Git・ログへ書かない。

Supabase Dashboard → Edge Functions → Secrets:

| 名前 | 値 |
| --- | --- |
| DISCORD_TODO_WEBHOOK_URL | Discordで作成したWebhook URL |
| APP_BASE_URL | https://kiwi-staging-603b3.web.app （既存の設定を利用） |
| TODO_NOTIFICATION_TOKEN | パスワード管理ツールで生成した32文字以上のランダム値 |

Supabase Integrations → Vault → Secrets:

| 名前 | 値 |
| --- | --- |
| todo_notification_url | https://mhxtmqhavytcklszbvtk.supabase.co/functions/v1/todo-notify |
| todo_notification_token | TODO_NOTIFICATION_TOKENと同じ値 |

上記Vaultの2件がない間、定期実行は外部通信しない。手動通知はWebhookとAPP_BASE_URLで利用可能。
Staging Deploymentはmigrationの後にtodo-notifyを配備する。Secret値の未設定は他の機能の配備を妨げない。
全Secret設定後に手動通知を試し、翌朝08:00の実通知を確認する。ローカル環境にStagingのWebhookを流用しない。

## 重複・失敗

- dailyは日本時間の日付につき1回だけ送信を試みる。手動通知は独立し、全体で1分間に1回。
- 手動リクエストUUIDと利用者IDの組で重複を防ぐ。ボタン連打中は無効化。
- Discordはwait=trueで送信確定の応答を待つ。成功応答後だけsentを記録する。
- 通信切断など配送結果が不明な場合はunknown。自動再送しない（重複送信を避ける）。
- ワーカー中断・記録失敗時はsendingのまま残り得る。Discordとログを確認してから再送を判断する。
- 明確な失敗はfailed。設定修正後に新しい手動通知で確認する。
- 同一日の定期実行に自動リトライ・停止中の取り戻し配信はない。Freeプロジェクト休止中は配信されない。

SQL Editorで値を露出せず監査する:

```sql
select mode,status,task_count,error_code,created_at,finished_at
from private.todo_notifications order by created_at desc limit 20;
select jobname,schedule,active from cron.job where jobname='daily-todo-discord';
```

停止: Vaultのtodo_notification_tokenを削除するかcron.alter_jobでジョブを無効化する。
Webhookを失効させる場合はDiscord側から削除・再生成する。

## 検証

Deno: JST境界、送信先制限、文字数・メンション抑止、認可拒否、未設定、正常、重複、送信失敗・不明。
DB: administrator制約、サービス専用RPC、手動連打、日次重複、送信結果の保護、UTC cron。
Flutter: 権限、送信中の連打、未設定を成功表示しない、既存ホームの回帰。
実Discord・毎朝配信はSecret設定とStaging配備後に確認する。

参考: https://docs.discord.com/developers/resources/webhook#execute-webhook

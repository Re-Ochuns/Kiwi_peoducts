# 選果後ラベル一括印刷完了契約

## 1. 対象

- RPC: `public.label_batch_mark_printed(req jsonb)`
- 関連Issue: #114
- 関連契約: `sorting_confirm`、`label_mark_printed`

## 2. 目的

1件の選果確定で生成された全コンテナのラベルを、利用者の1回の確認で印刷済みにする。全件を同一トランザクションで処理し、一部だけ完了した状態を残さない。

## 3. 要求

共通封筒の `input` に次を指定する。

| 項目 | 型 | 必須 | 内容 |
|---|---|---:|---|
| `sorting_result_id` | uuid | 必須 | 対象の選果結果 |
| `worker_id` | uuid | 必須 | 印刷を確認した有効な担当者 |
| `location_id` | uuid | 任意 | 全対象へ設定する有効な冷蔵庫 |

## 4. 成功応答

`data` は `sorting_result_id`、`completed_count`、`labels` を返す。`labels` の各要素は `label_job_id`、`container_id`、`status`、`printed_copies`、`required_copies`、`container_status`、`container_version` を含む。

## 5. 更新規則

- 対象は指定した選果結果から直接生成された、追熟前のコンテナに限定する。
- 全ラベルジョブが `not_printed` または `partially_printed` の場合だけ更新する。
- 各ジョブの不足枚数を印刷イベントへ記録し、`printed_copies = required_copies`、`status = printed` とする。
- 各コンテナを `cold_storage` へ遷移し、指定時は同じ `location_id` を設定する。
- ラベルジョブとコンテナの変更履歴を対象ごとに記録する。
- 途中で競合または検証エラーが起きた場合は全更新を取り消す。

## 6. 冪等性・競合

- 共通契約どおりUUID v4の `idempotency_key` と `correlation_id` を必須とする。
- 同一キー・同一入力の再送は保存済み応答を返し、イベントや履歴を重複作成しない。
- 対応済みジョブが含まれる場合は `CONFLICT_STALE` を返し、一件も更新しない。

## 7. 権限

`authenticated` のうち、有効な `member` または `administrator` だけが実行できる。`anon` には実行権限を付与しない。

## 8. 必須テスト

- 複数ジョブの一括完了、在庫遷移、場所設定、イベント・履歴
- 同一キーの再送で副作用が増えないこと
- 未認証・利用停止・対象なし・無効な担当者・無効な保管場所
- 対応済みジョブ混在時に全件がロールバックされること

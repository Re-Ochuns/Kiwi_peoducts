# RPC契約: label_mark_printed

- 状態: 草案
- 版: 1
- 対象Issue: [#17](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/17)
- 関連要件: [01. 業務要件 第6章](../../production-spec/01_BUSINESS_REQUIREMENTS.md)、[03. 状態遷移・データモデル 第2・5章](../../production-spec/03_STATE_AND_DATA_MODEL.md)、[ADR-0002](../../docs/adr/0002-a5-label-pdf-generation.md)

[RPC共通契約](../rpc-contract-spec.md)を前提とし、本書は差分と操作固有の内容だけを定義する。

## 1. 概要

コンテナのラベルジョブへ印刷済み枚数を記録する。累計印刷枚数が必要枚数に達したらジョブを`printed`で完了し、同一トランザクションでコンテナを`cold_storage`へ遷移させる。未達なら`partially_printed`で待機する。ラベルPDFの生成は[label-pdf Edge Function](../../docs/edge-functions/label-pdf.md)が担い、本RPCはPDFを生成しない。

## 2. Function

| 項目 | 内容 |
|---|---|
| Function名 | `label_mark_printed` |
| 種別 | PostgreSQL Function |
| 権限 | 認証済みかつ`active`な利用者（member / administrator） |

## 3. 要求

| フィールド | 型 | 必須 | 内容・制約 |
|---|---|---|---|
| label_job_id | uuid | 必須 | 対象のラベルジョブ |
| worker_id | uuid | 必須 | 対応した作業者マスター（有効であること） |
| copies | number | 任意 | 今回の印刷枚数。1以上999以下の整数。既定1 |
| location_id | uuid | 任意 | 完了時に設定する冷蔵庫。`cold_storage`種別のみ |

```json
{
  "req": {
    "meta": { "idempotency_key": "…", "correlation_id": "…" },
    "input": {
      "label_job_id": "…",
      "worker_id": "…",
      "copies": 1,
      "location_id": "…"
    }
  }
}
```

## 4. 応答

| フィールド | 型 | 内容 |
|---|---|---|
| label_job_id | uuid | 対象ラベルジョブ |
| container_id | uuid | 対象コンテナ |
| status | text | `partially_printed` または `printed` |
| printed_copies | number | 累計印刷枚数 |
| required_copies | number | 必要枚数 |
| reprint_count | number | 再印刷回数（本操作では不変） |
| completed_at | text/null | 完了日時（UTC ISO 8601）。未完了はnull |
| container_status | text | 完了時`cold_storage`、未完了は`awaiting_label` |
| container_version | number | コンテナの版（完了時または場所設定時に加算） |
| location_id | uuid/null | コンテナの現在の保管場所 |

## 5. 業務エラー

共通コードを使用する。`VALIDATION_FAILED`の`details`は`field`と`reason`を含む（`location_id`が冷蔵庫でない場合は`reason = invalid_value`）。`reason`はこの操作では指定できず、指定すると`reason = not_allowed`。

## 6. 競合条件

`CONFLICT_STALE`はジョブが`not_printed` / `partially_printed`以外（すでに`printed`・`handwritten`）のときに返し、`details.current`へ`label_job_id`・`status`・`printed_copies`・`required_copies`・`reprint_count`を含める。

## 7. 冪等性

共通契約どおり。保存済み応答の再生は同一利用者に限る。

## 8. 排他制御

ラベルジョブと対応コンテナを`SELECT ... FOR UPDATE`でロックし、状態と枚数を検証してから更新する。完了判定・コンテナ遷移まで同一トランザクションで行う。

## 9. 副作用

- `public.label_jobs`の`status`・`printed_copies`・`completed_at`・`completed_by`を更新する。
- `public.label_events`へ`event_type = 'print'`のイベントを追記する。
- 完了時または`location_id`指定時に`public.containers`の`status`（完了時`cold_storage`）・`location_id`・`version`を更新する。
- `public.change_history`へ`label_job`のtransitionと、コンテナ更新時は`container`のtransition/updateを追記する。
- `private.idempotency_records`へ確定した封筒を保存する。

## 10. 履歴

`change_history`へ`label_job`（operation=`transition`、before/after付き、reason=`印刷済み確定`）を記録する。コンテナを更新した場合は`container`（完了時`transition`、場所のみ`update`）も記録する。`changed_by = auth.uid()`、`correlation_id = meta.correlation_id`。

## 11. 例

正常系（完了）は第3・4章のとおり。完了済みジョブへの再要求。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "conflict",
    "code": "CONFLICT_STALE",
    "message": "このラベルはすでに対応が完了しています。最新の状態を確認してください。",
    "retryable": false,
    "details": {
      "current": { "label_job_id": "…", "status": "printed", "printed_copies": 1, "required_copies": 1, "reprint_count": 0 }
    }
  }
}
```

## 変更履歴

| 版 | 日付 | 内容 | 承認 |
|---|---|---|---|
| 1 | 2026-09-10 | 初版作成 | 未承認（Issue #17のレビュー中） |

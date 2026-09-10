# RPC契約: label_mark_handwritten

- 状態: 草案
- 版: 1
- 対象Issue: [#17](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/17)
- 関連要件: [01. 業務要件 第6章](../../production-spec/01_BUSINESS_REQUIREMENTS.md)、[ADR-0002 手書きフォールバック](../../docs/adr/0002-a5-label-pdf-generation.md)

[RPC共通契約](../rpc-contract-spec.md)を前提とし、本書は差分と操作固有の内容だけを定義する。

## 1. 概要

PDF生成・印刷が困難な場合の手書きフォールバックを確定する。ラベルジョブを`handwritten`で完了し、同一トランザクションでコンテナを`cold_storage`へ遷移させる。作業者が「手書き対応」を確定した時点で対応済みとし、実行者・日時をイベントと履歴へ残す。

## 2. Function

| 項目 | 内容 |
|---|---|
| Function名 | `label_mark_handwritten` |
| 種別 | PostgreSQL Function |
| 権限 | 認証済みかつ`active`な利用者（member / administrator） |

## 3. 要求

| フィールド | 型 | 必須 | 内容・制約 |
|---|---|---|---|
| label_job_id | uuid | 必須 | 対象のラベルジョブ |
| worker_id | uuid | 必須 | 手書き対応した作業者マスター（有効であること） |
| notes | text | 任意 | 手書き対応の備考。イベントへ記録する |
| location_id | uuid | 任意 | 完了時に設定する冷蔵庫。`cold_storage`種別のみ |

`copies`は指定できない（`reason = not_allowed`）。

```json
{
  "req": {
    "meta": { "idempotency_key": "…", "correlation_id": "…" },
    "input": {
      "label_job_id": "…",
      "worker_id": "…",
      "notes": "印刷機故障のため",
      "location_id": "…"
    }
  }
}
```

## 4. 応答

`label_mark_printed`と同形。`status`は`handwritten`、`printed_copies`は変化しない、`completed_at`は完了日時、`container_status`は`cold_storage`。

## 5. 業務エラー

共通コードを使用する。`copies`・`reason`を指定すると`VALIDATION_FAILED`（`reason = not_allowed`）。`location_id`が冷蔵庫でない場合は`reason = invalid_value`。

## 6. 競合条件

`CONFLICT_STALE`はジョブが`not_printed` / `partially_printed`以外のときに返す。`details.current`は`label_mark_printed`と同じ。

## 7. 冪等性

共通契約どおり。保存済み応答の再生は同一利用者に限る。

## 8. 排他制御

ラベルジョブと対応コンテナを`SELECT ... FOR UPDATE`でロックし、状態を検証してから完了・遷移する。

## 9. 副作用

- `public.label_jobs`を`status = 'handwritten'`・`completed_at`・`completed_by`へ更新する。
- `public.label_events`へ`event_type = 'handwritten'`・`copies = 1`のイベントを追記する（`notes`があれば記録）。
- `public.containers`を`cold_storage`へ遷移させ、`location_id`指定時は設定、`version`を加算する。
- `public.change_history`へ`label_job`のtransitionと`container`のtransitionを追記する。
- `private.idempotency_records`へ確定した封筒を保存する。

## 10. 履歴

`change_history`へ`label_job`（transition、reason=`手書き対応確定`）と`container`（transition）を記録する。`changed_by = auth.uid()`、`correlation_id = meta.correlation_id`。

## 11. 例

正常系は第3・4章のとおり。競合は`label_mark_printed`の例に準じる。

## 変更履歴

| 版 | 日付 | 内容 | 承認 |
|---|---|---|---|
| 1 | 2026-09-10 | 初版作成 | 未承認（Issue #17のレビュー中） |

# RPC契約: label_reprint

- 状態: 草案
- 版: 1
- 対象Issue: [#17](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/17)
- 関連要件: [01. 業務要件 第6章](../../production-spec/01_BUSINESS_REQUIREMENTS.md)

[RPC共通契約](../rpc-contract-spec.md)を前提とし、本書は差分と操作固有の内容だけを定義する。

## 1. 概要

印刷済み（`printed`）のラベルを理由付きで再印刷する。汚損・紛失などで刷り直した実行者・日時・理由・枚数を追跡できるようにする。状態は`printed`のまま、`reprint_count`と`printed_copies`を加算する。コンテナ状態は変更しない。

## 2. Function

| 項目 | 内容 |
|---|---|
| Function名 | `label_reprint` |
| 種別 | PostgreSQL Function |
| 権限 | 認証済みかつ`active`な利用者（member / administrator） |

## 3. 要求

| フィールド | 型 | 必須 | 内容・制約 |
|---|---|---|---|
| label_job_id | uuid | 必須 | 対象のラベルジョブ。`printed`であること |
| worker_id | uuid | 必須 | 再印刷した作業者マスター（有効であること） |
| reason | text | 必須 | 再印刷理由。空白のみ不可。イベントと履歴へ記録する |
| copies | number | 任意 | 今回の再印刷枚数。1以上999以下の整数。既定1 |

`notes`・`location_id`は指定できない（`reason = not_allowed`）。

```json
{
  "req": {
    "meta": { "idempotency_key": "…", "correlation_id": "…" },
    "input": {
      "label_job_id": "…",
      "worker_id": "…",
      "reason": "汚損のため再印刷",
      "copies": 1
    }
  }
}
```

## 4. 応答

`label_mark_printed`と同形。`status`は`printed`のまま、`printed_copies`は加算後、`reprint_count`は加算後、`completed_at`は既存値、`container_status`・`container_version`は不変。

## 5. 業務エラー

| code | 発生条件 | details |
|---|---|---|
| LABEL_NOT_REPRINTABLE | 対象ジョブが`printed`でない（`not_printed` / `partially_printed` / `handwritten`） | `label_job_id`、`status` |

`reason`欠落は共通の`VALIDATION_FAILED`（`field = reason`）。

## 6. 競合条件

前提状態は`printed`のみ。それ以外は業務エラー`LABEL_NOT_REPRINTABLE`として扱い、`CONFLICT_STALE`は用いない（再印刷は状態遷移を伴わず、前提の崩れではなく対象の不適合であるため）。`IDEMPOTENCY_KEY_REUSED`は共通契約どおり。

## 7. 冪等性

共通契約どおり。保存済み応答の再生は同一利用者に限る。

## 8. 排他制御

ラベルジョブを`SELECT ... FOR UPDATE`でロックし、`status = 'printed'`を検証してからカウンタを加算する。

## 9. 副作用

- `public.label_jobs`の`printed_copies`・`reprint_count`を加算する（`status`・`completed_at`は不変）。
- `public.label_events`へ`event_type = 'reprint'`のイベントを追記する（`notes`へ理由を保存）。
- `public.change_history`へ`label_job`の`update`（reasonへ再印刷理由）を追記する。
- `private.idempotency_records`へ確定した封筒を保存する。
- コンテナは変更しない。

## 10. 履歴

`change_history`へ`label_job`（operation=`update`、before/after付き、reasonへ`input.reason`の原文）を記録する。`changed_by = auth.uid()`、`correlation_id = meta.correlation_id`。

## 11. 例

正常系は第3・4章のとおり。未完了ジョブの再印刷。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "business",
    "code": "LABEL_NOT_REPRINTABLE",
    "message": "印刷済みのラベルだけを再印刷できます。",
    "retryable": false,
    "details": { "label_job_id": "…", "status": "partially_printed" }
  }
}
```

## 変更履歴

| 版 | 日付 | 内容 | 承認 |
|---|---|---|---|
| 1 | 2026-09-10 | 初版作成 | 未承認（Issue #17のレビュー中） |

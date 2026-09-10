# RPC契約: receiving_correct

- 状態: 草案
- 版: 1
- 対象Issue: [#12](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/12)
- 関連要件: [01. 業務要件 第4章](../../production-spec/01_BUSINESS_REQUIREMENTS.md)、[03. 状態遷移・データモデル 第7章](../../production-spec/03_STATE_AND_DATA_MODEL.md)

[RPC共通契約](../rpc-contract-spec.md)を前提とし、本書は差分と操作固有の内容だけを定義する。

## 1. 概要

登録済みで選果前（`awaiting_sorting`）の受入ロットを、理由必須・履歴付きで修正する。修正は業務入力の全量置換であり、部分更新は行わない。選果確定後のロットは修正できない（次工程後の訂正はO-01として未決）。

## 2. Function

| 項目 | 内容 |
|---|---|
| Function名 | `receiving_correct` |
| 種別 | PostgreSQL Function |
| 権限 | 認証済みかつ`active`な利用者（member / administrator） |

## 3. 要求

`input`は[receiving_register 第3章](receiving_register.md)の全業務フィールドに加えて次を必須とする。業務フィールドの検証規則は登録と同一で、`source_type`の変更（収穫↔仕入れ）も検証を満たす限り許可する。`sorting_due_date`省略時は登録時と同じ規則で再計算する。

`display_id`は登録時の受入年度を含む不変値であるため、`received_date`は現在の受入日と同じ暦年内でのみ変更できる。

| フィールド | 型 | 必須 | 内容・制約 |
|---|---|---|---|
| receiving_lot_id | uuid | 必須 | 修正対象の受入ロット |
| expected_version | number | 必須 | クライアントが表示していた版（楽観制御の前提値） |
| reason | text | 必須 | 修正理由。空白のみは不可。履歴へそのまま記録する |

```json
{
  "req": {
    "meta": { "idempotency_key": "…", "correlation_id": "…" },
    "input": {
      "receiving_lot_id": "…",
      "expected_version": 1,
      "reason": "計量誤り修正",
      "source_type": "harvest",
      "received_date": "2028-05-01",
      "orchard_id": "…",
      "plot_id": "…",
      "tree_id": "…",
      "origin_name": "デモ農園 北区画A",
      "variety_id": "…",
      "total_weight_kg": 30.00,
      "container_count": 2,
      "worker_id": "…"
    }
  }
}
```

## 4. 応答

成功時の`data`はreceiving_registerと同形。`display_id`は変更されず、`version`は1加算された値を返す。

```json
{
  "ok": true,
  "correlation_id": "…",
  "idempotent_replay": false,
  "data": {
    "receiving_lot_id": "…",
    "display_id": "受入-2028-001",
    "status": "awaiting_sorting",
    "received_date": "2028-05-01",
    "sorting_due_date": "2028-05-22",
    "version": 2
  }
}
```

## 5. 業務エラー

操作固有のコードはない。共通の`VALIDATION_FAILED`を使用する（`details.reason`の値は[receiving_register 第5章](receiving_register.md)と同一）。対象ロットが存在しない場合は`details`を`{ "field": "receiving_lot_id", "reason": "not_found" }`とする。

`received_date`を別の暦年へ変更しようとした場合は、表示IDとの不整合を防ぐため`VALIDATION_FAILED`とし、`details`を`{ "field": "received_date", "reason": "year_change_not_allowed" }`とする。

## 6. 競合条件

`CONFLICT_STALE`は次の場合に返し、`details.current`へ`receiving_lot_id`・`status`・`version`を含める。

| 前提の崩れ方 | 判定 |
|---|---|
| 対象ロットが`sorted`（選果確定済み） | 行ロック後の状態検証で検出 |
| `expected_version`が現在の`version`と不一致 | 他の修正が先に確定した |

## 7. 冪等性

共通契約どおり。receiving_registerと同じく、保存済み応答の再生は同一利用者に限る。

## 8. 排他制御

1. 業務入力を検証する（書き込みなし）。
2. 対象ロットを`SELECT ... FOR UPDATE`でロックする。
3. `status = 'awaiting_sorting'`と`version = expected_version`を検証してから更新する。

検証失敗時はロック解放とともにロールバックし、部分更新を残さない。

## 9. 副作用

- `public.receiving_lots`の対象行を全量置換で更新し、`version`を1加算する（`display_id`・`status`・`created_*`は不変。`updated_at / updated_by`はtriggerが設定）。
- `public.change_history`へ`operation = 'correct'`の監査行を追記する。
- `private.idempotency_records`へ確定した封筒を保存する（認証エラー時は保存しない）。
- 表示IDの採番は行わない。

## 10. 履歴

`change_history`へ次を記録する。

| 列 | 値 |
|---|---|
| entity_type / entity_id | `receiving_lot` / 修正したロットID |
| operation | `correct` |
| before_data | 修正前の全列スナップショット |
| after_data | 修正後の全列スナップショット |
| reason | `input.reason`の原文 |
| changed_by | `auth.uid()` |
| correlation_id | `meta.correlation_id` |

## 11. 例

正常系は第3・4章のとおり。代表的な競合:

別の修正が先に確定していた。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "conflict",
    "code": "CONFLICT_STALE",
    "message": "この受入ロットは他の操作で更新されています。最新の状態を確認してください。",
    "retryable": false,
    "details": {
      "current": { "receiving_lot_id": "…", "status": "awaiting_sorting", "version": 2 }
    }
  }
}
```

選果確定済みロットへの修正。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "conflict",
    "code": "CONFLICT_STALE",
    "message": "この受入ロットはすでに選果が確定されています。最新の状態を確認してください。",
    "retryable": false,
    "details": {
      "current": { "receiving_lot_id": "…", "status": "sorted", "version": 1 }
    }
  }
}
```

## 変更履歴

| 版 | 日付 | 内容 | 承認 |
|---|---|---|---|
| 1 | 2026-09-10 | 初版作成 | 未承認（Issue #12のレビュー中） |

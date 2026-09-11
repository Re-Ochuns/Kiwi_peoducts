# RPC契約: master_update

- 状態: 草案
- 版: 1
- 対象Issue: [#39](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/39)
- 関連要件: [01. 業務要件 第2章](../../production-spec/01_BUSINESS_REQUIREMENTS.md)、[03. 状態遷移・データモデル 第6章](../../production-spec/03_STATE_AND_DATA_MODEL.md)

[RPC共通契約](../rpc-contract-spec.md)を前提とし、本書は差分と操作固有の内容だけを定義する。`master_type`と業務フィールドの定義は[master_register 第3・4章](master_register.md)を参照する。

## 1. 概要

登録済みマスターの属性を理由必須・履歴付きで修正する。修正は変更可能フィールドの全量置換であり、部分更新は行わない。無効化済み（`is_active = false`）のマスターも修正できる（再有効化前の訂正を許すため）。有効・無効の切替は本Functionでは行わず、[master_deactivate](master_deactivate.md) / [master_activate](master_activate.md)を使う。

## 2. Function

| 項目 | 内容 |
|---|---|
| Function名 | `master_update` |
| 種別 | PostgreSQL Function |
| 権限 | 認証済みかつ`active`なadministratorのみ |

## 3. 要求

`input`共通（すべて必須）:

| フィールド | 型 | 必須 | 内容・制約 |
|---|---|---|---|
| master_type | text | 必須 | [master_register 第3章](master_register.md)の列挙値 |
| master_id | uuid | 必須 | 修正対象の内部ID |
| expected_version | number | 必須 | クライアントが表示していた版（楽観制御の前提値） |
| reason | text | 必須 | 修正理由。空白のみは不可。履歴へそのまま記録する |

変更可能フィールド（全量置換のため必須）と不変フィールド:

| master_type | 変更可能（必須） | 不変 |
|---|---|---|
| variety | code / name | — |
| grade | display_order | code（固定候補のため変更不可） |
| orchard | code / name | — |
| orchard_plot | code / name | orchard_id |
| tree | code / name | plot_id、variety_id |
| supplier | management_code / name | — |
| worker | code / display_name | — |
| storage_location | code / name / location_type | — |
| sorting_deadline_rule | deadline_days | harvest_year、harvest_month、variety_id |

不変フィールドは省略するか、現在値と同じ値を送る。異なる値を送ると`VALIDATION_FAILED`、`details = { "field": "<フィールド>", "reason": "immutable" }`。所属や適用条件を変えたい場合は無効化して新規登録する。等級の`display_order`は他の等級と重複できず、入替えは空き番号を経由する2回の操作で行う。

```json
{
  "req": {
    "meta": { "idempotency_key": "…", "correlation_id": "…" },
    "input": {
      "master_type": "variety",
      "master_id": "…",
      "expected_version": 1,
      "reason": "名称の誤記修正",
      "code": "hayward",
      "name": "ヘイワード"
    }
  }
}
```

## 4. 応答

成功時の`data`は[master_register 第5章](master_register.md)と同形。`version`は1加算された値を返す。

## 5. 業務エラー

[master_register 第6章](master_register.md)の`MASTER_DUPLICATE`を同じ形式で返す（自分自身は重複判定から除外する）。対象が存在しない場合は`VALIDATION_FAILED`、`details = { "field": "master_id", "reason": "not_found" }`。

## 6. 競合条件

`CONFLICT_STALE`は次の場合に返し、`details.current`へ`master_id`・`is_active`・`version`を含める。

| 前提の崩れ方 | 判定 |
|---|---|
| `expected_version`が現在の`version`と不一致 | 他の修正・無効化・再有効化が先に確定した |

## 7. 冪等性

共通契約どおり。保存済み応答の再生は同一利用者に限る。

## 8. 排他制御

1. `master_type`・`master_id`・`expected_version`・`reason`と業務入力を検証する（書き込みなし）。
2. 対象行を`SELECT ... FOR UPDATE`でロックする。
3. `version = expected_version`と重複を検証してから更新する。

検証失敗時はロールバックし、部分更新を残さない。

## 9. 副作用

- 対象テーブルの行を全量置換で更新し、`version`を1加算する（`id`・`is_active`・`created_*`は不変。`updated_at / updated_by`はtriggerが設定）。
- `public.change_history`へ`operation = 'update'`の監査行を追記する。
- `private.idempotency_records`へ確定した封筒を保存する。

## 10. 履歴

`change_history`へ次を記録する。

| 列 | 値 |
|---|---|
| entity_type / entity_id | `master` / 修正した行のID |
| operation | `update` |
| before_data / after_data | 修正前後の全列スナップショット + `master_type` |
| reason | `input.reason`の原文 |
| changed_by | `auth.uid()` |
| correlation_id | `meta.correlation_id` |

## 11. 例

別の修正が先に確定していた。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "conflict",
    "code": "CONFLICT_STALE",
    "message": "このマスターは他の操作で更新されています。最新の状態を確認してください。",
    "retryable": false,
    "details": {
      "current": { "master_id": "…", "is_active": true, "version": 2 }
    }
  }
}
```

樹体の所属区画を変更しようとした。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "business",
    "code": "VALIDATION_FAILED",
    "message": "樹体の所属区画は変更できません。",
    "retryable": false,
    "details": { "field": "plot_id", "reason": "immutable" }
  }
}
```

## 変更履歴

| 版 | 日付 | 内容 | 承認 |
|---|---|---|---|
| 1 | 2026-09-11 | 初版作成 | 未承認（Issue #39のレビュー中） |

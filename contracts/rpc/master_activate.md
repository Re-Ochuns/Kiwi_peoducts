# RPC契約: master_activate

- 状態: 草案
- 版: 1
- 対象Issue: [#39](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/39)
- 関連要件: [01. 業務要件 第2章](../../production-spec/01_BUSINESS_REQUIREMENTS.md)、[06. 画面要件](../../production-spec/06_SCREEN_REQUIREMENTS.md)

[RPC共通契約](../rpc-contract-spec.md)を前提とし、本書は差分と操作固有の内容だけを定義する。`master_type`の定義は[master_register 第3章](master_register.md)、無効化は[master_deactivate](master_deactivate.md)を参照する。

## 1. 概要

無効化済みのマスターを再有効化する（`is_active = true`）。誤って無効化した場合や取引・利用を再開する場合の取り消し操作であり、再有効化されたマスターは再び業務入力の選択肢に表示される。

## 2. Function

| 項目 | 内容 |
|---|---|
| Function名 | `master_activate` |
| 種別 | PostgreSQL Function |
| 権限 | 認証済みかつ`active`なadministratorのみ |

## 3. 要求

[master_deactivate 第3章](master_deactivate.md)と同形（`master_type`・`master_id`・`expected_version`・`reason`すべて必須）。

## 4. 応答

成功時の`data`は[master_register 第5章](master_register.md)と同形（`is_active`はtrue、`version`は1加算）。

## 5. 業務エラー

| code | 発生条件 | details |
|---|---|---|
| MASTER_PARENT_INACTIVE | 上位マスターが無効のまま（下表） | `field`（無効な親のフィールド名）、`parent: { master_type, master_id }` |

| 再有効化対象 | activeであることを要求する上位 |
|---|---|
| orchard_plot | orchard |
| tree | orchard_plot、variety |
| sorting_deadline_rule | variety |
| variety / grade / orchard / supplier / worker / storage_location | なし |

上位から順（農園 → 区画 → 樹体）に再有効化する。対象が存在しない場合は`VALIDATION_FAILED`、`details = { "field": "master_id", "reason": "not_found" }`。

## 6. 競合条件

`CONFLICT_STALE`は次の場合に返し、`details.current`へ`master_id`・`is_active`・`version`を含める。

| 前提の崩れ方 | 判定 |
|---|---|
| `expected_version`が現在の`version`と不一致 | 他の操作が先に確定した |
| 対象がすでに有効 | 別の利用者が先に再有効化した |

## 7. 冪等性

共通契約どおり。

## 8. 排他制御

1. 対象行を`SELECT ... FOR UPDATE`でロックする。
2. `version = expected_version`と`is_active = false`を検証する。
3. 上位マスターの行を`FOR SHARE`でロックし、activeであることを検証する。上位を無効化する[master_deactivate](master_deactivate.md)（`FOR UPDATE`）と直列化されるため、無効な親の下で子が有効化されない。

## 9. 副作用

- 対象行の`is_active`をtrueにし、`version`を1加算する。他の列は変更しない。
- `public.change_history`へ`operation = 'transition'`の監査行を追記する。
- `private.idempotency_records`へ確定した封筒を保存する。

## 10. 履歴

[master_deactivate 第10章](master_deactivate.md)と同じ（`operation = 'transition'`）。

## 11. 例

区画が無効のまま樹体を再有効化しようとした。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "business",
    "code": "MASTER_PARENT_INACTIVE",
    "message": "上位マスターが無効のため有効化できません。先に上位マスターを有効化してください。",
    "retryable": false,
    "details": {
      "field": "plot_id",
      "parent": { "master_type": "orchard_plot", "master_id": "…" }
    }
  }
}
```

## 変更履歴

| 版 | 日付 | 内容 | 承認 |
|---|---|---|---|
| 1 | 2026-09-11 | 初版作成 | 未承認（Issue #39のレビュー中） |

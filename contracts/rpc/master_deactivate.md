# RPC契約: master_deactivate

- 状態: 草案
- 版: 1
- 対象Issue: [#39](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/39)
- 関連要件: [01. 業務要件 第2章](../../production-spec/01_BUSINESS_REQUIREMENTS.md)、[06. 画面要件](../../production-spec/06_SCREEN_REQUIREMENTS.md)

[RPC共通契約](../rpc-contract-spec.md)を前提とし、本書は差分と操作固有の内容だけを定義する。`master_type`の定義は[master_register 第3章](master_register.md)を参照する。

## 1. 概要

マスターを削除の代わりに無効化する（`is_active = false`）。物理削除は行わないため、受入ロット・選果実績・変更履歴などからの参照は無効化後も読み取れる。無効化されたマスターは新規業務入力の選択肢に表示しない（各画面・各RPCの検証はactiveなマスターのみを許可する）。取り消しは[master_activate](master_activate.md)で行う。

## 2. Function

| 項目 | 内容 |
|---|---|
| Function名 | `master_deactivate` |
| 種別 | PostgreSQL Function |
| 権限 | 認証済みかつ`active`なadministratorのみ |

## 3. 要求

| フィールド | 型 | 必須 | 内容・制約 |
|---|---|---|---|
| master_type | text | 必須 | [master_register 第3章](master_register.md)の列挙値 |
| master_id | uuid | 必須 | 無効化対象の内部ID |
| expected_version | number | 必須 | クライアントが表示していた版 |
| reason | text | 必須 | 無効化理由。空白のみは不可。履歴へそのまま記録する |

```json
{
  "req": {
    "meta": { "idempotency_key": "…", "correlation_id": "…" },
    "input": {
      "master_type": "worker",
      "master_id": "…",
      "expected_version": 1,
      "reason": "退職のため"
    }
  }
}
```

## 4. 応答

成功時の`data`は[master_register 第5章](master_register.md)と同形（`is_active`はfalse、`version`は1加算）。

## 5. 業務エラー

| code | 発生条件 | details |
|---|---|---|
| MASTER_IN_USE | activeな依存データが残っている（下表） | `master_id`、`dependencies: [{ entity, active_count }]` |

| 無効化対象 | 無効化を妨げる依存 |
|---|---|
| orchard | activeな区画（`entity: "orchard_plot"`） |
| orchard_plot | activeな樹体（`entity: "tree"`） |
| variety | activeな樹体（`entity: "tree"`）、activeな選果期限ルール（`entity: "sorting_deadline_rule"`） |
| storage_location | 出荷・期限切れ以外のコンテナ（`entity: "container"`） |
| grade / tree / supplier / worker / sorting_deadline_rule | なし |

依存はactiveなものだけを数える。上位から順に無効化する場合は、末端（樹体）から順に無効化する。過去の業務データ（受入ロット・選果実績・コンテナ等）からの参照は無効化を妨げない。

対象が存在しない場合は`VALIDATION_FAILED`、`details = { "field": "master_id", "reason": "not_found" }`。

## 6. 競合条件

`CONFLICT_STALE`は次の場合に返し、`details.current`へ`master_id`・`is_active`・`version`を含める。

| 前提の崩れ方 | 判定 |
|---|---|
| `expected_version`が現在の`version`と不一致 | 他の操作が先に確定した |
| 対象がすでに無効化済み | 別の利用者が先に無効化した |

## 7. 冪等性

共通契約どおり。同一キーによる再送は保存済み応答を再生するため、二重無効化にならない。

## 8. 排他制御

1. 対象行を`SELECT ... FOR UPDATE`でロックする。
2. `version = expected_version`と`is_active = true`を検証する。
3. activeな依存データを数え、残っていれば`MASTER_IN_USE`で失敗する。

対象行の`FOR UPDATE`は、子を登録・再有効化する操作（親を`FOR SHARE`でロックする）と直列化されるため、無効化した親の下にactiveな子が入り込まない。

## 9. 副作用

- 対象行の`is_active`をfalseにし、`version`を1加算する。他の列は変更しない。行の削除は行わない。
- `public.change_history`へ`operation = 'transition'`の監査行を追記する。
- `private.idempotency_records`へ確定した封筒を保存する。

## 10. 履歴

`change_history`へ次を記録する。

| 列 | 値 |
|---|---|
| entity_type / entity_id | `master` / 無効化した行のID |
| operation | `transition` |
| before_data / after_data | 無効化前後の全列スナップショット + `master_type` |
| reason | `input.reason`の原文 |
| changed_by | `auth.uid()` |
| correlation_id | `meta.correlation_id` |

## 11. 例

activeな区画が残る農園の無効化。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "business",
    "code": "MASTER_IN_USE",
    "message": "使用中のため無効化できません。先に関連するデータを無効化または整理してください。",
    "retryable": false,
    "details": {
      "master_id": "…",
      "dependencies": [ { "entity": "orchard_plot", "active_count": 2 } ]
    }
  }
}
```

すでに無効化済み。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "conflict",
    "code": "CONFLICT_STALE",
    "message": "このマスターはすでに無効化されています。最新の状態を確認してください。",
    "retryable": false,
    "details": {
      "current": { "master_id": "…", "is_active": false, "version": 2 }
    }
  }
}
```

## 変更履歴

| 版 | 日付 | 内容 | 承認 |
|---|---|---|---|
| 1 | 2026-09-11 | 初版作成 | 未承認（Issue #39のレビュー中） |

# RPC契約: master_register

- 状態: 草案
- 版: 1
- 対象Issue: [#39](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/39)
- 関連要件: [01. 業務要件 第2章](../../production-spec/01_BUSINESS_REQUIREMENTS.md)、[03. 状態遷移・データモデル 第6章](../../production-spec/03_STATE_AND_DATA_MODEL.md)、[07. 非機能・セキュリティ](../../production-spec/07_NON_FUNCTIONAL_SECURITY.md)

[RPC共通契約](../rpc-contract-spec.md)を前提とし、本書は差分と操作固有の内容だけを定義する。

## 1. 概要

段階1マスターの新規登録。マスター9種を`input.master_type`で指定する共通Functionとし、対象ごとの個別Functionは設けない。本書の`master_type`とフィールド定義は[master_update](master_update.md)・[master_deactivate](master_deactivate.md)・[master_activate](master_activate.md)からも参照される。

## 2. Function

| 項目 | 内容 |
|---|---|
| Function名 | `master_register` |
| 種別 | PostgreSQL Function |
| 権限 | 認証済みかつ`active`なadministratorのみ。memberは`AUTH_FORBIDDEN` |

マスター管理は要件書で管理者の担当業務であり（01 第2章、07「作業担当者は管理者がマスター登録し」）、更新4操作すべてをadministratorに限定する。memberを含むactiveな利用者の参照はRLSで引き続き許可する。authenticated利用者へのテーブル直接更新権限は付与しない。

## 3. master_type（共通定義）

| master_type | 対象テーブル | 日本語 |
|---|---|---|
| variety | varieties | 品種 |
| grade | grades | 等級 |
| orchard | orchards | 農園 |
| orchard_plot | orchard_plots | 区画 |
| tree | trees | 樹体 |
| supplier | suppliers | 仕入先 |
| worker | workers | 作業者 |
| storage_location | storage_locations | 保管場所 |
| sorting_deadline_rule | sorting_deadline_rules | 選果期限ルール |

等級は固定候補（`5L`〜`SS`の8コード）であり、**登録できない**（`VALIDATION_FAILED`、`details.reason = "not_allowed"`）。コードの追加・変更は仕様変更としてmigrationで扱う。

## 4. 要求

`input`共通:

| フィールド | 型 | 必須 | 内容・制約 |
|---|---|---|---|
| master_type | text | 必須 | 第3章の列挙値 |
| reason | text | 任意 | 履歴に記録する登録理由。省略時は`マスター登録` |

`master_type`ごとの業務フィールド（すべて必須）:

| master_type | フィールド | 型 | 内容・制約 |
|---|---|---|---|
| variety | code / name | text | いずれも全マスター内で一意 |
| orchard | code / name | text | codeは一意 |
| orchard_plot | orchard_id | uuid | 所属農園。activeであること |
| | code / name | text | codeは同一農園内で一意 |
| tree | plot_id | uuid | 所属区画。activeであること |
| | variety_id | uuid | 品種。activeであること |
| | code / name | text | codeは同一区画内で一意 |
| supplier | management_code / name | text | management_codeは一意 |
| worker | code / display_name | text | codeは一意 |
| storage_location | code / name | text | codeは一意 |
| | location_type | text | `cold_storage` / `other` |
| sorting_deadline_rule | harvest_year | number | 2000〜9999 |
| | harvest_month | number | 1〜12 |
| | variety_id | uuid | 品種。activeであること |
| | deadline_days | number | 1以上の整数。初期値運用は30 |

親参照（orchard_id、plot_id、variety_id）は存在しかつactiveであること。見つからないか無効な場合は`VALIDATION_FAILED`、`details = { "field": "<親フィールド>", "reason": "not_found" }`。

```json
{
  "req": {
    "meta": { "idempotency_key": "…", "correlation_id": "…" },
    "input": {
      "master_type": "tree",
      "plot_id": "…",
      "variety_id": "…",
      "code": "tree-02",
      "name": "デモ樹2号"
    }
  }
}
```

## 5. 応答

成功時の`data`は共通フィールドと、第4章の業務フィールドをそのまま返す。

| フィールド | 型 | 内容 |
|---|---|---|
| master_type | text | 要求の`master_type` |
| master_id | uuid | 発行された内部ID |
| is_active | boolean | 常にtrue |
| version | number | 常に1（楽観制御の初期値） |
| （業務フィールド） | | 第4章の全フィールド |

```json
{
  "ok": true,
  "correlation_id": "…",
  "idempotent_replay": false,
  "data": {
    "master_type": "tree",
    "master_id": "…",
    "plot_id": "…",
    "variety_id": "…",
    "code": "tree-02",
    "name": "デモ樹2号",
    "is_active": true,
    "version": 1
  }
}
```

## 6. 業務エラー

| code | 発生条件 | details |
|---|---|---|
| MASTER_DUPLICATE | 一意制約と重複する値（code、name、management_code、区画内code、年度・収穫月・品種の組合せ） | `field`（複合キーは代表フィールド。選果期限ルールは`variety_id`）、`reason: "duplicate"`、`existing: { master_id, is_active }` |

無効化済みの既存データと重複した場合も`MASTER_DUPLICATE`とし、`existing.is_active = false`を根拠にクライアントは再有効化（[master_activate](master_activate.md)）を促す。

必須・型・値域・親不在・等級登録は共通の`VALIDATION_FAILED`（`details.reason`: `required` / `invalid_type` / `invalid_format` / `invalid_value` / `out_of_range` / `not_found` / `not_allowed`）。

## 7. 競合条件

新規登録に楽観制御の前提値はない。同時に同じ値を登録した場合、後着は事前検査または一意制約により`MASTER_DUPLICATE`となる（一意制約で検出された場合の`details`は`{ "reason": "duplicate" }`のみ）。

## 8. 冪等性

共通契約どおり。保存済み応答の再生は同一利用者に限る。

## 9. 排他制御

親マスター（農園・区画・品種）の行を`FOR SHARE`でロックしてから活性を検証する。親を無効化する[master_deactivate](master_deactivate.md)は同じ行を`FOR UPDATE`でロックするため、親の無効化と子の登録は直列化され、無効な親の下に新しい子が入らない。

## 10. 副作用

- `master_type`に対応するテーブルへ1行insertする（`created_by / updated_by = auth.uid()`）。
- `public.change_history`へ`operation = 'create'`の監査行を追記する。
- `private.idempotency_records`へ確定した封筒を保存する（認証エラー時は保存しない）。
- 表示IDの採番は行わない（マスターは表示IDを持たない）。

## 11. 履歴

`change_history`へ次を記録する。

| 列 | 値 |
|---|---|
| entity_type / entity_id | `master` / 登録した行のID |
| operation | `create` |
| before_data | なし |
| after_data | 登録後の全列スナップショット + `master_type` |
| reason | `input.reason`（省略時`マスター登録`） |
| changed_by | `auth.uid()` |
| correlation_id | `meta.correlation_id` |

## 12. 例

正常系は第4・5章のとおり。無効化済みデータとの重複。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "business",
    "code": "MASTER_DUPLICATE",
    "message": "すでに同じ値で登録されています。無効化済みの場合は再有効化してください。",
    "retryable": false,
    "details": {
      "field": "code",
      "reason": "duplicate",
      "existing": { "master_id": "…", "is_active": false }
    }
  }
}
```

## 変更履歴

| 版 | 日付 | 内容 | 承認 |
|---|---|---|---|
| 1 | 2026-09-11 | 初版作成 | 未承認（Issue #39のレビュー中） |

## S3の追熟マスター

`ripening_rule` の登録・更新・有効化・無効化は [追熟予定・期限](ripening_deadlines.md) を参照。

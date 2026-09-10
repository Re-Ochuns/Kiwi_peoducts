# RPC契約: receiving_register

- 状態: 草案
- 版: 1
- 対象Issue: [#12](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/12)
- 関連要件: [01. 業務要件 第4章](../../production-spec/01_BUSINESS_REQUIREMENTS.md)、[03. 状態遷移・データモデル 第7・9章](../../production-spec/03_STATE_AND_DATA_MODEL.md)

[RPC共通契約](../rpc-contract-spec.md)を前提とし、本書は差分と操作固有の内容だけを定義する。

## 1. 概要

収穫または仕入れの受入ロットを1件登録し、選果待ち状態と年度別表示IDを確定する。

## 2. Function

| 項目 | 内容 |
|---|---|
| Function名 | `receiving_register` |
| 種別 | PostgreSQL Function |
| 権限 | 認証済みかつ`active`な利用者（member / administrator） |

## 3. 要求

`input`のフィールドを定義する。未知のフィールドは無視するが、冪等性ハッシュには含まれる。

| フィールド | 型 | 必須 | 内容・制約 |
|---|---|---|---|
| source_type | text | 必須 | `harvest`（収穫）/ `purchase`（仕入れ） |
| received_date | text | 必須 | 受入日。Asia/Tokyoの`YYYY-MM-DD` |
| orchard_id | uuid | harvestのみ必須 | 農園マスター。purchaseでは指定不可 |
| plot_id | uuid | harvestのみ必須 | 区画マスター。`orchard_id`に属すること。purchaseでは指定不可 |
| tree_id | uuid | harvestのみ必須 | 樹体マスター。`plot_id`に属し品種が`variety_id`と一致すること。purchaseでは指定不可 |
| supplier_id | uuid | purchaseのみ必須 | 仕入先マスター。harvestでは指定不可 |
| supplier_reference | text | purchaseのみ必須 | 仕入先管理ID。harvestでは指定不可 |
| origin_name | text | 必須 | 産地・区画の表示名 |
| variety_id | uuid | 必須 | 品種マスター |
| total_weight_kg | number | 必須 | 総重量。0より大きく0.01kg単位 |
| container_count | number | 必須 | コンテナ数。1以上の整数 |
| sorting_due_date | text | 任意 | 選果期限。省略時は選果期限マスター（適用年度・収穫月・品種）から計算し、ルールがなければ受入日+30日。指定時は受入日以降 |
| worker_id | uuid | 必須 | 受入担当の作業者マスター |

参照するマスターはすべて有効（`is_active`）であること。文字列は前後の空白を除去して保存する。

`meta.idempotency_key`・`meta.correlation_id`は共通契約§3のとおりUUID v4（versionが4、variantが8〜b）とし、非v4（v1・nil・variant不正など）は`VALIDATION_FAILED / invalid_format`とする。業務入力の`*_id`はマスターの内部IDをそのまま受け取るため版を問わない。

```json
{
  "req": {
    "meta": { "idempotency_key": "…", "correlation_id": "…" },
    "input": {
      "source_type": "harvest",
      "received_date": "2028-05-01",
      "orchard_id": "…",
      "plot_id": "…",
      "tree_id": "…",
      "origin_name": "デモ農園 北区画A",
      "variety_id": "…",
      "total_weight_kg": 25.50,
      "container_count": 2,
      "worker_id": "…"
    }
  }
}
```

## 4. 応答

成功時の`data`を定義する。

| フィールド | 型 | 内容 |
|---|---|---|
| receiving_lot_id | uuid | 登録された受入ロットの内部ID |
| display_id | text | 発行された年度別表示ID（`受入-YYYY-NNN`） |
| status | text | 常に`awaiting_sorting` |
| received_date | text | 確定した受入日 |
| sorting_due_date | text | 確定した選果期限（既定値計算後） |
| version | number | 楽観制御の版。登録時は常に1 |

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
    "version": 1
  }
}
```

## 5. 業務エラー

操作固有のコードはない。共通の`VALIDATION_FAILED`を使用し、`details`へ`field`（対象フィールド）と`reason`を含める。

| details.reason | 発生条件 |
|---|---|
| required | 必須フィールドの欠落・空文字 |
| invalid_type / invalid_format / invalid_value | 型・書式・列挙値の違反 |
| invalid_precision | 重量が0.01kg単位でない |
| out_of_range | 重量・個数・選果期限の値域違反 |
| not_found | マスターが存在しないか無効 |
| not_allowed | 区分に許されないフィールドの指定（例: harvestへの`supplier_id`） |
| variety_mismatch | 樹体の品種が`variety_id`と不一致 |

## 6. 競合条件

対象行を前提としないため`CONFLICT_STALE`は発生しない。`IDEMPOTENCY_KEY_REUSED`は共通契約どおり。

## 7. 冪等性

共通契約どおり。特記事項として、保存済み応答の再生は同一利用者（`auth.uid()`）に限る。別の利用者が同じキーを送った場合は入力が同一でも`IDEMPOTENCY_KEY_REUSED`とする。

## 8. 排他制御

- `private.display_id_counters`の該当行（`受入`×年度）をupsertでロックし、表示ID採番を直列化する。
- 業務検証はすべて採番・書き込みより前に行い、検証失敗で表示ID番号を消費しない。

## 9. 副作用

- `public.receiving_lots`へ1行insertする（`status = 'awaiting_sorting'`、`version = 1`、`created_by / updated_by = auth.uid()`）。
- `private.display_id_counters`の`受入`×受入日の年の行を加算し、表示ID`受入-YYYY-NNN`（NNNは3桁以上のゼロ埋め連番）を発行する。
- `public.change_history`へ`operation = 'create'`の監査行を追記する。
- `private.idempotency_records`へ確定した封筒を保存する（認証エラー時は保存しない）。
- 作業タスク（選果タスク）は段階1のスキーマに存在しないため生成しない。導入時に本契約を改訂する。

## 10. 履歴

`change_history`へ次を記録する。

| 列 | 値 |
|---|---|
| entity_type / entity_id | `receiving_lot` / 登録したロットID |
| operation | `create` |
| before_data | null |
| after_data | 登録行の全列スナップショット |
| reason | 固定文言`受入登録` |
| changed_by | `auth.uid()` |
| correlation_id | `meta.correlation_id` |

## 11. 例

正常系は第3・4章のとおり。代表的な失敗:

purchaseで`supplier_reference`欠落。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "business",
    "code": "VALIDATION_FAILED",
    "message": "supplier_reference は必須です。",
    "retryable": false,
    "details": { "field": "supplier_reference", "reason": "required" }
  }
}
```

同一キー・異なる入力の再送。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "conflict",
    "code": "IDEMPOTENCY_KEY_REUSED",
    "message": "同じ操作キーで内容の異なる要求を受け取りました。操作をやり直してください。",
    "retryable": false
  }
}
```

## 変更履歴

| 版 | 日付 | 内容 | 承認 |
|---|---|---|---|
| 1 | 2026-09-10 | 初版作成 | 未承認（Issue #12のレビュー中） |

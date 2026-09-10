# RPC契約: sorting_confirm

- 状態: 草案
- 版: 1
- 対象Issue: [#14](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/14)
- 関連要件: [01. 業務要件 第5章](../../production-spec/01_BUSINESS_REQUIREMENTS.md)、[03. 状態遷移・データモデル 第2・8・9章](../../production-spec/03_STATE_AND_DATA_MODEL.md)

[RPC共通契約](../rpc-contract-spec.md)を前提とし、本書は差分と操作固有の内容だけを定義する。

## 1. 概要

選果待ちの受入ロット全量の選果を確定する。選果実績、規格別コンテナ（初期在庫）、コンテナごとのラベルジョブを同一トランザクションで生成し、受入ロットを`sorted`へ閉じる。

- 選果対象の取得は本RPCの対象外。RLSで保護されたData APIで`receiving_lots`の`status = 'awaiting_sorting'`を読み取る。
- 確定の取消・確定後の修正は提供しない（次工程後の訂正はO-01として未決。DBトリガーが確定後の変更を拒否する）。
- 全量ロス（コンテナ0件）の確定は現時点で許可しない。必要になった場合は互換な変更として緩和する。

## 2. Function

| 項目 | 内容 |
|---|---|
| Function名 | `sorting_confirm` |
| 種別 | PostgreSQL Function |
| 権限 | 認証済みかつ`active`な利用者（member / administrator） |

## 3. 要求

`input`のフィールドを定義する。

| フィールド | 型 | 必須 | 内容・制約 |
|---|---|---|---|
| receiving_lot_id | uuid | 必須 | 選果対象の受入ロット。`awaiting_sorting`であること |
| sorting_date | text | 必須 | 選果日。Asia/Tokyoの`YYYY-MM-DD` |
| worker_id | uuid | 必須 | 選果担当の作業者マスター（有効であること） |
| expected_lot_version | number | 必須 | クライアントが表示していた受入ロットの版（楽観制御の前提値） |
| containers | array | 必須 | 出力コンテナ。1件以上。配列順がそのまま枝番（1始まり）になる |
| containers[].grade_id | uuid | 必須 | 等級マスター（有効であること）。同一等級の複数指定可 |
| containers[].weight_kg | number | 必須 | 正味重量。0より大きく0.01kg単位 |

`containers`の欠落・JSON null・空配列は`VALIDATION_FAILED / required`、配列以外の型（オブジェクト・数値など）は`VALIDATION_FAILED / invalid_type`とする（[receiving_register 第5章](receiving_register.md)の語彙に準拠）。コンテナ要素の検証エラーでは`details.field`を`containers[i].weight_kg`のように0始まりの添字付きで返す。

```json
{
  "req": {
    "meta": { "idempotency_key": "…", "correlation_id": "…" },
    "input": {
      "receiving_lot_id": "…",
      "sorting_date": "2029-05-10",
      "worker_id": "…",
      "expected_lot_version": 1,
      "containers": [
        { "grade_id": "…", "weight_kg": 6.00 },
        { "grade_id": "…", "weight_kg": 3.50 }
      ]
    }
  }
}
```

## 4. 応答

成功時の`data`を定義する。

| フィールド | 型 | 内容 |
|---|---|---|
| sorting_result_id | uuid | 生成された選果実績の内部ID |
| display_id | text | 選果実績の年度別表示ID（`選果-YYYY-NNN`。年は選果日から） |
| sorting_date | text | 確定した選果日 |
| input_weight_kg | number | 投入量（受入ロット総重量） |
| output_weight_kg | number | 選果後重量（コンテナ合計） |
| loss_weight_kg | number | ロス（投入量 − 選果後重量） |
| receiving_lot_id | uuid | 閉じた受入ロット |
| receiving_lot_status | text | 常に`sorted` |
| receiving_lot_version | number | 加算後の受入ロット版 |
| containers | array | 生成されたコンテナ。要求と同順 |
| containers[].container_id | uuid | コンテナ内部ID |
| containers[].display_id | text | `選果-YYYY-NNN-K`（Kは枝番） |
| containers[].grade_id | uuid | 等級 |
| containers[].weight_kg | number | 元重量（=現在量） |
| containers[].status | text | 常に`awaiting_label` |

```json
{
  "ok": true,
  "correlation_id": "…",
  "idempotent_replay": false,
  "data": {
    "sorting_result_id": "…",
    "display_id": "選果-2029-001",
    "sorting_date": "2029-05-10",
    "input_weight_kg": 10.00,
    "output_weight_kg": 9.50,
    "loss_weight_kg": 0.50,
    "receiving_lot_id": "…",
    "receiving_lot_status": "sorted",
    "receiving_lot_version": 2,
    "containers": [
      { "container_id": "…", "display_id": "選果-2029-001-1", "grade_id": "…", "weight_kg": 6.00, "status": "awaiting_label" },
      { "container_id": "…", "display_id": "選果-2029-001-2", "grade_id": "…", "weight_kg": 3.50, "status": "awaiting_label" }
    ]
  }
}
```

## 5. 業務エラー

共通コードに加えて次を定義する。

| code | 発生条件 | details |
|---|---|---|
| SORTING_WEIGHT_EXCEEDED | コンテナ合計が受入ロット総重量を超える | `input_total_kg`（コンテナ合計）、`lot_total_kg`（ロット総重量） |

`VALIDATION_FAILED`の`details.reason`は[receiving_register 第5章](receiving_register.md)と同一の語彙を使う。

## 6. 競合条件

`CONFLICT_STALE`は次の場合に返し、`details.current`へ`receiving_lot_id`・`status`・`version`・`total_weight_kg`を含める。

| 前提の崩れ方 | 判定 |
|---|---|
| 対象ロットが`sorted`（別の操作が先に確定した） | 行ロック後の状態検証で検出 |
| `expected_lot_version`が現在の`version`と不一致（受入修正が先に確定した） | 選果画面表示後の受入修正を検出し、変更後の重量での再確認を促す |

## 7. 冪等性

共通契約どおり。受入RPCと同じく、保存済み応答の再生は同一利用者に限る。二重確定は冪等再生（同一キー）または`CONFLICT_STALE`（新キー）となり、二重在庫は生成されない。`meta.idempotency_key`・`meta.correlation_id`は共通契約§3のUUID v4のみ受理し、非v4は`VALIDATION_FAILED / invalid_format`とする（受入RPCと同一の`private.rpc_try_uuid_v4`検証）。

## 8. 排他制御

1. 入力形式・作業者・等級を検証する（書き込みなし）。
2. 対象の受入ロットを`SELECT ... FOR UPDATE`でロックする。
3. `status = 'awaiting_sorting'`、`version = expected_lot_version`、`コンテナ合計 <= 総重量`を検証する。
4. `private.display_id_counters`の`選果`×年度行をupsertでロックして採番する（検証失敗では番号を消費しない）。

検証失敗時はロールバックし、選果実績・コンテナ・在庫が中途半端に残らない。

## 9. 副作用

- `public.sorting_results`へ1行insertする（投入量=ロット総重量、出力=コンテナ合計、ロス=差分）。
- `public.containers`へ要求順に生成する（品種はロットから継承、`original_weight_kg = current_weight_kg`、`status = 'awaiting_label'`、表示IDは`選果-YYYY-NNN-K`）。
- `public.label_jobs`をコンテナごとに1件生成する（`status = 'not_printed'`、`required_copies = 1`）。ラベル対応タスクの発生条件（03 第5章）に対応する。
- `public.receiving_lots`を`status = 'sorted'`へ遷移させ、`version`を1加算する。
- `public.change_history`へ監査行を追記する（第10章）。
- `private.idempotency_records`へ確定した封筒を保存する（認証エラー時は保存しない）。

## 10. 履歴

`change_history`へ次を1トランザクションで記録する。reasonはすべて固定文言`選果確定`、`changed_by = auth.uid()`、`correlation_id = meta.correlation_id`。

| entity_type / operation | before_data | after_data |
|---|---|---|
| sorting_result / create | null | 選果実績の全列 |
| container / create（コンテナごと） | null | コンテナの全列 |
| label_job / create（コンテナごと） | null | ラベルジョブの全列 |
| receiving_lot / transition | 遷移前の全列 | 遷移後の全列 |

## 11. 例

正常系は第3・4章のとおり。

重量超過。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "business",
    "code": "SORTING_WEIGHT_EXCEEDED",
    "message": "選果後の合計重量が受入重量を超えています。",
    "retryable": false,
    "details": { "input_total_kg": 5.01, "lot_total_kg": 5.00 }
  }
}
```

別の利用者が先に確定した。HTTP 200:

```json
{
  "ok": false,
  "correlation_id": "…",
  "idempotent_replay": false,
  "error": {
    "category": "conflict",
    "code": "CONFLICT_STALE",
    "message": "このロットはすでに選果が確定されています。最新の状態を確認してください。",
    "retryable": false,
    "details": {
      "current": { "receiving_lot_id": "…", "status": "sorted", "version": 2, "total_weight_kg": 10.00 }
    }
  }
}
```

## 変更履歴

| 版 | 日付 | 内容 | 承認 |
|---|---|---|---|
| 1 | 2026-09-10 | 初版作成 | 未承認（Issue #14のレビュー中） |

# 工程ボード受注 RPC

管理者のみ。匿名呼出し不可。数量はkg、小数2桁、正数。UUIDと各マスターの有効性はサーバーで検証する。

## board_order_candidates(input_value jsonb)

```json
{"scheduled_ship_date":"2027-06-01","variety_id":"UUID","grade_id":"UUID","ordered_weight_kg":2.5}
```

候補配列を返す。各要素は `kind`（container / lot）、`id`、`display_id`、`stage`（sorted / ripening / resting / shippable）、`available_weight_kg`、`planned_ethylene_at`、`planned_completion_at`、`location_id`、`container_ids`（表示用文字列）、`version`（不透明な比較トークン）。検索は業務データを変更しない。エラーはPostgRESTエラーとして返す。

## board_order_confirm(req jsonb)

```json
{
  "meta":{"idempotency_key":"UUID v4","correlation_id":"UUID v4"},
  "input":{
    "scheduled_ship_date":"2027-06-01","variety_id":"UUID","grade_id":"UUID","ordered_weight_kg":2.5,
    "candidate_kind":"container","candidate_id":"UUID","candidate_version":"検索結果のversion",
    "customer_id":"UUID","shipping_destination_id":"UUID",
    "storage_location_id":"UUID","assigned_worker_id":"UUID"
  }
}
```

`storage_location_id` と `assigned_worker_id` は新規コンテナ計画で必須。既存ロットは保存済み設定を利用する。

標準のRPC envelopeを返す。成功時 `data` は `order_id`、`order_number`、`ripening_lot_id`、`ripening_display_id`、`existing_plan`。再送時 `idempotent_replay: true`。入力変更には新しいキーを使い、通信失敗の再送では元のキーと入力を維持する。業務失敗も冪等結果に保存する。

代表エラー：`VALIDATION_FAILED`、`AUTH_REQUIRED`、`AUTH_FORBIDDEN`、`INVENTORY_UNAVAILABLE`、`IDEMPOTENCY_KEY_REUSED`。顧客・配送先・計画の既存業務エラーも引き継ぐ。候補競合時は再検索する。通信結果が不明なとき、新規キーで作り直してはいけない。

排他：既存業務と共通のadvisory transaction lock (53, 0)、対象行ロック、候補再計算、トークン比較。部分成功を許さない。監査履歴・タスク投影は既存処理を再利用する。

日程・数量の詳細は `production-spec/12_PROCESS_BOARD_ORDER_PLAN.md` を参照。

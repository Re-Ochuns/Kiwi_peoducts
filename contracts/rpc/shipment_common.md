# 出荷RPC（S3-05 / #64）

状態: 実装済み・3担当レビュー待ち。共通封筒は [RPC共通契約](../rpc-contract-spec.md) に従う。

## 更新API

`shipment_confirm(req jsonb)` と `shipment_cancel(req jsonb)` は active の member / administrator が利用できる。
匿名・pending は拒否する。テーブルへの直接更新権限は付与しない。
`meta.correlation_id` と `meta.idempotency_key` は UUID v4。

### shipment_confirm

入力例（`req.input`）:

```json
{
  "order_id": "53300000-0000-0000-0000-000000000001",
  "expected_order_version": 1,
  "worker_id": "a7000000-0000-0000-0000-000000000001",
  "checked": true,
  "reason": "出荷内容確認済み",
  "lines": [{
    "container_id": "64100000-0000-0000-0000-000000000001",
    "expected_version": 1,
    "shipped_weight_kg": 2.5
  }]
}
```

- `shipped_at` は省略時にサーバー現在時刻。指定時はタイムゾーン付きISO 8601で現在以前。`notes` は任意。
- `reason` は必須、`checked` は true、有効な `worker_id` を指定する。
- 明細は1〜100件、コンテナ重複不可、重量は正の0.01kg単位。未定義項目は拒否する。
- 受注は confirmed / in_progress / partially_shipped。追熟コンテナの品種・等級が受注に一致し、shippable で期限設定済みであること。
- `shippable_from` が設定されている場合、現在時刻・出荷実績日時が開始前なら出荷不可。候補一覧にも含めない。
- ロック取得後の実時刻が出荷期限・賞味期限のいずれかに達したら出荷不可（ロック待ち中の期限超過も拒否）。過去日時の入力でも期限判定を回避できない。
- 各明細はコンテナ現在量−予約量以下。ロット別の明細合計は、その受注の計画割当−取消を除く出荷済量以下。全明細合計は受注未出荷量以下。
- 予備在庫をこのRPCで新規受注へ割り当てることはできない。他受注への割当も消費しない。
- 顧客情報と受注の納品先スナップショットを保存する。表示IDは出荷日時の日本時間年で採番する。
- 同一コンテナIDで在庫を減算し、残量0で shipped。受注は一部なら partially_shipped、全量なら shipped。
- 管理対象の出荷タスクは全量出荷時に completed。完了作業者は workers のIDで保存する。

### shipment_cancel

入力: `shipment_id`, `expected_version`, `reason`（すべて必須）。
出荷単位で全明細を取消し、元の在庫イベントを参照する正の逆イベントを記録する。元データを削除しない。
取消後の在庫が元重量を超える場合は拒否。confirmed の出荷のみ対象で、取消済み受注では操作不可。
賞味期限を過ぎた在庫は復元しても expired とし、再出荷を許可しない。
受注は有効な出荷合計から再計算し、残出荷0なら実行済み計画の有無により in_progress / confirmed に戻す。
出荷タスクを pending に戻し、完了日時・完了作業者を解除する。

両APIの成功 `data` は出荷ヘッダーに `lines`, `total_weight_kg`, `order`（order_get形式）を追加したもの。
変更前のversionを渡すと CONFLICT_STALE。同じキー・同じ入力の再送は元の結果と `idempotent_replay: true` を返す。
相関IDは再送の値に置換する。別の内容へのキー再利用は IDEMPOTENCY_KEY_REUSED。
業務エラーも保存されるため、修正後の操作は新しいキーを使う。

## 読取API

共通封筒なし。active ユーザーのみデータを取得できる。

| Function | 引数 | 応答 |
|---|---|---|
| shipment_get | shipment_id_value uuid | 出荷ヘッダー＋lines＋total_weight_kg、存在しない／非表示ならnull |
| shipment_list | order_id_value uuid（省略可） | 取消を含む出荷ヘッダー配列。省略時は全受注、出荷日時降順 |
| shipment_container_list | order_id_value uuid | 対象受注の割当ロットにある出荷可能コンテナ配列＋available_weight_kg＋remaining_use_type |
| shipment_inventory_list | なし | 追熟コンテナ配列（残量0・期限切れも含む）＋remaining_use_type |

`available_weight_kg` はコンテナ使用可能量、ロットの対象受注未出荷割当、受注未出荷量の最小値（下限0）。
同一ロット内で複数行に共通の割当上限が適用されるため、候補行の値を合算して総出荷可能量にしない。
0の候補は選択を無効化する。確定APIが明細合計を再検証する。

計画の `ripening_allocations` / `use_type` は計画履歴として保持する。
残在庫の表示は `remaining_use_type` を使う。取消を除く出荷済量を計画の受注割当から引き、
未出荷割当が0なら reserve、残量が未出荷割当より多ければ mixed、それ以外は order。
これはロット単位の分類を各出力コンテナへ返すもので、個々の現物への割当位置を表さない。
取消時は未出荷割当が復活するので分類も戻る。

## エラー・整合性

| 種別 | コード |
|---|---|
| auth | AUTH_REQUIRED / AUTH_FORBIDDEN |
| business | VALIDATION_FAILED / CONFIRMATION_REQUIRED / ORDER_WEIGHT_EXCEEDED / CONTAINER_UNAVAILABLE / DEADLINE_UNSET / CONTAINER_EXPIRED / INVENTORY_UNAVAILABLE / ALLOCATION_UNAVAILABLE |
| conflict | ORDER_UNAVAILABLE / SHIPMENT_UNAVAILABLE / CONFLICT_STALE / INVENTORY_CONFLICT / IDEMPOTENCY_KEY_REUSED |

業務変更は単一トランザクション。失敗時に出荷・在庫・受注・タスクの一部だけを残さない。
計画・受注RPCと共通のadvisory lock、その内側で受注・出荷・UUID順のコンテナ行をロックする。
在庫イベント制約とトリガーでも残量・出荷明細・逆イベントの整合を保証する。
出荷、明細、在庫イベント、コンテナ、受注、タスクの変更を actor / reason / correlation_id 付きで記録する。
カレンダー同期は既存のタスク変更キューを利用し、このRPC内では外部APIを呼ばない。

出荷画面は #69、追熟実績RPCとの縦通しは #62 の実装後に結合確認する。

## 検証

- 全マイグレーション適用後に `supabase db lint --local --fail-on warning` と `supabase test db` を実行する。
- `00170_shipment_rpc_test.sql` は権限・重量・期限・版競合・部分出荷・取消・履歴を確認する。
- `00180_shipment_rpc_concurrency_test.sql` は別DBセッションのロック待ちを確認してからコミットし、二重減算・二重復元と競合出荷を検証する。
- HTTP検証: 専用 `kiwi_issue64`（API 59321 / DB 59322）を空から再構築し、Authのパスワードログインをテスト用に有効化して、`SUPABASE_CMD=/path/to/supabase python3 scripts/verify_shipment_http.py /path/to/runtime` を実行する。他プロジェクト・ポートでは拒否する。ダミーデータのみを使い、認証情報をファイルへ保存しない。再実行前に専用DBをリセットする。
- HTTP検証は複数明細、同時再送、部分→全量→取消、復元重量、スナップショット、4読取API、匿名・pending拒否を確認する。終了後は専用環境を停止する。

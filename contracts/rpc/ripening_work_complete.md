# 追熟作業RPC（S3-02 / Issue #62）

状態: 実装済み・DB/バックエンド/フロント担当レビュー待ち。
共通封筒、認証、冪等性は [RPC共通契約](../rpc-contract-spec.md) に従う。

| Function | 前提 | 更新 |
|---|---|---|
| ripening_ethylene_injection_complete | confirmed計画、未完了の注入タスク | 部分予約をconsumed、元在庫を減算、追熟コンテナ1個を生成、計画・受注を作業中へ |
| ripening_ethylene_removal_complete | in_progress計画、注入済み、現物ethylene_processing | 抜き確認・寝かせ開始を1実績行へ保存、現物resting |
| ripening_ripeness_complete | in_progress計画、抜き確認済み、現物resting/awaiting_ripeness_check | 現物shippable、計画completed |
| ripening_work_get | 有効利用者、ripening_lot_id_value uuid | 計画・内訳・予約・results・containers・tasksを返す。参照は共通封筒なし |

## 入力
更新は単一jsonb引数req。metaはidempotency_key/correlation_id（UUID v4）。
inputは以下のみ。未知のキー、延長・再処理の指定は拒否。

- ripening_lot_id: UUID、expected_version: 正整数、必須。
- checked: JSON boolean true、必須。対象と作業実施の確認。
- actual_at: タイムゾーン付きISO 8601。省略時はサーバーのstatement_timestamp。
  明示nullは不正。再送は初回に保存した結果と実績日時を維持。
- actual_temperature: 有限のJSON数値、必須。温度範囲の追加業務規則は定義しない。
- location_id / performed_by: 有効な場所・作業者マスターのUUID、必須。
- notes: 任意文字列。
- 抜き確認のみ rest_started_at（省略時actual_at）とrest_temperature（有限数値、必須）。
  rest_started_atは抜き確認以降。
- 後続工程のactual_atは前工程の実績（寝かせ開始）以降。

## 原子性と並行実行
S2と同じadvisory lock (53,0)、ロット・受注・コンテナの行ロックを利用。
expected_versionを検証し、成功ごとに計画versionを増やす。
同じ操作キー・同じinputは成功・業務エラーとも再返却する。
異なるinputまたは異なるRPCでキーを使い回すとIDEMPOTENCY_KEY_REUSED。
別キーによる二重実行はCONFLICT_STALEまたはINVALID_WORK_STATE。

注入は全予約・内訳の合計と商品・参照状態を再検証する。
入力から内訳・予約量・出力重量を上書きさせない。
元コンテナIDと残量を維持し、出力表示IDは計画表示ID + "-1"。
在庫イベントのINSERTトリガーだけで重量を移動し、二重加減算しない。
確定済み受注・予備の内訳行と重量は全工程で不変。

各工程でタスクをcompletedにし、実績担当者・日時を保存する。
既存のカレンダーキューへ完了リビジョンを登録する。
注入・抜き確認の実績場所は、同じロットの計画管理対象かつ未完了の後続タスクの
task_details.locationへ反映し、変更履歴とカレンダー再同期キューを保存する。
予定日時・計画場所・完了済みタスクを保持し、場所表示が同じ場合は後続タスクを更新しない。
計画、予約、受注、コンテナ、作業タスク、実績の変更履歴を同一トランザクションで保存。
在庫イベント・実績の自動履歴のcorrelation_idは基盤仕様により操作ID、
RPCが書く集約・タスク履歴は要求のcorrelation_id。

## エラー
- AUTH_REQUIRED / AUTH_FORBIDDEN: JWTなし・非active。
- VALIDATION_FAILED: 形式、参照マスター、時系列、未対応項目。
- CONFIRMATION_REQUIRED: checkedがtrueでない。
- CONFLICT_STALE: version不一致。
- INVALID_WORK_STATE: 前工程未完了、現物工程不一致、タスクなし・完了済み、再処理。
- RIPENING_WEIGHT_MISMATCH / ORDER_UNAVAILABLE / INVENTORY_UNAVAILABLE。
エラー時は業務更新を全部ロールバックし、封筒を冪等性レコードへ保存する。
予期しないDBエラーはSQLエラーとなり要求全体がロールバックされる。

## #63および後続機能との境界
計画の予定日時とmaster_snapshotを変更しない。注入実績からの計算予定・期限・タスク更新は
[追熟予定・期限](ripening_deadlines.md) に従う。マスター未設定の開始はRIPENING_MASTER_NOT_FOUND。
shippableは現物工程の確認完了を示すが、期限が未設定のコンテナは
#60の出荷イベント検証によって出荷を拒否される。
期限は保存済みマスターと注入実績から計算し、仮値で埋めない。
ラベル出力・既存一覧への追熟コンテナ表示の統合は本RPCの対象外。

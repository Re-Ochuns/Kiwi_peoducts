# 作業タスク・Googleカレンダー同期契約（#57 / S2-06）

版: 1。実装済み・担当者レビュー待ち。
更新RPCは[共通契約](../rpc-contract-spec.md)に従う。

## タスク生成

- ripening_plan_confirm成功時に、注入・抜き確認・追熟確認の3タスクを同じトランザクションで作成する。
- 注入はplanned_ethylene_at、抜き確認は注入予定+既定168時間（1週間）、追熟確認はplanned_completion_at。
- 確定時の処理時間はmaster_snapshot.task_ethylene_processing_hoursへ保存し、既定値の後日変更では変えない。
- 完了予定が抜き確認より早い場合はCOMPLETION_BEFORE_REMOVALをschedule_warningへ保存する。
  既存の予定を勝手に修正せず、管理画面の警告件数へ含める。
- order_confirm成功時に受注ごとの出荷タスクを作成する。出荷日はAsia/Tokyoの終日予定とする。
- 作業タスクの一意性は追熟ロット+作業種別、受注+shippingで保証する。
- 変更によって計画・受注が下書きへ戻ると旧タスクをcancelledにし、再確定で同じタスクIDを再利用する。
- 受注変更・中止で関連計画が下書きへ戻った場合も、関連タスクを同じ処理で更新する。
- 計画・受注中止ではタスクを削除しない。work_taskの変更前後、理由、実行者、correlation_idをchange_historyへ記録する。
- 冪等再送ではタスク・履歴・同期ジョブを増やさない。Googleへ接続する処理はDBの確定処理に含めない。

task_detailsはvariety、grade、weight_kg、必要時のlocation、出荷時のshipping_dateだけを持つ。
顧客名・住所・受注の自由記入欄はコピーしない。
target_urlは /work-tasks/{task_id}。この画面へのルーティング実装は #56 の担当範囲。
注入・確認イベントの15分枠はカレンダー表示用で、処理時間・期限の計算ではない。

## 参照・移行RPC

| Function | 入力 | 権限・出力 |
|---|---|---|
| work_task_list | なし | activeユーザー、期限順のwork_tasks行 |
| work_task_get | task_id_value uuid | activeユーザー、タスクJSONまたはnull |
| work_task_sync_warnings | なし | activeユーザー、失敗・未送信・同期停滞・予定矛盾の件数 |
| work_tasks_reconcile | 共通封筒、input.reason必須 | administrator、移行前の確定済み計画・受注も再構成しprocessed_sourcesを返す |

参照はRLSで保護し、pending/disabledユーザーは行を取得できない。
reconcileは共通の認証・冪等性・理由・監査履歴を使い、計画・受注と同じadvisory lockで直列化する。
移行時に架空の実行者を作らず、管理者がこのRPCを実行して既存計画を取り込む。
業務入力エラーはVALIDATION_FAILED、未認証はAUTH_REQUIRED、管理者以外はAUTH_FORBIDDEN、
異なる入力での同一操作キー再利用はIDEMPOTENCY_KEY_REUSED。

## 非同期ワーカー

calendar_sync_claim(batch_size integer=5) / calendar_sync_finish(task_id_value, lease_token_value,
revision_value, error_code_value) はservice_role専用。一般ユーザーは実行不可。
claimは最大5件をFOR UPDATE SKIP LOCKEDで取得し、5分間のリースを発行する。
finishはリーストークンとrevisionを確認し、古い処理結果で新しい計画を同期済みにしない。
期限切れリースは再取得できる。失敗は1、2、4、8、16、32分、以後最大1時間で再試行する。
成功後も15分後から再同期対象にし、カレンダー側の変更をアプリ値へ戻す。
1回5件のため、負荷や失敗件数によって実際の反映時刻は遅れる。

calendar_event_idは送信前からタスクUUIDに基づく値を持ち、pending/failedでも保持する。
Googleへの作成応答が失われても同じIDで再試行する。
Googleが削除済みイベントを復元できない場合だけ、世代番号を増やして次回再作成する。
中止はGoogleイベントを削除せず【中止】の予定として保持する。
送信結果はprivate.calendar_sync_logへ保存する。外部エラー本文や秘密情報は保存しない。

Edge Functionはx-calendar-sync-tokenを検証する。ブラウザーから直接呼ばない。
APIの設定と運用は[運用手順](../../docs/edge-functions/calendar-sync.md)を参照。

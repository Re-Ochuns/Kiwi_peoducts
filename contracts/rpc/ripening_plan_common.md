# 追熟計画RPC（S2-04 / #53）

> #109: 在庫選択から始める新方式の確定・更新・取消は[受注時予約の契約](order_inventory_reservation.md)に従う。以下の既存記述は移行前受注にも適用する。

状態: 実装済み・3担当レビュー待ち。共通封筒は [RPC共通契約](../rpc-contract-spec.md) に従う。

| Function | 入力 | 動作 |
|---|---|---|
| ripening_plan_register | 下記の全計画項目、reason（任意） | draft作成、部分予約 |
| ripening_plan_update | 全計画項目、ripening_lot_id、expected_version、reason | 作業前の全項目置換、draft・needs_review=true |
| ripening_plan_confirm | ripening_lot_id、expected_version、reason | 内訳・予約合計、参照先を再検証しconfirmed |
| ripening_plan_cancel | ripening_lot_id、expected_version、reason | 作業前の予約・受注割当を解除してcancelled |
| ripening_plan_get | ripening_lot_id_value uuid | 内訳・予約付き詳細（参照は共通封筒なし） |
| ripening_inventory_available | 引数なし | 冷蔵コンテナの現在量、予約量、使用可能量 |

全計画項目: variety_id、grade_id、total_weight_kg、storage_location_id、
planned_ethylene_at、planned_completion_at、assigned_worker_id、notes（任意）、
allocations、reservations。日時はタイムゾーン付きISO 8601、完了は注入以降。
重量は正の0.01kg単位。品種・等級・場所・担当者は有効なマスター。
用途区分、集計量、状態、表示ID、version、master_snapshotはクライアント指定不可。
明示した予定日時は保存し、収穫年度・月によるマスターのコピーと計算予定は
[S3-04 追熟予定・期限](ripening_deadlines.md) の契約に従う。

allocations: [{allocation_type: "order" | "reserve", order_id: UUID（orderのみ）,
allocated_weight_kg: number, notes?: string}]。
同一受注の重複・予備複数行は不可。受注はconfirmed/in_progress/partially_shippedで
品種・等級が一致し、全計画の割当が受注重量を超えないこと。
reservations: [{container_id: UUID, reserved_weight_kg: number, notes?: string}]。
同一コンテナの重複不可。冷蔵・品種等級一致、現在量−全予約量以内。
下書きは空配列・不足合計を許容し、各合計は追熟重量以下。
確定時は両合計が追熟重量と完全一致する必要がある。
内訳・予約の文字列とUUIDは共通入力ヘルパーで正規化した値を保存する。
用途区分・UUID・備考の前後空白を除去し、任意のorder_idと備考の空文字はnullにする。
予備内訳に非nullのorder_id、不正なUUIDを指定した場合はVALIDATION_FAILEDとする。

有効な作業者（member）・管理者が同じ権限で操作できる。匿名・pendingは禁止。
参照はsecurity invokerと既存RLSを使う。
作業開始後・中止後は変更・予約解除不可。変更・中止は楽観ロック必須。
変更で同一元コンテナを再選択しても二重予約しない。
中止では予約をreleasedとして保持し、内訳削除の履歴を保存する。

成功dataはロット行とallocations/reservationsの配列。
業務エラー: VALIDATION_FAILED、RIPENING_WEIGHT_MISMATCH、
INVENTORY_UNAVAILABLE、ORDER_UNAVAILABLE。競合: CONFLICT_STALE、
IDEMPOTENCY_KEY_REUSED。共通のAUTH_REQUIRED/AUTH_FORBIDDENも使用する。
エラーは業務変更全体をロールバックし、冪等再送は同じ結果を返す。

受注更新・キャンセルと計画更新は同じトランザクションadvisory lockで直列化する。
その内側でロットとコンテナ行をロックし、DBトリガーで予約量上限を再保証する。
これはS2の小規模運用における受注→計画/計画→受注のロック逆転を防ぐためである。
直接SQLによる予約も既存コンテナ行ロックにより過剰予約を拒否する。

計画・内訳・予約・受注集計・コンテナ集計の変更前後を同じcorrelation_id、
actor、reasonでchange_historyに記録する。冪等再送で履歴は増やさない。
確定時のタスク生成・カレンダー同期は #57、現物工程の開始は #62 が担当する。

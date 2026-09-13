# 追熟予定・期限（S3-04 / #63）

## 収穫年度・月とマスター

`ripening_rules` は収穫年度 (`harvest_year`)、収穫月 (`harvest_month`)、品種の組合せを一意に持つ。
前年度産は前年度の情報を使用する。受入日・計画日・注入日から収穫年度を推測しない。
計画登録・更新の入力へ `harvest_year`（2000〜9999）、`harvest_month`（1〜12）を追加する。
利用者が対象原料の収穫年度・月を明示し、同じ収穫年度・月の原料を一計画にまとめる。

- 指定した年度・月・品種の有効マスターがなければ `RIPENING_MASTER_NOT_FOUND`。業務更新全体をロールバックする。
- 計画登録時にマスターの値・ID・versionを `master_snapshot` に保存する。
- 同じ年度・月・品種の計画更新・再確定では元のコピーを保持する。マスター変更・無効化で既存計画を再計算しない。
- 年度・月・品種を明示的に変更した場合は一致するマスターを新たにコピーする。
- 既存S2クライアントの下書き・確定は互換維持のため両項目省略を許容する。ただしマスター未設定の注入開始は `RIPENING_MASTER_NOT_FOUND`。
- 既存計画の更新時に両項目を省略した場合は保存済み年度・月を維持する。片方だけの指定は `VALIDATION_FAILED`。
- 作業開始前の旧計画は計画更新で年度・月を設定し、再確定してから注入する。
- 既に開始済みで期限未設定の旧計画には自動バックフィルを行わない。元の収穫情報・実績・マスターを確認した個別移行が必要。

`master_register` / `master_update` / `master_deactivate` / `master_activate` は `master_type: "ripening_rule"` を受け付ける。
有効な管理者のみ更新可能。参照はactive利用者、匿名・pendingは参照不可、authenticatedの直接DMLは禁止。
既存の封筒・冪等性・楽観ロック・理由・変更履歴を使用する。年度・月・品種は登録後変更不可。

| マスター項目 | 範囲・意味 |
|---|---|
| ethylene_temperature / rest_temperature | −50〜100℃、数値 |
| ethylene_hours | 0より大きく720時間以下 |
| rest_days | 0より大きく365日以下 |
| shippable_days | 寝かせ終了後の出荷可能日数、0より大きく365日以下 |
| best_before_days | 寝かせ終了後の賞味期限日数、出荷可能日数以上・365日以下 |

## 計算と予定の分離

1日は24時間。時刻はtimestamptzで保存し、タイムゾーンによる日数のずれを避ける。

| 項目 | 計算 |
|---|---|
| calculated_removal_at | 基準日時 + ethylene_hours |
| calculated_rest_end_at | 抜き予定 + rest_days × 24時間 |
| calculated_shippable_until | 寝かせ終了予定 + shippable_days × 24時間 |
| calculated_best_before_at | 寝かせ終了予定 + best_before_days × 24時間 |

注入前の基準日時は `planned_ethylene_at`、注入後は注入実績の `actual_at`。
`planned_ethylene_at` / `planned_completion_at` と実績行は上書きしない。
抜き確認・追熟確認タスクの日時を計算結果へ合わせ、既存のカレンダー同期キューを更新する。
抜き実績や寝かせ開始実績の遅延で、注入基準の賞味期限を延長しない。
追熟コンテナへ `shippable_from`（寝かせ終了予定）、`shippable_until`、`best_before_at` を保存する。
出荷には手動の追熟確認完了と `shippable_from <= 現在時刻 < shippable_until` および `現在時刻 < best_before_at` が必要。
出荷入力日時も開始前は拒否する。候補一覧・出荷確定で判定し、定期処理の遅延で期限切れ出荷を許可しない。

## 自動更新

`public.ripening_deadlines_process()` は引数なし、service_roleのみ実行可。戻り値は `{expired: 件数, overdue: 件数}`。
pg_cronの `ripening-deadlines` が毎分実行する。privateの日時指定はテスト専用で、一般利用者には公開しない。
既存の計画・作業・出荷RPCと同じadvisory lock (53,0) を使い、ロック取得後の時刻で判定する。

- pendingの注入・抜き確認・追熟確認・出荷タスクは `due_at <= 現在時刻` で `is_overdue=true`。完了・中止は対象外。
- overdueは作業statusと独立し、期限超過後も手動確認できる。完了・中止時にフラグを解除する。
- 寝かせ終了予定到来で現物を `resting` → `awaiting_ripeness_check`。出荷可能への遷移には手動確認が必要。
- 出荷可能期限到来で現物・関連計画・受注・予約を `needs_review=true`。
- 賞味期限到来で残量のある現物を `expired` にし、`expired_at` を記録する。未確認の工程も対象。
- 期限切れ状態へ戻る出荷取消在庫も要再確認の対象。全量出荷済みで残量0の現物は処理しない。
- 在庫重量、在庫イベント、予約の消費・解除状態を変えない。現物の廃棄は別操作。
- 同じ対象の再実行でversionや履歴を増やさない。自動更新履歴は `changed_by=null` と自動処理の理由を記録する。

計算項目・期限超過・要再確認フラグは既存の詳細・一覧APIに追加される。
フロントで年度・月の入力とマスター編集を接続する際は本契約を使用する。

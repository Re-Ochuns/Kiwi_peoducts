# 段階2 受注・追熟計画DBスキーマ運用

Issue #52（S2-01）で追加する顧客・受注・追熟計画・在庫予約・作業タスクの基盤を定義する。登録・状態変更RPCは後続のIssue #50、#53、#57で実装し、クライアントからの直接更新は許可しない。

## テーブル

- 顧客・受注: `customers`、`shipping_destinations`、`orders`
- 追熟計画: `ripening_lots`、`ripening_allocations`
- 在庫予約: `inventory_reservations`
- 作業予定: `work_tasks`
- 監査: 既存の`change_history`へ段階2のエンティティ種別を追加

顧客は複数の配送先を持てる。受注は顧客と配送先の組み合わせを複合外部キーで検証し、配送先の表示内容をJSONスナップショットとして保持する。

## 追熟内訳

一つの`ripening_lots`に複数の`ripening_allocations`を登録する。内訳は受注または予備のどちらかであり、受注内訳だけが`order_id`を持つ。

- 受注のみ: `use_type = order`
- 予備のみ: `use_type = reserve`
- 受注と予備の両方: `use_type = mixed`

内訳変更時に追熟ロットと受注の割当済み重量をDBトリガーで更新する。追熟ロットの割当合計を総重量より大きくできず、受注への割当合計も注文重量を超えられない。計画確定時は内訳合計と追熟重量が一致している必要がある。

## 在庫予約

`inventory_reservations`は選果後コンテナの一部重量を追熟ロットへ予約する。一つの追熟ロットから同じコンテナへ作れる予約は一件とする。予約追加・重量変更・解除時はコンテナ行を更新して次を保証する。

```text
使用可能量 = containers.current_weight_kg - containers.reserved_weight_kg
0 <= containers.reserved_weight_kg <= containers.current_weight_kg
```

予約重量はコンテナ行への条件付き更新で加減する。同じコンテナを複数セッションが同時予約した場合も行ロックで直列化され、後続処理が残量を超える場合はSQLSTATE `23514`で失敗する。

予約の追加・解除は追熟ロットが`draft`の間だけ許可する。`consumed`への変更は計画確定後の追熟開始処理に限定する。計画を`confirmed`へ進めるには、有効予約合計も追熟重量と一致している必要がある。

初期実装は、確定した追熟計画が予定どおり開始・完了する正常系を対象とする。作業開始後の受注キャンセル、および受注割当から予備割当への振替は対象外とし、後続Issueで扱う。通常の追熟内訳変更と予約重量変更は`draft`の間だけ許可する。

## 作業タスク

`work_tasks`は選果、ラベル、エチレン注入、エチレン抜き確認、追熟確認、出荷を扱う。対象は受入ロット、ラベル、追熟ロット、受注のいずれか一つとし、作業種別と対象種別の不一致をDB制約で拒否する。

Googleカレンダー連携用にイベントID、同期状態、試行回数、直近エラーを保持する。同期実装と再試行はIssue #57で行う。

## RLSと個人情報

- `anon`、未承認ユーザー、無効ユーザーは段階2テーブルを参照できない。
- `active`なmemberとadministratorは顧客・受注・追熟計画・予約・作業タスクを参照できる。
- authenticated利用者へテーブルの直接更新権限を付与しない。
- 作成・修正・状態変更は、後続Issueで実装する監査・冪等性付きRPCへ限定する。
- `change_history`は従来どおりactiveなadministratorだけが参照できる。

## 検証

```bash
make db-start
make db-reset
supabase db lint --local --fail-on warning
make db-test
```

pgTAPでは顧客と配送先の1対多、受注・予備の複合内訳、割当合計、予約量、計画確定条件、作業対象、RLSを確認する。別セッションを使う競合テストで、同じコンテナへの同時予約が残量を超えないことも確認する。

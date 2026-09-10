# 選果RPC運用

Issue #14（S1-05）の選果確定RPCを定義する。クライアント向けの契約は[sorting_confirm](../../contracts/rpc/sorting_confirm.md)が正本であり、本書は実装・運用の内部事項だけを扱う。

## Function構成

- `public.sorting_confirm(req jsonb)`は`security definer`で、`authenticated`と`service_role`だけが実行できる。
- 封筒・入力検証・冪等性・表示ID採番は[受入RPC](receiving-rpc.md)で導入した`private`ヘルパーを再利用する。選果固有の実装は次のとおり。
  - コンテナ配列は要素ごとに検証し、エラーの`details.field`へ`containers[i].weight_kg`形式で0始まりの添字を付けて返す。
  - 選果実績・コンテナ・ラベルジョブの生成と受入ロットの`sorted`遷移を同一トランザクションで行う。受入ロットのDBトリガー（実績・重量整合の検証）が最終防衛となる。
  - 受入ロットの`version`を遷移時に1加算する。`expected_lot_version`の楽観制御により、選果画面表示後に受入修正（`receiving_correct`）が確定した場合は`CONFLICT_STALE`となる。

## 選果対象の取得

一覧はRPCではなくData APIで読み取る。

```sql
select id, display_id, total_weight_kg, sorting_due_on, version
from public.receiving_lots
where status = 'awaiting_sorting'
order by sorting_due_on, display_id;
```

## 表示ID採番

- 選果実績は`選果`接頭辞で選果日の年に対して採番し（`選果-2029-001`）、コンテナは配列順の枝番を付ける（`選果-2029-001-1`）。
- 採番はロットのロックと全検証の後に行うため、検証失敗・競合で番号を消費しない。

## 検証

```bash
make db-start
make db-reset
supabase db lint --local --fail-on warning
make db-test
```

pgTAPは`supabase/tests/00040_sorting_rpc_test.sql`で正常確定（実績・コンテナ・在庫・ラベルジョブ・監査行の生成）、重量整合、二重確定、版競合、冪等再送・キー誤用、要素単位の入力検証、権限境界、失敗時に中途半端な状態が残らないことを検証する。

## 未決事項

- 確定の取消と確定後の修正はO-01（次工程後の訂正方法）の決定後に別Issueで扱う。
- 全量ロス（コンテナ0件）の確定は現時点で拒否する。要件化された場合は互換な変更として緩和する。

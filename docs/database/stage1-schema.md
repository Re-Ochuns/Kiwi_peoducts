# 段階1 DBスキーマ運用

Issue #10（S1-01）の受入・選果・在庫・ラベル・変更履歴の基盤を定義する。受入の更新RPCはIssue #12（[受入RPC運用](receiving-rpc.md)）、選果の更新RPCはIssue #14（[選果RPC運用](sorting-rpc.md)）で実装済み。ラベルの更新RPCは後続Issue #17で実装する。

## テーブル

- マスター: `varieties`、`grades`、`orchards`、`orchard_plots`、`trees`、`suppliers`、`workers`、`storage_locations`、`sorting_deadline_rules`
- 業務: `receiving_lots`、`sorting_results`、`containers`、`label_jobs`、`label_events`
- 監査: `change_history`
- 内部制御: `private.idempotency_records`

重量には`weight_kg` domainを使用し、非負、上限、0.01kg精度をDBで検証する。表示IDは一意であり、発行後の変更をtriggerで拒否する。
選果期限は適用年度・収穫月・品種の組み合わせを一意なルールとして保持し、初期値を30日とする。

## 状態と整合性

- 受入ロットは`awaiting_sorting`から`sorted`へのみ進める。
- `sorted`へ進めるには、一件の選果実績、実績と一致する出力コンテナ合計、`受入重量 = 出力重量 + ロス`が必要となる。
- 選果後の受入元情報と重量は変更できない。次工程後の訂正方法が確定するまでは、前方修正migrationと後続RPCで扱う。
- 選果確定後は選果実績の重量・担当者・日付と、出力コンテナの親・品種・等級・元重量を変更できず、コンテナの追加・削除もできない。
- コンテナは仕様書の順序でのみ遷移する。段階1では`awaiting_label`から`cold_storage`までを使用する。
- ラベルが`printed`または`handwritten`になるまで、コンテナを`cold_storage`へ変更できない。
- 予約量は現在量以下、現在量は選果時重量以下とする。段階2・3で同時更新RPCが行ロックして数量を変更する。

## RLS

- `anon`と未承認・無効ユーザーは業務データを参照できない。
- `active`なmemberとadministratorは段階1のマスター・受入・在庫・ラベルを参照できる。
- `change_history`はactiveなadministratorだけが参照できる。
- authenticated利用者へテーブルの直接更新権限を付与しない。更新は後続Issueの監査・冪等性付きRPCに限定する。
- `private.idempotency_records`はservice roleだけが操作でき、応答を24時間以上保持する。期限切れレコードはpg_cronが毎時15分に削除する。
- Data APIのサーバー実行上限はクライアントの10秒より短い8秒とし、`authenticator` roleへ設定する。

## seedと代表クエリ

`supabase/seed.sql`はデモ専用マスター、収穫ロット、仕入ロットを決定的UUIDで投入する。実在する顧客・仕入先・在庫を追加してはならない。

```sql
select display_id, source_type, received_on, total_weight_kg, sorting_due_on
from public.receiving_lots
where status = 'awaiting_sorting'
order by sorting_due_on, display_id;
```

## 前進・再構築・ロールバック

```bash
make db-start
make db-reset
supabase db lint --local --fail-on warning
make db-test
```

共有環境へ適用済みのmigrationは編集・削除しない。修正は新しい前方migrationで行う。ローカルは`make db-reset`で空DBから再構築する。Stagingの破壊的変更やバックアップ復旧は別Issueと承認を必要とする。

## 未決事項

- 次工程開始後の訂正方法、仕入先詳細、冷蔵期限、ラベル一部再印刷単位は仕様書のO-01、O-07、O-08、O-10として残す。
- 本migrationでは未決事項を推測せず、確定済みの識別子、状態、重量、参照関係だけを保存する。

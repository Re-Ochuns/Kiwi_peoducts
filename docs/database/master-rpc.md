# マスターRPC運用

Issue #39のマスター管理更新RPCを定義する。クライアント向けの契約は[master_register](../../contracts/rpc/master_register.md)、[master_update](../../contracts/rpc/master_update.md)、[master_deactivate](../../contracts/rpc/master_deactivate.md)、[master_activate](../../contracts/rpc/master_activate.md)が正本であり、本書は実装・運用の内部事項だけを扱う。

## Function構成

- `public.master_register / master_update / master_deactivate / master_activate`（いずれも`(req jsonb)`）は`security definer`で、`authenticated`と`service_role`だけが実行できる。テーブルへの直接更新権限は引き続き付与しない。
- 4操作は`private.master_rpc(function_name, req)`の共通実装を`input.master_type`で分岐させる（ラベルRPCの`private.label_rpc`と同じ方式）。封筒・入力検証・冪等性・共通ログは受入RPCで導入した`private`ヘルパーを再利用する。
- 権限は封筒のauth検証で`private.current_user_has_role('administrator')`を要求する。memberは`AUTH_FORBIDDEN`となり、冪等性キーを消費しない。
- マスター9テーブルへ楽観制御用の`version bigint`列を追加した（既存行は1で開始）。`master_update / master_deactivate / master_activate`は`expected_version`の一致を要求する。

## 階層の整合とロック

- 無効な親の下にactiveな子が存在しない、を不変条件とする。
  - 登録・再有効化は親行（農園・区画・品種）を`FOR SHARE`でロックして活性を検証する。
  - 無効化は対象行を`FOR UPDATE`でロックし、activeな依存（農園→区画、区画→樹体、品種→樹体・選果期限ルール、保管場所→在庫コンテナ）が残っていれば`MASTER_IN_USE`で失敗する。
  - `FOR SHARE`と`FOR UPDATE`が衝突するため、親の無効化と子の登録・再有効化は直列化される。
- 一意制約（code、name、区画内code、年度・収穫月・品種）は事前検査で`MASTER_DUPLICATE`とフィールド情報を返し、同時登録の取りこぼしは`unique_violation`ハンドラが同じコードへ変換する。

## 等級の扱い

等級コードはスキーマのCHECK制約で8候補（`5L`〜`SS`）に固定されており、`master_register`は等級を受け付けない。変更できるのは`display_order`と有効・無効だけとし、候補の追加・コード変更は仕様変更としてmigrationで扱う（Issue #39の未決事項の決定）。

## 検証

```bash
make db-start
make db-reset
supabase db lint --local --fail-on warning
make db-test
```

pgTAPは`supabase/tests/00060_master_rpc_test.sql`で、9種の登録・修正・無効化・再有効化、管理者限定の権限境界、重複・親不在・不変フィールドの検証、版競合と無効化済み競合、冪等再送・キー誤用、変更履歴の記録、物理削除しないことを検証する。

## 未決事項

- 等級候補の追加・コード変更が必要になった場合は、仕様変更Issueとしてmigrationとseedの更新で扱う。
- マスターCSV出力はS1-10（#19）で扱う。

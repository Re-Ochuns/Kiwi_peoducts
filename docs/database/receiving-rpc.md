# 受入RPC運用

Issue #12（S1-03）の受入登録・履歴付き修正RPCを定義する。クライアント向けの契約は[receiving_register](../../contracts/rpc/receiving_register.md)と[receiving_correct](../../contracts/rpc/receiving_correct.md)が正本であり、本書は実装・運用の内部事項だけを扱う。

## Function構成

- `public.receiving_register(req jsonb)` / `public.receiving_correct(req jsonb)`は`security definer`で、`authenticated`と`service_role`だけが実行できる。テーブルへの直接更新権限は引き続き付与しない。
- 封筒・入力検証・冪等性のヘルパーは`private`スキーマに置き、後続の選果（S1-05）・ラベル（S1-08）RPCで再利用する。
  - 入力検証: `private.rpc_input_text / _uuid / _date / _weight / _positive_int`
  - 業務エラーはSQLSTATE `KW400`、競合は`KW409`で内部送出し、RPC入口だけが捕捉して封筒へ変換する。捕捉されない例外は全体をロールバックする（`unexpected`）。
  - 冪等性: `private.rpc_claim_idempotency`が業務処理前にキー行をinsertして先行請求し、同一キーの同時要求を直列化する。確定封筒は`private.rpc_store_idempotency`で保存する。認証エラーはキーを消費しない。

## 表示ID採番

- `private.display_id_counters`が接頭辞×年度ごとの最終番号を保持し、upsertの行ロックで採番を直列化する。番号は3桁以上のゼロ埋め（`受入-2028-001`）で、999超は桁を伸ばす。
- 採番は入力検証の後に行うため、検証失敗で番号を消費しない。
- seedや手動SQLで表示IDを直接発行した場合は、同じトランザクションで`display_id_counters`を同期させる（`supabase/seed.sql`の受入2027年の例を参照）。同期しないと後続のRPC採番が一意制約に衝突する。

## 検証

```bash
make db-start
make db-reset
supabase db lint --local --fail-on warning
make db-test
```

pgTAPは`supabase/tests/00030_receiving_rpc_test.sql`で正常登録、区分別の必須項目、権限境界、冪等再送・キー誤用、版競合、選果確定後の修正拒否、変更履歴の記録を検証する。

## 未決事項

- 選果タスクの自動生成はタスクテーブル導入時に契約とあわせて追加する。
- 選果確定後の受入訂正はO-01の決定後に別Issueで扱う。

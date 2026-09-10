# ラベル状態管理RPC運用

Issue #17（S1-08）のラベル印刷状態管理RPCを定義する。クライアント向けの契約は[label_mark_printed](../../contracts/rpc/label_mark_printed.md)・[label_mark_handwritten](../../contracts/rpc/label_mark_handwritten.md)・[label_reprint](../../contracts/rpc/label_reprint.md)が正本であり、本書は実装・運用の内部事項だけを扱う。PDF生成は[label-pdf Edge Function](../edge-functions/label-pdf.md)が担い、状態管理とは分離する。

## Function構成

- `public.label_mark_printed` / `label_mark_handwritten` / `label_reprint`はいずれも`security definer`で、`authenticated`と`service_role`だけが実行できる。
- 3操作は`private.label_rpc(function_name, req)`の単一実装を共有し、[受入RPC](receiving-rpc.md)の封筒・入力検証・冪等性ヘルパーを再利用する。操作差分は次のとおり。
  - `label_mark_printed`: `copies`（既定1、上限999）を加算。`printed_copies >= required_copies`で`printed`へ完了、未達は`partially_printed`。`not_printed` / `partially_printed`以外は`CONFLICT_STALE`。
  - `label_mark_handwritten`: `copies`不可。`handwritten`へ完了する。
  - `label_reprint`: `printed`のみ対象（それ以外は`LABEL_NOT_REPRINTABLE`）。`reason`必須、`reprint_count`加算、状態は`printed`のまま。
- ラベルジョブとコンテナを`FOR UPDATE`でロックし、完了時（`printed` / `handwritten`）にコンテナを`cold_storage`へ遷移して`version`を加算する。DBトリガー（ラベル完了必須・状態遷移）が最終防衛となる。
- `location_id`（冷蔵庫のみ）を任意で受け取り、完了時にコンテナへ設定する。

## PDF生成との分離

印刷状態の確定はRPC、PDF生成はEdge Functionと責務を分ける（ADR-0002）。生成の失敗・再試行はEdge Function側で完結し、`label_jobs`・`containers`へ副作用を残さない。手書きフォールバックは`label_mark_handwritten`で確定し、実行者・日時・イベントを記録する。

## 検証

```bash
make db-start
make db-reset
supabase db lint --local --fail-on warning
make db-test
```

pgTAPは`supabase/tests/00050_label_rpc_test.sql`で印刷完了・一部印刷・手書き・再印刷（理由必須）・二重完了の競合・冪等再送・キー誤用・操作別の入力制約・権限境界・イベント/履歴記録・コンテナ遷移を検証する。

## 未決事項

- 一部再印刷の単位は実機確認後に確定する（ADR-0002）。現状は`copies`を任意で受け取り、`required_copies`との比較で完了判定する。
- 追熟ラベル（S1-09）は別レイアウト・別コンテナ生成のため後続Issueで扱う。

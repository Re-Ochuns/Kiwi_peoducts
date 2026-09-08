# RPC契約: <function名>

- 状態: 草案 | 承認済み
- 版: 1
- 対象Issue: [#NN](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/NN)
- 関連要件: production-specの該当章へのリンク

[RPC共通契約](../rpc-contract-spec.md)を前提とし、本書は差分と操作固有の内容だけを定義する。

## 1. 概要

この操作が業務上何を確定するかを1〜3行で記述する。

## 2. Function

| 項目 | 内容 |
|---|---|
| Function名 | `<領域>_<操作>` |
| 種別 | PostgreSQL Function / Edge Function |
| 権限 | 認証済み利用者。追加の条件があれば記載 |

## 3. 要求

`input`のフィールドを定義する。

| フィールド | 型 | 必須 | 内容・制約 |
|---|---|---|---|
| example_id | uuid | 必須 | 対象の内部ID |

```json
{
  "req": {
    "meta": { "idempotency_key": "…", "correlation_id": "…" },
    "input": {}
  }
}
```

## 4. 応答

成功時の`data`を定義する。

| フィールド | 型 | 内容 |
|---|---|---|
| example_id | uuid | 確定した対象 |

```json
{
  "ok": true,
  "correlation_id": "…",
  "idempotent_replay": false,
  "data": {}
}
```

## 5. 業務エラー

共通コード（`VALIDATION_FAILED`など）は記載不要。操作固有のコードを定義する。

| code | 発生条件 | details |
|---|---|---|
| EXAMPLE_LIMIT_EXCEEDED | 発生する業務条件 | 含めるフィールド |

## 6. 競合条件

`CONFLICT_STALE`となる前提の崩れ方と、`details.current`へ含める内容を列挙する。楽観制御の前提値を`input`へ含める場合はここで定義する。

## 7. 冪等性

共通契約どおりの場合は「共通契約どおり」とだけ記す。キーの単位や再生範囲に特記事項があれば記載する。

## 8. 排他制御

ロック対象の行・順序と、検証する状態・数量を記載する。

## 9. 副作用

更新するテーブル、表示IDの採番、作業タスクの生成・完了、外部連携など、`data`に現れない効果をすべて列挙する。

## 10. 履歴

変更履歴（03_STATE_AND_DATA_MODEL.md 第7章）へ何を記録するかを記載する。

## 11. 例

正常系1件と、代表的な業務エラー・競合の要求・応答例を記載する。

## 変更履歴

| 版 | 日付 | 内容 | 承認 |
|---|---|---|---|
| 1 | YYYY-MM-DD | 初版作成 | フロント / バックエンド / DB・CI |

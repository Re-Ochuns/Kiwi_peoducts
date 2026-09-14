# RPC契約: order_update

> #109: 在庫選択から始める新方式の確定・更新・取消は[受注時予約の契約](order_inventory_reservation.md)に従う。以下の既存記述は移行前受注にも適用する。

- 状態: 実装済み
- 版: 1
- 対象Issue: #50

draftまたはconfirmedの受注を全項目更新する。
order_id、expected_version、reasonが必須。confirmedの変更では受注をdraftへ、
関連追熟計画をdraft・needs_review=trueへ戻す。
注文量を割当済み量未満には変更できない。
詳細は[共通仕様](customer_order_common.md)に従う。

配送先IDが同じ場合は既存スナップショットを保持し、明示的に別IDへ変更した場合のみ再生成する。
関連計画の変更前後も同じ理由・操作者・相関IDで履歴へ保存する。

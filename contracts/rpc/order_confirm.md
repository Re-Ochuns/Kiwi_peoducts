# RPC契約: order_confirm

> #109: 在庫選択から始める新方式の確定・更新・取消は[受注時予約の契約](order_inventory_reservation.md)に従う。以下の既存記述は移行前受注にも適用する。

- 状態: 実装済み
- 版: 1
- 対象Issue: #50

order_id、expected_version、reasonを受け取り、draftをconfirmedへ遷移させる。
顧客、配送先、品種、等級のactive状態を確定時に再検証する。
成功時はversionを1増やしてtransition履歴を記録する。
詳細は[共通仕様](customer_order_common.md)に従う。

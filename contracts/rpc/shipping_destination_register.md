# RPC契約: shipping_destination_register

- 状態: 実装済み
- 版: 1
- 対象Issue: #50

activeな顧客へ配送先を登録する。inputはcustomer_id、destination_name、
recipient_name、postal_code、addressが必須、reasonは任意。
同一顧客内の名称重複はSHIPPING_DESTINATION_DUPLICATE。
詳細は[共通仕様](customer_order_common.md)に従う。

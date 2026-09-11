# RPC契約: order_register

- 状態: 実装済み
- 版: 1
- 対象Issue: #50

受注をdraftで登録する。顧客、配送先、注文日、出荷予定日、品種、等級、注文量を
検証し、order_numberを「受注-年度-連番」で発行する。
配送先の名称、受取人、郵便番号、住所を登録時点のJSONへコピーする。
入力とエラーは[共通仕様](customer_order_common.md)に従う。

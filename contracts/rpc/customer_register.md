# RPC契約: customer_register

- 状態: 実装済み
- 版: 1
- 対象Issue: #50

activeなadministratorが顧客を登録する更新RPC。
共通封筒のinputにcustomer_code、name、postal_code、addressを必須、
nicknameとreasonを任意で指定する。成功dataは登録行で、versionは1。
customer_code重複はCUSTOMER_DUPLICATE。冪等性・履歴・権限は
[顧客・配送先・受注RPC共通仕様](customer_order_common.md)に従う。

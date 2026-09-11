# RPC契約: customer_update

- 状態: 実装済み
- 版: 1
- 対象Issue: #50

customer_id、expected_version、reasonと顧客の全業務項目を受け取る。
成功時はversionを1増やして変更履歴を記録する。古いversionはCONFLICT_STALE、
customer_code重複はCUSTOMER_DUPLICATE。
詳細は[共通仕様](customer_order_common.md)に従う。

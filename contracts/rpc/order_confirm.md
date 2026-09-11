# RPC契約: order_confirm

- 状態: 実装済み
- 版: 1
- 対象Issue: #50

order_id、expected_version、reasonを受け取り、draftをconfirmedへ遷移させる。
顧客、配送先、品種、等級のactive状態を確定時に再検証する。
成功時はversionを1増やしてtransition履歴を記録する。
詳細は[共通仕様](customer_order_common.md)に従う。

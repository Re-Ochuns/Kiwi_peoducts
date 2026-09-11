# RPC契約: shipping_destination_update

- 状態: 実装済み
- 版: 1
- 対象Issue: #50

shipping_destination_id、expected_version、reasonと配送先の全業務項目を受け取る。
customer_idは変更不可。成功時はversionを1増やす。
既存受注の配送先スナップショットは更新しない。
詳細は[共通仕様](customer_order_common.md)に従う。

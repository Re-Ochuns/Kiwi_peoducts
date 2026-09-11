# RPC契約: order_cancel

- 状態: 実装済み
- 版: 1
- 対象Issue: #50

order_id、expected_version、reasonを受け取り、draftまたはconfirmedをcancelledへ遷移する。
関連する作業前の追熟計画をdraft・needs_review=trueへ戻し、
当該受注の追熟割当を削除して対応重量の在庫予約を解除する。
作業開始済みの追熟計画がある場合はCONFLICT_STALE。
成功時はversionを1増やしてtransition履歴を記録する。
詳細は[共通仕様](customer_order_common.md)に従う。

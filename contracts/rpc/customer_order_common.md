# 顧客・配送先・受注RPC共通仕様

- 状態: 実装済み
- 版: 1
- 対象Issue: [#50](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/50)

更新Functionは[RPC共通契約](../rpc-contract-spec.md)の封筒、UUID v4、冪等性、
相関ID、エラー分類に従う。更新はactiveなadministratorだけが実行でき、
authenticatedから対象テーブルを直接更新することはできない。

## 公開Function

| Function | 用途 |
|---|---|
| customer_register / customer_update | 顧客登録・全項目更新 |
| shipping_destination_register / shipping_destination_update | 配送先登録・全項目更新 |
| order_register / order_update | 下書き受注登録・全項目更新 |
| order_confirm / order_cancel | 受注確定・作業開始前キャンセル |
| customer_list / customer_get | 顧客一覧・配送先を含む詳細 |
| shipping_destination_list | 顧客別配送先一覧 |
| order_list / order_get | 不足量を含む受注一覧・割当を含む詳細 |

参照Functionは共通更新封筒を使わず、security invokerとRLSで保護する。
anonは実行不可、pending利用者は0件またはnull、active利用者は参照できる。

## 顧客・配送先

顧客はcustomer_code、name、nickname（任意）、postal_code、addressを持つ。
配送先はcustomer_id、destination_name、recipient_name、postal_code、addressを持ち、
同一顧客へ複数登録できる。customer_code、および同一顧客内のdestination_nameは重複不可。
更新は全項目、expected_version、reasonが必須で、顧客のversionと配送先のversionを
楽観制御に用いる。配送先のcustomer_idは変更できない。

## 受注

order_registerのinput:

| フィールド | 必須 | 制約 |
|---|---|---|
| customer_id / shipping_destination_id | 必須 | activeで同一顧客に属する |
| ordered_date | 必須 | YYYY-MM-DD |
| scheduled_ship_date | 必須 | 注文日以降 |
| variety_id / grade_id | 必須 | active |
| ordered_weight_kg | 必須 | 0より大きく0.01kg単位 |
| notes / reason | 任意 | 自由入力、reason既定値は受注下書き登録 |

order_numberはサーバーが「受注-年度-連番」で発行する。登録時statusはdraft、
versionは1である。配送先名、受取人名、郵便番号、住所は
shipping_destination_snapshotへコピーされ、配送先の後日更新では変化しない。

order_updateは上記業務項目にorder_id、expected_version、reasonを加えた全項目更新。
draftまたはconfirmedだけ変更できる。confirmedを変更するとorderをdraftへ戻し、
関連するdraft/confirmedの追熟計画をdraft・needs_review=trueへ更新する。
注文量を既存allocated_weight_kg未満にはできない。

order_confirmはorder_id、expected_version、reasonを受け取り、
draftをconfirmedへ遷移させる。参照中の顧客、配送先、品種、等級がactiveであることを再検証する。

order_cancelはorder_id、expected_version、reasonを受け取り、draftまたはconfirmedを
cancelledへ遷移させる。関連追熟計画はdraft・needs_review=trueへ戻し、
当該受注の追熟割当を削除して対応重量の作業前在庫予約を解除する。
作業開始済みの追熟計画がある場合はCONFLICT_STALEとする。

## 成功data

更新対象行をJSONで返す。order_update/order_cancelはaffected_plan_countも返す。
order_listはordered_weight_kg - allocated_weight_kgをshortage_weight_kgとして返す。

## エラー

| code | 内容 |
|---|---|
| VALIDATION_FAILED | 必須、型、日付、重量、参照、未知フィールドの不正 |
| CUSTOMER_DUPLICATE | customer_code重複 |
| SHIPPING_DESTINATION_DUPLICATE | 顧客内destination_name重複 |
| ORDER_REFERENCE_INACTIVE | 確定時の参照先が無効 |
| ORDER_WEIGHT_BELOW_ALLOCATED | 注文量が割当済み量未満 |
| CONFLICT_STALE | versionまたは状態が古い、作業開始後キャンセル |
| IDEMPOTENCY_KEY_REUSED | 同一キーを異なる入力で再利用 |

## 履歴と個人情報

更新成功時はchange_historyへcreate/update/transitionを記録する。
サーバーログにはFunction名、利用者ID、相関ID、冪等性キー、エラーコードだけを記録し、
顧客名、住所、自由入力を含めない。

## 検証

pgTAPで権限、複数配送先、楽観制御、冪等再送、日付・重量、
配送先スナップショット、状態遷移、関連計画の再確認、キャンセル、履歴、参照RLSを検証する。

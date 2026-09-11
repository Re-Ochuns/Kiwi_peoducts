# 10. Issueバックログ

## 1. 発行方針

M0とM1の検証後、確定した要件を反映してM2とM3を発行する。各段階の実装開始前に依存Issueと未解決事項を再確認する。

## 2. M0 基盤・技術検証

| ID | 担当 | Issue | 依存 |
|---|---|---|---|
| FND-01 | 共通 | システム構成と担当境界をADRとして確定する | なし |
| FND-02 | DB・CI | Flutterプロジェクトとモノレポ構成を初期化する | FND-01 |
| FND-03 | バックエンド | RPC契約・エラー・冪等性の共通形式を定義する | FND-01 |
| FND-04 | フロント | Flutterアプリシェルとレスポンシブ基盤を構築する | FND-02 |
| FND-05 | DB・CI | Google認証・プロフィール・基本RLSを構築する | FND-02、FND-03 |
| FND-06 | フロント | Googleログイン画面と認証後ルーティングを実装する | FND-04、FND-05 |
| FND-07 | 共通 | 日本語A5ラベルPDFと実機印刷を検証する | FND-02 |
| FND-08 | DB・CI | Flutter・SupabaseのCI/CDを構築する | FND-02 |

## 3. M1 受入・選果・在庫・ラベル

| ID | 担当 | Issue | 依存 |
|---|---|---|---|
| S1-01 | DB・CI | 段階1のDBスキーマ・制約・RLSを作成する | FND-03、FND-05 |
| S1-02 | フロント | マスター管理画面を実装する | S1-01、FND-04 |
| S1-03 | バックエンド | 受入登録・履歴付き修正RPCを実装する | S1-01 |
| S1-04 | フロント | 収穫・仕入れ登録画面を実装する | FND-04、S1-03 |
| S1-05 | バックエンド | 選果確定・コンテナ生成RPCを実装する | S1-01、FND-03 |
| S1-06 | フロント | 選果対象・選果入力画面を実装する | S1-05 |
| S1-07 | フロント | 在庫一覧・詳細・履歴画面を実装する | S1-01、S1-05 |
| S1-08 | バックエンド | ラベルPDF生成・印刷状態管理を実装する | FND-07、S1-05 |
| S1-09 | フロント | ラベル確認・印刷・手書き対応画面を実装する | S1-08 |
| S1-10 | 共通 | 在庫・マスター・変更履歴のCSV出力を実装する | S1-01、S1-02、S1-07 |
| S1-11 | 共通 | 段階1の統合テストと現場リハーサルを実施する | S1-02〜S1-10 |

## 4. M2 受注・追熟計画・予約・ToDo

| ID | 担当 | Issue | 依存 |
|---|---|---|---|
| S2-00 | 共通 | [#54 S2・S3要件書とIssueバックログを更新する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/54) | S1完了判断 |
| S2-01 | DB・CI | [#52 顧客・受注・追熟計画・割当・予約・作業タスクのDB基盤を作成する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/52) | S2-00、S1-01 |
| S2-02 | バックエンド | [#50 顧客・配送先・受注登録と状態遷移RPCを実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/50) | S2-01 |
| S2-03 | フロント | [#51 顧客・配送先・受注の管理画面を実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/51) | S2-02、FND-04 |
| S2-04 | バックエンド | [#53 追熟計画・複数内訳・部分予約RPCを実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/53) | S2-01、S2-02、S1-07 |
| S2-05 | フロント | [#55 作業者・管理者向け追熟計画作成画面を実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/55) | S2-04、S1-07 |
| S2-06 | バックエンド | [#57 作業タスク生成とGoogleカレンダー同期を実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/57) | S2-04、O-13 |
| S2-07 | フロント | [#56 スマホToDo・期限超過・作業リンク画面を実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/56) | S2-05、S2-06 |
| S2-08 | フロント | [#58 PC予定・警告・予約不足画面を実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/58) | S2-02、S2-04、S2-06 |
| S2-09 | 共通 | [#59 S2の統合テストと現場リハーサルを実施する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/59) | S2-01〜S2-08 |

## 5. M3 追熟実績・出荷・期限

| ID | 担当 | Issue | 依存 |
|---|---|---|---|
| S3-01 | DB・CI | [#60 追熟実績・出荷・在庫イベント・期限管理のDB基盤を作成する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/60) | S2-01、S2-04 |
| S3-02 | バックエンド | [#62 エチレン注入・抜き確認・寝かせ・追熟確認RPCを実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/62) | S3-01、S2-04 |
| S3-03 | フロント | [#61 作業者向け追熟作業画面を実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/61) | S3-02、S2-07 |
| S3-04 | バックエンド | [#63 追熟予定計算・確認期限・自動期限切れを実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/63) | S3-01、S3-02、追熟マスター |
| S3-05 | バックエンド | [#64 部分出荷・在庫減算・出荷取消RPCを実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/64) | S3-01、S2-02、S2-04 |
| S3-06 | フロント | [#69 出荷対象・部分出荷・出荷取消画面を実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/69) | S3-05、S2-03 |
| S3-07 | フロント | [#67 PC工程ボードとコンテナ詳細・工程操作を実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/67) | S1-07、S2-04、S3-02、S3-05 |
| S3-08 | バックエンド | [#65 追熟開始時のラベル生成・印刷状態管理を拡張する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/65) | S1-08、S1-09、S3-02 |
| S3-09 | 共通 | [#66 受注・追熟・出荷CSVを実装する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/66) | S1-10-IMP、S2-02、S2-04、S3-05 |
| S3-10 | 共通 | [#68 S3の統合テストと現場リハーサルを実施する](https://github.com/Re-Ochuns/Kiwi_peoducts/issues/68) | S3-01〜S3-09 |

## 6. M4 本番移行・安定化

M4ではセキュリティ、バックアップ、性能、教育、本番移行、現場リハーサルを扱う。M4 IssueはS3の現場検証と未決事項の解消後に発行する。

## 7. 共通受け入れ条件

- 関連仕様書と契約へのリンクがある。
- 対象範囲と対象外が明確である。
- 依存Issueが設定されている。
- 正常系、業務エラー、通信エラーの確認方法がある。
- 必要なUnit、Widget、Integration、pgTAPテストを指定する。
- UIは360px、390px、430px、PCの必要な範囲を確認する。
- DB更新はRLS、トランザクション、履歴、冪等性の必要性を確認する。
- Stagingでの確認方法が記載されている。

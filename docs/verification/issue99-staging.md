# Issue #99 Staging検証記録

状態: **準備中。実環境未作成・未デプロイ。Issueは未完了。**

## 調査（2026-09-14）

- ソース基点: develop 7f184e1（PR #98を含む）
- GitHub Environment: 初期調査時0件。stagingを作成済み、developだけを許可。
- develop branch protection: APIはプラン制約で403。保護設定済みとは判定していない。
- Environment required reviewer: 未設定。手動実行者がStagingの配備責任者。
- GitHub Variables / Secrets: 初期調査時未設定。
- Staging Deploymentの実行履歴: 初期調査時なし。
- Firebase / Supabaseプロジェクト: ユーザー確認により未作成。
- 管理アカウント: Googleのみ用意済み。Supabase登録が必要。
- 費用方針: 無料枠優先。課金有効化・有料契約は実施していない。
- ブラウザ操作: 実行環境の初期化エラーにより接続不可。クラウド登録・設定は未実施。
- 既存作業用DB/Docker: 変更なし。

## 環境と実測結果（実施後に記入）

| 項目 | 結果 |
| --- | --- |
| Google/Firebase所有者・プロジェクトID・Spark確認 | 未実施 |
| Supabase所有者・Free組織・project ref・region | 未実施 |
| 公開HTTPS URL | 未確定 |
| Google OAuth / Site URL / Redirect URLs | 未設定 |
| GitHub Variables / Secrets（値は記載しない） | 未設定 |
| Edge Secrets / Vault / cron / 共有カレンダー | 未設定 |
| 配備SHA / Actions run URL / Hosting release ID | 未実施 |
| PC直接URL・再読込 | 未実施 |
| スマートフォン直接URL・再読込 | 未実施 |
| Googleログイン / active / pending / disabled / anonymous | 未実施 |
| ダミー業務データの登録・参照・更新 | 未実施 |
| A5 PDF / CSV / カレンダー正常同期 | 未実施 |
| 外部連携失敗の追跡・再試行 | 未実施 |
| 同一SHA再配備 | 未実施 |
| 直前Hosting releaseへのrollback・旧SHA確認 | 未実施 |
| rollback後の再配備 | 未実施 |
| Frontend / Backend影響レビュー | 未実施 |
| 本番向け後続Issue | 未作成 |

実機検証には端末・OS・ブラウザ・実施日時・期待値・実結果を記録する。
Secret、実アカウントのメール、顧客情報をこのファイルへ記載しない。

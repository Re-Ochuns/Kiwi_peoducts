# Issue #99 Staging検証記録

状態: **準備中。初回公開済み・受入検証中。Issueは未完了。**

## 調査（2026-09-14）

- ソース基点: develop 7f184e1（PR #98を含む）
- GitHub Environment: 初期調査時0件。stagingを作成済み、developだけを許可。
- develop branch protection: APIはプラン制約で403。保護設定済みとは判定していない。
- Environment required reviewer: 未設定。手動実行者がStagingの配備責任者。
- GitHub Variables / Secrets: 初期調査時未設定。
- Staging Deploymentの実行履歴: 初期調査時なし。
- Firebase / Supabaseプロジェクト: ユーザーが作成済み（下表）。
- 管理アカウント: Google・Supabaseともユーザーが登録済み。
- 費用方針: 無料枠優先。課金有効化・有料契約は実施していない。
- ブラウザ操作: 実行環境の初期化エラーにより接続不可。クラウド画面の設定はユーザーが実施。
- 既存作業用DB/Docker: 変更なし。

## 環境と実測結果（実施後に記入）

| 項目 | 結果 |
| --- | --- |
| Google/Firebase所有者・プロジェクトID・Spark確認 | 未実施 |
| Supabase所有者・Free組織・project ref・region | 未実施 |
| 公開HTTPS URL | https://kiwi-staging-603b3.web.app （初回公開済み） |
| Google OAuth / Site URL / Redirect URLs | ユーザー設定完了報告。公開Auth settings APIでgoogle=trueを確認。URL設定値・実ログインは未検証 |
| GitHub Variables / Secrets（値は記載しない） | Variables 4件・Secrets 3件の登録名を確認。Secret値の妥当性は配備前検査で確認予定 |
| Edge Secrets / Vault / cron / 共有カレンダー | Edge Secrets・共有カレンダーはユーザー設定完了報告。登録名・値・権限は未検証。Vault・cronは配備後に設定・確認 |
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

## 設定進捗（2026-09-14）

- Firebase project ID: `kiwi-staging-603b3`
- Supabase project ref: `mhxtmqhavytcklszbvtk`
- Supabase URL: https://mhxtmqhavytcklszbvtk.supabase.co
- Variables: FIREBASE_PROJECT_ID、SUPABASE_PROJECT_REF、SUPABASE_URL、SUPABASE_PUBLISHABLE_KEY
- Secrets: FIREBASE_SERVICE_ACCOUNT_STAGING、SUPABASE_ACCESS_TOKEN、SUPABASE_DB_PASSWORD
- 所有者・リージョン・料金プランは管理画面による確認が残る。
- Google Providerの有効状態の確認は、OAuth往復・利用承認境界の検証を代替しない。

## 初回配備（2026-09-14）

- PR #100をレビュー・マージ済み。事前検査10件とPR CI全5項目が成功。
- 配備SHA: `4581fdc7c122118363d28f21523afe27d74d98e4`。developのFlutter・Database CI成功を確認。
- Actions: https://github.com/Re-Ochuns/Kiwi_peoducts/actions/runs/34793326501
- DB migration・Edge Functions 2本・Firebase Hostingの配備成功。
- 公開ビルドID一致、ルートとSPA直接URLのHTTP 200を確認。ブラウザ描画は未検証。
- calendar-syncとprofilesの未認証リクエストは401。
- 最終検査はPDFの必須container_id不足により400となり失敗。検査へ有効形式のダミーIDを追加する。
- Vault設定、Google実ログイン、実カレンダー同期、実機受入は未完了。

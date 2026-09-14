# 段階3 実行・現場リハーサル記録

## 実施情報

| 項目 | 記録 |
|---|---|
| 対象Issue | #68 |
| Staging対象SHA | `576cce74ceb3c93c92821bb14c79bd7c79d23d1d`（PR #104反映済み） |
| ローカル確認基点SHA | `2cbca7a802a96297258f1871c94c62f22a071b21`（PR #102＋最新develop） |
| Staging | `https://kiwi-staging-603b3.web.app` |
| 実施日 | 2026-09-14 |
| 実施者 | Codex（読み取り専用ブラウザ確認） |
| 実機・現場確認者 | 未実施 |

## 先行確認

| 項目 | 期待結果 | 実測 | 状態 |
|---|---|---|---|
| Stagingトップ | Flutterアプリが描画される | 「おおくま農園」「ログイン」「Googleでログイン」を表示 | Pass |
| 未認証の作業URL | 業務データを表示しない | ダミーUUIDの`/work-tasks/{id}`を直接開き、ログイン画面を表示 | Pass |
| 公開境界スモーク | Hosting、SPA、未認証APIを安全に確認 | staging Environmentの公開キーを使い、対象SHAで再実行してPass | Pass |
| 固定ツール検査 | Flutter 3.47.2、Dart 3.13.2、Node.js 24.19.0、Supabase CLI 2.117.0 | Flutter・Dartは一致。Node.jsが26.5.0のため停止 | Blocked |
| Flutter format・analyze | 差分・解析エラーなし | 103ファイル変更なし、解析エラーなし | Pass |
| Flutter非Goldenテスト | 既存機能とS3画面の回帰なし | 最新develop追従後に282件成功 | Pass |
| Web release build | ビルド成功 | 成功 | Pass |
| Linux Golden | Ubuntu正本と一致 | PR #102のFlutter CIで成功 | Pass |
| DB lint・pgTAP | migration・RLS・RPC・競合が成功 | PR #102のDatabase CIで成功 | Pass |
| Edge Functions | 型検査・自動テスト成功 | 対象SHAのStaging配備で型検査・テスト成功 | Pass |
| Google OAuth往復 | 登録済みGoogleアカウントでログイン | アカウント操作を伴うため未実施 | Not Run |
| S3業務E2E | 計画から出荷・取消まで成立 | 検証用ログインとダミーデータ操作が必要 | Not Run |
| 実機・印刷・現場 | 現物と表示・ラベル・重量が一致 | 実施者と設備が必要 | Not Run |

トップ画面と作業URLはブラウザのアクセシビリティツリーでも文字ラベルを確認した。
ログインボタンは押しておらず、Googleアカウント情報や業務データを変更していない。

CI証跡:

- [PR #102 Flutter CI](https://github.com/Re-Ochuns/Kiwi_peoducts/actions/runs/34803394423)
- [PR #102 Database CI](https://github.com/Re-Ochuns/Kiwi_peoducts/actions/runs/34803394302)
- [対象SHAのStaging配備](https://github.com/Re-Ochuns/Kiwi_peoducts/actions/runs/34794046119)
- [PR #104 修正配備](https://github.com/Re-Ochuns/Kiwi_peoducts/actions/runs/34819180995)

## PR #104反映後の再確認

手動検証で報告された管理メニュー遷移と在庫一覧取得の不具合は、Issue #103・PR #104で修正され、
`develop`とStagingへ反映された。PR #102へ最新`develop`を競合なく取り込み、次を再確認した。

| 項目 | 実測 | 状態 |
|---|---|---|
| 在庫クエリ回帰 | 取得・件数・検索・状態・ソート・ページングの4件が成功 | Pass |
| 管理画面遷移回帰 | 全管理メニュー間の遷移とホーム復帰の1件が成功 | Pass |
| Flutter format | 103ファイル、変更0件 | Pass |
| Flutter analyze | 問題なし | Pass |
| Flutter非Goldenテスト | 282件成功 | Pass |
| Web release build | 成功 | Pass |
| Stagingトップ | 「おおくま農園」「ログイン」「Googleでログイン」を再表示 | Pass |
| 未認証の作業URL | ダミーUUIDの`/work-tasks/{id}`で業務データを表示せずログイン画面を再表示 | Pass |
| Googleログイン後の修正確認 | アカウント操作が必要 | Not Run |

PR #104のStaging配備Actionは配備直後のスモークが失敗したが、同一SHAの後続手動スモークは成功している。
Action全体を成功扱いにはせず、ログイン後の画面確認を残す。

## シナリオ記録欄

| ID | 端末・ブラウザ | 実施者・日時 | 期待結果 | 実測・証跡 | 状態 |
|---|---|---|---|---|---|
| S3-E2E-01〜09 | 未記入 | | `stage3-e2e-plan.md`参照 | | Not Run |
| S3-RES-01〜02 | 未記入 | | 同上 | | Not Run |
| S3-CON-01〜02 | 未記入 | | 同上 | | Not Run |
| S3-AUTH-01 | Stagingブラウザ | Codex・2026-09-14 | 未認証時に業務データを表示しない | ログイン画面を表示 | Pass |
| S3-AUTH-02 | 未記入 | | pending・disabled・権限不足を拒否 | | Not Run |
| S3-PERF-01〜03 | 未記入 | | `stage3-e2e-plan.md`参照 | | Not Run |

## 発見事項

手動検証で発見された2件はPR #104で修正済み。ログイン後のStaging確認は未実施のため、修正確認完了とは扱わない。
未実施は合格ではなく、次の作業を妨げる環境・権限・設備を明記して継続する。

| 分類 | 内容 | 次の対応 |
|---|---|---|
| 確認待ち | Google OAuthと検証用active/pending/disabledアカウント | アカウント所有者の許可を得て画面確認 |
| 修正確認待ち | 管理メニュー遷移と在庫一覧取得 | PR #104配備済み。Googleログイン後にStagingで再確認 |
| 確認待ち | S3ダミーデータによる業務E2E | 検証環境とデータを特定して実行 |
| 環境差異 | ローカルNode.js 26.5.0（必須24.19.0） | Node.js 24.19.0の環境またはCIで受入コマンドを再実行 |
| 環境差異 | Docker・Podman・Denoなし | CIで自動確認を補完済み。ローカル実APIは対応端末で再実行 |
| 現場作業 | 実機、複数端末、A5印刷、手書き復旧 | 現場確認者が端末・プリンターと実測を記録 |
| 性能試験 | 20,000件・10セッション | 専用ダミーデータ環境で測定 |

# 段階3 実行・現場リハーサル記録

## 実施情報

| 項目 | 記録 |
|---|---|
| 対象Issue | #68 |
| 対象SHA | `a3fbf34800bd9d8dbba545eb1807fed102f46527` |
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
| Flutter format・analyze | 差分・解析エラーなし | 101ファイル変更なし、解析エラーなし | Pass |
| Flutter非Goldenテスト | 既存機能とS3画面の回帰なし | 277件成功 | Pass |
| Web release build | ビルド成功 | 成功 | Pass |
| Linux Golden | Ubuntu正本と一致 | macOSのため未実施。PRのFlutter CIで確認する | Not Run |
| DB lint・pgTAP | migration・RLS・RPC・競合が成功 | Docker・Podmanがないため未実施 | Not Run |
| Edge Functions | 型検査・自動テスト成功 | Denoがないため未実施 | Not Run |
| Google OAuth往復 | 登録済みGoogleアカウントでログイン | アカウント操作を伴うため未実施 | Not Run |
| S3業務E2E | 計画から出荷・取消まで成立 | 検証用ログインとダミーデータ操作が必要 | Not Run |
| 実機・印刷・現場 | 現物と表示・ラベル・重量が一致 | 実施者と設備が必要 | Not Run |

トップ画面と作業URLはブラウザのアクセシビリティツリーでも文字ラベルを確認した。
ログインボタンは押しておらず、Googleアカウント情報や業務データを変更していない。

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

現時点でアプリ不具合と判断できる事象はない。未実施は合格ではなく、次の作業を妨げる環境・権限・設備を明記して継続する。

| 分類 | 内容 | 次の対応 |
|---|---|---|
| 確認待ち | Google OAuthと検証用active/pending/disabledアカウント | アカウント所有者の許可を得て画面確認 |
| 確認待ち | S3ダミーデータによる業務E2E | 検証環境とデータを特定して実行 |
| 環境差異 | ローカルNode.js 26.5.0（必須24.19.0） | Node.js 24.19.0の環境またはCIで受入コマンドを再実行 |
| 環境差異 | Docker・Podman・Denoなし | Database CIとEdge Functions CIで補完し、ローカル実APIは対応端末で再実行 |
| 現場作業 | 実機、複数端末、A5印刷、手書き復旧 | 現場確認者が端末・プリンターと実測を記録 |
| 性能試験 | 20,000件・10セッション | 専用ダミーデータ環境で測定 |

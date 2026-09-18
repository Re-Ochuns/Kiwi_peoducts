# キウイ在庫管理システム 本番要件

## 文書の目的

本ディレクトリは、中間発表用MOCKを実業務で利用できるシステムへ発展させるための要件一式である。2026年9月時点のヒアリング結果を基に、確定事項、段階的な実装範囲、未解決事項を分離して記載する。

## 前提

- 対象農園：おおくま農園
- 主利用者：作業者、管理者
- 作業者の主端末：個人スマートフォン
- 管理者の主端末：PC
- 在庫基準単位：kg（0.01kg単位）
- アプリはGoogleアカウントを求めず、初回起動時に匿名セッションを自動作成する
- 公開URLから利用できる環境に実在する顧客の個人情報を登録しない
- 対象期間：収穫・仕入れから出荷による在庫減算まで
- 正式用語：キウイを出荷可能な状態へ進める工程は「追熟」と表記し、旧称の「成熟」は使用しない
- 作業者向けスマートフォン画面からも追熟計画を作成できる
- 作業者画面には固定の下部タブを設けず、ホームの作業ボタンから各工程へ遷移する
- 管理者向けPC画面に、選果済み、追熟、寝かせ、出荷可能を一覧する工程ボードを設ける

## 文書一覧

| 文書 | 内容 |
|---|---|
| [01_BUSINESS_REQUIREMENTS.md](01_BUSINESS_REQUIREMENTS.md) | 業務目的、利用者、業務フロー、業務ルール |
| [02_MOCK_GAP_ANALYSIS.md](02_MOCK_GAP_ANALYSIS.md) | 現行MOCKと本番要件の差分 |
| [03_STATE_AND_DATA_MODEL.md](03_STATE_AND_DATA_MODEL.md) | 状態、タスク、主要データ、ID、重量整合性 |
| [04_RELEASE_PLAN.md](04_RELEASE_PLAN.md) | 3段階の構築計画と受け入れ条件 |
| [05_OPEN_QUESTIONS.md](05_OPEN_QUESTIONS.md) | 未解決事項と現場確認項目 |
| [06_SCREEN_REQUIREMENTS.md](06_SCREEN_REQUIREMENTS.md) | スマホ・PCの画面一覧と表示要件 |
| [07_NON_FUNCTIONAL_SECURITY.md](07_NON_FUNCTIONAL_SECURITY.md) | セキュリティ、性能、バックアップ、外部連携 |
| [08_DESIGN_REQUIREMENTS.md](08_DESIGN_REQUIREMENTS.md) | スマホ・PCの情報設計、表示、操作、レスポンシブ、受け入れ基準 |
| [09_DEVELOPMENT_WORKFLOW.md](09_DEVELOPMENT_WORKFLOW.md) | 共同開発、Issue・PR、UI変更、レビュー運用 |
| [10_ISSUE_BACKLOG.md](10_ISSUE_BACKLOG.md) | GitHubへ発行するIssue、依存関係、マイルストーン |

システム構成と技術判断は [Architecture Decision Records](../docs/adr/README.md) に記録する。業務要件とADRが矛盾する場合は、本ディレクトリの要件を優先し、変更Issueで解消する。

既存のMOCK仕様は [../MOCK_SPEC.md](../MOCK_SPEC.md) を参照する。本番要件と矛盾する場合は、本ディレクトリの文書を優先する。

## 構築順序

1. 収穫・仕入れ、選果、在庫、ラベル
2. 顧客・受注、追熟計画、予約、ToDo、Googleカレンダー
3. 追熟実績、出荷、期限管理、工程ボード

## 要件の扱い

- 「確定」はヒアリングで合意した内容を示す。
- 「暫定」は初期値または仮の運用を示す。
- 「未解決」は実装前に現場確認が必要な内容を示す。
- 未解決事項を推測で確定しない。

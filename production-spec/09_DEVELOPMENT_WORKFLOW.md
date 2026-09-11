# 09. 共同開発・Issue運用

## 1. 基本方針

- `production-spec`を業務・画面要件の正本とする。
- GitHub Issueを作業と変更要求の正本とし、Issueのない実装を行わない。
- 一つのIssueは、原則として一つの担当領域と一つのPull Requestに対応させる。
- LocalとProductionを分離し、実在する顧客情報をLocalへ投入しない。Stagingを用意する場合も分離し、実在する顧客情報を投入しない。
- 現時点ではStagingを必須とせず、Issueの受入確認はローカル検証とCIで行う。
- 整合性が必要な確定操作は、Flutterからの複数更新ではなくDatabase Functionへ集約する。

## 2. 担当領域

### フロント設計者

- Flutterアプリ、画面、ViewModel、Repositoryインターフェース
- スマホ作業モード、PC管理モード、レスポンシブ表示
- デザインシステム、入力検証、エラー表示
- Unit、Widget、画面Integration Test
- PDFの表示、ダウンロード、印刷操作

ViewとViewModelからSupabaseを直接呼ばず、Repositoryを経由する。

### バックエンド設計者

- RPC契約、業務エラー、冪等性
- Database Function、トランザクション、排他制御
- 在庫イベント、変更履歴、表示ID採番
- Edge Functions、A5 PDF、Googleカレンダー同期と再試行
- バックエンド結合テスト

Database FunctionのSQLはバックエンド設計者が作成し、DB・CI設計者がレビューする。

### DB・CI設計者

- PostgreSQLテーブル、外部キー、制約、インデックス
- RLS、認証、最小権限
- マイグレーション、シード、pgTAP
- Local、Staging、Production環境
- GitHub Actions、Firebase Hosting、Supabaseデプロイ
- バックアップ、復旧、監視、秘密情報管理

マージ済みマイグレーションは変更せず、修正用マイグレーションを追加する。

## 3. ディレクトリ所有

```text
apps/kiwi_inventory/     フロント設計者
supabase/functions/      バックエンド設計者
supabase/migrations/     DB・CI設計者が管理
supabase/tests/          バックエンド、DB・CI共同
contracts/               3担当共同
production-spec/         要件の正本
.github/workflows/       DB・CI設計者
```

`contracts`、Database Function、RLS、CIの変更には複数担当のレビューを要求する。

## 4. Issue

Issue本文には背景・目的、実装範囲、対象外、依存Issue、入出力または画面状態、受け入れ条件、必須テスト、参照仕様書、担当領域、レビュー担当を記載する。

```text
Backlog → Ready → In Progress → Pull Request → Local Verification → Done
```

- `Ready`へ移す前に受け入れ条件と依存Issueを確定する。
- 作業開始時に担当者を設定し、ブランチとPull RequestからIssueをリンクする。
- ローカル検証とCIの成功を記録する前にIssueを完了しない。
- ブロック理由はコメントへ残し、`blocked`ラベルを付ける。

## 5. ブランチとPull Request

- `develop`と`main`への直接pushを禁止する。
- 担当と目的が分かる短期ブランチを使う。
- 一つのPull Requestへ無関係な変更を含めない。
- Draft Pull Requestを早期に作り、契約差異を発見する。
- Squash mergeを基本とする。
- DB変更はマイグレーション、RLS、テストを同じPull Requestへ含める。
- 仕様変更を伴う場合は`production-spec`も同じPull Requestで更新する。

## 6. RPC契約

並行開発前に`contracts`へFunction名、権限、リクエスト、レスポンス、業務エラー、冪等性、排他制御、副作用、履歴を記載する。フロントは契約に基づくFake Repositoryを先行実装できる。契約変更は3担当の承認を必要とする。

## 7. UI変更

変更要求は発生時点でIssueへ登録し、実装への取り込みは原則としてSprint計画時に判断する。

| レベル | 内容 | 扱い |
|---|---|---|
| L1 | 余白、文字、色、既存部品内の配置 | マージ前なら元Issue内で対応可能 |
| L2 | 一画面の入力順、カード構成、ボタン位置 | UI変更Issueを作成して判断 |
| L3 | ナビゲーション、共通フォーム、モーダル、デザイン体系 | 次Sprint候補。3担当で影響確認 |
| L4 | 入力項目、確定手順、状態、業務ルール | 要件変更として全担当で承認 |

- 実装開始前：元Issueの受け入れ条件と画面要件を更新できる。
- 実装中：L1以外は変更Issueを作り、元Issueとの依存関係を設定する。
- Pull Requestレビュー中：軽微修正だけを現在のPRへ含める。
- ローカル受入確認後：当初仕様の未達は不具合、改善要求は新しいIssueとする。
- 本番後：操作不能、誤操作、情報漏えい以外は次Sprintへ入れる。

UI変更Issueには変更理由、対象画面、現在の状態、変更内容、対象外、各担当への影響、確認画面幅、受け入れ条件を記載する。

L1はフロント担当者間、L2はフロント設計者と現場・要件担当、L3とL4は3担当と要件責任者が承認する。

## 8. CIとテスト

Pull Requestごとに次を実行する。

```text
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release
supabase db reset
supabase test db
```

- ViewModelと計算処理：Unit Test
- 共通部品と画面状態：Widget Test
- 主要業務フロー：Integration Test
- 制約、Function、RLS：pgTAP
- UI：360px、390px、430px、PCで確認

### ローカル受入確認

- 対象コミット、環境・ツールバージョン、確認者、実行手順、期待結果・実測結果、CIへのリンクをIssueへ記録する。
- 対象機能に応じて、ローカルのアプリとSupabaseを接続し、正常系・業務エラー・権限拒否・再送・競合とデータ整合性を確認する。RPCのみのIssueはローカルAPI経由で確認できる。
- 自動テストの成功だけで業務フローの受入確認を代替しない。実機・現場・印刷確認、担当者レビューなどの既存条件は維持する。
- 実環境固有の認証・接続・デプロイなどローカルで未検証の項目と残存リスクをIssueに記録する。本番反映前には対象環境で別途確認し、ローカル検証を本番稼働の承認とみなさない。
- この方針変更によってClose済みIssueの検証記録を書き換えたり、未実施の確認を完了扱いにしたりしない。


## 9. 完了条件

- Issueの受け入れ条件をすべて満たす。
- 読み込み、空、成功、業務エラー、通信エラーを扱う。
- 必要な自動テストを追加している。
- RLSの許可と拒否を確認している。
- 同時実行と二重送信を確認している。
- ローカル受入確認と必要なCIが成功し、結果と未検証事項がIssueに記録されている。
- 必要な操作履歴が残る。
- 仕様または契約変更が文書へ反映されている。
- 必要な担当者のレビューを得ている。

## 10. 定例

- Sprint開始：Ready Issue、契約、依存関係、担当を確定する。
- 毎日：進捗、ブロッカー、契約変更の有無を短時間で確認する。
- 週2回：ローカルのアプリとバックエンドを接続して縦方向の統合を確認する。
- Sprint終了：業務フローでデモし、未達と改善要求を分離してIssue化する。

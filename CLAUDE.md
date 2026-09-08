# CLAUDE.md

おおくま農園向けキウイ在庫管理システム。業務・画面要件の正本は`production-spec/`、開発運用の詳細は[09. 共同開発・Issue運用](production-spec/09_DEVELOPMENT_WORKFLOW.md)を参照する。

## Pull Request

- 本文は[.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md)の構成に従う。`gh pr create`で本文を直接指定する場合も同じ構成にする。
- 冒頭に`Closes #<Issue番号>`を記載し、merge時に対象Issueを自動closeさせる。複数のIssueを閉じる場合は`Closes #1, Closes #2`のように並べる。
- Issueを自動closeさせない参照には`Refs #<Issue番号>`を使う。
- ベースブランチは`develop`。`develop`と`main`へ直接pushしない。
- PRタイトルは`FND-03 〜を定義`のように管理IDから始める日本語とする。

## コミット

- コミットメッセージは英語の命令形で書く（例: `Add common RPC contract spec`）。

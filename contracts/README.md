# Contracts

Flutterとバックエンドを並行開発するためのRPC・DTO契約を配置する。

## 構成

```text
contracts/
  rpc-contract-spec.md                共通契約。全RPCの命名・封筒・エラー・冪等性・互換性
  rpc/<function名>.md                 個別契約。実装Issueごとに作成
  templates/rpc-contract-template.md  個別契約のテンプレート
```

## 運用

- 個別契約は実装開始前に作成し、Function名、権限、request、response、業務エラー、冪等性、排他制御、副作用、履歴を含める（[09. 共同開発・Issue運用](../production-spec/09_DEVELOPMENT_WORKFLOW.md) 第6章）。
- フロントは個別契約だけを根拠にFake Repositoryを先行実装できる。
- 契約の追加・変更はフロント、バックエンド、DB・CIの3担当レビューを必要とする。破壊的変更は[共通契約 第10章](rpc-contract-spec.md)の手順に従う。

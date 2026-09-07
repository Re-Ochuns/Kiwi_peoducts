# Contracts

Flutterとバックエンドを並行開発するためのRPC・DTO契約を配置する。

契約にはFunction名、権限、request、response、業務エラー、冪等性、排他制御、副作用、履歴を含める。変更はフロント、バックエンド、DB・CIのレビューを必要とする。具体形式はIssue #4で決定する。

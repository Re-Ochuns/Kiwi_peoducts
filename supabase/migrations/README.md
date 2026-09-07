# Migrations

PostgreSQLテーブル、制約、索引、RLS、Database Functionのmigrationを時系列で配置する。

マージ済みmigrationは変更せず、修正用migrationを追加する。Database Functionはバックエンド担当が設計し、DB・CI担当がmigrationと権限をレビューする。

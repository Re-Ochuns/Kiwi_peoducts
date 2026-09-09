# CI/CD・Staging運用

## 1. 目的

Pull RequestごとのFlutter・Supabase検証と、承認されたStaging反映を再現可能にする。本番環境へのデプロイは本Issueの対象外とする。

## 2. Pull Requestの必須チェック

`develop`と`main`を対象とするPull Requestでは、変更パスにかかわらず次の3チェックを実行する。GitHubのブランチ保護ルールにも同じチェック名を登録する。

| 必須チェック名 | 内容 |
|---|---|
| `Flutter CI / flutter-quality` | format、analyze、test |
| `Flutter CI / flutter-web-build` | release Web build、成果物保存 |
| `Database CI / database-migrations-lint-pgtap` | migration再構築、lint、pgTAP |

Flutterの品質検査とWebビルド、およびDatabase CIは独立ジョブとして並列実行する。Flutter SDKとpub cacheは`subosito/flutter-action`のcacheを利用する。キャッシュへ資格情報や`.env`を保存してはならない。

CIが失敗した場合は、失敗ジョブ内のステップ名とログから原因を確認する。Database CIは失敗時にSupabase状態とDockerコンテナ一覧を追加出力する。

## 3. 秘密情報の境界

Pull Requestで動く`flutter-ci.yml`と`database-ci.yml`は、GitHub Environment、Repository Secret、本番・Stagingの資格情報を参照しない。DBテストのGoogle OAuth設定には固定のダミー値だけを使う。

Staging用の値はGitHub Environment `staging`へ登録する。

| 種別 | 名前 | 用途 |
|---|---|---|
| Environment secret | `SUPABASE_ACCESS_TOKEN` | Supabase CLI認証 |
| Environment secret | `SUPABASE_DB_PASSWORD` | Staging DB接続 |
| Environment secret | `FIREBASE_SERVICE_ACCOUNT_STAGING` | Firebase Hosting反映 |
| Environment variable | `SUPABASE_PROJECT_REF` | Staging Supabase識別子 |
| Environment variable | `SUPABASE_URL` | Flutter Web公開設定 |
| Environment variable | `SUPABASE_PUBLISHABLE_KEY` | Flutter Web公開設定 |
| Environment variable | `FIREBASE_PROJECT_ID` | 本番と分離したStaging専用Firebaseプロジェクト識別子 |

`SUPABASE_SERVICE_ROLE_KEY`、Google OAuth client secret、Production資格情報はFlutter buildへ渡さない。

## 4. Stagingデプロイ

実行者はGitHub Actionsの`Staging Deployment`を`develop`ブランチから手動実行する。別ブランチからの実行は`validate-staging-source`で停止する。

1. `develop`へ取り込まれたコミットで3つの必須チェックが成功していることを確認する。
2. `Staging Deployment`を`develop`から`Run workflow`する。
3. GitHub Environment `staging`の承認者が、実行者・対象SHA・変更内容を確認して承認する。
4. WorkflowがFlutter WebをStaging用公開設定でbuildする。
5. Supabaseの未適用migrationをStagingへ反映する。
6. Staging専用FirebaseプロジェクトのHosting Live Channelへリリースを反映する。
7. Actions履歴へ実行者、対象SHA、実行結果を残す。

GitHub Environmentには最低1名のRequired reviewerを設定する。可能な場合は、実装者以外を承認者とする。`develop`以外のDeployment branchを許可しない。

## 5. 承認境界

| 操作 | 実行者 | 承認 |
|---|---|---|
| PRのCI | GitHub Actions | 不要、秘密情報なし |
| Stagingデプロイ | 開発担当者 | `staging` Environment承認者 |
| Stagingの確認 | 影響を受ける領域の担当者 | PRレビューに記録 |
| Productionデプロイ | 未定義 | 本Issueでは実装しない |

## 6. ロールバック

### Firebase Hosting

Staging専用FirebaseプロジェクトのFirebase Consoleで、Hostingのリリース履歴から直前に確認済みのバージョンへロールバックする。実行者は対象バージョンと理由をIssueまたはPRへ記録する。本番FirebaseプロジェクトのLive Channelは操作しない。

### Supabase

適用済みmigrationをその場で編集・削除しない。原則は前方修正migrationを作成し、同じCIを通して再デプロイする。データ損失またはサービス継続不能がある場合だけ、事前に確認したStagingバックアップから復旧する。破壊的migrationは別Issueと承認を必要とする。

Firebaseだけを戻しても、DB契約と非互換なら復旧にならない。デプロイ前に後方互換性を確認し、DB変更を先に反映してからWebを反映する。

## 7. 初回セットアップと試行記録

リポジトリ管理者は初回だけ次を行う。

1. 本番と分離したStaging専用Firebaseプロジェクトを作成し、Hostingを初期化する。
2. GitHub Environment `staging`を作成し、Required reviewerと`develop`のDeployment branch ruleを設定する。
3. 前述のEnvironment secretsとvariablesを登録し、`FIREBASE_PROJECT_ID`にはStaging専用プロジェクトを指定する。
4. `develop`のブランチ保護へ3つの必須チェックを登録する。
5. ダミー変更のPRでFlutter解析エラーとpgTAP失敗を別々に発生させ、各ジョブが停止することを確認する。
6. Stagingへデプロイし、対象SHAと画面・DB migrationを確認する。
7. Staging専用FirebaseプロジェクトのHostingを直前のバージョンへ戻し、表示が復旧することを確認する。
8. 必要なら前方修正migrationをStagingへ適用し、DB復旧手順を確認する。
9. 実施日、実行者、Actions URL、結果をIssue #9へ記録する。

実環境の資格情報が未登録の場合、手順6〜8は実施済みにしない。

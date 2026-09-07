# ローカル開発ガイド

## 1. 対象構成

| パス | 内容 | 主担当 |
|---|---|---|
| apps/kiwi_inventory | Flutter Webアプリ | フロント |
| contracts | RPC・DTO契約 | 3担当共同 |
| supabase/functions | Edge Functions | バックエンド |
| supabase/migrations | PostgreSQL migration | DB・CI |
| supabase/tests | DB・RLS・Functionテスト | バックエンド、DB・CI |
| scripts | 共通開発スクリプト | DB・CI |
| docs/adr | 技術判断 | 3担当共同 |
| production-spec | 業務・画面要件の正本 | 要件責任者 |

## 2. 固定バージョン

- Flutter 3.47.2（.fvmrc）
- Dart 3.13.2（Flutter同梱、pubspec.yaml）
- Node.js 24.19.0（.nvmrc）
- Supabase CLI 2.117.0（package.json / package-lock.json）
- PostgreSQL 17（supabase/config.toml）

バージョン更新は専用IssueとPRで行い、ローカル・CIを同時に更新する。

## 3. 前提ソフトウェア

- Git
- Make
- Flutter 3.47.2、またはFVM
- Node.js 24.19.0、npm
- Supabaseローカル環境を使う場合はDocker DesktopとWSL 2 integration

FVMを使う場合は、以降のMakeコマンドへ次のように渡す。

```bash
make FLUTTER="fvm flutter" DART="fvm dart" doctor
make FLUTTER="fvm flutter" DART="fvm dart" app-run
```

## 4. 新規クローンからの準備

```bash
git clone https://github.com/Re-Ochuns/Kiwi_peoducts.git
cd Kiwi_peoducts
nvm use
make setup
make doctor
```

nvm未使用の場合も、.nvmrcと同じNode.jsを用意する。make doctorはFlutter、Dart、Node.js、Supabase CLIの完全一致を検査する。

## 5. Flutterアプリ

Chromeで起動する。

```bash
make app-run
```

WSLやヘッドレス環境でChromeを直接起動できない場合は、Web Serverデバイスを指定する。

```bash
make app-run DEVICE=web-server
```

品質確認はリポジトリルートから実行する。

```bash
make format-check
make analyze
make test
make build-web
```

まとめて検査する場合はmake checkを使用する。自動生成パッケージ導入後のコード生成はmake codegenへ統一する。生成器が未導入の間は安全に何も変更せず終了する。

## 6. Supabaseローカル環境

Docker Desktopを起動し、Settings > Resources > WSL Integrationで利用中のUbuntuを有効にする。

```bash
make db-start
make db-status
```

このリポジトリは他のSupabaseプロジェクトとの衝突を避けるため55321番台を使用する。初回起動時はコンテナイメージ取得に時間がかかる。表示されたAPI URLとpublishable keyをローカルの.envへ設定する。.envはGit管理対象外である。

DBをmigrationとseedから再構築する。

```bash
make db-reset
make db-test
```

作業終了時:

```bash
make db-stop
```

## 7. 環境変数と秘密情報

.env.exampleを.envへコピーし、ローカル値だけを設定する。本番・Stagingの値はGitHub EnvironmentおよびSupabase Secretで管理する。

Flutter Webへ埋め込まれた値は利用者から閲覧できる。Supabase URLとpublishable key以外の秘密情報、特にservice role key、Google API秘密鍵、更新トークンをFlutterへ渡してはならない。

LocalとStagingへ実在する顧客・配送先データを投入しない。

## 8. ブランチと生成物

- developとmainへ直接pushしない。
- Issueごとに短期ブランチとPRを作成する。
- pubspec.lockとpackage-lock.jsonはコミットする。
- .dart_tool、build、node_modules、supabase/.temp、.envはコミットしない。
- マージ済みmigrationは編集せず、修正migrationを追加する。

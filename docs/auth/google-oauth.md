# Google OAuth・プロフィール・RLS運用ガイド

## 目的

Supabase AuthのGoogle OAuthを入口とし、承認済みユーザーだけがアプリのプロフィールと権限を参照できるようにします。Googleログインの成功だけでは利用を許可せず、新規ユーザーは必ず `pending` から開始します。

## アクセスモデル

- `pending`: Google認証済み、利用承認前。RLSによりプロフィールを取得できません。
- `active`: 利用承認済み。`member` または `administrator` のアクセスロールを持ちます。
- `disabled`: 利用停止。既存セッションが残っていてもRLSにより取得できません。

アクセスロールは認可専用です。画面上の「作業者モード／管理者モード」とは分離し、ユーザーが変更できる `raw_user_meta_data` を認可判定に使用しません。

## 環境別設定

Google CloudではLocal、Staging、ProductionごとにOAuthクライアントを分けます。資格情報をGitへコミットせず、Localはルートの `.env`、Staging/ProductionはSupabase DashboardとCI/CDのSecretで管理します。

| 環境 | アプリURL / JavaScript origin | GoogleのAuthorized redirect URI | 資格情報 |
| --- | --- | --- | --- |
| Local | `http://localhost:58080` | `http://127.0.0.1:55321/auth/v1/callback` | `.env` |
| Staging | Issue #9で確定するHTTPS URL | `https://<staging-project-ref>.supabase.co/auth/v1/callback` | Staging Secret |
| Production | 本番HTTPS URL | `https://<production-project-ref>.supabase.co/auth/v1/callback` | Production Secret |

Supabase Dashboardの **Authentication > URL Configuration** ではSite URLとRedirect URLsを環境ごとに登録します。ワイルドカードはローカルやプレビュー用途に限定し、Productionでは完全一致を使用します。

## Localセットアップ

1. Google Cloud ConsoleでLocal用のWeb OAuthクライアントを作成します。
2. Authorized JavaScript originsに `http://localhost:58080` を登録します。
3. Authorized redirect URIsに `http://127.0.0.1:55321/auth/v1/callback` を登録します。
4. 設定ファイルを作成し、Local用の値だけを設定します。

```bash
cp .env.example .env
```

```dotenv
SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID=<local-client-id>
SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_SECRET=<local-client-secret>
```

5. Supabaseを起動してマイグレーションとRLSテストを実行します。

```bash
make db-start
make db-reset
make db-test
```

FlutterからOAuthを開始するときは、アプリへ戻す `redirectTo` をSupabaseのRedirect URLs許可リストにも登録してください。WebのLocal確認では `http://localhost:58080` を使用します。

## 利用承認と停止

新規Googleユーザーにはトリガーでプロフィールが作成されます。初回の管理者を含む承認操作は、Supabase SQL Editorまたは信頼されたバックエンドからのみ実行します。クライアントへ `service_role` キーを配布してはいけません。

メンバーとして承認:

```sql
select private.set_user_access(
  '<user-uuid>',
  'active',
  array['member'],
  '<operator-user-uuid>'
);
```

管理者として承認:

```sql
select private.set_user_access(
  '<user-uuid>',
  'active',
  array['administrator'],
  '<operator-user-uuid>'
);
```

初回管理者のみ `actor_user_id` を `null` にできます。以後は操作した管理者のUUIDを渡し、`access_changed_by` とロールの `assigned_by` に監査情報を残します。

利用停止:

```sql
select private.set_user_access(
  '<user-uuid>',
  'disabled',
  array[]::text[],
  '<operator-user-uuid>'
);
```

## 検証チェックリスト

- 未認証ユーザーは `profiles` / `user_roles` をSELECTできない。
- `pending` と `disabled` のユーザーは、自分のプロフィールも取得できない。
- `member` は自分のプロフィールとロールだけを取得できる。
- `administrator` は全プロフィールと全ロールを取得できる。
- 認証済みクライアントからプロフィールやロールを直接変更できない。
- Stagingで許可対象のGoogleアカウントがログインし、プロフィールを取得できる。
- Staging/ProductionのURLとSecretがリポジトリ外で管理されている。

SQLによるRLS項目は `supabase/tests/00010_profiles_rls_test.sql` でCI実行できます。実際のGoogleリダイレクト確認は、Issue #7のFlutter認証実装とIssue #9のStaging環境構築後に行います。

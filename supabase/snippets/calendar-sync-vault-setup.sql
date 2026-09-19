-- Googleカレンダー同期 Vault 設定（Issue #79）
-- Supabase SQL Editor で実行する。
-- 実際の値を貼るため、実行後にSQL Editorの履歴を閉じ、クリップボードを消去する。
-- 値をPR・Issue・チャットへ貼らない。
--
-- 前提: Edge Function の CALENDAR_SYNC_TOKEN と同じランダム文字列を用意しておく。
--       openssl rand -base64 48 などで生成する。

-- ── 新規登録（初回のみ） ────────────────────────────────────────────────────

-- calendar_sync_url: Edge Function の呼び出し URL
-- <project-ref> を実際の Supabase プロジェクト参照に置き換える。
select vault.create_secret(
  'https://<project-ref>.supabase.co/functions/v1/calendar-sync',
  'calendar_sync_url',
  'calendar-sync Edge Function の呼び出し URL（Issue #79）'
);

-- calendar_sync_token: Edge Function の CALENDAR_SYNC_TOKEN と同一の値
-- <token> を実際のトークン文字列に置き換える。
select vault.create_secret(
  '<token>',
  'calendar_sync_token',
  'calendar-sync Edge Function の共有認証トークン（Issue #79）'
);

-- ── 更新（値を差し替える場合） ────────────────────────────────────────────────

-- 既存レコードの id は以下で確認できる（値は表示されない）:
-- select id, name, description, created_at from vault.secrets order by name;

-- 第3引数は名前、第4引数は説明。名前は null で既存値を維持する。
-- select vault.update_secret('<vault-secret-id>', '<新しい値>', null, '更新理由');

-- ── 確認（設定後に名前と更新日時だけを確認する） ──────────────────────────────

-- select id, name, description, created_at, updated_at
-- from vault.secrets
-- where name in ('calendar_sync_url', 'calendar_sync_token')
-- order by name;

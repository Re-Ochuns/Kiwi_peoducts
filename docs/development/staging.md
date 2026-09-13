# Staging構築・デプロイ・復旧（Issue #99）

## 方針と現在地

2026-09-14時点の調査では、クラウドプロジェクトは未作成。
利用者の方針は無料枠を優先し、Google管理アカウントは用意済み。
GitHubにはstaging Environmentを作成し、deployment branch policyでdevelopだけを許可した。
Variables / Secrets / 配備履歴 / 公開URL / 実機検証は未設定・未実施。
これは準備手順であり、Issue #99の完了記録ではない。

Firebase HostingはSpark、SupabaseはFree組織を使用する。
有料プランへの変更、課金アカウントの紐付け、独自ドメインは今回実施しない。
無料枠超過・停止時は検証を止めて所有者へ確認する。可用性や復旧保証を本番相当とみなさない。
Supabase Freeは低稼働が7日続くと休止対象になるため、リハーサル前にDashboardで稼働を確認する。
料金と上限は作成時に公式ページで再確認する。

- [Firebase料金](https://firebase.google.com/pricing)
- [Supabase料金](https://supabase.com/pricing)
- [Supabase Freeの休止](https://supabase.com/docs/guides/platform/free-project-pausing)

## 初回構築

1. 所有者がGoogleアカウントとSupabaseアカウントへログインする。
   作成先の所有者・組織名を[検証記録](../verification/issue99-staging.md)へ記入する。
2. Firebase ConsoleでStaging専用プロジェクトを作成する。
   表示名の例はkiwi-staging。プロジェクトIDは作成時に確定し、Productionへ流用しない。
   Google Analyticsは今回不要。Sparkを維持する。
   Firebase Hostingを使用し、App HostingやCloud Functionsを追加しない。
   既定Hostingサイトを使用する。URLは https://<FIREBASE_PROJECT_ID>.web.app 。
3. SupabaseでFree組織内にStaging専用プロジェクトを作成する。
   日本から利用するため利用可能ならTokyoを選ぶ。DBパスワードはパスワード管理ツールへ保存する。
   project ref、Project URL、publishable keyを控える。Service Role / secret keyはアプリへ入れない。
4. Firebase用デプロイサービスアカウントをGoogle Cloud側に作り、Stagingプロジェクトだけに
   Firebase Hosting Adminを付与する。JSON鍵をリポジトリ外へ保存し、後述のEnvironment Secretへ登録する。
   サービスアカウントをOwner/Editorにしない。組織ポリシーで鍵作成が禁止される場合は無理に緩和せず、
   Workload Identity Federationへの変更を別途設計する。
5. 以下のOAuth・カレンダー設定を完了し、GitHubのVariables/Secretsを設定する。

## GitHub Environmentと実行境界

Environment名はstaging、許可するdeployment branchはdevelopだけ。
現時点ではrequired reviewerを設定していない。手動workflow_dispatchを実行するWrite権限者が
Stagingの配備実行者となる。Environment管理者はこの制約を変更できるため、
本番の承認者分離を代替するものではない。Productionには別Environmentと承認者が必要。
2026-09-14のbranch protection API確認はprivateリポジトリのプラン制約で403だった。
developの保護やレビュー必須を設定済みとはみなさず、無料枠運用中は所有者がマージ・実行を管理する。
有料プランへの切り替えやリポジトリ公開は行っていない。

deploy workflowは次を満たさない場合、クラウドへ書き込む前に停止する。

- 実行元がdevelop。
- 同じコミットSHAのdevelop pushに対するFlutter CIとDatabase CIの最新runが成功。
- 同じcheckoutのEdge Functionsの型検査・テストが成功。
- 必須設定が揃い、Supabase URLとproject ref、Firebase鍵とproject IDが一致。
- アプリのキーがpublishable keyまたは同一project refのanon JWT。
- カレンダー用Edge Secretsの名前が存在する（値と共有権限の正しさは別途実機検証）。

Variables（Settings → Environments → staging）:

| 名前 | 値 |
| --- | --- |
| FIREBASE_PROJECT_ID | StagingのFirebase project ID |
| SUPABASE_PROJECT_REF | Stagingの20文字project ref |
| SUPABASE_URL | https://<project-ref>.supabase.co |
| SUPABASE_PUBLISHABLE_KEY | Stagingのpublishable keyまたはlegacy anon JWT |

Secrets:

| 名前 | 値 |
| --- | --- |
| FIREBASE_SERVICE_ACCOUNT_STAGING | Staging専用デプロイアカウントのJSON |
| SUPABASE_ACCESS_TOKEN | Stagingへアクセスできる管理用PAT |
| SUPABASE_DB_PASSWORD | Staging DBパスワード |

SecretはGitHub画面へ直接入力するか、gh secret setの標準入力から登録する。
チャット、Issue、PR本文、コマンド引数、Git管理ファイルへ貼らない。
個人PATのアクセス範囲と有効期限を確認し、不要になったら失効する。
Repository SecretやProduction用Secretへ代替登録しない。

## Google OAuthと初回利用承認

Staging専用Web OAuthクライアントを作成する。
Googleの同意画面をTestingで使用する場合は、検証アカウントをテストユーザーへ登録する。

- JavaScript origin: https://<FIREBASE_PROJECT_ID>.web.app
- Google Authorized redirect URI: https://<SUPABASE_PROJECT_REF>.supabase.co/auth/v1/callback
- Supabase Google Provider: Staging用client ID / secretをDashboardで設定。
- Supabase Site URLとRedirect URLs: https://<FIREBASE_PROJECT_ID>.web.app
- URLは完全一致。Local用localhost、ProductionのURLをStagingへ追加しない。
- メールパスワード、匿名ログインなど未使用のプロバイダは有効化しない。

ローカルconfig.tomlのGoogle設定はクラウドへ自動反映されない。
このworkflowはsupabase config pushを実行しないので、Dashboardで設定・確認する。
詳細なプロフィール承認・停止SQLは[Google OAuthガイド](../auth/google-oauth.md)を使用する。
最初に本人がGoogleログインしpendingプロフィールを作成し、所有者がSQL Editorから初回管理者を承認する。
以後の承認・停止には操作管理者UUIDを記録する。UUIDや実メールを公開検証記録へ載せない。

## Edge Functions・Secret・Storage・スケジュール

| 対象 | 配備・設定 | 検証 |
| --- | --- | --- |
| label-pdf | workflowで配備。日本語フォントはstatic_filesで同梱 | 未認証401、非active403、ダミーコンテナのA5 PDF |
| calendar-sync | workflowで配備。下記Secret + Vaultが必要 | 共有カレンダーの作成/変更/再送/中止 |
| Storage | 現実装に専用bucketは不要。PDFは応答として返す | 不要な公開bucketを作らない |
| delete-expired-idempotency-records | migrationで毎時15分に登録 | 期限切れ冪等性レコードの削除 |
| ripening-deadlines | migrationで毎分登録 | private.process_ripening_deadlines、警告/期限更新 |
| calendar-sync-dispatch | migrationで毎分登録 | Vault設定後に配信開始 |

Supabase側が提供するSUPABASE_URL、SUPABASE_ANON_KEY、SUPABASE_SERVICE_ROLE_KEYは
手動上書きしない。gatewayのverify_jwt=falseは既存configに従う。
label-pdfはハンドラ内でJWTとRLSを確認し、calendar-syncは共有トークンを照合する。

カレンダーは本番や個人のprimaryを使わず、ダミー検証用カレンダーを新規作成する。
Calendar APIを有効にし、カレンダー専用サービスアカウントへ「予定の変更」を共有する。
ドメイン全体の代理権限は不要。

Supabase Edge Secrets（Dashboardへ直接入力。値をGitへ保存しない）:

- GOOGLE_CALENDAR_SERVICE_ACCOUNT: カレンダー専用JSON鍵
- GOOGLE_CALENDAR_ID: ダミー検証カレンダーID
- APP_BASE_URL: https://<FIREBASE_PROJECT_ID>.web.app
- CALENDAR_SYNC_TOKEN: パスワード管理ツールで生成した長いランダムな共有値

初回migration・Function配備後にSQL EditorのVault管理で次を登録する。
同名Secretの重複を作らず、既存値があれば更新する。

- calendar_sync_url: https://<project-ref>.supabase.co/functions/v1/calendar-sync
- calendar_sync_token: EdgeのCALENDAR_SYNC_TOKENと同一値

Vault未設定中は既存dispatch処理が外部送信を行わない。
cron.jobでは名前・schedule・activeだけを確認し、Vaultのdecrypted_secretをログに出さない。
Google障害時はprivate.calendar_sync_logとwork_task_sync_warningsの安全なコードを確認する。
資格情報や共有権限を修正すると既存キューが再試行する。
[カレンダー運用](../edge-functions/calendar-sync.md)を参照。

## 配備と再デプロイ

1. developへレビュー済み変更をマージし、対象SHAのFlutter CI / Database CI完了を待つ。
2. 対象がStaging専用であり、OAuth/Secrets/ダミーカレンダーの設定が完了したことを確認する。
3. 既存配備があればFirebase Hostingの直前release/version IDとdeployment.jsonを記録する。
   既存DBに残したい検証データがある場合は保護された場所へバックアップする。
4. Actions → Staging Deployment → Run workflow → develop。
5. workflowは設定確認 → Webビルド/成果物保存 → DB dry-run/push → Edge2本 → Hostingの順で進む。
   DB migrationはアプリ・Edgeの旧版でも動く後方互換な変更に限定する。
   dry-runが想定外のmigrationを示したら実行を止め、履歴を調査する。
   include-allやmigration repairで無理に通さない。
6. 配備後にdeployment.jsonのSHA、SPA直アクセス、未認証のPDF/カレンダー/プロフィール制限を検査する。
   これはログイン後の業務検証を代替しない。
7. 同じdevelopコミットで再実行しても、適用済みmigrationは再適用されない。
   ただしEdge/Hostingは再配備される。実機受入を改めて実施する。

Cloud設定・URLの変更だけでも再ビルドが必要。Flutterのdart-defineは成果物へ固定される。
7日保持のstaging-web artifactには公開可能設定を含むので、非公開リポジトリのアクセス制限を維持する。
DBバックアップやGoogle鍵をartifactへ入れない。

## 障害時とロールバック

- CI/設定チェック失敗: クラウドは未変更。対象SHAのCIとEnvironment設定を確認する。
- DB適用失敗: Hostingへ進まない。migration履歴を確認し、原因を修正migrationで解消する。
- Edge配備失敗: DBは更新済みの可能性がある。アプリは旧版。DB/Edge旧版互換性を確認して再実行する。
- Hosting/スモーク失敗: DB/Edge/Hostingの一部が更新済みの可能性がある。下記でアプリを戻す。
- Googleログイン失敗: Google callback、Supabase Site URL/Redirect URLs、テストユーザーを確認。
- カレンダー失敗: CONFIG_*、GOOGLE_ACCESS_DENIED等の安全なコードから設定・共有権限を確認。

Firebase Console → Hosting → Release historyで記録済みの直前releaseへRoll backする。
アプリを戻すだけでDBとEdgeは戻らない。deployment.jsonも旧SHAになることを確認し、
PC/スマホから再読み込み・代表的な参照を検証する。
次にStaging workflowで新しい版を再配備して復旧試験を完了する。
初回配備だけでは「直前版へのロールバック」を試せないため、2回目の配備後に実施する。

DBを逆migrationやdb resetで戻さない。破壊的な問題は接続先を確認して作業停止し、
修正migrationかバックアップから別プロジェクトへ復元して切り替える。
Freeで自動バックアップ/PITRが利用できると仮定しない。
バックアップにはダミーであってもAuth・内部状態を含み得るため、暗号化した管理領域で保持する。
バックアップ取得・復元試験が未実施なら、復旧可能と記録しない。

## 完了判定と本番への引き継ぎ

[検証記録](../verification/issue99-staging.md)に公開URL・SHA・Actions URL・
スマホ/PC・認証境界・登録/更新・PDF/CSV/カレンダー・再配備・rollbackの実測結果を記入して
初めてIssue #99を完了する。未実施は未実施とする。

Productionの別プロジェクト/OAuth/Secret、main昇格と承認者分離、日次バックアップと復元試験、
実利用者停止の運用、料金・容量監視は本番公開前の後続タスクとして切り出す。
Front/Backendの影響領域レビューを実環境の受入前に受ける。

## 参考

- [Supabase FunctionsのGitHub Actions配備](https://supabase.com/docs/guides/functions/examples/github-actions)
- [Supabase Edge Secrets](https://supabase.com/docs/guides/functions/secrets)
- [Firebase Hostingのrelease管理とrollback](https://firebase.google.com/docs/hosting/manage-hosting-resources)

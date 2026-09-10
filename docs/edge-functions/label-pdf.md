# label-pdf Edge Function

Issue #17（S1-08）の選果後A5ラベルPDFを生成するEdge Functionを定義する。設計方針はADR-0002に従い、PDF生成をサーバーへ集約して再現性と監査性を確保する。印刷状態の確定は[ラベル状態管理RPC](../database/label-rpc.md)が担い、本Functionは状態を変更しない。

## エンドポイント

- パス: `/functions/v1/label-pdf`
- メソッド: `GET`（`?container_id=<uuid>`）または `POST`（`{"container_id":"<uuid>","correlation_id":"<任意>"}`）
- 認可: 呼び出し元のJWTを`auth.getUser`で検証し、`profiles`をRLS越しに参照して`active`利用者だけへ許可する。`config.toml`の`verify_jwt = false`はゲートウェイ検証を切り、ブラウザのCORSプリフライト（Authorizationなしの`OPTIONS`）を通すための設定で、認可はFunction内で行う。
- `profiles`参照が**行なし**なら権限なしとして403、参照そのものが**エラー**（PostgREST障害・通信障害）なら再試行可能な500 `UNEXPECTED`として扱い、権限判定と取得障害を区別する。
- 応答: 成功時`application/pdf`（A5縦1ページ）。失敗時は`{ "error": { "code, message }, "correlation_id" }`のJSON。
- CORS: `Access-Control-Expose-Headers`へ`Content-Disposition, X-Label-Layout-Version`を露出し、Flutter Web（ブラウザ`fetch`）からファイル名とレイアウト版を読めるようにする。

| 状況 | HTTP | code |
|---|---|---|
| 成功 | 200 | （PDFバイト列） |
| container_idが不正 | 400 | VALIDATION_FAILED |
| 未認証・無効セッション | 401 | AUTH_REQUIRED |
| 認証済みだが非active | 403 | AUTH_FORBIDDEN |
| コンテナが存在しない／選果未確定 | 404 | CONTAINER_NOT_FOUND |
| profile取得やPDF生成の予期しない失敗 | 500 | UNEXPECTED |

## レイアウトと再現性

- `layout.ts`がFND-07試作（`experiments/fnd-07`）のレイアウトを移植する。ページはA5（148×210mm）、安全余白10mm、コンテナIDと正味重量を最優先で大きく表示する。試作のみの100mm確認線は含めない。
- 同一入力・同一レイアウト版から同一バイト列を再生成できるよう、PDFメタデータの日時を固定し、埋め込みフォントのサブセット名を固定する。レイアウト版は`LABEL_LAYOUT_VERSION`（応答ヘッダー`X-Label-Layout-Version`）で管理する。
- 表示項目は選果後ラベルの必須項目（コンテナ表示ID、産地・区画、品種、等級、正味重量、選果日、担当者）を`containers`→`sorting_results`→`workers`/`receiving_lots`から取得する。

## フォント

- `assets/NotoSansJP-VariableFont_wght.ttf`（SIL OFL 1.1、`assets/OFL.txt`）を同梱し、`config.toml`の`static_files`でランタイムへ配置する。
- `pdf-lib`＋`@pdf-lib/fontkit`でサブセット埋め込みし、生成PDFは約12KB（全約9.1MBのフォントを丸ごと積まない）。ADR-0002のバンドル制約に対し、ローカルCLIバンドル＋サブセット化で対応する。

## 監視

- 各要求で`{ "fn": "label-pdf", "outcome", "container_id", "correlation_id", "layout_version", "pdf_bytes", "duration_ms" }`をJSONで1行ログ出力する。`outcome`は`ok` / `invalid_request` / `auth_required` / `auth_forbidden` / `not_found` / `error`。
- 顧客情報・住所・トークンはログへ含めない（共通契約 第9章）。生成失敗は業務データへ副作用を残さないため、クライアントは同じ`container_id`で安全に再試行できる。

## テスト

```bash
cd supabase/functions
deno test --allow-read tests/
```

リクエスト処理は`handler.ts`へ分離し、`createHandler({ fontBytes, createClient })`でSupabaseクライアントを注入できるようにしている（`index.ts`は実クライアントとフォントを配線するだけ）。`tests/label-pdf.test.ts`がA5寸法、単一ページ、Noto Sans JPサブセット埋め込み、同一入力の再現性、入力検証、日本語日付整形を検証し、`tests/handler.test.ts`が偽クライアントで成功時のExpose-Headers、profile取得失敗→500、profileなし→403、コンテナ取得失敗→500、未存在→404、未認証401、不正ID 400を検証する。`.github/workflows/edge-functions-ci.yml`が`deno check`と合わせてCIで実行する。ローカルでは`supabase functions serve label-pdf`に対し、activeなJWTでの200・PDF生成・Expose-Headers、未認証401、不正ID 400、CORSプリフライト200をe2e確認した。

## 未決事項

- 対象プリンター・ブラウザでの実機印刷確認はADR-0002および[A5ラベル印刷検証記録](../printing/a5-label-verification.md)に従い実施する。印字可能領域・許容ずれ・一部再印刷単位は実機確認後に確定する。
- 追熟ラベルのレイアウトはS1-09（#18）で追加する。

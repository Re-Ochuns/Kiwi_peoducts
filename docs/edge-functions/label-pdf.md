# label-pdf Edge Function

Issue #17（S1-08）の選果後A5ラベル、Issue #65（S3-08）の追熟コンテナA5ラベル、Issue #112の収穫・受入仮ラベルPDFを生成するEdge Functionを定義する。設計方針はADR-0002に従い、PDF生成をサーバーへ集約して再現性と監査性を確保する。印刷状態の確定は[ラベル状態管理RPC](../database/label-rpc.md)が担い、本Functionは状態を変更しない。

## エンドポイント

- パス: `/functions/v1/label-pdf`
- 個別印刷は`container_id`、Issue #114の選果後一括印刷は`sorting_result_id`、Issue #112の受入仮ラベルは`receiving_lot_id`を指定する。一括PDFでは`expected_page_count`も必須とし、対象IDの複数指定または未指定は受け付けない。
- メソッド: `GET`（`?container_id=<uuid>`）または `POST`（`{"receiving_lot_id":"<uuid>","expected_page_count":2,"correlation_id":"<任意>"}`）
- 認可: 呼び出し元のJWTを`auth.getUser`で検証し、`profiles`をRLS越しに参照して`active`利用者だけへ許可する。`config.toml`の`verify_jwt = false`はゲートウェイ検証を切り、ブラウザのCORSプリフライト（Authorizationなしの`OPTIONS`）を通すための設定で、認可はFunction内で行う。
- `profiles`参照が**行なし**なら権限なしとして403、参照そのものが**エラー**（PostgREST障害・通信障害）なら再試行可能な500 `UNEXPECTED`として扱い、権限判定と取得障害を区別する。
- 応答: 成功時`application/pdf`（個別はA5縦1ページ、一括は1コンテナ1ページの複数ページ）。失敗時は`{ "error": { "code, message }, "correlation_id" }`のJSON。
- CORS: `Access-Control-Expose-Headers`へ`Content-Disposition, X-Label-Layout-Version, X-Label-Page-Count`を露出し、Flutter Webからファイル名・レイアウト版・ページ数を読めるようにする。

| 状況 | HTTP | code |
|---|---|---|
| 成功 | 200 | （PDFバイト列） |
| container_idが不正 | 400 | VALIDATION_FAILED |
| 選果確定結果とPDF対象件数が不一致 | 409 | LABEL_COUNT_MISMATCH |
| 受入ロットが選果待ちではない | 409 | RECEIVING_LOT_NOT_AVAILABLE |
| 未認証・無効セッション | 401 | AUTH_REQUIRED |
| 認証済みだが非active | 403 | AUTH_FORBIDDEN |
| コンテナが存在しない／選果未確定 | 404 | CONTAINER_NOT_FOUND |
| 受入ロットが存在しない | 404 | RECEIVING_LOT_NOT_FOUND |
| profile取得やPDF生成の予期しない失敗 | 500 | UNEXPECTED |

## コンテナ種別の判定

`containers.ripening_lot_id` が非NULLであれば追熟コンテナとみなし、追熟ラベルを生成する。NULLであれば選果後コンテナとして従来の選果ラベルを生成する。追熟コンテナのラベルデータは `public.ripening_label_get(container_id_value)` RPC（SECURITY INVOKER）で一括取得する。

| 種別 | 判定条件 | データ取得 | レイアウト |
|---|---|---|---|
| 選果後 | `ripening_lot_id IS NULL` | `containers` → `sorting_results` | `buildSortingLabelPdf` |
| 追熟 | `ripening_lot_id IS NOT NULL` | `ripening_label_get` RPC | `buildRipeningLabelPdf` |

## レイアウトと再現性

- `layout.ts`がFND-07試作（`experiments/fnd-07`）のレイアウトを移植する。ページはA5（148×210mm）、安全余白10mm、コンテナIDと正味重量を最優先で大きく表示する。試作のみの100mm確認線は含めない。
- 同一入力・同一レイアウト版から同一バイト列を再生成できるよう、PDFメタデータの日時を固定し、埋め込みフォントのサブセット名を固定する。レイアウト版は`LABEL_LAYOUT_VERSION`（応答ヘッダー`X-Label-Layout-Version`）で管理する。
- 選果後ラベルの表示項目（コンテナ表示ID、産地・区画、品種、等級、正味重量、選果日、担当者）を`containers`→`sorting_results`→`workers`/`receiving_lots`から取得する。
- `sorting_result_id`指定時は`sorting_labels_get`で当該選果結果の追熟前コンテナだけを取得し、等級表示順・コンテナ表示ID順の1つの複数ページPDFを返す。1コンテナをA5の1ページとし、`expected_page_count`と取得件数が一致しなければPDFを生成しない。
- 選果後ラベルは白地・黒文字・黒罫線だけを使用する。選果サイズと品種を最優先、正味重量とコンテナ表示IDを次点として、人が目視で判別できる階層にする。
- 収穫・受入仮ラベルは登録コンテナ数と同じA5ページ数で生成する。白地・黒文字・黒罫線だけを使い、品種と産地を最優先、受入表示IDと`n / N`を次点にする。QRコードには`APP_BASE_URL/sorting/<receiving_lot_id>`だけを格納し、品種・産地などの業務情報を含めない。
- 仮ラベルのQRリンクはHTTPSのみとし、ログイン後に当該受入ロットの選果入力を直接開く。対象なし・選果済み・権限なしは画面上で理由を表示する。
- 日本語の文字欠けを防ぐため、選果後ラベルPDFにはNoto Sans JPを1ファイルにつき1回完全埋め込みする。ファイル容量より現場での可読性を優先する。
- 追熟ラベルの表示項目（コンテナ表示ID、産地、品種、等級、正味重量、注入日時、抜き予定、出荷可能予定、場所）を`ripening_label_get` RPCから取得する。

## フォント

- 選果ラベルには可変フォントから固定ウェイト化した`assets/NotoSansJP-SemiBold.ttf`、追熟ラベルには従来の`assets/NotoSansJP-VariableFont_wght.ttf`を使う。どちらもSIL OFL 1.1（`assets/OFL.txt`）で、`config.toml`の`static_files`から配置する。
- `pdf-lib`＋`@pdf-lib/fontkit`でフォントをPDFごとに1回完全埋め込みする。選果ラベルはファイル容量より、ブラウザ・プリンター間で日本語が欠けないことを優先する。

## 環境変数

- `APP_BASE_URL`: QRコードの遷移先となる公開済みFlutter WebアプリのHTTPS URL。クエリ・フラグメント・認証情報は指定しない。

## 監視

- 各要求で`{ "fn": "label-pdf", "outcome", "container_id", "correlation_id", "layout_version", "pdf_bytes", "duration_ms" }`をJSONで1行ログ出力する。`outcome`は`ok` / `invalid_request` / `auth_required` / `auth_forbidden` / `not_found` / `error`。
- 顧客情報・住所・トークンはログへ含めない（共通契約 第9章）。生成失敗は業務データへ副作用を残さないため、クライアントは同じ`container_id`で安全に再試行できる。

## テスト

```bash
cd supabase/functions
deno test --allow-read tests/
```

リクエスト処理は`handler.ts`へ分離し、`createHandler({ fontBytes, createClient })`でSupabaseクライアントを注入できるようにしている（`index.ts`は実クライアントとフォントを配線するだけ）。`tests/label-pdf.test.ts`がA5寸法、Noto Sans JPサブセット埋め込み、再現性、入力検証、日本語日付整形（選果・追熟の両方）を検証し、`tests/handler.test.ts`が偽クライアントで選果後コンテナの成功パス・追熟コンテナのRPC呼び出しパスとエラー系を検証する。SQLのテストは`supabase/tests/00190_ripening_label_rpc_test.sql`が`ripening_label_get`・ラベル印刷RPC（追熟）の動作を確認する。`.github/workflows/edge-functions-ci.yml`が`deno check`と合わせてCIで実行する。

## 未決事項

- 対象プリンター・ブラウザでの実機印刷確認はADR-0002および[A5ラベル印刷検証記録](../printing/a5-label-verification.md)に従い実施する。印字可能領域・許容ずれ・一部再印刷単位は実機確認後に確定する。

### 追熟ラベルの日時・内訳

日時はタイムゾーン付き値を `Asia/Tokyo` へ変換して表示する。内訳にはロット全体の受注番号・予備区分・割当重量を表示する。個別コンテナへの割当重量ではない。
内訳が1枚へ収まらない場合は、同じコンテナIDを付けたA5の続きページへ出力する。長い受注番号は折り返し、行を省略しない。
追熟ラベルは可変フォントのサブセット埋め込みによる文字欠落を避けるためフォントを完全埋め込みする（サンプルPDF約5.8MB）。

# Issue #62 ローカル検証

## 対象
- develop 2f297c5（#89マージ済み）を起点とするcodex/62-ripening-rpc。
- 確認日2026-09-13、確認者Codex。
- WSL Ubuntu、Supabase CLI 2.117.0、PostgreSQL 17.6、Python 3.12。
- 独立プロジェクトkiwi_issue62。API56421、DB56422。
  作業設定はkiwi-verification/issue62-db。実在顧客データは使用しない。
- kiwi_productsやissue60のDB・プレビューサービスは変更していない。

## 実装と境界
エチレン注入、抜き確認＋寝かせ開始、追熟確認の更新RPCと詳細取得を追加した。
実績日時を省略するとサーバー現在時刻。手動日時、温度、場所、担当者、備考を保存する。
必須確認なしの実行、工程飛ばし、再処理・延長、古いversionを拒否する。
予約消費、部分元在庫の減算、追熟出力生成、工程・受注・タスク・履歴を原子的に更新する。
確定済み受注と予備の内訳、予定日時とマスターコピーは変更しない。

契約: contracts/rpc/ripening_work_complete.md。
期限計算は#63。現物がshippableでも期限未設定なら既存の出荷イベント制約が出荷を拒否する。
本番出荷運用前に#63との結合が必要。画面・追熟ラベルは本Issueの対象外。

## DB検証
各CLIコマンドには次の指定を付ける。
--workdir /home/kugis/products/hackathon/kiwi-verification/issue62-db

- supabase db start / db reset: 全migration・seedから構築。
- supabase db lint --local --fail-on warning: エラーなし。
- supabase test db supabase/tests/00170_ripening_work_rpc_test.sql: 59件成功。
- 全DB回帰検証: 19ファイル809テスト成功。
- 正常系: 10kg元在庫から8kg部分消費し同じ元IDに2kgを維持。
  6kg受注＋2kg予備の内訳を保って3工程を完了。
- 時間省略・手動入力、状態・タスク・カレンダー同期キュー更新を検証。
- 非active権限拒否、確認欠落、不正日時・温度、stale、工程飛ばし、未対応項目を拒否。
- 各工程の再送で二重書込みせず、キー使い回しを拒否。
- 実績INSERTで故意に業務エラーを発生させ、先行した在庫移動・予約消費・出力生成・
  履歴をロールバック。原因除去後も同じキーの業務エラー結果を再返却することを確認。

## HTTP API受入
再現スクリプト: scripts/verify_issue62_local_api.py
実行: python3 scripts/verify_issue62_local_api.py

このスクリプトはkiwi_issue62と56421ポートを確認してから専用DBへ合成fixtureを登録する。
ローカルJWT秘密鍵をプロセス内だけで扱い、キーやトークンを出力しない。
実行後は必ず専用DBをdb resetする（スクリプトは既存fixtureがある場合停止する）。

実測PASS:
- active JWTによる3工程のHTTP実行、pending拒否、必須確認拒否。
- 同じ操作キーで2リクエストを並行送信し、両方成功・一方だけ再送応答。
- 別キー・同じversionで抜き確認を並行送信し、1成功・1CONFLICT_STALE。
- 元在庫2kg、在庫イベント2件、3実績とタスク完了。
- 予定日時・受注予備内訳不変、完了後の再処理拒否。

終了後に専用DBを全migrationから再構築し、合成受入データを除去した。
既存pgTAPの固定ホスト名は専用DB内だけの自己参照エイリアスで解決する。
ソースの既存テストや本番設定は変更していない。

## 未検証・レビュー
- #63の期限計算、フロント、実Googleカレンダーへの反映との結合。
- 本番認証・接続・適用、実機・現場確認。
- 契約・Database Functionについて複数担当のレビューが必要。
  本記録を本番運用承認やIssue Closeとみなさない。

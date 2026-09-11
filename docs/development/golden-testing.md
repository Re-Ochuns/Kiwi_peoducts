# Goldenテスト運用

## 固定する描画条件

- Flutterの版はルートの`.fvmrc`に従い、DartはそのFlutter SDKに同梱された版を使用する。CIの`flutter-version`と`scripts/check_tool_versions.sh`も同じ版へ揃える。
- テスト用フォントはリポジトリ内の`experiments/fnd-07/assets/NotoSansJP-VariableFont_wght.ttf`を`GoldenNotoSansJP`として読み込む。
- Goldenテストに限り、アプリテーマへ`GoldenNotoSansJP`を指定する。本番テーマとアプリの表示フォントは変更しない。
- `devicePixelRatio`は1.0、論理サイズは各テストで宣言した値に固定する。
- 日付、認証状態、Repositoryの応答はテスト内の固定値を使用する。

## 実行

リポジトリのルートで次を実行する。

```bash
make golden-test
```

この実行は現在のOSでの差分確認用であり、macOSやWindowsでは文字ラスタライズの画素差が出る場合がある。合否の基準はUbuntu上の`Flutter CI / flutter-golden`とする。通常の`make check`はGolden以外のテストを実行する。

ローカルで更新後の見た目を確認する場合は次を実行する。この画像はOSの文字ラスタライズ差を含むため、そのまま正式な基準画像にはしない。

```bash
make golden-update
make golden-test
```

WindowsでもPowerShellまたはGit Bashから同じMakefileターゲットを使用する。`make`を利用できない場合は`apps/kiwi_inventory`へ移動し、対応する`flutter test`コマンドを実行する。

正式な基準画像はGitHub ActionsのUbuntu runnerで生成する。OSにかかわらず、GitHubのActions画面から`Flutter CI`を対象ブランチで手動実行し、`update_goldens`を有効にする。完了後、`golden-reference-<commit>-<attempt>` artifactをダウンロードして`apps/kiwi_inventory/test/goldens`へ反映する。

## UI変更時の更新とレビュー

1. UI変更後、基準画像を更新する前に`make golden-test`を実行する。
2. 失敗時に生成される`test/failures`の`masterImage`、`testImage`、`maskedDiff`、`isolatedDiff`を確認する。
3. 意図した差分だけであることを確認する。必要なら`make golden-update`でローカル表示も確認する。
4. `Flutter CI`を`update_goldens`付きで手動実行し、生成された`golden-reference-<commit>-<attempt>`を取得する。
5. Ubuntu基準画像のPNGをPRへ含め、変更理由と対象画面をPR本文へ記載する。
6. 通常のPR CIを再実行し、`Flutter CI / flutter-golden`が成功することを確認する。

意図を説明できない画素差分や、ローカル環境だけで発生する差分を基準画像へ取り込まない。

## CI

`Flutter CI / flutter-quality`はformat、analyze、Golden以外のWidgetテストを実行する。`Flutter CI / flutter-golden`は固定した描画条件でGoldenを検査し、差分があれば失敗する。

差分発生時は比較画像を`golden-test-failures-<commit>-<attempt>` artifactへ保存する。成功・失敗にかかわらず、そのコミットで使用または手動生成した基準画像を`golden-reference-<commit>-<attempt>` artifactへ保存する。`attempt`は同一workflow runの再実行番号であり、再実行時のartifact名衝突を防ぐ。

Branch protectionで必須チェックを設定できない間は、次をマージ条件とする。

1. PR作成者が最新コミットの`Flutter CI / flutter-golden`成功を確認する。
2. UI変更を含む場合、レビュー担当者が`golden-reference-<commit>-<attempt>` artifactを確認する。
3. 確認結果または対象外の理由をPRの検証欄へ記録する。

必須チェックを利用できるようになった場合は、リポジトリ管理者が`Flutter CI / flutter-golden`を`develop`と`main`へ設定する。チェック名を変更する場合は、ブランチ保護設定も同時に更新する。

## 現在の制約

- CIは`ubuntu-latest`を正本環境としている。GitHubがrunnerイメージを更新した際は画素差が発生し得るため、意図しない差分か環境更新による差分かをartifactで確認する。OSイメージまで固定する場合はworkflowの`runs-on`を特定のUbuntu版へ変更する。
- 非公開リポジトリの現在のGitHubプランではBranch protectionとRulesets APIがHTTP 403になり、`flutter-golden`を必須チェックとして設定できない。このため、現在は上記の手動確認をIssue #32の受入条件とする。GitHubによる強制ではないため、確認漏れのリスクが残ることを受容し、必須チェック化は利用可能になった時点で行う。

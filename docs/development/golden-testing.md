# Goldenテスト運用

## 固定する描画条件

- Flutter・Dartの版はルートの`.tool-versions`に従う。
- テスト用フォントはリポジトリ内の`experiments/fnd-07/assets/NotoSansJP-VariableFont_wght.ttf`を`GoldenNotoSansJP`として読み込む。
- Goldenテストに限り、アプリテーマへ`GoldenNotoSansJP`を指定する。本番テーマとアプリの表示フォントは変更しない。
- `devicePixelRatio`は1.0、論理サイズは各テストで宣言した値に固定する。
- 日付、認証状態、Repositoryの応答はテスト内の固定値を使用する。

## 実行

リポジトリのルートで次を実行する。

```bash
make golden-test
```

ローカルで更新後の見た目を確認する場合は次を実行する。この画像はOSの文字ラスタライズ差を含むため、そのまま正式な基準画像にはしない。

```bash
make golden-update
make golden-test
```

WindowsでもPowerShellまたはGit Bashから同じMakefileターゲットを使用する。`make`を利用できない場合は`apps/kiwi_inventory`へ移動し、対応する`flutter test`コマンドを実行する。

正式な基準画像はGitHub ActionsのUbuntu runnerで生成する。OSにかかわらず、GitHubのActions画面から`Flutter CI`を対象ブランチで手動実行し、`update_goldens`を有効にする。完了後、`golden-reference-<commit>` artifactをダウンロードして`apps/kiwi_inventory/test/goldens`へ反映する。

## UI変更時の更新とレビュー

1. UI変更後、基準画像を更新する前に`make golden-test`を実行する。
2. 失敗時に生成される`test/failures`の`masterImage`、`testImage`、`maskedDiff`、`isolatedDiff`を確認する。
3. 意図した差分だけであることを確認する。必要なら`make golden-update`でローカル表示も確認する。
4. `Flutter CI`を`update_goldens`付きで手動実行し、生成された`golden-reference-<commit>`を取得する。
5. Ubuntu基準画像のPNGをPRへ含め、変更理由と対象画面をPR本文へ記載する。
6. 通常のPR CIを再実行し、`Flutter CI / flutter-golden`が成功することを確認する。

意図を説明できない画素差分や、ローカル環境だけで発生する差分を基準画像へ取り込まない。

## CI

`Flutter CI / flutter-quality`はformat、analyze、Golden以外のWidgetテストを実行する。`Flutter CI / flutter-golden`は固定した描画条件でGoldenを検査し、差分があれば失敗する。

差分発生時は比較画像を`golden-test-failures-<commit>` artifactへ保存する。成功・失敗にかかわらず、そのコミットで使用または手動生成した基準画像を`golden-reference-<commit>` artifactへ保存する。

リポジトリ管理者は`Flutter CI / flutter-golden`を`develop`と`main`の必須チェックへ設定する。チェック名を変更する場合は、ブランチ保護設定も同時に更新する。

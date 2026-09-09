# Goldenテスト運用

## 現在の扱い

`Flutter CI / flutter-quality`ではformat、analyze、Golden以外のtestを必須検査として実行する。

`Flutter CI / flutter-golden-advisory`は既存Golden画像の描画環境差を検出する助言チェックとして別に実行する。差異があっても必須チェックは停止させず、比較画像を7日間artifactへ保存する。

## 分離した理由

2026-09-10時点で、同じFlutter 3.47.2を使ったUbuntu runnerとWindows runnerの両方に次の画像差が発生した。

- ログイン画面: 0.28〜0.30%
- 作業者ホーム: 0.78〜0.81%
- 管理者ホーム: 0.45〜0.49%

通常のWidgetテスト16件、format、analyze、Web buildは成功しており、差分はGoldenの文字描画を中心とする環境依存だった。基準画像をCIの生成結果で無条件に上書きせず、再現可能なフォントと描画条件の確立を後続課題として扱う。

## 差分の確認

助言チェックに差異が出た場合は、artifactに含まれる次の画像を確認する。

- `masterImage`: リポジトリの基準画像
- `testImage`: CIで生成された画像
- `maskedDiff`: 差異を重ねた画像
- `isolatedDiff`: 差異だけを抽出した画像

意図したUI変更の場合も、基準画像の更新は画面担当者のレビュー後に行う。

## 必須チェックへ戻す条件

次をすべて満たしたら`flutter-golden-advisory`を必須チェックへ変更する。

1. テスト用フォントと描画条件をリポジトリ内で固定する。
2. ローカルまたはコンテナとGitHub runnerで同じ画像を生成できる。
3. 基準画像の更新手順とレビュー方法を文書化する。
4. 連続する複数回のCIで画像差が発生しない。

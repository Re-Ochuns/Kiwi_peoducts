# FND-07 A5ラベルPDF試作

日本語フォントを埋め込んだA5ラベルのレイアウト、ページ寸法、安全余白を再現可能な形で確認する試作である。本番用PDF生成処理ではない。

## 生成と検証

Python 3.11以降を用意し、依存パッケージをインストールする。

```bash
python3 -m pip install -r experiments/fnd-07/requirements.txt
make pdf-label-prototype
make pdf-label-verify
```

入力は`label-sample.json`、成果物は`output/pdf/fnd-07-a5-label-prototype.pdf`である。別の入力、フォント、出力先は各スクリプトの引数で指定できる。

## フォント

`assets/NotoSansJP-VariableFont_wght.ttf`はGoogle FontsのNoto Sans Japaneseを取得したもので、`assets/OFL.txt`のSIL Open Font License 1.1に従う。試作を同じ条件で再生成できるよう、元フォントを同梱している。

## 実機印刷

自動検証だけでは印字可能領域やプリンタードライバーによる縮小を判定できない。`docs/printing/a5-label-verification.md`に従い、対象機種で確認結果を記録する。

# 段階1受入

Issue #20（S1-11）の統合テストと現場リハーサルに使用する文書を管理する。

- [E2Eシナリオと受入基準](stage1-e2e-plan.md)
- [実行・現場リハーサル記録](stage1-rehearsal-record.md)
- [Go/No-Go判定](stage1-go-no-go.md)

自動確認はリポジトリルートで次を実行する。

```bash
make FLUTTER="fvm flutter" DART="fvm dart" stage1-acceptance
```

PDF検査用のPython依存は初回実行前に仮想環境へ導入する。

```bash
python3 -m venv /tmp/kiwi-stage1-pdf
/tmp/kiwi-stage1-pdf/bin/pip install -r experiments/fnd-07/requirements.txt
make FLUTTER="fvm flutter" DART="fvm dart" \
  PDF_PYTHON=/tmp/kiwi-stage1-pdf/bin/python stage1-acceptance
```

Goldenの正本はUbuntu GitHub Actionsの`flutter-golden`結果とartifactとする。
LinuxではローカルGoldenも補助的に実行するが、`TZ=UTC`だけでOS間の描画差は
固定できない。非LinuxではGoldenをNot Runとして残りの検査を継続し、
GitHub Actionsが成功するまで段階1の自動検証を合格としない。
Issue #32のmacOS描画差は段階1のGo/No-Go判定対象外とする。

Dockerを利用できない端末やPDF検証環境を分離する場合だけ、
`STAGE1_SKIP_DATABASE=1`または`STAGE1_SKIP_PDF=1`を指定する。
スキップした項目は合格として扱わず、別の実行証跡を記録する。

# Edge Functions

A5 PDF、Google Calendar、外部API、再試行など、秘密情報またはサーバー実行環境が必要な処理を配置する。

業務データの原子的更新はEdge Function内へ分散させず、PostgreSQL Functionへ集約する。

## Functions

- `label-pdf`: 選果後コンテナのA5ラベルPDFを生成する（Issue #17 / ADR-0002）。詳細は[docs/edge-functions/label-pdf.md](../../docs/edge-functions/label-pdf.md)。

- `calendar-sync`: 作業タスクを農園共通Googleカレンダーへ一方向同期する（Issue #57）。[設定・運用手順](../../docs/edge-functions/calendar-sync.md)。

## テスト

各Functionのユニットテストは`tests/`へ置き、リポジトリルートの`supabase/functions`で実行する。

```bash
cd supabase/functions
deno test --allow-read tests/
```

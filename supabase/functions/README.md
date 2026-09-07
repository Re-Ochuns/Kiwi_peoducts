# Edge Functions

A5 PDF、Google Calendar、外部API、再試行など、秘密情報またはサーバー実行環境が必要な処理を配置する。

業務データの原子的更新はEdge Function内へ分散させず、PostgreSQL Functionへ集約する。

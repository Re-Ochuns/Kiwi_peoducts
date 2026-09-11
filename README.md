# Kiwi_peoducts

おおくま農園向けキウイ在庫管理システム。

## ドキュメント

- [本番要件書](production-spec/README.md)
- [Architecture Decision Records](docs/adr/README.md)
- [RPC・DTO契約](contracts/README.md)
- [ローカル開発ガイド](docs/development/README.md)
- [段階1受入](docs/acceptance/README.md)

## クイックスタート

固定バージョンはFlutter 3.47.2、Node.js 24.19.0、Supabase CLI 2.117.0である。詳細な前提ソフトウェアとFVMの利用方法はローカル開発ガイドを参照する。

```bash
git clone https://github.com/Re-Ochuns/Kiwi_peoducts.git
cd Kiwi_peoducts
nvm use
make setup
make doctor
make app-run
```

品質確認:

```bash
make check
make build-web
```

Supabaseローカル環境:

```bash
make db-start
make db-status
make db-reset
make db-test
```

Supabaseローカル環境にはDocker DesktopのWSL 2 integrationが必要となる。

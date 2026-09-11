# Flutterフロントエンド開発ガイド

## 構成

`apps/kiwi_inventory/lib`では、画面から外部サービスを直接呼びません。

```text
lib/
├── main.dart                         アプリ起動、認証後のホーム、既存画面
├── auth/
│   ├── auth_repository.dart         ViewModelが利用する認証境界
│   ├── supabase_auth_repository.dart Supabase Authとプロフィール参照
│   ├── auth_controller.dart         認証状態と画面状態の変換
│   └── auth_gate.dart               未認証・承認確認・認証後の振り分け
└── core/
    ├── app_breakpoints.dart          画面幅の基準
    ├── app_config.dart               公開可能な実行時設定
    ├── app_theme.dart                色、余白、角丸、共通テーマ
    └── common_state_view.dart        読み込み・空・エラー表示
```

業務画面の実装メモ:

- [選果対象・選果入力画面](sorting-input.md)
- [在庫一覧・詳細・履歴画面](inventory-reference.md)

業務機能を追加するときは、機能単位のディレクトリにView、ViewModel、Repositoryインターフェースを配置します。ViewとViewModelからSupabaseを直接呼ばず、Repositoryを経由してください。ViewModelは`ChangeNotifier`を基本とし、Repositoryはコンストラクタから注入します。画面側はViewModelが公開する画面状態だけを参照します。

## 画面を追加する

1. 対象Issueの画面状態と受け入れ条件を確認する。
2. 機能ディレクトリへ画面とViewModelを追加する。
3. 外部データが必要な場合はRepositoryインターフェースを先に定義する。
4. 認証済み領域の画面だけを`AuthGate`の内側から開く。
5. 読み込み・空・エラーには`CommonStateView`を使用する。
6. 360px、390px、430px、900px、1280pxで表示を確認する。
7. ViewModelのUnit Testと画面状態のWidget Testを追加する。

一画面の主要な確定ボタンは一つにし、矢印以外の装飾アイコン、グラデーション、通常コンテナの影を追加しません。詳細な表示規則は`production-spec/08_DESIGN_REQUIREMENTS.md`を正本とします。

最小構成の例:

```dart
abstract interface class TaskRepository {
  Future<List<WorkTask>> loadTasks();
}

class TaskListViewModel extends ChangeNotifier {
  TaskListViewModel(this._repository);

  final TaskRepository _repository;

  Future<void> load() async {
    // Repositoryの結果を読み込み・空・成功・エラーの画面状態へ変換する。
    notifyListeners();
  }
}
```

Repositoryの実装はアプリシェルで生成し、ViewModelのコンストラクタへ渡します。テストでは同じインターフェースのFakeを渡し、外部サービスへ接続せず画面状態を確認します。

## アクセシビリティ

- 通常のタップ・クリック領域は44px以上、入力欄は48px以上にする。
- スマートフォンの主要確定ボタンは54〜56px以上にする。
- キーボードフォーカスを視認でき、表示順と同じ順序で移動できるようにする。
- 矢印には文字ラベルを併記し、対象IDを含むSemantics名を設定する。
- エラーや状態は色だけで表現せず、日本語の状態名または説明を表示する。
- 200%文字拡大時にも主要な値と操作を隠さない。

## 共通状態を表示する

- 読み込み中: `CommonStateView.loading`
- 対象データなし: `CommonStateView.empty`
- 再試行可能な失敗: `CommonStateView.error`

エラー文は日本語で、利用者が次に行える操作を含めます。処理中は同じ操作を再度実行できるボタンを表示しません。

## Google認証をローカルで確認する

ルートの`.env`はSupabase CLI用です。Flutter Webには公開可能な値だけを`--dart-define`で渡します。

```bash
cd apps/kiwi_inventory
flutter run -d chrome --web-port 58080 \
  --dart-define=SUPABASE_URL=http://127.0.0.1:55321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<local-publishable-key>
```

Google Client Secretと`service_role`キーをFlutterへ渡してはいけません。Google CloudとSupabase側の設定は`docs/auth/google-oauth.md`を参照してください。

認証後、`profiles.access_status = active`をRLS経由で確認できた利用者だけをホームへ通します。RLSのため`pending`と`disabled`はクライアントから区別できないので、どちらも「利用承認を確認できません」と表示します。

## 検証

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release
```

実際のGoogleリダイレクトはLocalまたはStagingで確認します。自動テストではFake Repositoryを使用し、未認証、処理中、成功、承認確認不可、通信失敗を再現します。

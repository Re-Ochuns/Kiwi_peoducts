class AppConfig {
  const AppConfig({required this.supabaseUrl, required this.supabaseKey});

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabaseKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    );
  }

  final String supabaseUrl;
  final String supabaseKey;

  String? validate() {
    if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
      return '接続設定がありません。SUPABASE_URLとSUPABASE_PUBLISHABLE_KEYを設定してください。';
    }

    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'SUPABASE_URLの形式が正しくありません。';
    }

    return null;
  }
}

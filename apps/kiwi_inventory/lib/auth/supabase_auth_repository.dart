import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../core/app_config.dart';
import 'auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository._(this._client, this._redirectTo);

  static Future<SupabaseAuthRepository> initialize(AppConfig config) async {
    await supabase.Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseKey,
    );
    final redirectTo = authRedirectTo(Uri.base);
    return SupabaseAuthRepository._(
      supabase.Supabase.instance.client,
      redirectTo,
    );
  }

  final supabase.SupabaseClient _client;
  final String _redirectTo;

  @override
  AuthUser? get currentUser => _toAuthUser(_client.auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges => _client.auth.onAuthStateChange.map(
    (event) => _toAuthUser(event.session?.user),
  );

  @override
  Future<void> signInWithGoogle() async {
    final started = await _client.auth.signInWithOAuth(
      supabase.OAuthProvider.google,
      redirectTo: _redirectTo,
    );
    if (!started) {
      throw const supabase.AuthException('Googleログインを開始できませんでした。');
    }
  }

  @override
  Future<UserAccessStatus> loadAccessStatus(String userId) async {
    final row = await _client
        .from('profiles')
        .select('access_status')
        .eq('id', userId)
        .maybeSingle();

    return row?['access_status'] == 'active'
        ? UserAccessStatus.active
        : UserAccessStatus.unavailable;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  static AuthUser? _toAuthUser(supabase.User? user) {
    if (user == null) return null;
    return AuthUser(id: user.id, email: user.email);
  }
}

// Preserve task deep links across the full-page OAuth round trip.
String authRedirectTo(Uri uri) {
  final route = uri.fragment.startsWith('/') ? uri.fragment : uri.path;
  if (RegExp(r'^/work-tasks/[^/?#]+$').hasMatch(route)) {
    return Uri.parse('${uri.origin}/').replace(fragment: route).toString();
  }
  return uri.origin;
}

class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;
}

enum UserAccessStatus { active, unavailable }

abstract interface class AuthRepository {
  AuthUser? get currentUser;

  Stream<AuthUser?> get authStateChanges;

  Future<void> signInWithGoogle();

  Future<UserAccessStatus> loadAccessStatus(String userId);

  Future<void> signOut();
}

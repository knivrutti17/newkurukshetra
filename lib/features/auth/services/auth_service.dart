import '../../../data/models/app_user.dart';

/// Authentication contract used by the presentation layer.
///
/// A Firebase-backed implementation can replace the local demo service later
/// without changing the login screen or dashboard routing.
abstract interface class AuthService {
  Future<AppUser> signIn({required String email, required String password});

  Future<void> signOut();
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

import '../../../data/models/app_user.dart';
import 'auth_service.dart';

class DemoAccount {
  const DemoAccount({required this.user, required this.password});

  final AppUser user;
  final String password;
}

/// Local-only authentication for the InstituteOS frontend demonstration.
///
/// These credentials are intentionally visible in the UI for a demo and must
/// never be used as a production authentication mechanism.
class MockAuthService implements AuthService {
  MockAuthService({this.requestDelay = const Duration(milliseconds: 500)});

  final Duration requestDelay;

  static const demoAccounts = <DemoAccount>[
    DemoAccount(
      user: AppUser(
        id: 'demo-owner',
        name: 'Aarav Mehta',
        email: 'owner@demo.com',
        role: AppRole.owner,
      ),
      password: 'Owner@123',
    ),
    DemoAccount(
      user: AppUser(
        id: 'demo-counselor',
        name: 'Priya Shah',
        email: 'counselor@demo.com',
        role: AppRole.counselor,
      ),
      password: 'Counselor@123',
    ),
    DemoAccount(
      user: AppUser(
        id: 'demo-trainer',
        name: 'Rohan Kulkarni',
        email: 'trainer@demo.com',
        role: AppRole.trainer,
      ),
      password: 'Trainer@123',
    ),
    DemoAccount(
      user: AppUser(
        id: 'demo-accounts',
        name: 'Neha Iyer',
        email: 'accounts@demo.com',
        role: AppRole.accounts,
      ),
      password: 'Accounts@123',
    ),
  ];

  @override
  Future<AppUser?> restoreSession() async => null;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(requestDelay);
    final normalizedEmail = email.trim().toLowerCase();
    final account = demoAccounts.cast<DemoAccount?>().firstWhere(
      (item) => item?.user.email == normalizedEmail,
      orElse: () => null,
    );

    if (account == null || account.password != password) {
      throw const AuthException(
        'We could not find a demo account with those credentials.',
      );
    }

    return account.user;
  }

  @override
  Future<void> signOut() => Future<void>.delayed(requestDelay ~/ 3);
}

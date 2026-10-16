import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/core/routing/role_navigation.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/features/auth/controllers/session_controller.dart';
import 'package:kurukshetra/features/auth/services/mock_auth_service.dart';

void main() {
  group('MockAuthService demo accounts', () {
    for (final account in MockAuthService.demoAccounts) {
      test('signs in ${account.user.role.label}', () async {
        final service = MockAuthService(requestDelay: Duration.zero);

        final user = await service.signIn(
          email: account.user.email,
          password: account.password,
        );

        expect(user.email, account.user.email);
        expect(user.role, account.user.role);
      });
    }

    test('rejects invalid credentials with a friendly error', () async {
      final service = MockAuthService(requestDelay: Duration.zero);

      expect(
        () => service.signIn(email: 'owner@demo.com', password: 'incorrect'),
        throwsA(
          isA<Object>().having(
            (error) => error.toString(),
            'message',
            contains('could not find a demo account'),
          ),
        ),
      );
    });
  });

  test('session logs out and supports switching roles', () async {
    final session = SessionController(
      authService: MockAuthService(requestDelay: Duration.zero),
    );
    addTearDown(session.dispose);

    await session.signIn(email: 'owner@demo.com', password: 'Owner@123');
    expect(session.currentUser?.role, AppRole.owner);

    await session.signOut();
    expect(session.currentUser, isNull);

    await session.signIn(email: 'accounts@demo.com', password: 'Accounts@123');
    expect(session.currentUser?.role, AppRole.accounts);
  });

  test('each role receives only its navigation configuration', () {
    expect(
      navigationForRole(AppRole.owner).map((item) => item.label),
      containsAll(['Approvals', 'Reports', 'Staff & Settings']),
    );
    expect(
      navigationForRole(AppRole.counselor).map((item) => item.label),
      contains('Student Follow-ups'),
    );
    expect(
      navigationForRole(AppRole.trainer).map((item) => item.label),
      containsAll(['My Batches', 'My Timetable']),
    );
    expect(
      navigationForRole(AppRole.accounts).map((item) => item.label),
      containsAll(['Fee Management', 'Payments', 'Reminder Drafts']),
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/features/auth/controllers/session_controller.dart';
import 'package:kurukshetra/features/auth/screens/login_screen.dart';
import 'package:kurukshetra/features/auth/services/mock_auth_service.dart';

void main() {
  testWidgets('invalid credentials show the authentication error', (
    tester,
  ) async {
    final session = SessionController(
      authService: MockAuthService(requestDelay: Duration.zero),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: session,
          builder: (context, _) => LoginScreen(sessionController: session),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'owner@demo.com');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'not-the-password',
    );
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(
      find.text('We could not find a demo account with those credentials.'),
      findsOneWidget,
    );
  });

  testWidgets('valid credentials populate the session with the owner role', (
    tester,
  ) async {
    final session = SessionController(
      authService: MockAuthService(requestDelay: Duration.zero),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: session,
          builder: (context, _) => LoginScreen(sessionController: session),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'owner@demo.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'Owner@123');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(session.currentUser?.role, AppRole.owner);
    expect(session.isSignedIn, isTrue);
  });
}

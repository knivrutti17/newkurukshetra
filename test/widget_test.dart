import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/app.dart';

void main() {
  testWidgets('invalid demo credentials show a friendly error', (tester) async {
    await tester.pumpWidget(const InstituteOsApp());

    await tester.enterText(find.byType(EditableText).at(0), 'owner@demo.com');
    await tester.enterText(find.byType(EditableText).at(1), 'not-the-password');
    await tester.tap(find.text('Log in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.text('We could not find a demo account with those credentials.'),
      findsOneWidget,
    );
  });

  testWidgets('demo login shows credentials and signs an owner in and out', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const InstituteOsApp());

    expect(find.text('DEMO MODE'), findsOneWidget);
    expect(find.text('Owner / Admin'), findsOneWidget);
    expect(find.text('Accounts Staff'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).at(0), 'owner@demo.com');
    await tester.enterText(find.byType(EditableText).at(1), 'Owner@123');
    await tester.tap(find.text('Log in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('Good to see you, Aarav.'), findsOneWidget);
    final menuButton = find.byTooltip('Open navigation menu');
    if (menuButton.evaluate().isNotEmpty) {
      await tester.tap(menuButton);
      await tester.pumpAndSettle();
    }
    expect(find.text('Approvals'), findsOneWidget);

    await tester.tap(find.text('Log out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Sign in to your workspace'), findsOneWidget);
  });
}

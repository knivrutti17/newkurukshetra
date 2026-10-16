import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/controllers/session_controller.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/services/mock_auth_service.dart';
import 'features/dashboard/screens/dashboard_shell.dart';

class InstituteOsApp extends StatefulWidget {
  const InstituteOsApp({this.firebaseSetupMessage, super.key});

  /// A non-sensitive setup failure from the Firebase demo bootstrap.
  final String? firebaseSetupMessage;

  @override
  State<InstituteOsApp> createState() => _InstituteOsAppState();
}

class _InstituteOsAppState extends State<InstituteOsApp> {
  late final SessionController _sessionController;

  @override
  void initState() {
    super.initState();
    _sessionController = SessionController(authService: MockAuthService());
  }

  @override
  void dispose() {
    _sessionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstituteOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: AnimatedBuilder(
        animation: _sessionController,
        builder: (context, child) {
          final user = _sessionController.currentUser;
          if (user == null) {
            return LoginScreen(sessionController: _sessionController);
          }
          return DashboardShell(
            user: user,
            sessionController: _sessionController,
            firebaseSetupMessage: widget.firebaseSetupMessage,
          );
        },
      ),
    );
  }
}

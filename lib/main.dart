import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/firebase_app_check_initializer.dart';
import 'data/services/firebase_demo_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseSetupMessage = await FirebaseDemoSession().initialize();
  await FirebaseAppCheckInitializer.activateIfConfigured();
  runApp(InstituteOsApp(firebaseSetupMessage: firebaseSetupMessage));
}

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'data/services/firebase_demo_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseSetupMessage = await FirebaseDemoSession().initialize();
  runApp(InstituteOsApp(firebaseSetupMessage: firebaseSetupMessage));
}

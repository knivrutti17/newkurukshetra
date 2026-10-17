import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';

/// Initializes Firebase without creating a fake anonymous demo session.
///
/// Real authentication is handled by FirebaseAuthService and the user's stored
/// role document. This keeps the app aligned with Firebase Authentication and
/// avoids the previous mock-provider shortcuts.
class FirebaseDemoSession {
  Future<String?> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } on FirebaseException catch (error) {
      return 'Firebase could not start (${error.code}). Check the existing Firebase configuration.';
    } catch (_) {
      return 'Firebase could not start. Check the existing Firebase configuration.';
    }

    return null;
  }
}

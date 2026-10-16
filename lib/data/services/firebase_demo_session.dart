import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';

/// Starts a Firebase identity for the demo without changing its visible login.
///
/// The anonymous identity only satisfies an authentication-required Firestore
/// rule for a fictional-data demo. It deliberately has no relationship to the
/// local Owner/Counselor/Trainer/Accounts role selected in the UI.
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

    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } on FirebaseAuthException catch (error) {
      return 'Firebase demo access is unavailable (${error.code}). Enable the Anonymous provider in Firebase Authentication before using Firestore.';
    } catch (_) {
      return 'Firebase demo access is unavailable. Check Firebase Authentication setup.';
    }

    return null;
  }
}

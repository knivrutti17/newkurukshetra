import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../data/models/app_user.dart';
import 'auth_service.dart';

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Future<AppUser?> restoreSession() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      return null;
    }
    return _fromFirebaseUser(firebaseUser);
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        throw const AuthException(
          'No signed-in user was returned by Firebase.',
        );
      }
      return await _fromFirebaseUser(firebaseUser);
    } on FirebaseAuthException catch (error) {
      throw AuthException(_friendlyAuthError(error.code, error.message));
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Unable to sign in with Firebase. Please try again.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<AppUser> _fromFirebaseUser(User firebaseUser) async {
    final userDoc = await _firestore
        .collection('users')
        .doc(firebaseUser.uid)
        .get();
    final data = userDoc.data();
    if (!userDoc.exists || data == null) {
      throw const AuthException(
        'Your Firebase account is not provisioned yet. Ask the institute owner to create a role record for this user.',
      );
    }

    final active = data['isActive'] as bool? ?? true;
    if (!active) {
      throw const AuthException(
        'This account is inactive. Contact the institute owner to reactivate it.',
      );
    }

    final role = AppUser.roleFromString(data['role'] as String?);
    if (role == null) {
      throw const AuthException(
        'This account has no valid institute role assigned. Contact the owner for access.',
      );
    }

    return AppUser(
      id: firebaseUser.uid,
      name:
          (data['name'] as String?) ??
          firebaseUser.displayName ??
          'Institute User',
      email: (data['email'] as String?) ?? firebaseUser.email ?? '',
      role: role,
    );
  }

  String _friendlyAuthError(String code, String? message) {
    return switch (code) {
      'invalid-email' => 'Please enter a valid email address.',
      'user-not-found' || 'wrong-password' => 'Incorrect email or password.',
      'user-disabled' => 'This Firebase account has been disabled.',
      'too-many-requests' =>
        'Too many attempts. Please wait a moment and try again.',
      'network-request-failed' =>
        'Network error. Check your connection and try again.',
      _ => message ?? 'Authentication failed. Please try again.',
    };
  }
}

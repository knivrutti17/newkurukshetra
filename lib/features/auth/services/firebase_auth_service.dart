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
    } on FirebaseException catch (error) {
      throw AuthException(_friendlyFirestoreError(error.code, error.message));
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

    final instituteId = (data['instituteId'] as String?)?.trim();
    if (instituteId == null || instituteId.isEmpty) {
      throw const AuthException(
        'This account has no institute assigned. Contact the owner for access.',
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
      instituteId: instituteId,
    );
  }

  String _friendlyAuthError(String code, String? message) {
    return switch (code) {
      'invalid-email' => 'Please enter a valid email address.',
      'user-not-found' || 'wrong-password' => 'Incorrect email or password.',
      'user-disabled' => 'This Firebase account has been disabled.',
      'operation-not-allowed' || 'provider-disabled' =>
        'Email/password sign-in is not enabled in Firebase Authentication.',
      'too-many-requests' =>
        'Too many attempts. Please wait a moment and try again.',
      'network-request-failed' =>
        'Network error. Check your connection and try again.',
      'invalid-credential' => 'Incorrect email or password.',
      _ => message ?? 'Authentication failed. Please try again.',
    };
  }

  String _friendlyFirestoreError(String code, String? message) {
    return switch (code) {
      'permission-denied' => 'Authentication succeeded, but the user role profile could not be loaded. Check the Firestore rules and the users/{uid} document.',
      'unavailable' =>
        'Firebase is temporarily unavailable. Please try again in a moment.',
      'service-disabled' => 'Cloud Firestore is disabled in this Firebase project. Enable Firestore in the Firebase Console.',
      'not-found' => 'The authenticated account is valid, but no role profile was found for this user. Add a users/{uid} document with a valid role.',
      'failed-precondition' => 'Firebase is not fully configured for this app. Check project setup and Firestore enablement.',
      _ => message ?? 'The account authenticated, but the user role profile could not be loaded.',
    };
  }
}

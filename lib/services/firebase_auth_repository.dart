import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  GoogleSignIn? _googleSignIn;
  final bool _googleSignInEnabled;
  final Map<String, _PendingSignInMfa> _pendingSignInChallenges = {};
  final Map<String, _PendingEnrollmentMfa> _pendingEnrollmentChallenges = {};

  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
    bool googleSignInEnabled = true,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn,
        _googleSignInEnabled = googleSignInEnabled;

  @override
  bool get isGoogleSignInAvailable => _googleSignInEnabled;

  @override
  Future<AuthUser?> currentUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return _mapUserWithProfile(user);
    } catch (_) {
      return _mapUserFallback(user);
    }
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        throw const AuthException('Sign in failed');
      }
      return _mapUserWithProfile(user);
    } on FirebaseAuthMultiFactorException catch (e) {
      final challenge = await _startSignInMfaChallenge(e);
      throw AuthMfaRequiredException(
        challenge: challenge,
        message:
            'A verification code was sent to ${challenge.phoneNumber ?? 'your phone'}.',
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    } catch (e) {
      throw AuthException(_messageForUnknownError(e));
    }
  }

  @override
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String dateOfBirth,
    required String phoneNumber,
  }) async {
    final first = firstName.trim();
    final last = lastName.trim();
    final dob = dateOfBirth.trim();
    final phone = phoneNumber.trim();
    if (first.isEmpty || last.isEmpty || dob.isEmpty || phone.isEmpty) {
      throw const AuthException(
        'First name, last name, date of birth, and phone number are required',
      );
    }
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        throw const AuthException('Sign up failed');
      }
      await user.updateDisplayName('$first $last');
      await _userDoc(user.uid).set({
        'email': email.trim(),
        'firstName': first,
        'lastName': last,
        'dateOfBirth': dob,
        'phoneNumber': phone,
        'mfaEnabled': false,
        'profileComplete': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return _mapUserWithProfile(user);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    } catch (e) {
      throw AuthException(_messageForUnknownError(e));
    }
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    if (!_googleSignInEnabled) {
      throw const AuthException(
        'Google sign-in is not configured for this iOS app yet. Re-run flutterfire configure after enabling Google provider.',
      );
    }
    try {
      final googleSignIn = _googleSignIn ??= GoogleSignIn();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthException('Google sign-in canceled.');
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        throw const AuthException('Google sign-in failed.');
      }
      return _mapUserWithProfile(user);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(_messageForUnknownError(e));
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      final googleSignIn = _googleSignIn ?? GoogleSignIn();
      await googleSignIn.signOut();
    } catch (_) {
      // Ignore Google sign-out errors when no Google session exists.
    }
  }

  @override
  Future<AuthMfaChallenge> beginPhoneMfaEnrollment({
    required String phoneNumber,
  }) async {
    final phone = phoneNumber.trim();
    if (phone.isEmpty) {
      throw const AuthException('Phone number is required for MFA enrollment.');
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in before enabling MFA.');
    }
    final session = await user.multiFactor.getSession();
    final completer = Completer<AuthMfaChallenge>();
    Object? verificationError;
    await _auth.verifyPhoneNumber(
      multiFactorSession: session,
      phoneNumber: phone,
      verificationCompleted: (_) {},
      verificationFailed: (e) {
        debugPrint('MFA enrollment verifyPhoneNumber failed: ${e.code} ${e.message}');
        verificationError = e;
        if (!completer.isCompleted) {
          completer.completeError(AuthException(_messageFor(e)));
        }
      },
      codeSent: (verificationId, _) {
        debugPrint('MFA enrollment code sent to $phone');
        final challengeId = _newChallengeId();
        _pendingEnrollmentChallenges[challengeId] = _PendingEnrollmentMfa(
          user: user,
          verificationId: verificationId,
          phoneNumber: phone,
        );
        if (!completer.isCompleted) {
          completer.complete(AuthMfaChallenge(
            id: challengeId,
            type: AuthMfaChallengeType.enrollment,
            phoneNumber: phone,
          ));
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 90));
    } on TimeoutException {
      debugPrint('MFA enrollment verifyPhoneNumber timed out. Last error: $verificationError');
      if (verificationError is FirebaseAuthException) {
        throw AuthException(_messageFor(verificationError! as FirebaseAuthException));
      }
      throw const AuthException(
        'Could not send verification code. Check Firebase Phone Auth setup (Authentication > Sign-in method > Phone), iOS app verification config, and try again.',
      );
    }
  }

  @override
  Future<void> completePhoneMfaEnrollment({
    required String challengeId,
    required String smsCode,
  }) async {
    final pending = _pendingEnrollmentChallenges.remove(challengeId);
    if (pending == null) {
      throw const AuthException('MFA enrollment session expired. Try again.');
    }
    final code = smsCode.trim();
    if (code.isEmpty) {
      throw const AuthException('Enter the SMS verification code.');
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: pending.verificationId,
        smsCode: code,
      );
      await pending.user.multiFactor.enroll(
        PhoneMultiFactorGenerator.getAssertion(credential),
      );
      await _userDoc(pending.user.uid).set({
        'phoneNumber': pending.phoneNumber,
        'mfaEnabled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    } catch (e) {
      throw AuthException(_messageForUnknownError(e));
    }
  }

  @override
  Future<AuthUser> completeMfaSignIn({
    required String challengeId,
    required String smsCode,
  }) async {
    final pending = _pendingSignInChallenges.remove(challengeId);
    if (pending == null) {
      throw const AuthException(
          'MFA sign-in session expired. Please sign in again.');
    }
    final code = smsCode.trim();
    if (code.isEmpty) {
      throw const AuthException('Enter the SMS verification code.');
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: pending.verificationId,
        smsCode: code,
      );
      final result = await pending.resolver.resolveSignIn(
        PhoneMultiFactorGenerator.getAssertion(credential),
      );
      final user = result.user;
      if (user == null) {
        throw const AuthException('MFA sign-in failed.');
      }
      return _mapUserWithProfile(user);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(_messageForUnknownError(e));
    }
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  Future<AuthUser> _mapUserWithProfile(User user) async {
    final snap = await _userDoc(user.uid).get();
    final data = snap.data() ?? const <String, dynamic>{};
    final firstName = data['firstName'] as String?;
    final lastName = data['lastName'] as String?;
    final dateOfBirth = data['dateOfBirth'] as String?;
    final phoneNumber = data['phoneNumber'] as String?;
    final mfaEnabled = data['mfaEnabled'] as bool? ?? false;
    return AuthUser(
      id: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: dateOfBirth,
      phoneNumber: phoneNumber,
      mfaEnabled: mfaEnabled,
    );
  }

  AuthUser _mapUserFallback(User user) {
    return AuthUser(
      id: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );
  }

  Future<AuthMfaChallenge> _startSignInMfaChallenge(
    FirebaseAuthMultiFactorException e,
  ) async {
    PhoneMultiFactorInfo? firstPhoneHint;
    for (final hint in e.resolver.hints) {
      if (hint is PhoneMultiFactorInfo) {
        firstPhoneHint = hint;
        break;
      }
    }
    if (firstPhoneHint == null) {
      throw const AuthException(
        'MFA is required, but no phone factor is available for this account.',
      );
    }
    final completer = Completer<AuthMfaChallenge>();
    Object? verificationError;
    await _auth.verifyPhoneNumber(
      multiFactorSession: e.resolver.session,
      multiFactorInfo: firstPhoneHint,
      verificationCompleted: (_) {},
      verificationFailed: (err) {
        debugPrint('MFA sign-in verifyPhoneNumber failed: ${err.code} ${err.message}');
        verificationError = err;
        if (!completer.isCompleted) {
          completer.completeError(AuthException(_messageFor(err)));
        }
      },
      codeSent: (verificationId, _) {
        debugPrint('MFA sign-in code sent to hint: ${firstPhoneHint?.phoneNumber}');
        final challengeId = _newChallengeId();
        _pendingSignInChallenges[challengeId] = _PendingSignInMfa(
          resolver: e.resolver,
          verificationId: verificationId,
        );
        if (!completer.isCompleted) {
          completer.complete(AuthMfaChallenge(
            id: challengeId,
            type: AuthMfaChallengeType.signIn,
            phoneNumber: firstPhoneHint?.phoneNumber,
          ));
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 90));
    } on TimeoutException {
      debugPrint('MFA sign-in verifyPhoneNumber timed out. Last error: $verificationError');
      if (verificationError is FirebaseAuthException) {
        throw AuthException(_messageFor(verificationError! as FirebaseAuthException));
      }
      throw const AuthException(
        'Could not send MFA sign-in code. Check phone auth configuration and try again.',
      );
    }
  }

  String _newChallengeId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_pendingSignInChallenges.length + _pendingEnrollmentChallenges.length}';

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password';
      case 'operation-not-allowed':
        return 'Auth operation is not allowed. In Firebase Console > Authentication > Sign-in method, enable Email/Password and Phone (required for SMS MFA).';
      case 'email-already-in-use':
        return 'An account with this email already exists';
      case 'weak-password':
        return 'Password is too weak';
      case 'too-many-requests':
        return 'Too many attempts. Try again later';
      case 'network-request-failed':
        return 'Network error. Check your connection';
      case 'account-exists-with-different-credential':
        return 'An account already exists with the same email using another sign-in method.';
      case 'popup-closed-by-user':
        return 'Google sign-in canceled.';
      default:
        if ((e.message ?? '').contains('CONFIGURATION_NOT_FOUND')) {
          return 'Firebase authentication is not configured for this app. Run flutterfire configure and rebuild.';
        }
        return e.message ?? 'Authentication error';
    }
  }

  String _messageForUnknownError(Object e) {
    final raw = e.toString();
    if (raw.contains('CONFIGURATION_NOT_FOUND')) {
      return 'Firebase Authentication is not enabled for this project. In Firebase Console, enable Authentication and the Email/Password provider.';
    }
    if (raw.contains('FIRAuthErrorDomain Code=17999') ||
        raw.contains('FIRAuthInternalErrorDomain')) {
      return 'Authentication service is unavailable due to app configuration. Check Firebase setup and try again.';
    }
    if (raw.contains('sign_in_failed') || raw.contains('GoogleSignIn')) {
      return 'Google sign-in failed. Check iOS/Android Firebase OAuth setup and try again.';
    }
    if (raw.contains('network') || raw.contains('SocketException')) {
      return 'Network error. Check your connection and try again.';
    }
    return 'Authentication failed. Please try again.';
  }
}

class _PendingSignInMfa {
  final MultiFactorResolver resolver;
  final String verificationId;

  _PendingSignInMfa({
    required this.resolver,
    required this.verificationId,
  });
}

class _PendingEnrollmentMfa {
  final User user;
  final String verificationId;
  final String phoneNumber;

  _PendingEnrollmentMfa({
    required this.user,
    required this.verificationId,
    required this.phoneNumber,
  });
}

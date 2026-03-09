import 'package:equatable/equatable.dart';

class AuthUser extends Equatable {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String? firstName;
  final String? lastName;
  final String? dateOfBirth;
  final String? phoneNumber;
  final bool mfaEnabled;

  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.firstName,
    this.lastName,
    this.dateOfBirth,
    this.phoneNumber,
    this.mfaEnabled = false,
  });

  bool get isMfaProfileComplete =>
      (firstName ?? '').trim().isNotEmpty &&
      (lastName ?? '').trim().isNotEmpty &&
      (dateOfBirth ?? '').trim().isNotEmpty &&
      (phoneNumber ?? '').trim().isNotEmpty;

  @override
  List<Object?> get props => [
        id,
        email,
        displayName,
        photoUrl,
        firstName,
        lastName,
        dateOfBirth,
        phoneNumber,
        mfaEnabled,
      ];
}

enum AuthMfaChallengeType { signIn, enrollment }

class AuthMfaChallenge extends Equatable {
  final String id;
  final AuthMfaChallengeType type;
  final String? phoneNumber;

  const AuthMfaChallenge({
    required this.id,
    required this.type,
    this.phoneNumber,
  });

  @override
  List<Object?> get props => [id, type, phoneNumber];
}

abstract class AuthRepository {
  bool get isGoogleSignInAvailable;
  Future<AuthUser?> currentUser();
  Future<AuthUser> signIn({
    required String email,
    required String password,
  });
  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String dateOfBirth,
    required String phoneNumber,
  });
  Future<AuthUser> signInWithGoogle();
  Future<AuthMfaChallenge> beginPhoneMfaEnrollment({
    required String phoneNumber,
  });
  Future<void> completePhoneMfaEnrollment({
    required String challengeId,
    required String smsCode,
  });
  Future<AuthUser> completeMfaSignIn({
    required String challengeId,
    required String smsCode,
  });
  Future<void> signOut();
}

class InMemoryAuthRepository implements AuthRepository {
  AuthUser? _user;

  @override
  bool get isGoogleSignInAvailable => true;

  @override
  Future<AuthUser?> currentUser() async => _user;

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthException('Email and password are required');
    }
    _user = AuthUser(
      id: 'local-${email.trim().toLowerCase()}',
      email: email.trim().toLowerCase(),
      displayName: 'Local User',
    );
    return _user!;
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
    if (firstName.trim().isEmpty ||
        lastName.trim().isEmpty ||
        dateOfBirth.trim().isEmpty ||
        phoneNumber.trim().isEmpty) {
      throw const AuthException(
          'First name, last name, date of birth, and phone number are required');
    }
    final user = await signIn(email: email, password: password);
    _user = AuthUser(
      id: user.id,
      email: user.email,
      displayName: '${firstName.trim()} ${lastName.trim()}',
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      dateOfBirth: dateOfBirth.trim(),
      phoneNumber: phoneNumber.trim(),
    );
    return _user!;
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    _user = const AuthUser(
      id: 'local-google-user',
      email: 'google.user@local.dev',
      displayName: 'Google User (Local)',
    );
    return _user!;
  }

  @override
  Future<AuthMfaChallenge> beginPhoneMfaEnrollment({
    required String phoneNumber,
  }) async {
    throw const AuthException(
        'MFA enrollment requires Firebase authentication.');
  }

  @override
  Future<void> completePhoneMfaEnrollment({
    required String challengeId,
    required String smsCode,
  }) async {
    throw const AuthException(
        'MFA enrollment requires Firebase authentication.');
  }

  @override
  Future<AuthUser> completeMfaSignIn({
    required String challengeId,
    required String smsCode,
  }) async {
    throw const AuthException('MFA sign-in requires Firebase authentication.');
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthMfaRequiredException implements Exception {
  final AuthMfaChallenge challenge;
  final String message;

  const AuthMfaRequiredException({
    required this.challenge,
    required this.message,
  });

  @override
  String toString() => message;
}

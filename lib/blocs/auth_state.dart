part of 'auth_bloc.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  mfaRequired,
  failure
}

class AuthState extends Equatable {
  final AuthStatus status;
  final AuthUser? user;
  final String? errorMessage;
  final AuthMfaChallenge? mfaChallenge;

  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
    this.mfaChallenge,
  });

  const AuthState.initial()
      : status = AuthStatus.initial,
        user = null,
        errorMessage = null,
        mfaChallenge = null;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    bool clearUser = false,
    String? errorMessage,
    bool clearError = false,
    AuthMfaChallenge? mfaChallenge,
    bool clearMfaChallenge = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      mfaChallenge:
          clearMfaChallenge ? null : (mfaChallenge ?? this.mfaChallenge),
    );
  }

  @override
  List<Object?> get props => [status, user, errorMessage, mfaChallenge];
}

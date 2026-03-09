part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthStarted extends AuthEvent {
  const AuthStarted();
}

class AuthSignInRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthSignInRequested({
    required this.email,
    required this.password,
  });

  @override
  List<Object?> get props => [email, password];
}

class AuthSignUpRequested extends AuthEvent {
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String dateOfBirth;
  final String phoneNumber;

  const AuthSignUpRequested({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.dateOfBirth,
    required this.phoneNumber,
  });

  @override
  List<Object?> get props =>
      [email, password, firstName, lastName, dateOfBirth, phoneNumber];
}

class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

class AuthGoogleSignInRequested extends AuthEvent {
  const AuthGoogleSignInRequested();
}

class AuthSessionRefreshed extends AuthEvent {
  const AuthSessionRefreshed();
}

class AuthMfaCodeSubmitted extends AuthEvent {
  final String smsCode;

  const AuthMfaCodeSubmitted({required this.smsCode});

  @override
  List<Object?> get props => [smsCode];
}

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../services/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  AuthBloc({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(const AuthState.initial()) {
    on<AuthStarted>(_onStarted);
    on<AuthSignInRequested>(_onSignInRequested);
    on<AuthSignUpRequested>(_onSignUpRequested);
    on<AuthGoogleSignInRequested>(_onGoogleSignInRequested);
    on<AuthSignOutRequested>(_onSignOutRequested);
    on<AuthSessionRefreshed>(_onSessionRefreshed);
    on<AuthMfaCodeSubmitted>(_onMfaCodeSubmitted);
  }

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    emit(state.copyWith(status: AuthStatus.loading, clearError: true));
    final user = await _authRepository.currentUser();
    if (user != null) {
      emit(state.copyWith(status: AuthStatus.authenticated, user: user));
    } else {
      emit(state.copyWith(status: AuthStatus.unauthenticated, clearUser: true));
    }
  }

  Future<void> _onSignInRequested(
    AuthSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthStatus.loading, clearError: true));
    try {
      final user = await _authRepository.signIn(
        email: event.email,
        password: event.password,
      );
      emit(state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        clearMfaChallenge: true,
      ));
    } on AuthMfaRequiredException catch (e) {
      emit(state.copyWith(
        status: AuthStatus.mfaRequired,
        mfaChallenge: e.challenge,
        errorMessage: e.message,
        clearUser: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: _errorMessageFor(e),
        clearUser: true,
        clearMfaChallenge: true,
      ));
      emit(state.copyWith(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> _onSignUpRequested(
    AuthSignUpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthStatus.loading, clearError: true));
    try {
      final user = await _authRepository.signUp(
        email: event.email,
        password: event.password,
        firstName: event.firstName,
        lastName: event.lastName,
        dateOfBirth: event.dateOfBirth,
        phoneNumber: event.phoneNumber,
      );
      emit(state.copyWith(status: AuthStatus.authenticated, user: user));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: _errorMessageFor(e),
        clearUser: true,
        clearMfaChallenge: true,
      ));
      emit(state.copyWith(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> _onSignOutRequested(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authRepository.signOut();
    emit(state.copyWith(
      status: AuthStatus.unauthenticated,
      clearUser: true,
      clearError: true,
      clearMfaChallenge: true,
    ));
  }

  Future<void> _onGoogleSignInRequested(
    AuthGoogleSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthStatus.loading, clearError: true));
    try {
      final user = await _authRepository.signInWithGoogle();
      emit(state.copyWith(status: AuthStatus.authenticated, user: user));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: _errorMessageFor(e),
        clearUser: true,
        clearMfaChallenge: true,
      ));
      emit(state.copyWith(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> _onSessionRefreshed(
    AuthSessionRefreshed event,
    Emitter<AuthState> emit,
  ) async {
    final user = await _authRepository.currentUser();
    emit(state.copyWith(
      status:
          user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated,
      user: user,
      clearUser: user == null,
      clearMfaChallenge: true,
    ));
  }

  Future<void> _onMfaCodeSubmitted(
    AuthMfaCodeSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final challenge = state.mfaChallenge;
    if (challenge == null || challenge.type != AuthMfaChallengeType.signIn) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: 'No MFA sign-in challenge is active.',
      ));
      emit(state.copyWith(status: AuthStatus.unauthenticated));
      return;
    }
    emit(state.copyWith(status: AuthStatus.loading, clearError: true));
    try {
      final user = await _authRepository.completeMfaSignIn(
        challengeId: challenge.id,
        smsCode: event.smsCode,
      );
      emit(state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        clearMfaChallenge: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.mfaRequired,
        errorMessage: _errorMessageFor(e),
      ));
    }
  }

  String _errorMessageFor(Object e) {
    if (e is AuthException) return e.message;
    final raw = e.toString();
    if (raw.contains('CONFIGURATION_NOT_FOUND')) {
      return 'Firebase authentication is not configured for this app. Run flutterfire configure and rebuild.';
    }
    if (raw.contains('AuthException:')) {
      return raw.replaceFirst('AuthException:', '').trim();
    }
    return 'Authentication failed. Please try again.';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../blocs/auth_bloc.dart';
import '../services/auth_repository.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mfaCodeController = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    _mfaCodeController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null) return;
    final mm = picked.month.toString().padLeft(2, '0');
    final dd = picked.day.toString().padLeft(2, '0');
    _dobController.text = '${picked.year}-$mm-$dd';
  }

  void _submit() {
    final mfaStep =
        context.read<AuthBloc>().state.status == AuthStatus.mfaRequired;
    if (mfaStep) {
      context.read<AuthBloc>().add(
            AuthMfaCodeSubmitted(smsCode: _mfaCodeController.text.trim()),
          );
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (_isSignUp) {
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final dob = _dobController.text.trim();
      final phone = _phoneController.text.trim();
      context.read<AuthBloc>().add(
            AuthSignUpRequested(
              email: email,
              password: password,
              firstName: firstName,
              lastName: lastName,
              dateOfBirth: dob,
              phoneNumber: phone,
            ),
          );
    } else {
      context.read<AuthBloc>().add(
            AuthSignInRequested(email: email, password: password),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.bg2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final loading = state.status == AuthStatus.loading;
                    final mfaStep = state.status == AuthStatus.mfaRequired;
                    final googleAvailable =
                        context.read<AuthRepository>().isGoogleSignInAvailable;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEXUSBOT',
                          style: GoogleFonts.syne(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          mfaStep
                              ? 'Multi-factor verification'
                              : (_isSignUp ? 'Create account' : 'Sign in'),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        if (mfaStep) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Enter the code sent to ${state.mfaChallenge?.phoneNumber ?? 'your phone'}.',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (!mfaStep && _isSignUp) ...[
                          TextField(
                            controller: _firstNameController,
                            enabled: !loading,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'First name',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _lastNameController,
                            enabled: !loading,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Last name',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _dobController,
                            enabled: !loading,
                            readOnly: true,
                            onTap: loading ? null : _pickDob,
                            decoration: const InputDecoration(
                              labelText: 'Date of birth (YYYY-MM-DD)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _phoneController,
                            enabled: !loading,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone number',
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (mfaStep)
                          TextField(
                            controller: _mfaCodeController,
                            keyboardType: TextInputType.number,
                            enabled: !loading,
                            decoration: const InputDecoration(
                              labelText: 'SMS verification code',
                            ),
                          )
                        else
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            enabled: !loading,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                          ),
                        const SizedBox(height: 10),
                        if (!mfaStep)
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            enabled: !loading,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                            ),
                          ),
                        if (state.errorMessage != null &&
                            state.errorMessage!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.redBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.red),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  size: 16,
                                  color: AppTheme.red,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    state.errorMessage!,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 11,
                                      color: AppTheme.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: loading ? null : _submit,
                            child: Text(
                              loading
                                  ? 'Please wait...'
                                  : (mfaStep
                                      ? 'Verify Code'
                                      : (_isSignUp
                                          ? 'Create Account'
                                          : 'Sign In')),
                            ),
                          ),
                        ),
                        if (!mfaStep) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: (loading || !googleAvailable)
                                  ? null
                                  : () => context
                                      .read<AuthBloc>()
                                      .add(const AuthGoogleSignInRequested()),
                              icon: const Icon(Icons.account_circle_outlined,
                                  size: 16),
                              label: const Text('Continue with Google'),
                            ),
                          ),
                          if (!googleAvailable) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Google sign-in is not configured for iOS yet.',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton(
                              onPressed: loading
                                  ? null
                                  : () =>
                                      setState(() => _isSignUp = !_isSignUp),
                              child: Text(
                                _isSignUp
                                    ? 'Already have an account? Sign in'
                                    : 'No account? Create one',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 11,
                                  color: AppTheme.blue,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

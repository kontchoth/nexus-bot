import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../blocs/auth_bloc.dart';
import '../blocs/trading_bloc.dart';
import 'wallet_screen.dart';
import '../services/auth_repository.dart';
import '../services/app_settings_repository.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _alertsEnabled = true;
  bool _hapticsEnabled = true;
  bool _loadingPrefs = true;
  bool _mfaLoading = false;
  TradingBloc? _tradingBloc;

  @override
  void initState() {
    super.initState();
    try {
      _tradingBloc = context.read<TradingBloc>();
    } catch (_) {
      _tradingBloc = null;
    }
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final authState = context.read<AuthBloc>().state;
    final user = authState.user;
    if (user == null) {
      if (!mounted) return;
      setState(() => _loadingPrefs = false);
      return;
    }
    final settings = await context.read<AppSettingsRepository>().load(user.id);
    if (!mounted) return;
    setState(() {
      _alertsEnabled = settings.alertsEnabled;
      _hapticsEnabled = settings.hapticsEnabled;
      _loadingPrefs = false;
    });
    _tradingBloc?.add(
      UpdateAlertPreferences(
        alertsEnabled: _alertsEnabled,
        hapticsEnabled: _hapticsEnabled,
      ),
    );
  }

  Future<void> _persistPrefs() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    await context.read<AppSettingsRepository>().save(
          user.id,
          AppPreferences(
            alertsEnabled: _alertsEnabled,
            hapticsEnabled: _hapticsEnabled,
          ),
        );
  }

  Future<void> _enableMfa() async {
    final authState = context.read<AuthBloc>().state;
    final user = authState.user;
    var phone = user?.phoneNumber?.trim() ?? '';
    if (phone.isEmpty) {
      final entered = await _promptForPhoneNumber();
      if (entered == null || entered.trim().isEmpty) {
        return;
      }
      phone = entered.trim();
    }
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use E.164 format phone number, e.g. +15551234567',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _mfaLoading = true);
    try {
      final repo = context.read<AuthRepository>();
      final challenge = await repo.beginPhoneMfaEnrollment(phoneNumber: phone);
      final code = await _promptForCode();
      if (code == null || code.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('MFA setup cancelled.')),
          );
        }
        return;
      }
      await repo.completePhoneMfaEnrollment(
        challengeId: challenge.id,
        smsCode: code,
      );
      if (!mounted) return;
      context.read<AuthBloc>().add(const AuthSessionRefreshed());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MFA enabled successfully.')),
      );
    } catch (e, st) {
      debugPrint('MFA enrollment flow failed: $e');
      debugPrint('$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('MFA setup failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _mfaLoading = false);
      }
    }
  }

  Future<String?> _promptForPhoneNumber() async {
    final existing = context.read<AuthBloc>().state.user?.phoneNumber ?? '';
    final controller = TextEditingController(text: existing);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add phone number'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '+15551234567',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptForCode() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Verify phone'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'SMS code',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Verify'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final user = authState.user;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.syne(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _loadingPrefs
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _SectionCard(
                  title: 'Account',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? 'Trader',
                        style: GoogleFonts.syne(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? 'No email',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            context
                                .read<AuthBloc>()
                                .add(const AuthSignOutRequested());
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign out'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WalletScreen(),
                            ),
                          ),
                          icon:
                              const Icon(Icons.account_balance_wallet_outlined),
                          label: const Text('Manage wallet'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Security',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.mfaEnabled == true
                            ? 'MFA status: Enabled'
                            : 'MFA status: Not enabled',
                        style: GoogleFonts.spaceGrotesk(
                          color: user?.mfaEnabled == true
                              ? AppTheme.green
                              : AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Phone: ${((user?.phoneNumber ?? '').isEmpty) ? 'Not set' : user!.phoneNumber}',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (user?.mfaEnabled == true || _mfaLoading)
                              ? null
                              : _enableMfa,
                          icon: const Icon(Icons.verified_user_outlined),
                          label: Text(
                            _mfaLoading ? 'Sending code...' : 'Enable MFA',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Preferences',
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _alertsEnabled,
                        onChanged: (v) {
                          setState(() => _alertsEnabled = v);
                          _tradingBloc?.add(
                            UpdateAlertPreferences(
                              alertsEnabled: _alertsEnabled,
                              hapticsEnabled: _hapticsEnabled,
                            ),
                          );
                          _persistPrefs();
                        },
                        title: Text(
                          'Trade Alerts',
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          'Notifications for buy/sell events',
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const Divider(color: AppTheme.border),
                      SwitchListTile(
                        value: _hapticsEnabled,
                        onChanged: (v) {
                          setState(() => _hapticsEnabled = v);
                          _tradingBloc?.add(
                            UpdateAlertPreferences(
                              alertsEnabled: _alertsEnabled,
                              hapticsEnabled: _hapticsEnabled,
                            ),
                          );
                          _persistPrefs();
                        },
                        title: Text(
                          'Haptic Feedback',
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          'Enable vibration on key actions',
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              color: AppTheme.blue,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

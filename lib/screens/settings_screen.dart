import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import '../blocs/auth_bloc.dart';
import '../blocs/crypto/crypto_bloc.dart';
import '../blocs/spx/spx_bloc.dart';
import 'wallet_screen.dart';
import '../models/crypto_models.dart';
import '../services/auth_repository.dart';
import '../services/app_settings_repository.dart';
import '../services/remote_push_service.dart';
import '../theme/app_theme.dart';

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
const _tradierTokenKey = 'tradier_api_token';
const _robinhoodTokenKey = 'robinhood_crypto_token';

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
  CryptoBloc? _tradingBloc;

  // Tradier token
  final _tokenController = TextEditingController();
  bool _tokenObscured = true;
  bool _tokenSaving = false;
  final _robinhoodTokenController = TextEditingController();
  bool _robinhoodTokenObscured = true;
  bool _robinhoodTokenSaving = false;
  CryptoDataProvider _cryptoDataProvider = CryptoDataProvider.binance;
  SpxTermMode _spxTermMode = SpxTermMode.exact;
  int _spxExactDte = 7;
  int _spxMinDte = 5;
  int _spxMaxDte = 14;
  String _spxExecutionMode = SpxOpportunityExecutionMode.manualConfirm;
  int _spxEntryDelaySeconds = 30;
  int _spxValidationWindowSeconds = 120;
  double _spxMaxSlippagePct = 5.0;

  @override
  void initState() {
    super.initState();
    try {
      _tradingBloc = context.read<CryptoBloc>();
    } catch (_) {
      _tradingBloc = null;
    }
    _loadPrefs();
    _loadToken();
    _loadRobinhoodToken();
  }

  Future<void> _loadToken() async {
    final token = await _storage.read(key: _tradierTokenKey);
    if (!mounted) return;
    final normalized = (token ?? '').trim();
    setState(() => _tokenController.text = normalized);
    if (normalized.isEmpty) return;
    try {
      context.read<SpxBloc>().add(UpdateTradierToken(normalized));
    } catch (_) {}
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    setState(() => _tokenSaving = true);
    try {
      if (token.isEmpty) {
        await _storage.delete(key: _tradierTokenKey);
      } else {
        await _storage.write(key: _tradierTokenKey, value: token);
      }
      if (!mounted) return;
      // Hot-swap token in SpxBloc so the live feed retries immediately
      try {
        context.read<SpxBloc>().add(UpdateTradierToken(token));
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(token.isEmpty
              ? 'Tradier token cleared — using simulator'
              : 'Tradier token saved — retrying live feed'),
          backgroundColor: AppTheme.blue.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _tokenSaving = false);
    }
  }

  Future<void> _loadRobinhoodToken() async {
    final token = await _storage.read(key: _robinhoodTokenKey);
    if (!mounted) return;
    final normalized = (token ?? '').trim();
    setState(() => _robinhoodTokenController.text = normalized);
    try {
      context.read<CryptoBloc>().add(UpdateRobinhoodToken(normalized));
    } catch (_) {}
  }

  Future<void> _saveRobinhoodToken() async {
    final token = _robinhoodTokenController.text.trim();
    setState(() => _robinhoodTokenSaving = true);
    try {
      if (token.isEmpty) {
        await _storage.delete(key: _robinhoodTokenKey);
      } else {
        await _storage.write(key: _robinhoodTokenKey, value: token);
      }
      if (!mounted) return;
      try {
        context.read<CryptoBloc>().add(UpdateRobinhoodToken(token));
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            token.isEmpty ? 'Robinhood token cleared' : 'Robinhood token saved',
          ),
          backgroundColor: AppTheme.blue.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _robinhoodTokenSaving = false);
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _robinhoodTokenController.dispose();
    super.dispose();
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
      _cryptoDataProvider = settings.cryptoDataProvider == 'robinhood'
          ? CryptoDataProvider.robinhood
          : CryptoDataProvider.binance;
      _spxTermMode = settings.spxTermMode == 'range'
          ? SpxTermMode.range
          : SpxTermMode.exact;
      _spxExactDte = settings.spxExactDte;
      _spxMinDte = settings.spxMinDte;
      _spxMaxDte = settings.spxMaxDte < settings.spxMinDte
          ? settings.spxMinDte
          : settings.spxMaxDte;
      _spxExecutionMode = SpxOpportunityExecutionMode.normalize(
        settings.spxOpportunityExecutionMode,
      );
      _spxEntryDelaySeconds =
          settings.spxEntryDelaySeconds.clamp(0, 3600).toInt();
      _spxValidationWindowSeconds =
          settings.spxValidationWindowSeconds.clamp(15, 3600).toInt();
      _spxMaxSlippagePct =
          settings.spxMaxSlippagePct.clamp(0.1, 100.0).toDouble();
      _loadingPrefs = false;
    });
    _tradingBloc?.add(
      UpdateAlertPreferences(
        alertsEnabled: _alertsEnabled,
        hapticsEnabled: _hapticsEnabled,
      ),
    );
    _tradingBloc?.add(UpdateCryptoDataProvider(_cryptoDataProvider));
    _pushSpxExecutionSettings();
  }

  Future<void> _persistPrefs() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return;
    await context.read<AppSettingsRepository>().save(
          user.id,
          AppPreferences(
            alertsEnabled: _alertsEnabled,
            hapticsEnabled: _hapticsEnabled,
            cryptoDataProvider:
                _cryptoDataProvider == CryptoDataProvider.robinhood
                    ? 'robinhood'
                    : 'binance',
            spxTermMode: _spxTermMode == SpxTermMode.range ? 'range' : 'exact',
            spxExactDte: _spxExactDte,
            spxMinDte: _spxMinDte,
            spxMaxDte: _spxMaxDte,
            spxOpportunityExecutionMode: _spxExecutionMode,
            spxEntryDelaySeconds: _spxEntryDelaySeconds,
            spxValidationWindowSeconds: _spxValidationWindowSeconds,
            spxMaxSlippagePct: _spxMaxSlippagePct,
          ),
        );
  }

  void _setCryptoProvider(CryptoDataProvider provider) {
    setState(() => _cryptoDataProvider = provider);
    try {
      context.read<CryptoBloc>().add(UpdateCryptoDataProvider(provider));
    } catch (_) {}
    _persistPrefs();
  }

  void _pushSpxTermFilter() {
    try {
      context.read<SpxBloc>().add(
            UpdateSpxTermFilter(
              SpxTermFilter(
                mode: _spxTermMode,
                exactDte: _spxExactDte,
                minDte: _spxMinDte,
                maxDte: _spxMaxDte,
              ),
            ),
          );
    } catch (_) {}
  }

  void _setExactDte(int value) {
    final next = value.clamp(0, 365).toInt();
    setState(() => _spxExactDte = next);
    _pushSpxTermFilter();
    _persistPrefs();
  }

  void _setRange({int? minDte, int? maxDte}) {
    var nextMin = (minDte ?? _spxMinDte).clamp(0, 365).toInt();
    var nextMax = (maxDte ?? _spxMaxDte).clamp(0, 365).toInt();
    if (nextMax < nextMin) nextMax = nextMin;
    setState(() {
      _spxMinDte = nextMin;
      _spxMaxDte = nextMax;
    });
    _pushSpxTermFilter();
    _persistPrefs();
  }

  void _setSpxExecutionMode(String mode) {
    setState(
        () => _spxExecutionMode = SpxOpportunityExecutionMode.normalize(mode));
    _pushSpxExecutionSettings();
    _persistPrefs();
  }

  void _setSpxEntryDelaySeconds(int seconds) {
    final next = seconds.clamp(0, 3600).toInt();
    setState(() => _spxEntryDelaySeconds = next);
    _pushSpxExecutionSettings();
    _persistPrefs();
  }

  void _setSpxValidationWindowSeconds(int seconds) {
    final next = seconds.clamp(15, 3600).toInt();
    setState(() => _spxValidationWindowSeconds = next);
    _pushSpxExecutionSettings();
    _persistPrefs();
  }

  void _setSpxMaxSlippagePct(double value, {bool persist = true}) {
    final next = value.clamp(0.1, 100.0).toDouble();
    setState(() => _spxMaxSlippagePct = next);
    _pushSpxExecutionSettings();
    if (persist) _persistPrefs();
  }

  void _pushSpxExecutionSettings() {
    try {
      context.read<SpxBloc>().add(
            UpdateSpxExecutionSettings(
              executionMode: _spxExecutionMode,
              entryDelaySeconds: _spxEntryDelaySeconds,
              validationWindowSeconds: _spxValidationWindowSeconds,
              maxSlippagePct: _spxMaxSlippagePct,
              notificationsEnabled: _alertsEnabled,
            ),
          );
    } catch (_) {}
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
                  title: 'SPX Options — Tradier API',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enter your Tradier API token to enable live SPX options data. Leave blank to use the Black-Scholes simulator.',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _tokenController,
                        obscureText: _tokenObscured,
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                        ),
                        decoration: InputDecoration(
                          hintText: 'paste token here…',
                          hintStyle: GoogleFonts.spaceGrotesk(
                            color: AppTheme.textDim,
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: AppTheme.bg3,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: AppTheme.border2),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: AppTheme.border2),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _tokenObscured
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                              color: AppTheme.textMuted,
                            ),
                            onPressed: () => setState(
                                () => _tokenObscured = !_tokenObscured),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _tokenSaving ? null : _saveToken,
                          icon: _tokenSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined, size: 16),
                          label: Text(_tokenSaving ? 'Saving…' : 'Save token'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 12, color: AppTheme.textDim),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Get a free token at tradier.com → API Access. Use sandbox for testing.',
                              style: GoogleFonts.spaceGrotesk(
                                color: AppTheme.textDim,
                                fontSize: 10,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Crypto Scanner Controls',
                  child: BlocBuilder<CryptoBloc, CryptoState>(
                    builder: (context, cryptoState) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Moved from the top bar for easier access and fewer accidental taps.',
                            style: GoogleFonts.spaceGrotesk(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _SelectCard<CryptoDataProvider>(
                            label: 'Data Source',
                            value: _cryptoDataProvider,
                            items: CryptoDataProvider.values,
                            itemLabel: (p) => p.label,
                            onChanged: (p) {
                              if (p == null) return;
                              _setCryptoProvider(p);
                            },
                          ),
                          const SizedBox(height: 10),
                          if (_cryptoDataProvider ==
                              CryptoDataProvider.robinhood)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.bg3,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.border2),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Robinhood Crypto Token',
                                    style: GoogleFonts.spaceGrotesk(
                                      color: AppTheme.textMuted,
                                      fontSize: 10,
                                      letterSpacing: 0.8,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _robinhoodTokenController,
                                    obscureText: _robinhoodTokenObscured,
                                    style: GoogleFonts.spaceGrotesk(
                                      color: AppTheme.textPrimary,
                                      fontSize: 12,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: 'paste robinhood token…',
                                      hintStyle: GoogleFonts.spaceGrotesk(
                                        color: AppTheme.textDim,
                                        fontSize: 11,
                                      ),
                                      filled: true,
                                      fillColor: AppTheme.bg2,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                          color: AppTheme.border2,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                          color: AppTheme.border2,
                                        ),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _robinhoodTokenObscured
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: 18,
                                          color: AppTheme.textMuted,
                                        ),
                                        onPressed: () => setState(
                                          () => _robinhoodTokenObscured =
                                              !_robinhoodTokenObscured,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: _robinhoodTokenSaving
                                          ? null
                                          : _saveRobinhoodToken,
                                      icon: _robinhoodTokenSaving
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.save_outlined,
                                              size: 16,
                                            ),
                                      label: Text(
                                        _robinhoodTokenSaving
                                            ? 'Saving…'
                                            : 'Save Robinhood token',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Default remains Binance unless you switch Data Source to Robinhood.',
                                    style: GoogleFonts.spaceGrotesk(
                                      color: AppTheme.textDim,
                                      fontSize: 10,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_cryptoDataProvider ==
                              CryptoDataProvider.robinhood)
                            const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _SelectCard<Exchange>(
                                  label: 'Exchange',
                                  value: cryptoState.selectedExchange,
                                  items: Exchange.values,
                                  itemLabel: (e) =>
                                      e == Exchange.all ? 'All' : e.label,
                                  onChanged: (e) {
                                    if (e == null) return;
                                    context
                                        .read<CryptoBloc>()
                                        .add(ChangeExchange(e));
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _SelectCard<Timeframe>(
                                  label: 'Timeframe',
                                  value: cryptoState.selectedTimeframe,
                                  items: Timeframe.values,
                                  itemLabel: (t) => t.label,
                                  onChanged: (t) {
                                    if (t == null) return;
                                    context
                                        .read<CryptoBloc>()
                                        .add(ChangeTimeframe(t));
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'SPX Terms (DTE)',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose an exact DTE or a DTE range for SPX expirations.',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<SpxTermMode>(
                        segments: const [
                          ButtonSegment<SpxTermMode>(
                            value: SpxTermMode.exact,
                            label: Text('Exact DTE'),
                          ),
                          ButtonSegment<SpxTermMode>(
                            value: SpxTermMode.range,
                            label: Text('DTE Range'),
                          ),
                        ],
                        selected: {_spxTermMode},
                        onSelectionChanged: (selection) {
                          final selected = selection.first;
                          setState(() => _spxTermMode = selected);
                          _pushSpxTermFilter();
                          _persistPrefs();
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          textStyle: WidgetStatePropertyAll(
                            GoogleFonts.spaceGrotesk(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_spxTermMode == SpxTermMode.exact)
                        _DteStepper(
                          label: 'Exact DTE',
                          value: _spxExactDte,
                          onMinus: () => _setExactDte(_spxExactDte - 1),
                          onPlus: () => _setExactDte(_spxExactDte + 1),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: _DteStepper(
                                label: 'Min DTE',
                                value: _spxMinDte,
                                onMinus: () =>
                                    _setRange(minDte: _spxMinDte - 1),
                                onPlus: () => _setRange(minDte: _spxMinDte + 1),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DteStepper(
                                label: 'Max DTE',
                                value: _spxMaxDte,
                                onMinus: () =>
                                    _setRange(maxDte: _spxMaxDte - 1),
                                onPlus: () => _setRange(maxDte: _spxMaxDte + 1),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'SPX Entry Controls',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose whether entries require approval, execute after a delay, or execute immediately.',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: SpxOpportunityExecutionMode.manualConfirm,
                            label: Text('Manual Confirm'),
                          ),
                          ButtonSegment<String>(
                            value: SpxOpportunityExecutionMode.autoAfterDelay,
                            label: Text('Auto + Delay'),
                          ),
                          ButtonSegment<String>(
                            value: SpxOpportunityExecutionMode.autoImmediate,
                            label: Text('Auto Now'),
                          ),
                        ],
                        selected: {_spxExecutionMode},
                        onSelectionChanged: (selection) {
                          _setSpxExecutionMode(selection.first);
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          textStyle: WidgetStatePropertyAll(
                            GoogleFonts.spaceGrotesk(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_spxExecutionMode ==
                          SpxOpportunityExecutionMode.autoAfterDelay)
                        _DteStepper(
                          label: 'Entry Delay (sec)',
                          value: _spxEntryDelaySeconds,
                          onMinus: () => _setSpxEntryDelaySeconds(
                              _spxEntryDelaySeconds - 5),
                          onPlus: () => _setSpxEntryDelaySeconds(
                              _spxEntryDelaySeconds + 5),
                        ),
                      if (_spxExecutionMode ==
                          SpxOpportunityExecutionMode.manualConfirm)
                        _DteStepper(
                          label: 'Validation Window (sec)',
                          value: _spxValidationWindowSeconds,
                          onMinus: () => _setSpxValidationWindowSeconds(
                            _spxValidationWindowSeconds - 5,
                          ),
                          onPlus: () => _setSpxValidationWindowSeconds(
                            _spxValidationWindowSeconds + 5,
                          ),
                        ),
                      if (_spxExecutionMode ==
                          SpxOpportunityExecutionMode.autoImmediate)
                        Text(
                          'Auto Now mode executes immediately after guard checks.',
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTheme.textDim,
                            fontSize: 10,
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        'Max allowed slippage: ${_spxMaxSlippagePct.toStringAsFixed(1)}%',
                        style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Slider(
                        value: _spxMaxSlippagePct,
                        min: 0.1,
                        max: 25.0,
                        divisions: 249,
                        label: '${_spxMaxSlippagePct.toStringAsFixed(1)}%',
                        onChanged: (value) =>
                            _setSpxMaxSlippagePct(value, persist: false),
                        onChangeEnd: _setSpxMaxSlippagePct,
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
                          _pushSpxExecutionSettings();
                          unawaited(
                            RemotePushService.instance.updateAlertsPreference(
                              alertsEnabled: _alertsEnabled,
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

class _SelectCard<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;

  const _SelectCard({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              color: AppTheme.textDim,
              fontWeight: FontWeight.w700,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: AppTheme.bg2,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppTheme.textMuted,
              ),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              items: items
                  .map(
                    (e) => DropdownMenuItem<T>(
                      value: e,
                      child: Text(itemLabel(e)),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _DteStepper extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _DteStepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label: $value',
              style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded, size: 16),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onPlus,
            icon: const Icon(Icons.add_rounded, size: 16),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

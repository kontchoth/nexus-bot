import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nexusbot/firebase_options.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';
import 'blocs/auth_bloc.dart';
import 'blocs/crypto/crypto_bloc.dart';
import 'blocs/spx/spx_bloc.dart';
import 'models/models.dart';
import 'screens/auth_screen.dart';
import 'screens/crypto/scanner_screen.dart';
import 'screens/crypto/positions_screen.dart';
import 'screens/crypto/dashboard_screen.dart';
import 'screens/spx/spx_chain_screen.dart';
import 'screens/spx/spx_positions_screen.dart';
import 'screens/spx/spx_dashboard_screen.dart';
import 'screens/spx/spx_journal_screen.dart';
import 'screens/log_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_repository.dart';
import 'services/app_settings_repository.dart';
import 'services/wallet_repository.dart';
import 'services/firebase_auth_repository.dart';
import 'services/spx/spx_trade_journal_repository.dart';
import 'theme/app_theme.dart';

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
const _tradierTokenKey = 'tradier_api_token';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AuthRepository authRepository = InMemoryAuthRepository();
  AppSettingsRepository settingsRepository = LocalAppSettingsRepository();
  WalletRepository walletRepository = LocalWalletRepository();
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    await Firebase.initializeApp(options: options);
    final googleEnabled = defaultTargetPlatform != TargetPlatform.iOS ||
        ((options.iosClientId ?? '').isNotEmpty);
    authRepository = FirebaseAuthRepository(googleSignInEnabled: googleEnabled);
    settingsRepository = FirebaseAppSettingsRepository();
    walletRepository = FirebaseWalletRepository();
  } catch (_) {
    // Firebase not configured — keep local in-memory auth for development.
  }
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(NexusBotApp(
    authRepository: authRepository,
    settingsRepository: settingsRepository,
    walletRepository: walletRepository,
  ));
}

class NexusBotApp extends StatelessWidget {
  final AuthRepository authRepository;
  final AppSettingsRepository settingsRepository;
  final WalletRepository walletRepository;
  const NexusBotApp({
    super.key,
    required this.authRepository,
    required this.settingsRepository,
    required this.walletRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>(create: (_) => authRepository),
        RepositoryProvider<AppSettingsRepository>(
            create: (_) => settingsRepository),
        RepositoryProvider<WalletRepository>(create: (_) => walletRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              authRepository: context.read<AuthRepository>(),
            )..add(const AuthStarted()),
          ),
        ],
        child: MaterialApp(
          title: 'NexusBot',
          theme: AppTheme.theme,
          debugShowCheckedModeBanner: false,
          home: const _AuthGate(),
        ),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state.status == AuthStatus.loading ||
            state.status == AuthStatus.initial) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (state.status == AuthStatus.authenticated) {
          return _AuthenticatedShell(user: state.user!);
        }
        return const AuthScreen();
      },
    );
  }
}

class _AuthenticatedShell extends StatefulWidget {
  final AuthUser user;
  const _AuthenticatedShell({required this.user});

  @override
  State<_AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends State<_AuthenticatedShell> {
  late final CryptoBloc _cryptoBloc;
  late final SpxBloc _spxBloc;
  late final SpxTradeJournalRepository _spxJournalRepository;

  @override
  void initState() {
    super.initState();
    _cryptoBloc = CryptoBloc()..add(InitializeMarket());
    _spxJournalRepository = Firebase.apps.isNotEmpty
        ? FirebaseSpxTradeJournalRepository()
        : LocalSpxTradeJournalRepository();
    if (kDebugMode) {
      debugPrint(
        '[SPX-JOURNAL] Repository: ${_spxJournalRepository.runtimeType}',
      );
    }
    _spxBloc = SpxBloc(
      userId: widget.user.id,
      journalRepository: _spxJournalRepository,
    )..add(const InitializeSpx());
    _applySavedTradierToken();
    _loadAlertPreferences();
  }

  Future<void> _applySavedTradierToken() async {
    final token = (await _secureStorage.read(key: _tradierTokenKey) ?? '').trim();
    if (token.isEmpty) {
      if (kDebugMode) {
        debugPrint('[SPX-LIVE] No saved Tradier token found in secure storage');
      }
      return;
    }
    if (kDebugMode) {
      debugPrint('[SPX-LIVE] Loaded saved Tradier token (length=${token.length})');
    }
    try {
      _spxBloc.add(UpdateTradierToken(token));
    } catch (_) {}
  }

  Future<void> _loadAlertPreferences() async {
    final settings =
        await context.read<AppSettingsRepository>().load(widget.user.id);
    if (!mounted) return;
    try {
      _cryptoBloc.add(UpdateAlertPreferences(
        alertsEnabled: settings.alertsEnabled,
        hapticsEnabled: settings.hapticsEnabled,
      ));
      final mode = settings.spxTermMode == 'range'
          ? SpxTermMode.range
          : SpxTermMode.exact;
      _spxBloc.add(UpdateSpxTermFilter(SpxTermFilter(
        mode: mode,
        exactDte: settings.spxExactDte,
        minDte: settings.spxMinDte,
        maxDte: settings.spxMaxDte,
      )));
    } catch (_) {
      // BLoC may have closed before async completed.
    }
  }

  @override
  void dispose() {
    _cryptoBloc.close();
    _spxBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SpxTradeJournalRepository>.value(
          value: _spxJournalRepository,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<CryptoBloc>.value(value: _cryptoBloc),
          BlocProvider<SpxBloc>.value(value: _spxBloc),
        ],
        child: const HomeShell(),
      ),
    );
  }
}

// ── Home Shell ────────────────────────────────────────────────────────────────

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  StreamSubscription<TradeAlert>? _cryptoAlertSub;
  StreamSubscription<TradeAlert>? _spxAlertSub;

  // 0 = Crypto, 1 = SPX
  int _activeModule = 0;
  int _cryptoTab    = 0;
  int _spxTab       = 0;

  static const _cryptoScreens = [
    ScannerScreen(),
    PositionsScreen(),
    DashboardScreen(),
    LogScreen(),
    SettingsScreen(),
  ];

  static const _spxScreens = [
    SpxChainScreen(),
    SpxPositionsScreen(),
    SpxDashboardScreen(),
    SpxJournalScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _cryptoAlertSub = context.read<CryptoBloc>().alertsStream.listen(_onAlert);
    _spxAlertSub    = context.read<SpxBloc>().alertsStream.listen(_onAlert);
  }

  void _onAlert(TradeAlert alert) {
    if (!mounted) return;
    final haptics = context.read<CryptoBloc>().state.hapticsEnabled;
    if (haptics) HapticFeedback.selectionClick();
    final color = switch (alert.type) {
      TradeLogType.buy  => AppTheme.green,
      TradeLogType.win  => AppTheme.green,
      TradeLogType.loss => AppTheme.red,
      TradeLogType.sell => AppTheme.red,
      _                 => AppTheme.blue,
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${alert.title}: ${alert.message}'),
      backgroundColor: color.withValues(alpha: 0.95),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  void dispose() {
    _cryptoAlertSub?.cancel();
    _spxAlertSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCrypto  = _activeModule == 0;
    final activeTab = isCrypto ? _cryptoTab : _spxTab;
    final screens   = isCrypto ? _cryptoScreens : _spxScreens;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: PreferredSize(
        preferredSize:
            Size.fromHeight(56 + MediaQuery.paddingOf(context).top),
        child: _NexusAppBar(
          activeModule: _activeModule,
          onModuleChanged: (m) => setState(() {
            _activeModule = m;
          }),
        ),
      ),
      body: IndexedStack(index: activeTab, children: screens),
      bottomNavigationBar: _NexusNavBar(
        activeIndex: activeTab,
        activeModule: _activeModule,
        onTabChanged: (i) => setState(() {
          if (isCrypto) {
            _cryptoTab = i;
          } else {
            _spxTab = i;
          }
        }),
      ),
    );
  }
}

// ── App Bar ───────────────────────────────────────────────────────────────────

class _NexusAppBar extends StatelessWidget {
  final int activeModule;
  final ValueChanged<int> onModuleChanged;
  const _NexusAppBar({
    required this.activeModule,
    required this.onModuleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isCrypto = activeModule == 0;
    final isNarrow = MediaQuery.sizeOf(context).width < 390;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              // ── Logo ────────────────────────────────────────────────────
              RichText(
                text: TextSpan(children: [
                  TextSpan(
                    text: 'NEXUS',
                    style: GoogleFonts.syne(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                  TextSpan(
                    text: 'BOT',
                    style: GoogleFonts.syne(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.green),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              // ── Module switcher pill ─────────────────────────────────────
              _ModulePill(
                activeModule: activeModule,
                onChanged: onModuleChanged,
              ),
              const SizedBox(width: 8),
              // ── Module-specific controls ─────────────────────────────────
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: isCrypto
                        ? _CryptoControls(isNarrow: isNarrow)
                        : _SpxControls(isNarrow: isNarrow),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CRYPTO | SPX segmented toggle pill.
class _ModulePill extends StatelessWidget {
  final int activeModule;
  final ValueChanged<int> onChanged;
  const _ModulePill({required this.activeModule, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg3,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.border2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillSegment(
            label: 'CRYPTO',
            isActive: activeModule == 0,
            onTap: () => onChanged(0),
          ),
          _PillSegment(
            label: 'SPX',
            isActive: activeModule == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _PillSegment extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _PillSegment({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.blue.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: isActive ? AppTheme.blue : AppTheme.textMuted,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Right-side controls shown when Crypto module is active.
class _CryptoControls extends StatelessWidget {
  final bool isNarrow;
  const _CryptoControls({required this.isNarrow});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoBloc, CryptoState>(
      buildWhen: (p, c) =>
          p.botStatus != c.botStatus ||
          p.marketDataMode != c.marketDataMode,
      builder: (context, state) {
        final isActive = state.botStatus == BotStatus.active;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Data mode badge
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isNarrow ? 6 : 8, vertical: 3),
              decoration: BoxDecoration(
                color: state.marketDataMode == MarketDataMode.live
                    ? AppTheme.greenBg
                    : AppTheme.bg3,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: state.marketDataMode == MarketDataMode.live
                      ? AppTheme.green.withValues(alpha: 0.45)
                      : AppTheme.border2,
                ),
              ),
              child: Text(
                state.marketDataMode == MarketDataMode.live
                    ? (isNarrow ? 'LIVE' : 'LIVE FEED')
                    : (isNarrow ? 'SIM' : 'SIMULATOR'),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: state.marketDataMode == MarketDataMode.live
                        ? AppTheme.green
                        : AppTheme.textMuted,
                    letterSpacing: 0.5),
              ),
            ),
            SizedBox(width: isNarrow ? 6 : 8),
            // Bot toggle
            GestureDetector(
              onTap: () => context.read<CryptoBloc>().add(ToggleBot()),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 8 : 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.greenBg : AppTheme.bg3,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isActive
                        ? AppTheme.green.withValues(alpha: 0.5)
                        : AppTheme.border2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isActive
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 14,
                      color:
                          isActive ? AppTheme.green : AppTheme.textMuted,
                    ),
                    if (!isNarrow) ...[
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'PAUSE' : 'START',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? AppTheme.green
                                : AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Right-side controls shown when SPX module is active.
class _SpxControls extends StatelessWidget {
  final bool isNarrow;
  const _SpxControls({required this.isNarrow});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpxBloc, SpxState>(
      buildWhen: (p, c) =>
          p.scannerStatus != c.scannerStatus || p.dataMode != c.dataMode,
      builder: (context, state) {
        final isActive = state.scannerStatus == SpxScannerStatus.active;
        final isLive   = state.dataMode == SpxDataMode.live;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Data mode badge
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isNarrow ? 6 : 8, vertical: 3),
              decoration: BoxDecoration(
                color: isLive ? AppTheme.greenBg : AppTheme.bg3,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isLive
                      ? AppTheme.green.withValues(alpha: 0.45)
                      : AppTheme.border2,
                ),
              ),
              child: Text(
                isLive
                    ? (isNarrow ? 'LIVE' : 'TRADIER LIVE')
                    : (isNarrow ? 'SIM' : 'BS SIM'),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: isLive ? AppTheme.green : AppTheme.textMuted,
                    letterSpacing: 0.5),
              ),
            ),
            SizedBox(width: isNarrow ? 6 : 8),
            // Scanner toggle
            GestureDetector(
              onTap: () =>
                  context.read<SpxBloc>().add(const ToggleSpxScanner()),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 8 : 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.greenBg : AppTheme.bg3,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isActive
                        ? AppTheme.green.withValues(alpha: 0.5)
                        : AppTheme.border2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isActive
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 14,
                      color: isActive ? AppTheme.green : AppTheme.textMuted,
                    ),
                    if (!isNarrow) ...[
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'SCANNER ON' : 'SCANNER OFF',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? AppTheme.green
                                : AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Nav Bar ───────────────────────────────────────────────────────────────────

class _NexusNavBar extends StatelessWidget {
  final int activeIndex;
  final int activeModule;
  final ValueChanged<int> onTabChanged;
  const _NexusNavBar({
    required this.activeIndex,
    required this.activeModule,
    required this.onTabChanged,
  });

  static const _cryptoItems = [
    (Icons.radar_rounded, 'Scanner'),
    (Icons.account_balance_wallet_outlined, 'Positions'),
    (Icons.bar_chart_rounded, 'Dashboard'),
    (Icons.receipt_long_outlined, 'Activity'),
    (Icons.settings_outlined, 'Settings'),
  ];

  static const _spxItems = [
    (Icons.show_chart_rounded, 'Chain'),
    (Icons.account_balance_wallet_outlined, 'Positions'),
    (Icons.bar_chart_rounded, 'Dashboard'),
    (Icons.receipt_long_outlined, 'Activity'),
    (Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final items = activeModule == 0 ? _cryptoItems : _spxItems;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bg2,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: Row(
            children: items.asMap().entries.map((entry) {
              final i = entry.key;
              final (icon, label) = entry.value;
              final isActive = i == activeIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTabChanged(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 20,
                          color:
                              isActive ? AppTheme.blue : AppTheme.textMuted),
                      const SizedBox(height: 2),
                      Text(label,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              color: isActive
                                  ? AppTheme.blue
                                  : AppTheme.textMuted,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
